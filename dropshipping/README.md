# Dropshipping decision system

A product either makes money after every real cost, or it does not. This
decides which, before any money is spent.

It is analysis tooling. It does not create accounts, hold payment details,
contact suppliers, or place orders.

## Run it

```bash
python3 dropshipping/decide.py dropshipping/products.example.json
python3 dropshipping/test_dropshipping.py
```

Pure standard library. No install step.

## What it does

Three pieces:

- `unit_economics.py` computes contribution margin per order, counting
  landed cost, payment fees, platform fees, acquisition cost, expected
  refunds, and expected chargebacks.
- `vetting.py` scores the risks that are not numbers: trademark exposure,
  restricted categories, supplier history, delivery time, saturation.
- `decide.py` applies the gates and prints a verdict per product.

## The gates

A product must clear all four.

| Gate | Threshold | Why |
|---|---|---|
| Contribution per order | at least 8.00 | Thin absolute margin cannot absorb one refund |
| Margin | at least 20% | Below this, one bad ad week wipes the month |
| Markup on landed cost | at least 2.5x | Room for the fees that arrive later |
| Ad spend share of revenue | at most 35% | Above this, the auction sets your profit |

Any single blocking risk overrides good economics. Trademark exposure is
not a number you can optimize around.

## The two things people get wrong

**Acquisition cost is per order, not per click.** A click at 1.10 with a 2%
conversion rate costs 55.00 to make one sale. Most product spreadsheets use
the click price and show a profit that does not exist.

**Refunds and chargebacks are costs on every order.** A 7% refund rate on a
34.98 sale is a 3.19 expense on each order, not an occasional surprise.

## What the example data shows

Four candidates, one survives.

| Product | Contribution per order | Verdict |
|---|---|---|
| LED Sunset Projector Lamp | -25.85 | Falling demand, ad cost 129% of revenue |
| Magnetic Cable Organizer Set | -15.25 | Ticket too small to carry acquisition cost |
| Orthopedic Dog Bed (XL) | 40.16 | Clears every gate |
| Pokemon Plush Bundle | 6.91 | Trademark block, and margin fails anyway |

The pattern is consistent. Low-ticket trending products lose money because
acquisition cost does not shrink with the price. The survivor is a boring,
higher-value item shipped from a domestic warehouse.

## Fields

Put one JSON object per product in a list. Unknown keys are reported and
ignored, so notes are safe to include.

Money fields are in one currency throughout. Rates are fractions, so 0.05
means 5%.

Economics: `price`, `shipping_charged`, `cogs`, `shipping_cost`,
`payment_pct`, `payment_flat`, `platform_pct`, `refund_rate`,
`refund_recovery`, `chargeback_rate`, `chargeback_fee`, `cpc`,
`conversion_rate`, `cac_override`.

Risk: `category`, `supplier_orders`, `supplier_rating`, `supplier_years`,
`sample_ordered`, `fulfillment_days`, `ships_from_domestic`, `branded`,
`patent_risk`, `competitors_running_ads`, `months_trending`,
`search_volume_trend`, `fragile`, `weight_kg`, `has_sizing`,
`battery_powered`.

## Getting the inputs

The output is only as good as what goes in. Two numbers decide most
verdicts, so get these from data rather than hope:

- **Cost per click** comes from a real test campaign in your market, not
  from a published average.
- **Conversion rate** comes from your own store. Before you have one, 1-2%
  is the honest assumption for cold traffic.

Order the sample before trusting anything else. The tooling blocks any
product you have not held.

## Stress test

Every product is re-run at 150% and 200% of its ad cost and refund rate.
A product that only clears the gates at today's numbers is not viable, it
is lucky. Ad costs rise once a product works and competitors notice.

## Adjusting the gates

Thresholds are constants at the top of `decide.py`. Restricted categories
and trademark keywords are sets at the top of `vetting.py`. Both are
starting points, not law. Change them deliberately, and rerun the tests.
