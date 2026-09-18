"""Tests for the dropshipping decision system.

Run:  python3 dropshipping/test_dropshipping.py
"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from unit_economics import Product, compute, customer_acquisition_cost, sensitivity, InputError
from vetting import Candidate, Level, vet, verdict
from decide import evaluate, check_gates, load, _split_fields


class TestCAC(unittest.TestCase):
    def test_cac_is_cost_per_order_not_per_click(self):
        p = Product(name="t", price=50, cpc=1.00, conversion_rate=0.02)
        # 1 dollar a click, 1 sale per 50 clicks, so 50 dollars per sale.
        self.assertAlmostEqual(customer_acquisition_cost(p), 50.0)

    def test_override_wins(self):
        p = Product(name="t", price=50, cpc=1.00, conversion_rate=0.02, cac_override=12.0)
        self.assertAlmostEqual(customer_acquisition_cost(p), 12.0)

    def test_no_paid_traffic_means_no_cac(self):
        p = Product(name="t", price=50)
        self.assertEqual(customer_acquisition_cost(p), 0.0)


class TestEconomics(unittest.TestCase):
    def test_hand_computed_case(self):
        """Every term checked by hand so a refactor cannot quietly drift."""
        p = Product(
            name="t", price=100.0, shipping_charged=0.0,
            cogs=20.0, shipping_cost=5.0,
            payment_pct=0.029, payment_flat=0.30, platform_pct=0.0,
            refund_rate=0.10, refund_recovery=0.0,
            chargeback_rate=0.01, chargeback_fee=15.0,
            cac_override=25.0,
        )
        e = compute(p)
        self.assertAlmostEqual(e.revenue, 100.0)
        self.assertAlmostEqual(e.landed_cost, 25.0)
        self.assertAlmostEqual(e.payment_fees, 3.20)          # 2.90 + 0.30
        self.assertAlmostEqual(e.cac, 25.0)
        self.assertAlmostEqual(e.refund_loss, 12.50)          # 0.10 * (100 + 25)
        self.assertAlmostEqual(e.chargeback_loss, 1.40)       # 0.01 * (100 + 25 + 15)
        # 100 - 25 - 3.20 - 0 - 25 - 12.50 - 1.40
        self.assertAlmostEqual(e.contribution, 32.90)
        self.assertAlmostEqual(e.margin_pct, 0.3290)
        self.assertAlmostEqual(e.markup_multiple, 4.0)

    def test_gross_margin_ignores_ads_and_true_margin_does_not(self):
        """A product can look excellent before ads and lose money after them."""
        p = Product(name="t", price=20.0, shipping_charged=3.0, cogs=3.0,
                    shipping_cost=2.0, cac_override=25.0)
        e = compute(p)
        # 23 revenue, 5 landed cost, so 78% "margin" by the usual definition.
        self.assertAlmostEqual(e.gross_margin_pct, 18.0 / 23.0)
        self.assertGreater(e.gross_margin_pct, 0.70)
        self.assertLess(e.contribution, 0)

    def test_gross_margin_is_always_at_least_true_margin(self):
        p = Product(name="t", price=100.0, cogs=20.0, shipping_cost=5.0,
                    cac_override=10.0, refund_rate=0.05)
        e = compute(p)
        self.assertGreater(e.gross_margin_pct, e.margin_pct)

    def test_refund_recovery_reduces_loss(self):
        base = dict(name="t", price=100.0, cogs=20.0, shipping_cost=5.0, refund_rate=0.10)
        no_recovery = compute(Product(**base, refund_recovery=0.0))
        full_recovery = compute(Product(**base, refund_recovery=1.0))
        self.assertGreater(full_recovery.contribution, no_recovery.contribution)
        # Recovering all goods saves 10% of the 25 landed cost.
        self.assertAlmostEqual(
            full_recovery.contribution - no_recovery.contribution, 2.50
        )

    def test_shipping_charged_counts_as_revenue(self):
        a = compute(Product(name="t", price=50.0, shipping_charged=0.0, cogs=10.0))
        b = compute(Product(name="t", price=50.0, shipping_charged=5.0, cogs=10.0))
        self.assertGreater(b.contribution, a.contribution)

    def test_breakeven_cac_is_where_contribution_hits_zero(self):
        p = Product(name="t", price=100.0, cogs=20.0, shipping_cost=5.0, cac_override=25.0)
        e = compute(p)
        at_breakeven = compute(
            Product(name="t", price=100.0, cogs=20.0, shipping_cost=5.0,
                    cac_override=e.breakeven_cac)
        )
        self.assertAlmostEqual(at_breakeven.contribution, 0.0, places=6)

    def test_breakeven_cvr_actually_breaks_even(self):
        p = Product(name="t", price=100.0, cogs=20.0, shipping_cost=5.0,
                    cpc=1.00, conversion_rate=0.02)
        e = compute(p)
        self.assertIsNotNone(e.breakeven_conversion_rate)
        at = compute(Product(name="t", price=100.0, cogs=20.0, shipping_cost=5.0,
                             cpc=1.00, conversion_rate=e.breakeven_conversion_rate))
        self.assertAlmostEqual(at.contribution, 0.0, places=6)

    def test_zero_landed_cost_gives_infinite_markup_not_crash(self):
        e = compute(Product(name="t", price=10.0, cogs=0.0, shipping_cost=0.0))
        self.assertEqual(e.markup_multiple, float("inf"))

    def test_losing_product_reports_negative(self):
        p = Product(name="t", price=20.0, cogs=12.0, shipping_cost=6.0, cac_override=10.0)
        self.assertLess(compute(p).contribution, 0)


class TestValidation(unittest.TestCase):
    def test_zero_price_rejected(self):
        with self.assertRaises(InputError):
            compute(Product(name="t", price=0.0))

    def test_rate_above_one_rejected(self):
        with self.assertRaises(InputError):
            compute(Product(name="t", price=10.0, refund_rate=1.4))

    def test_negative_cost_rejected(self):
        with self.assertRaises(InputError):
            compute(Product(name="t", price=10.0, cogs=-5.0))

    def test_paid_traffic_with_zero_conversion_rejected(self):
        with self.assertRaises(InputError):
            compute(Product(name="t", price=10.0, cpc=1.0, conversion_rate=0.0))


class TestSensitivity(unittest.TestCase):
    def test_higher_cpc_lowers_contribution(self):
        p = Product(name="t", price=100.0, cogs=20.0, cpc=1.0, conversion_rate=0.02)
        results = sensitivity(p, "cpc")
        contributions = [econ.contribution for _, _, econ in results]
        self.assertEqual(contributions, sorted(contributions, reverse=True))

    def test_rates_stay_clamped_to_one(self):
        p = Product(name="t", price=100.0, cogs=20.0, refund_rate=0.6)
        for _, value, _ in sensitivity(p, "refund_rate"):
            self.assertLessEqual(value, 1.0)


class TestVetting(unittest.TestCase):
    def _clean(self, **over):
        base = dict(
            name="Plain Widget", supplier_orders=5000, supplier_rating=4.8,
            supplier_years=4.0, sample_ordered=True, fulfillment_days=6,
            ships_from_domestic=True, category="home", competitors_running_ads=5,
            months_trending=3.0, search_volume_trend="rising", weight_kg=0.3,
        )
        base.update(over)
        return Candidate(**base)

    def test_clean_candidate_passes(self):
        self.assertIs(verdict(vet(self._clean())), Level.PASS)

    def test_trademark_in_name_blocks(self):
        f = vet(self._clean(name="Disney Princess Night Light"))
        self.assertIs(verdict(f), Level.BLOCK)
        self.assertTrue(any(x.check == "trademark" for x in f))

    def test_branded_flag_blocks(self):
        self.assertIs(verdict(vet(self._clean(branded=True))), Level.BLOCK)

    def test_restricted_category_blocks(self):
        self.assertIs(verdict(vet(self._clean(category="supplements"))), Level.BLOCK)

    def test_category_matching_is_case_insensitive(self):
        self.assertIs(verdict(vet(self._clean(category="  CBD  "))), Level.BLOCK)

    def test_no_sample_blocks(self):
        f = vet(self._clean(sample_ordered=False))
        self.assertIs(verdict(f), Level.BLOCK)
        self.assertTrue(any(x.check == "sample" for x in f))

    def test_very_slow_delivery_blocks(self):
        self.assertIs(verdict(vet(self._clean(fulfillment_days=30))), Level.BLOCK)

    def test_slow_delivery_only_warns(self):
        self.assertIs(verdict(vet(self._clean(fulfillment_days=15))), Level.WARN)

    def test_falling_demand_blocks(self):
        self.assertIs(verdict(vet(self._clean(search_volume_trend="falling"))), Level.BLOCK)

    def test_saturation_warns(self):
        f = vet(self._clean(competitors_running_ads=80))
        self.assertIs(verdict(f), Level.WARN)
        self.assertTrue(any(x.check == "saturation" for x in f))

    def test_findings_are_deterministic(self):
        c = self._clean(name="Nike Style Trainers", category="vape", sample_ordered=False)
        self.assertEqual(
            [(f.level, f.check) for f in vet(c)],
            [(f.level, f.check) for f in vet(c)],
        )


class TestGates(unittest.TestCase):
    def test_negative_contribution_fails(self):
        e = compute(Product(name="t", price=20.0, cogs=15.0, shipping_cost=6.0))
        self.assertTrue(any("loses" in g for g in check_gates(e)))

    def test_thin_absolute_margin_fails_even_at_good_percentage(self):
        # 40% margin but only a few dollars per order.
        e = compute(Product(name="t", price=9.0, cogs=2.0, shipping_cost=1.0,
                            refund_rate=0.0, chargeback_rate=0.0, payment_flat=0.0,
                            payment_pct=0.0))
        self.assertGreater(e.margin_pct, 0.30)
        self.assertTrue(any("floor" in g for g in check_gates(e)))

    def test_healthy_product_clears_all_gates(self):
        e = compute(Product(name="t", price=129.0, cogs=28.0, shipping_cost=11.0,
                            refund_rate=0.05, chargeback_rate=0.004,
                            cpc=1.10, conversion_rate=0.030))
        self.assertEqual(check_gates(e), [])


class TestEndToEnd(unittest.TestCase):
    def setUp(self):
        here = os.path.dirname(os.path.abspath(__file__))
        self.rows = load(os.path.join(here, "products.example.json"))

    def test_example_file_parses(self):
        self.assertEqual(len(self.rows), 4)

    def test_no_unknown_fields_in_example(self):
        for _, _, unknown in self.rows:
            self.assertEqual(unknown, [], f"unrecognised keys: {unknown}")

    def test_trademarked_product_rejected_despite_fat_margin(self):
        product, candidate, _ = [r for r in self.rows if "Pokemon" in r[0].name][0]
        d = evaluate(product, candidate)
        self.assertGreater(d.economics.contribution, 0, "margin really is healthy")
        self.assertFalse(d.approved)
        self.assertIs(d.risk_verdict, Level.BLOCK)

    def test_low_ticket_product_rejected_on_absolute_margin(self):
        product, candidate, _ = [r for r in self.rows if "Magnetic" in r[0].name][0]
        d = evaluate(product, candidate)
        self.assertFalse(d.approved)
        self.assertTrue(d.gate_failures)

    def test_the_boring_product_is_the_one_that_passes(self):
        product, candidate, _ = [r for r in self.rows if "Dog Bed" in r[0].name][0]
        d = evaluate(product, candidate)
        self.assertTrue(d.approved, f"unexpected rejection: {d.gate_failures} {d.risk_verdict}")

    def test_split_ignores_unknown_keys_without_crashing(self):
        p, c, unknown = _split_fields({"name": "x", "price": 10.0, "vibes": "immaculate"})
        self.assertEqual(unknown, ["vibes"])
        self.assertEqual(p.price, 10.0)

    def test_bad_input_surfaces_as_error_not_exception(self):
        d = evaluate(Product(name="bad", price=0.0), Candidate(name="bad"))
        self.assertIsNotNone(d.error)
        self.assertFalse(d.approved)


if __name__ == "__main__":
    unittest.main(verbosity=2)
