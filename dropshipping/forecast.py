"""Earnings forecast for selling with organic content instead of paid ads.

The funnel is: views -> link clicks -> purchases. Both steps are small
numbers, and multiplying two small numbers gives a very small number. That
is the whole reason organic selling is slow.

Benchmarks used (ecommerce, 2026):
  link clicks per view   ~1%    engaged niche content, generous
  purchases per click    0.5-1% published organic conversion range
  posting cadence        3-5 per week for a small account

Run:  python3 dropshipping/forecast.py
"""

from dataclasses import dataclass
from typing import List

KD = 3.242  # USD per Kuwaiti dinar, September 2026


@dataclass
class Scenario:
    label: str
    avg_views: int          # typical views on an ordinary post
    spike_views: int = 0    # one post that travels further than the rest
    note: str = ""


def sales_from_views(views: float, click_rate: float, buy_rate: float) -> float:
    return views * click_rate * buy_rate


def run(profit_per_sale: float, weeks: int = 12, posts_per_week: int = 4,
        click_rate: float = 0.01, buy_rate: float = 0.0075) -> None:
    posts = weeks * posts_per_week
    views_per_sale = 1 / (click_rate * buy_rate)

    print(f"Assumptions: {posts_per_week} posts a week for {weeks} weeks = {posts} videos")
    print(f"  {click_rate*100:.1f}% of viewers tap the link, {buy_rate*100:.2f}% of those buy")
    print(f"  So roughly one sale per {views_per_sale:,.0f} views")
    print(f"  Profit kept per sale: ${profit_per_sale:.2f}  ({profit_per_sale/KD:.1f} KD)")
    print()

    scenarios: List[Scenario] = [
        Scenario("Nothing lands", 250, 0,
                 "The common outcome. Videos reach almost no one."),
        Scenario("Slow build", 900, 0,
                 "You improve, a few posts do modestly well."),
        Scenario("One video travels", 500, 180_000,
                 "A single post breaks out. The rest stay small."),
        Scenario("It genuinely works", 3_000, 400_000,
                 "Consistent reach plus a breakout. Uncommon."),
    ]

    print(f"{'Outcome':<22} {'Total views':>12} {'Sales':>7} {'Profit USD':>11} {'Profit KD':>10}")
    print("-" * 66)
    for s in scenarios:
        total_views = s.avg_views * posts + s.spike_views
        sales = sales_from_views(total_views, click_rate, buy_rate)
        profit = sales * profit_per_sale
        print(f"{s.label:<22} {total_views:>12,} {sales:>7.1f} {profit:>11,.0f} {profit/KD:>10,.0f}")

    print()
    for s in scenarios:
        print(f"  {s.label}: {s.note}")


if __name__ == "__main__":
    print("=" * 66)
    print("Wearable blanket hoodie, sold without paid advertising")
    print("=" * 66)
    run(profit_per_sale=39.57)
