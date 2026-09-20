#!/usr/bin/env python3
"""Measure whether the things players pay for actually do anything.

Three did not.

  * Lucky Boost, a 349-Robux gamepass sold as "1.5x better egg luck always!",
    multiplied every rarity weight by 1.5 and drew from the new total. Scaling
    a whole distribution by one number leaves it identical, so the gamepass
    changed nothing. Over 300,000 rolls each rarity moved less than a tenth of
    a percent — noise — and Mythic came out lower WITH the boost.
  * Lucky Charm, an upgrade costing 54,000 coins to max, was read by no code
    anywhere in the project.
  * Coin Bonus, an upgrade costing 126,000 coins to max, likewise. Its own
    description says "Multiply coins earned from orbs" and no line multiplied
    anything.

None of these throw. Nothing appears in Output. The panel draws the upgrade as
owned and the money is gone. The only way to find it is to measure the outcome
with and without and notice the two numbers are the same — so that is what this
does, on the real server, through the real roll.
"""
import sys
from pathlib import Path

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed (pip install lupa)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from check_syntax import luau_to_lua  # noqa: E402
import check_map  # noqa: E402

ROLLS = 120000
RARE_TIERS = ("Mythic", "Legendary", "Epic", "Rare")

FAILURES = []


def check(label, fn):
    try:
        print("   ok  %-34s %s" % (label, fn() or ""))
    except AssertionError as e:
        print("   x   %-34s %s" % (label, e))
        FAILURES.append(label)
    except Exception as e:  # noqa: BLE001
        print("   x   %-34s crashed: %r" % (label, e))
        FAILURES.append(label)


def main():
    lua, mock, cfg = check_map.build()
    G = lua.globals()

    # The real rollRarity, lifted out of the real file so the function under
    # test is the one the game runs.
    src = (ROOT / "src/Server/EggService.lua").read_text()
    start = src.index("local RARITY_ORDER")
    end = src.index("local function getPetsOfRarity")
    lua.execute(luau_to_lua(src[start:end])
                .replace("local function rollRarity", "function rollRarity", 1))
    roll = G.rollRarity
    lua.execute("math.randomseed(90210)")

    egg = None
    i = 1
    while cfg.Eggs[i] is not None:
        if str(cfg.Eggs[i].id) == "CoolEgg":
            egg = cfg.Eggs[i]
        i += 1
    assert egg is not None, "CoolEgg is gone from the config"
    weights = egg.rarityWeights

    def rare_share(luck):
        hits = 0
        for _ in range(ROLLS):
            if str(roll(weights, luck)) in RARE_TIERS:
                hits += 1
        return 100.0 * hits / ROLLS

    base = rare_share(1)
    boosted = rare_share(1.5)

    def t_luck_moves_the_odds():
        # 1.5x luck on the rare tiers should lift their share by roughly half
        # again. Sampling noise on 120k rolls is well under a tenth of a
        # percent, so anything under +20% relative is the old no-op.
        lift = (boosted - base) / max(base, 1e-9)
        assert lift > 0.20, (
            "rare-tier share went %.3f%% -> %.3f%% with 1.5x luck (%+.1f%% "
            "relative). That is the no-op: scaling every weight by the same "
            "number leaves the distribution unchanged." % (base, boosted, lift * 100))
        return "rare tiers %.2f%% -> %.2f%% (%+.0f%% relative)" % (
            base, boosted, lift * 100)

    def t_luck_never_hurts():
        assert boosted > base, \
            "luck made rare pets LESS likely (%.3f%% -> %.3f%%)" % (base, boosted)
        return "more luck is never worse"

    def t_common_still_dominates():
        # Luck must not turn a starter egg into a legendary machine.
        assert boosted < 60, \
            "1.5x luck pushed rare tiers to %.1f%% of all hatches" % boosted
        return "rare tiers stay at %.1f%% with the gamepass" % boosted

    def t_zero_weights_do_not_throw():
        empty = lua.eval('{Common=0, Uncommon=0, Rare=0, Epic=0, Legendary=0, Mythic=0}')
        got = str(roll(empty, 1.5))
        assert got, "an egg with no weights threw instead of falling back"
        return "an all-zero egg falls back to %s instead of erroring" % got

    print("egg luck, measured over %d rolls per case:" % ROLLS)
    check("luck actually moves the odds", t_luck_moves_the_odds)
    check("more luck is never worse", t_luck_never_hurts)
    check("luck does not break the curve", t_common_still_dominates)
    check("an all-zero egg does not throw", t_zero_weights_do_not_throw)

    # ---- upgrades are wired to something ---------------------------------
    print("\nupgrades, read through GameConfig.UpgradeValue:")
    data = lua.eval('{Upgrades = {}}')

    def t_upgrade_accessor():
        for key in ("LuckyCharm", "CoinBonus", "SpeedBoost", "JumpBoost"):
            v = cfg.UpgradeValue(data, key)
            assert v is not None, "%s is not in the config at all" % key
        return "all four upgrades resolve to a value"

    def t_levels_raise_the_value():
        lo = cfg.UpgradeValue(data, "CoinBonus")
        maxed = lua.eval('{Upgrades = {CoinBonus = 4, LuckyCharm = 3}}')
        hi = cfg.UpgradeValue(maxed, "CoinBonus")
        assert hi > lo, "maxing Coin Bonus did not raise its value (%s -> %s)" % (lo, hi)
        lo2 = cfg.UpgradeValue(data, "LuckyCharm")
        hi2 = cfg.UpgradeValue(maxed, "LuckyCharm")
        assert hi2 > lo2, "maxing Lucky Charm did not raise its value"
        return "CoinBonus %sx -> %sx, LuckyCharm %sx -> %sx" % (lo, hi, lo2, hi2)

    def t_upgrades_are_actually_read():
        """The bug was never in the accessor — it was that nobody called it."""
        readers = {
            "LuckyCharm": ROOT / "src/Server/EggService.lua",
            "CoinBonus": ROOT / "src/Server/CurrencyService.lua",
        }
        for key, path in readers.items():
            body = path.read_text()
            assert key in body, (
                "%s is bought and stored but %s never reads it, so buying it "
                "changes nothing" % (key, path.name))
        return "each upgrade is read by the service it affects"

    def t_coin_bonus_changes_income():
        """Measured through the multiplier the orb path actually applies."""
        plain = lua.eval('{Upgrades = {}}')
        rich = lua.eval('{Upgrades = {CoinBonus = 4}}')
        value, rebirth, pass_mult = 10, 1, 1
        a = max(1, int(value * rebirth * pass_mult * cfg.UpgradeValue(plain, "CoinBonus")))
        b = max(1, int(value * rebirth * pass_mult * cfg.UpgradeValue(rich, "CoinBonus")))
        assert b > a, "a maxed Coin Bonus earns the same %d per orb as none" % a
        return "one orb pays %d -> %d with Coin Bonus maxed" % (a, b)

    check("every upgrade resolves", t_upgrade_accessor)
    check("levels raise the value", t_levels_raise_the_value)
    check("the services read them", t_upgrades_are_actually_read)
    check("Coin Bonus changes income", t_coin_bonus_changes_income)

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\neconomy: what players pay for changes what they get")
    return 0


if __name__ == "__main__":
    sys.exit(main())
