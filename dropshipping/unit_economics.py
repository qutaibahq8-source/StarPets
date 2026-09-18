"""Unit economics for a single dropshipped product.

Everything here answers one question: after every cost that actually hits
the bank account, does one order leave money behind?

No dependencies. Pure stdlib so it runs anywhere.
"""

from dataclasses import dataclass, field, asdict
from typing import Optional


# --- Defaults reflect typical 2025/2026 rates. Override per platform. ---

DEFAULT_PAYMENT_PCT = 0.029          # card processing, percent of order
DEFAULT_PAYMENT_FLAT = 0.30          # card processing, flat per transaction
DEFAULT_CHARGEBACK_FEE = 15.00       # bank fee per disputed order
DEFAULT_PLATFORM_PCT = 0.0           # Shopify Basic = 0; marketplaces 8-15%


class InputError(ValueError):
    """Raised when inputs are impossible rather than merely unprofitable."""


@dataclass
class Product:
    """Every number needed to price one order honestly.

    Rates are fractions (0.05 == 5%), money is in one currency throughout.
    """

    name: str

    # Money in
    price: float                      # what the customer pays for the item
    shipping_charged: float = 0.0     # what you charge them for shipping

    # Money out, per order
    cogs: float = 0.0                 # supplier's price for the unit
    shipping_cost: float = 0.0        # what the supplier charges you to ship

    # Rates
    payment_pct: float = DEFAULT_PAYMENT_PCT
    payment_flat: float = DEFAULT_PAYMENT_FLAT
    platform_pct: float = DEFAULT_PLATFORM_PCT
    refund_rate: float = 0.05         # share of orders refunded
    refund_recovery: float = 0.0      # share of COGS recovered on a refund
    chargeback_rate: float = 0.005    # share of orders disputed
    chargeback_fee: float = DEFAULT_CHARGEBACK_FEE

    # Acquisition
    cpc: float = 0.0                  # cost per ad click
    conversion_rate: float = 0.02     # share of clicks that buy
    cac_override: Optional[float] = None   # use this instead of cpc/cvr if set

    # Context, not math
    fulfillment_days: int = 0         # supplier dispatch to customer doorstep
    notes: str = ""

    def validate(self) -> None:
        if self.price <= 0:
            raise InputError(f"{self.name}: price must be positive")
        for label, rate in (
            ("refund_rate", self.refund_rate),
            ("chargeback_rate", self.chargeback_rate),
            ("conversion_rate", self.conversion_rate),
            ("refund_recovery", self.refund_recovery),
            ("payment_pct", self.payment_pct),
            ("platform_pct", self.platform_pct),
        ):
            if not 0.0 <= rate <= 1.0:
                raise InputError(f"{self.name}: {label} must be between 0 and 1, got {rate}")
        if self.cac_override is None and self.cpc > 0 and self.conversion_rate == 0:
            raise InputError(f"{self.name}: conversion_rate of 0 with paid traffic means infinite CAC")
        for label, amount in (
            ("cogs", self.cogs),
            ("shipping_cost", self.shipping_cost),
            ("cpc", self.cpc),
            ("chargeback_fee", self.chargeback_fee),
        ):
            if amount < 0:
                raise InputError(f"{self.name}: {label} cannot be negative")


@dataclass
class Economics:
    """The decomposed per-order result. Every field is money per order."""

    revenue: float
    landed_cost: float
    payment_fees: float
    platform_fees: float
    cac: float
    refund_loss: float
    chargeback_loss: float
    gross_margin_pct: float
    contribution: float
    margin_pct: float
    markup_multiple: float
    cac_share_of_revenue: float
    breakeven_cac: float
    breakeven_conversion_rate: Optional[float]

    def as_dict(self) -> dict:
        return asdict(self)


def customer_acquisition_cost(p: Product) -> float:
    """Ad spend attributable to one *order*, not one click."""
    if p.cac_override is not None:
        return p.cac_override
    if p.cpc <= 0:
        return 0.0
    return p.cpc / p.conversion_rate


def compute(p: Product) -> Economics:
    """Full per-order contribution margin.

    Refunds and chargebacks are modelled as expected costs spread across all
    orders, which is how they actually land on a monthly P&L.
    """
    p.validate()

    revenue = p.price + p.shipping_charged
    landed_cost = p.cogs + p.shipping_cost

    payment_fees = revenue * p.payment_pct + p.payment_flat
    platform_fees = revenue * p.platform_pct
    cac = customer_acquisition_cost(p)

    # A refund returns the customer's money. The goods are usually gone, and
    # processors keep their cut on most plans. Recovery is whatever the
    # supplier or a restock actually gives back.
    unrecovered_goods = landed_cost * (1.0 - p.refund_recovery)
    refund_loss = p.refund_rate * (revenue + unrecovered_goods)

    # A chargeback loses the revenue, the goods, and adds a bank penalty.
    chargeback_loss = p.chargeback_rate * (revenue + landed_cost + p.chargeback_fee)

    contribution = (
        revenue
        - landed_cost
        - payment_fees
        - platform_fees
        - cac
        - refund_loss
        - chargeback_loss
    )

    # What most guides call "margin": price minus product cost, ignoring ads.
    # Useful only as a ceiling. The real margin is below it, often far below.
    gross_margin_pct = (revenue - landed_cost) / revenue if revenue else 0.0
    margin_pct = contribution / revenue if revenue else 0.0
    markup_multiple = revenue / landed_cost if landed_cost > 0 else float("inf")
    cac_share = cac / revenue if revenue else 0.0

    # The most CAC this product can absorb before it stops paying for itself.
    breakeven_cac = contribution + cac

    if p.cac_override is None and p.cpc > 0 and breakeven_cac > 0:
        breakeven_cvr = p.cpc / breakeven_cac
        breakeven_cvr = min(breakeven_cvr, 1.0) if breakeven_cvr <= 1.0 else None
    else:
        breakeven_cvr = None

    return Economics(
        revenue=revenue,
        landed_cost=landed_cost,
        payment_fees=payment_fees,
        platform_fees=platform_fees,
        cac=cac,
        refund_loss=refund_loss,
        chargeback_loss=chargeback_loss,
        gross_margin_pct=gross_margin_pct,
        contribution=contribution,
        margin_pct=margin_pct,
        markup_multiple=markup_multiple,
        cac_share_of_revenue=cac_share,
        breakeven_cac=breakeven_cac,
        breakeven_conversion_rate=breakeven_cvr,
    )


def sensitivity(p: Product, field_name: str, multipliers=(0.75, 1.0, 1.5, 2.0)) -> list:
    """Re-run the economics with one input scaled up or down.

    Ad costs rise and refund rates climb once volume is real. A product that
    only works at today's numbers is not a product, it is a coincidence.
    """
    from copy import deepcopy

    results = []
    for m in multipliers:
        variant = deepcopy(p)
        current = getattr(variant, field_name)
        if current is None:
            continue
        scaled = current * m
        if field_name in ("refund_rate", "chargeback_rate", "conversion_rate"):
            scaled = min(scaled, 1.0)
        setattr(variant, field_name, scaled)
        results.append((m, scaled, compute(variant)))
    return results
