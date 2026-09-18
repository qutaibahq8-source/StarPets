"""Turn economics plus vetting into one answer: sell it, or walk away.

Usage:
    python3 -m dropshipping.decide products.json
    python3 dropshipping/decide.py dropshipping/products.example.json
"""

import json
import sys
from dataclasses import dataclass
from typing import List, Optional

try:
    from .unit_economics import Product, Economics, compute, sensitivity, InputError
    from .vetting import Candidate, Finding, Level, vet, verdict
except ImportError:  # run as a plain script
    from unit_economics import Product, Economics, compute, sensitivity, InputError
    from vetting import Candidate, Finding, Level, vet, verdict


# --- Gates. A product must clear all of these to be worth running. ---

MIN_MARGIN_PCT = 0.20        # below this, one bad ad week wipes the month
MIN_CONTRIBUTION = 8.00      # thin absolute margin cannot absorb one refund
MIN_MARKUP = 2.5             # revenue over landed cost
MAX_CAC_SHARE = 0.35         # ad spend above a third of revenue is fragile


@dataclass
class Decision:
    name: str
    economics: Optional[Economics]
    findings: List[Finding]
    gate_failures: List[str]
    risk_verdict: Level
    approved: bool
    error: Optional[str] = None


def check_gates(e: Economics) -> List[str]:
    failures = []
    if e.contribution <= 0:
        failures.append(
            f"loses {abs(e.contribution):.2f} per order before you sell a single unit"
        )
    elif e.contribution < MIN_CONTRIBUTION:
        failures.append(
            f"contribution {e.contribution:.2f} is under the {MIN_CONTRIBUTION:.2f} floor, "
            "so a single refund erases several orders of profit"
        )
    if e.margin_pct < MIN_MARGIN_PCT:
        failures.append(
            f"margin {e.margin_pct * 100:.1f}% is under the {MIN_MARGIN_PCT * 100:.0f}% floor"
        )
    if e.markup_multiple < MIN_MARKUP:
        failures.append(
            f"markup {e.markup_multiple:.2f}x is under {MIN_MARKUP:.2f}x on landed cost"
        )
    if e.cac_share_of_revenue > MAX_CAC_SHARE:
        failures.append(
            f"ad spend is {e.cac_share_of_revenue * 100:.1f}% of revenue, over the "
            f"{MAX_CAC_SHARE * 100:.0f}% ceiling"
        )
    return failures


def evaluate(product: Product, candidate: Candidate) -> Decision:
    try:
        econ = compute(product)
    except InputError as exc:
        return Decision(
            name=product.name, economics=None, findings=[], gate_failures=[],
            risk_verdict=Level.BLOCK, approved=False, error=str(exc),
        )

    findings = vet(candidate)
    risk = verdict(findings)
    gates = check_gates(econ)
    approved = risk is not Level.BLOCK and not gates

    return Decision(
        name=product.name, economics=econ, findings=findings,
        gate_failures=gates, risk_verdict=risk, approved=approved,
    )


# --- Loading ---

def _split_fields(raw: dict):
    """One JSON object per product, split into the two dataclasses."""
    prod_keys = Product.__dataclass_fields__.keys()
    cand_keys = Candidate.__dataclass_fields__.keys()
    name = raw.get("name", "unnamed")
    prod = {k: v for k, v in raw.items() if k in prod_keys}
    cand = {k: v for k, v in raw.items() if k in cand_keys}
    prod["name"] = name
    cand["name"] = name
    unknown = set(raw) - set(prod_keys) - set(cand_keys)
    return Product(**prod), Candidate(**cand), sorted(unknown)


def load(path: str):
    with open(path) as fh:
        data = json.load(fh)
    if isinstance(data, dict):
        data = [data]
    return [_split_fields(row) for row in data]


# --- Reporting ---

BAR = "=" * 64


def money(x: float) -> str:
    return f"{x:>10,.2f}"


