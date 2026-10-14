#!/usr/bin/env python3
"""Quests: the daily roll, and the rebirth bug that ate progress.

Two things are being proved here, and the first one is a bug that shipped.

REBIRTH USED TO UNDO QUESTS. Rebirth sets TotalCoinsEarned to 0 and
UnlockedAreas back to { Meadow }. Four of the nine milestones read those
counters directly, so rebirthing silently reset them: "Unlock all worlds" (400
gems) could not be finished again until every world had been bought back, and
900k of a 1,000,000-coin quest went to zero with nothing said. Rebirth is the
game's main long-term goal; reaching it should not cost the rewards for
reaching it.

THE DAILY ROLL HAS TO AGREE ACROSS SERVERS. Each server runs its own copy of
this code with its own RNG. A roll that was not a pure function of (player,
day) would hand a player a different set of quests on every server — and with
them a fresh set of unclaimed rewards, three at a time, as fast as they could
hop.

Also checked, because the owner asked for the game to be harder rather than
more generous: a player who does nothing can claim nothing.
"""
import sys
from pathlib import Path

try:
    import lupa
except ImportError:
    sys.exit("lupa is not installed (pip install lupa)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import check_map  # noqa: E402

FAILURES = []


def check(label, fn):
    try:
        detail = fn()
        print("   ok  %-38s %s" % (label, detail or ""))
    except AssertionError as e:
        print("   x   %-38s %s" % (label, e))
        FAILURES.append(label)
    except Exception as e:  # noqa: BLE001
        print("   x   %-38s crashed: %r" % (label, e))
        FAILURES.append(label)


class Game:
    """The real server, booted, with a controllable clock."""

    def __init__(self):
        self.lua, self.mock, self.cfg = check_map.build()
        sss = self.mock["ServerScriptService"]
        self.holder = sss["FindFirstChild"](sss, "Server", True)
        # os.time is what decides which day it is. Freezing it is the only way
        # to test "tomorrow" without waiting for it.
        self.lua.execute("""
            local real = os.time
            FAKE_NOW = real()
            os.time = function() return FAKE_NOW end
        """)
        self.players = 0

    def mod(self, name):
        m = self.holder["FindFirstChild"](self.holder, name)
        return self.mock["MODULES"][m]

    def advance_days(self, n):
        self.lua.execute("FAKE_NOW = FAKE_NOW + %d" % (n * 86400))

    def join(self, user_id=4242, name="Tester"):
        p = self.mock["newInst"]("Player")
        p.Name = name
        p.UserId = user_id
        self.players += 1
        self.mock["PlayerList"][self.players] = p
        res = self.mod("DataManager").LoadPlayer(p)
        data = res[0] if isinstance(res, tuple) else res
        assert data is not None, "the player could not be loaded"
        return p, data


def lua_list(t):
    out, i = [], 1
    while t[i] is not None:
        out.append(t[i])
        i += 1
    return out


def quests(game, player):
    return lua_list(game.mod("QuestService").GetAll(player))


def by_id(rows, qid):
    for q in rows:
        if str(q.id) == qid:
            return q
    return None


def dailies(rows):
    return [q for q in rows if str(q.kind) == "daily"]


def unwrap(r):
    if isinstance(r, tuple):
        return r[0], (r[1] if len(r) > 1 else None)
    return r, None


# ------------------------------------------------------------------
# rebirth
# ------------------------------------------------------------------
def t_rebirth_keeps_progress():
    g = Game()
    p, data = g.join()
    data.TotalCoinsEarned = 900000
    data.Coins = 900000

    before = by_id(quests(g, p), "coins1m")
    assert before is not None, "the coins1m quest is gone from the config"
    assert int(before.progress) == 900000, \
        "progress read %s, not the 900,000 earned" % before.progress

    # Enough to rebirth, then do it.
    data.TotalCoinsEarned = 1e9
    ok, _ = unwrap(g.mod("RebirthService").DoRebirth(p))
    assert ok, "the rebirth itself failed, so this proves nothing"
    assert float(data.TotalCoinsEarned) == 0, \
        "rebirth no longer resets TotalCoinsEarned, so this check is vacuous"

    after = by_id(quests(g, p), "coins1m")
    assert int(after.progress) >= 900000, \
        "rebirth erased quest progress: %s left of 900,000" % after.progress
    return "kept %s coins of progress through a rebirth" % int(after.progress)


def t_rebirth_without_opening_the_panel():
    """The gap case: earn, rebirth, and never look at quests in between."""
    g = Game()
    p, data = g.join()
    quests(g, p)                      # a first look, so a baseline exists
    data.TotalCoinsEarned = 750000    # earned entirely between polls
    data.Coins = 750000

    data.TotalCoinsEarned = 1e9
    ok, _ = unwrap(g.mod("RebirthService").DoRebirth(p))
    assert ok, "the rebirth failed"

    after = by_id(quests(g, p), "coins1m")
    assert int(after.progress) >= 750000, \
        "earnings between two polls were lost at rebirth: %s" % after.progress
    return "banked at the rebirth, not at the next poll"


def t_worlds_quest_survives_rebirth():
    g = Game()
    p, data = g.join()
    data.UnlockedAreas = g.lua.eval(
        '{"Meadow","Forest","Desert","Volcano","Space"}')
    done = by_id(quests(g, p), "unlock5")
    assert bool(done.done), "unlocking every world did not finish unlock5"

    data.TotalCoinsEarned = 1e9
    unwrap(g.mod("RebirthService").DoRebirth(p))
    assert len(lua_list(data.UnlockedAreas)) == 1, \
        "rebirth no longer resets UnlockedAreas; this check is vacuous"

    after = by_id(quests(g, p), "unlock5")
    assert bool(after.done), \
        "'Unlock all worlds' came undone at rebirth — 400 gems, unreachable " \
        "until every world is bought again"
    return "unlock5 stays finished"


def t_equip_quest_is_a_peak_not_a_count():
    g = Game()
    p, data = g.join()
    data.EquippedPets = g.lua.eval('{"a","b","c"}')
    assert bool(by_id(quests(g, p), "equip3").done), "equipping 3 did not count"
    data.EquippedPets = g.lua.eval("{}")
    assert bool(by_id(quests(g, p), "equip3").done), \
        "unequipping undid a quest that asks whether you ever had 3 equipped"

    # And the other direction: one pet equipped and unequipped repeatedly must
    # never add up to three.
    g2 = Game()
    p2, d2 = g2.join()
    for _ in range(8):
        d2.EquippedPets = g2.lua.eval('{"a"}')
        quests(g2, p2)
        d2.EquippedPets = g2.lua.eval("{}")
        quests(g2, p2)
    assert not bool(by_id(quests(g2, p2), "equip3").done), \
        "equipping one pet eight times finished 'equip 3 pets at once'"
    return "peak, not a running total"


# ------------------------------------------------------------------
# dailies
# ------------------------------------------------------------------
def t_same_set_on_every_server():
    a, b = Game(), Game()
    # Same clock on both, as two live servers would have.
    b.lua.execute("FAKE_NOW = %d" % int(a.lua.globals().FAKE_NOW))
    # Different RNG state on each, which is the whole point.
    #
    # Two live Roblox servers are separate processes with separate math.random
    # streams; two Lua runtimes in one test process are not, and can happen to
    # agree. Seeding them apart — and burning a different number of draws on
    # each — makes an implementation that reaches for math.random produce
    # visibly different sets, instead of passing by luck.
    a.lua.execute("math.randomseed(1234) for _ = 1, 3 do math.random() end")
    b.lua.execute("math.randomseed(98765) for _ = 1, 29 do math.random() end")
    pa, _ = a.join(user_id=777)
    pb, _ = b.join(user_id=777)
    ids_a = [str(q.id) for q in dailies(quests(a, pa))]
    ids_b = [str(q.id) for q in dailies(quests(b, pb))]
    assert ids_a, "no daily quests were handed out at all"
    assert ids_a == ids_b, \
        "two servers rolled different sets (%s vs %s) — hopping servers would " \
        "hand out fresh claims" % (ids_a, ids_b)

    # And a different player should not simply get the same three.
    pc, _ = a.join(user_id=90210, name="Other")
    ids_c = [str(q.id) for q in dailies(quests(a, pc))]
    same = ids_c == ids_a
    return "%d quests, identical across servers%s" % (
        len(ids_a), "" if not same else " (note: same set for another player)")


def t_set_changes_tomorrow():
    g = Game()
    p, _ = g.join(user_id=555)
    today = [str(q.id) for q in dailies(quests(g, p))]
    seen = {tuple(today)}
    for d in range(1, 8):
        g.advance_days(1)
        seen.add(tuple(str(q.id) for q in dailies(quests(g, p))))
    assert len(seen) > 1, \
        "the same three quests came back every day for a week — the roll does " \
        "not depend on the day"
    return "%d different sets across 8 days" % len(seen)


def t_progress_is_todays_only():
    g = Game()
    p, data = g.join()
    data.EggsHatched = 10000          # a long-standing player
    rows = dailies(quests(g, p))
    for q in rows:
        assert int(q.progress) == 0, \
            "%s started at %s/%s on a lifetime counter" % (q.id, q.progress, q.goal)
        assert not bool(q.done), "%s was already complete on arrival" % q.id
    return "%d dailies all start at zero" % len(rows)


def t_nothing_for_doing_nothing():
    """The owner asked for harder, not more generous. No login reward."""
    g = Game()
    p, _ = g.join()
    rows = dailies(quests(g, p))
    assert rows, "no dailies to check"
    for q in rows:
        ok, err = unwrap(g.mod("QuestService").Claim(p, str(q.id)))
        assert not ok, "%s paid out without being played for" % q.id
        assert "not complete" in str(err), err
    return "all %d refused" % len(rows)


def t_claim_pays_once():
    g = Game()
    p, data = g.join()
    row = None
    for q in dailies(quests(g, p)):
        if str(q.desc).startswith("Hatch") or "coins" in str(q.id):
            row = q
            break
    row = row or dailies(quests(g, p))[0]

    kind = str(row.id)
    # Push the underlying counter past the goal.
    goal = int(row.goal)
    if kind.startswith("d_hatch"):
        data.EggsHatched = (data.EggsHatched or 0) + goal
    elif kind.startswith("d_coins"):
        data.TotalCoinsEarned = (data.TotalCoinsEarned or 0) + goal
    elif kind.startswith("d_fuse"):
        data.PetsFused = (data.PetsFused or 0) + goal
    elif kind.startswith("d_spin"):
        data.SpinsUsed = (data.SpinsUsed or 0) + goal

    fresh = by_id(quests(g, p), kind)
    assert bool(fresh.done), "%s did not complete after %d of its counter" % (kind, goal)

    coins_before, gems_before = float(data.Coins or 0), float(data.Gems or 0)
    ok, _ = unwrap(g.mod("QuestService").Claim(p, kind))
    assert ok, "a finished daily could not be claimed"
    gained = (float(data.Coins) - coins_before) + (float(data.Gems) - gems_before)
    assert gained > 0, "claiming paid nothing"

    ok2, err2 = unwrap(g.mod("QuestService").Claim(p, kind))
    assert not ok2, "the same daily paid out twice"
    assert "already" in str(err2), err2

    after = by_id(quests(g, p), kind)
    assert bool(after.claimed), "the claim did not stick"
    return "%s paid %s once, refused twice" % (kind, int(gained))


def t_one_quest_per_type():
    g = Game()
    seen_types = []
    for uid in (1, 2, 3, 101, 555, 90210, 123456):
        p, _ = g.join(user_id=uid, name="U%d" % uid)
        ids = [str(q.id) for q in dailies(quests(g, p))]
        kinds = [i.split("_")[1].rstrip("0123456789").rstrip("k") for i in ids]
        assert len(kinds) == len(set(kinds)), \
            "player %d got two quests of the same type: %s" % (uid, ids)
        seen_types.append(tuple(kinds))
    return "%d players, no repeated type" % len(seen_types)


def t_yesterdays_claim_does_not_block_today():
    g = Game()
    p, data = g.join(user_id=31337)
    row = dailies(quests(g, p))[0]
    kind = str(row.id)
    if kind.startswith("d_hatch"):
        data.EggsHatched = (data.EggsHatched or 0) + int(row.goal)
    elif kind.startswith("d_coins"):
        data.TotalCoinsEarned = (data.TotalCoinsEarned or 0) + int(row.goal)
    elif kind.startswith("d_fuse"):
        data.PetsFused = (data.PetsFused or 0) + int(row.goal)
    else:
        data.SpinsUsed = (data.SpinsUsed or 0) + int(row.goal)
    ok, _ = unwrap(g.mod("QuestService").Claim(p, kind))
    assert ok, "could not claim today's"

    g.advance_days(1)
    rows = dailies(quests(g, p))
    assert rows, "no dailies tomorrow"
    for q in rows:
        assert not bool(q.claimed), \
            "%s came back already claimed — yesterday's claim carried over" % q.id
        assert int(q.progress) == 0, \
            "%s carried yesterday's progress into today (%s)" % (q.id, q.progress)
    return "fresh set, nothing carried over"


def main():
    print("Quests:")
    check("rebirth keeps quest progress", t_rebirth_keeps_progress)
    check("progress banked at the rebirth", t_rebirth_without_opening_the_panel)
    check("'unlock all worlds' survives", t_worlds_quest_survives_rebirth)
    check("equip quest is a peak", t_equip_quest_is_a_peak_not_a_count)
    check("same daily set on every server", t_same_set_on_every_server)
    check("the set changes each day", t_set_changes_tomorrow)
    check("dailies measure today only", t_progress_is_todays_only)
    check("nothing paid for doing nothing", t_nothing_for_doing_nothing)
    check("a daily pays exactly once", t_claim_pays_once)
    check("one quest per type per day", t_one_quest_per_type)
    check("tomorrow starts clean", t_yesterdays_claim_does_not_block_today)

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\nquests: dailies roll the same everywhere, and rebirth costs nothing")
    return 0


if __name__ == "__main__":
    sys.exit(main())
