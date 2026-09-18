"""Risk vetting for a candidate product.

Margin math says whether a product *can* make money. This says whether it
will get the store shut down, the goods seized, or the ad account banned
before it gets the chance.

Each check returns a Finding. Findings are BLOCK, WARN, or PASS.
A single BLOCK kills the product regardless of how good the margin looks.
"""

from dataclasses import dataclass, field
from enum import Enum
from typing import List, Optional


class Level(str, Enum):
    PASS = "PASS"
    WARN = "WARN"
    BLOCK = "BLOCK"


@dataclass
class Finding:
    level: Level
    check: str
    message: str


# Categories that routinely trigger customs seizure, platform removal, or
# liability that a dropshipper cannot insure against.
RESTRICTED_CATEGORIES = {
    "supplements": "ingestibles carry health-claim liability and FDA/EFSA exposure",
    "cosmetics": "skin contact products need safety files and importer registration",
    "medical": "medical claims require device registration in most markets",
    "vape": "nicotine and vape products are age-gated and banned by most ad platforms",
    "cbd": "banned by most payment processors and ad platforms",
    "weapons": "including replicas and knives, seized at customs and banned by ads",
    "batteries": "loose lithium cells are restricted air cargo and often seized",
    "car-parts": "safety-critical parts carry product liability you cannot offload",
    "children-toys": "requires CPSIA/CE conformity testing and traceable importer",
    "electronics-mains": "anything plugged into mains needs certified conformity",
}

# Brands and franchises where lookalike goods invite takedowns and seizure.
IP_RISK_KEYWORDS = {
    "disney", "marvel", "pokemon", "nintendo", "nike", "adidas", "apple",
    "airpod", "gucci", "louis vuitton", "supreme", "lego", "hello kitty",
    "stanley", "dyson", "sanrio", "bluey", "squishmallow", "labubu",
}


@dataclass
class Candidate:
    """What you know about a product before committing money."""

    name: str

    # Supplier
    supplier_orders: int = 0            # units the supplier has shipped
    supplier_rating: float = 0.0        # 0-5
    supplier_years: float = 0.0         # how long they have traded
    sample_ordered: bool = False        # did you buy one yourself

    # Logistics
    fulfillment_days: int = 0           # order placed to doorstep
    ships_from_domestic: bool = False   # local warehouse vs overseas

    # Market
    category: str = ""
    competitors_running_ads: int = 0    # distinct stores advertising it now
    months_trending: float = 0.0        # how long demand has been climbing
    search_volume_trend: str = "flat"   # "rising" | "flat" | "falling"

    # Legal
    branded: bool = False               # carries someone else's mark
    patent_risk: bool = False           # known design or utility patent

    # Product
    fragile: bool = False
    weight_kg: float = 0.0
    has_sizing: bool = False            # apparel and footwear drive returns
    battery_powered: bool = False


def _check_supplier(c: Candidate) -> List[Finding]:
    out = []
    if not c.sample_ordered:
        out.append(Finding(
            Level.BLOCK, "sample",
            "No sample ordered. You cannot vouch for quality you have never held, "
            "and the first review will be written by a stranger.",
        ))
    if c.supplier_orders < 300:
        out.append(Finding(
            Level.WARN, "supplier-volume",
            f"Supplier has only {c.supplier_orders} recorded orders. "
            "Thin history means unproven fulfilment under load.",
        ))
    if c.supplier_rating and c.supplier_rating < 4.6:
        out.append(Finding(
            Level.WARN, "supplier-rating",
            f"Supplier rated {c.supplier_rating:.2f}. Below 4.6 correlates with "
            "defect and dispute rates that eat the margin.",
        ))
    if c.supplier_years < 1.0:
        out.append(Finding(
            Level.WARN, "supplier-age",
            "Supplier has traded under a year. High odds of disappearing mid-season.",
        ))
    if not out:
        out.append(Finding(Level.PASS, "supplier", "Supplier history and sample check out."))
    return out