def report(d: Decision) -> str:
    lines = [BAR, d.name, BAR]

    if d.error:
        lines.append(f"  INPUT ERROR: {d.error}")
        lines.append("")
        return "\n".join(lines)

    e = d.economics
    lines.append("  Per order")
    lines.append(f"    Revenue            {money(e.revenue)}")
    lines.append(f"    Landed cost        {money(-e.landed_cost)}")
    lines.append(f"    Payment fees       {money(-e.payment_fees)}")
    if e.platform_fees:
        lines.append(f"    Platform fees      {money(-e.platform_fees)}")
    lines.append(f"    Ad spend per sale  {money(-e.cac)}")
    lines.append(f"    Refunds (expected) {money(-e.refund_loss)}")
    lines.append(f"    Chargebacks (exp.) {money(-e.chargeback_loss)}")
    lines.append(f"    {'-' * 32}")
    lines.append(f"    Contribution       {money(e.contribution)}")
    lines.append("")
    lines.append(f"    Margin             {e.margin_pct * 100:>9.1f}%")
    lines.append(f"    Markup on cost     {e.markup_multiple:>9.2f}x")
    lines.append(f"    Breakeven CAC      {money(e.breakeven_cac)}")
    if e.breakeven_conversion_rate is not None:
        lines.append(
            f"    Breakeven CVR      {e.breakeven_conversion_rate * 100:>9.2f}%"
        )
    lines.append("")

    blocks = [f for f in d.findings if f.level is Level.BLOCK]
    warns = [f for f in d.findings if f.level is Level.WARN]

    if blocks:
        lines.append("  Blocking risks")
        for f in blocks:
            lines.append(f"    [{f.check}] {f.message}")
        lines.append("")
    if warns:
        lines.append("  Warnings")
        for f in warns:
            lines.append(f"    [{f.check}] {f.message}")
        lines.append("")
    if d.gate_failures:
        lines.append("  Failed economics gates")
        for g in d.gate_failures:
            lines.append(f"    {g}")
        lines.append("")

    lines.append(f"  VERDICT: {'RUN IT' if d.approved else 'DO NOT RUN'}")
    if d.approved and warns:
        lines.append(f"  ({len(warns)} warning(s) to price in before scaling spend.)")
    lines.append("")
    return "\n".join(lines)


def stress_report(product: Product) -> str:
    """Show what happens when ad costs rise and refunds climb.

    A product that only clears the gates at today's numbers is not viable,
    it is lucky. This is the double-check.
    """
    lines = ["  Stress test"]
    for field_name, label in (("cpc", "ad cost per click"), ("refund_rate", "refund rate")):
        current = getattr(product, field_name, 0)
        if not current:
            continue
        lines.append(f"    {label}:")
        for mult, value, econ in sensitivity(product, field_name):
            status = "ok" if econ.contribution > 0 else "LOSS"
            lines.append(
                f"      {mult:>4.0%} -> {value:>7.3f}   "
                f"contribution {econ.contribution:>8.2f}  {status}"
            )
    if len(lines) == 1:
        return ""
    lines.append("")
    return "\n".join(lines)


def main(argv: List[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2

    try:
        rows = load(argv[1])
    except FileNotFoundError:
        print(f"No such file: {argv[1]}")
        return 2
    except json.JSONDecodeError as exc:
        print(f"Bad JSON in {argv[1]}: {exc}")
        return 2

    approved = 0
    for product, candidate, unknown in rows:
        if unknown:
            print(f"  note: ignoring unknown fields on {product.name}: {', '.join(unknown)}")
        decision = evaluate(product, candidate)
        print(report(decision))
        if decision.economics:
            stress = stress_report(product)
            if stress:
                print(stress)
        if decision.approved:
            approved += 1

    print(BAR)
    print(f"{approved} of {len(rows)} products cleared every gate.")
    print(BAR)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