def _check_logistics(c: Candidate) -> List[Finding]:
    out = []
    if c.fulfillment_days > 21:
        out.append(Finding(
            Level.BLOCK, "delivery-time",
            f"{c.fulfillment_days} day delivery. Past three weeks, chargebacks and "
            "'item not received' disputes climb fast enough to threaten the merchant account.",
        ))
    elif c.fulfillment_days > 12:
        out.append(Finding(
            Level.WARN, "delivery-time",
            f"{c.fulfillment_days} day delivery. Budget for a higher refund rate "
            "and state the window plainly on the product page.",
        ))
    if c.fragile and not c.ships_from_domestic:
        out.append(Finding(
            Level.WARN, "fragility",
            "Fragile goods on long overseas routes arrive broken often enough to "
            "erase the margin. Model breakage as an extra refund point.",
        ))
    if c.battery_powered:
        out.append(Finding(
            Level.WARN, "battery",
            "Battery powered goods face air cargo restrictions and customs holds. "
            "Confirm the supplier ships certified cells.",
        ))
    if c.weight_kg > 2.0 and not c.ships_from_domestic:
        out.append(Finding(
            Level.WARN, "weight",
            f"{c.weight_kg:.1f} kg overseas. Shipping cost usually outruns what a "
            "customer will pay for it.",
        ))
    if not out:
        out.append(Finding(Level.PASS, "logistics", "Delivery window and handling are workable."))
    return out


def _check_legal(c: Candidate) -> List[Finding]:
    out = []
    name_lower = c.name.lower()
    hits = sorted(k for k in IP_RISK_KEYWORDS if k in name_lower)
    if hits or c.branded:
        out.append(Finding(
            Level.BLOCK, "trademark",
            f"Trademark exposure ({', '.join(hits) or 'flagged as branded'}). "
            "Selling another party's mark invites takedown, seizure, and a "
            "permanently closed payment account.",
        ))
    if c.patent_risk:
        out.append(Finding(
            Level.BLOCK, "patent",
            "Known patent or registered design on this product. Listings get pulled "
            "and the seller carries the liability, not the supplier.",
        ))
    key = c.category.strip().lower()
    if key in RESTRICTED_CATEGORIES:
        out.append(Finding(
            Level.BLOCK, "restricted-category",
            f"Category '{key}': {RESTRICTED_CATEGORIES[key]}.",
        ))
    if not out:
        out.append(Finding(Level.PASS, "legal", "No trademark, patent, or category blocks found."))
    return out


def _check_market(c: Candidate) -> List[Finding]:
    out = []
    if c.search_volume_trend == "falling":
        out.append(Finding(
            Level.BLOCK, "trend",
            "Demand is falling. By the time inventory and creative are ready, "
            "the curve is behind you.",
        ))
    if c.months_trending > 9:
        out.append(Finding(
            Level.WARN, "trend-age",
            f"Trending {c.months_trending:.0f} months. Late entry to a trend means "
            "competing with sellers who already have cheaper traffic.",
        ))
    if c.competitors_running_ads > 30:
        out.append(Finding(
            Level.WARN, "saturation",
            f"{c.competitors_running_ads} stores advertising this now. Auction "
            "pressure raises the cost per click you budgeted for.",
        ))
    if c.has_sizing:
        out.append(Finding(
            Level.WARN, "sizing",
            "Sized goods return at two to four times the rate of one-size goods. "
            "Raise the refund rate in the model before trusting the margin.",
        ))
    if not out:
        out.append(Finding(Level.PASS, "market", "Demand and competitive picture are acceptable."))
    return out


def vet(c: Candidate) -> List[Finding]:
    """Run every check. Order is stable so output diffs cleanly."""
    findings: List[Finding] = []
    findings += _check_legal(c)
    findings += _check_logistics(c)
    findings += _check_supplier(c)
    findings += _check_market(c)
    return findings


def verdict(findings: List[Finding]) -> Level:
    if any(f.level is Level.BLOCK for f in findings):
        return Level.BLOCK
    if any(f.level is Level.WARN for f in findings):
        return Level.WARN
    return Level.PASS
