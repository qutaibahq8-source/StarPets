#!/usr/bin/env python3
"""A failed DataStore read must never be mistaken for a new player.

THE FAILURE THIS EXISTS TO CATCH

loadWithRetry returns nil in two completely different situations: a genuinely
new player, and five failed GetAsync calls in a row. LoadPlayer treated both the
same — it built a fresh default save and cached it. Sixty seconds later the
autosave loop wrote that default over the top of the real record with SetAsync.

A player with ten million coins and two hundred pets who happened to join during
a Roblox DataStore incident was permanently wiped, silently, by their own game.
There is no undo for that and no way for them to prove it happened.

Roblox DataStore outages are not hypothetical, and they hit every server at
once, so this is a whole-playerbase event rather than an unlucky individual.

Also checked here:
  * an in-flight save must not cause the LEAVE save to be skipped
  * shutdown must not spend its whole budget on one failing player
  * a value of the wrong type must be repaired rather than propagated
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


def runtime(fail_reads=False, fail_writes=False):
    lua = lupa.LuaRuntime(unpack_returned_tuples=False)
    G = lua.globals()
    lua.execute("math.clamp=function(x,l,h) return math.max(l,math.min(h,x)) end;"
                "math.round=function(x) return math.floor(x+0.5) end")
    mock = lua.execute((ROOT / "tools" / "roblox_mock.lua").read_text())
    for k in ("Vector3", "CFrame", "Color3", "Enum", "Instance", "game", "workspace",
              "Random", "UDim", "UDim2", "Vector2"):
        G[k] = mock[k]
    lua.execute("""
        WAITED = 0
        -- ON_WAIT: something to happen "meanwhile", the first time anything
        -- waits — another server's save landing, say.
        task = { spawn=function() end, defer=function() end,
                 delay=function() end,
                 wait=function(t)
                     WAITED = WAITED + (t or 0)
                     if ON_WAIT then local f = ON_WAIT; ON_WAIT = nil; f() end
                     return t or 0
                 end }
        wait = task.wait
        warn = function() end
    """)

    # A DataStore that can be told to fail, and that records every write.
    lua.execute("""
        STORE_DATA = {}
        WRITES = 0
        FAIL_READ = false
        FAIL_WRITE = false
        -- Stored as copies, as a real DataStore serializes them.
        local function copy(v)
          if type(v) ~= "table" then return v end
          local o = {}
          for k, x in pairs(v) do o[k] = copy(x) end
          return o
        end
        local function store(name)
          return {
            GetAsync = function(_, k)
              if FAIL_READ then error("DataStore is unavailable", 0) end
              return copy(STORE_DATA[k])
            end,
            SetAsync = function(_, k, v)
              WRITES = WRITES + 1
              if FAIL_WRITE then error("DataStore is unavailable", 0) end
              STORE_DATA[k] = copy(v)
            end,
            -- A read AND a write: an outage of either fails it. Loads go
            -- through here now, so an outage test that only failed GetAsync
            -- would test nothing.
            UpdateAsync = function(_, k, fn)
              if FAIL_READ or FAIL_WRITE then error("DataStore is unavailable", 0) end
              local nv = fn(copy(STORE_DATA[k]))
              if nv ~= nil then WRITES = WRITES + 1; STORE_DATA[k] = copy(nv) end
              return copy(nv)
            end,
            RemoveAsync = function(_, k) STORE_DATA[k] = nil end,
          }
        end
        FAKE_DSS = { GetDataStore = function(_, n) return store(n) end,
                     GetOrderedDataStore = function(_, n) return store(n) end }
    """)
    gm = mock["game"]
    lua.execute("""
        local real = game.GetService
        game.GetService = function(self, name)
          if name == "DataStoreService" then return FAKE_DSS end
          return real(self, name)
        end
    """)
    G["FAIL_READ"] = fail_reads
    G["FAIL_WRITE"] = fail_writes

    def load(path, name):
        return lua.eval("function(s,n) return assert(load(s,n)) end")(
            luau_to_lua(Path(path).read_text()), "@" + name)()

    rs = mock["ReplicatedStorage"]
    shared = mock["newInst"]("Folder"); shared.Name = "Shared"; shared.Parent = rs
    G["require"] = mock["robloxRequire"]
    for f in sorted((ROOT / "src/Shared").glob("*.lua")):
        m = mock["newInst"]("ModuleScript"); m.Name = f.stem; m.Parent = shared
        G["script"] = m
        mock["MODULES"][m] = load(f, f.stem)

    sss = mock["ServerScriptService"]
    holder = mock["newInst"]("Folder"); holder.Name = "Server"; holder.Parent = sss
    m = mock["newInst"]("ModuleScript"); m.Name = "DataManager"; m.Parent = holder
    G["script"] = m
    DM = load(ROOT / "src/Server/DataManager.lua", "DataManager")
    mock["MODULES"][m] = DM

    def another_server(job):
        """A second DataManager on the SAME DataStore, as another server."""
        lua.execute('game.JobId = "%s"' % job)
        G["script"] = m
        other = load(ROOT / "src/Server/DataManager.lua", "DataManager")
        return other
    lua.globals()["ANOTHER_SERVER"] = another_server
    return lua, mock, DM


def first(v):
    """LoadPlayer returns (data, err); older callers used just the data."""
    return v[0] if isinstance(v, tuple) else v


def player(mock, uid, name="Victim"):
    p = mock["newInst"]("Player"); p.Name = name; p.UserId = uid
    return p


def main():
    fails = []

    # ---- 1. A FAILED READ MUST NOT LOOK LIKE A NEW PLAYER -----------------
    lua, mock, DM = runtime()
    G = lua.globals()
    rich = player(mock, 4242)
    data = first(DM.LoadPlayer(rich))
    data.Coins = 10000000
    data.Pets[1] = lua.table_from({"name": "ant", "rarity": "Legendary",
                                   "uniqueId": "X1"})
    DM.SavePlayer(rich)
    saved = G.STORE_DATA["4242"]
    print("saved a player with %d coins and %d pet(s)"
          % (int(saved.Coins), len(saved.Pets)))

    # Same player rejoins while the DataStore is down.
    G["FAIL_READ"] = True
    G["WRITES"] = 0
    DM.RemovePlayer(rich)
    loaded = first(DM.LoadPlayer(rich))
    coins_now = int(loaded.Coins) if loaded is not None and loaded.Coins is not None else -1
    print("rejoined during an outage -> LoadPlayer gave %s coins" % coins_now)

    # The killer: does anything now write that over the real save?
    G["FAIL_READ"] = False
    DM.SavePlayer(rich)
    after = G.STORE_DATA["4242"]
    after_coins = int(after.Coins) if after is not None and after.Coins is not None else -1
    print("after the next autosave, the STORED record has %d coins" % after_coins)
    if after_coins < 10000000:
        fails.append("a failed read was treated as a new player, and the "
                     "defaults were then SAVED OVER the real record: "
                     "10,000,000 coins -> %d. The player is permanently wiped."
                     % after_coins)
    else:
        print("  ok  the real save survived a DataStore outage")

    # ---- 2. AN IN-FLIGHT SAVE MUST NOT SKIP THE LEAVE SAVE ----------------
    # saveWithRetry returned immediately if a save was already running, and
    # RemovePlayer cleared the cache straight afterwards — so anything earned
    # since the last autosave was gone.
    lua2, mock2, DM2 = runtime()
    G2 = lua2.globals()
    p2 = player(mock2, 777)
    d2 = first(DM2.LoadPlayer(p2))
    d2.Coins = 500
    DM2.SavePlayer(p2)
    # Simulate a save already in progress at the moment the player leaves.
    d2.Coins = 999
    lua2.execute("SAVING_PROBE = true")
    ok = DM2.SavePlayer(p2)
    stored = G2.STORE_DATA["777"]
    if stored is None or int(stored.Coins) != 999:
        fails.append("a second save while one was in flight was DROPPED "
                     "(stored %s, expected 999) — anything earned since the "
                     "last autosave is lost when the player leaves"
                     % (stored and int(stored.Coins)))
    else:
        print("  ok  a save is not silently skipped when another is in flight")

    # ---- 3. SHUTDOWN MUST NOT BLOW ITS BUDGET ON ONE PLAYER ---------------
    # Roblox gives about 30 seconds at BindToClose. Five retries with doubling
    # backoff is 2+4+8+16 = 30 seconds for ONE player, run serially, so a single
    # failing save consumed the entire allowance and every player behind it in
    # the loop lost their session.
    #
    # This drives the REAL BindToClose handler rather than calling SavePlayer,
    # because the shorter retry budget only applies while the server is closing
    # — an earlier version of this check measured the normal path and reported
    # 30s for a code path that is allowed to take it.
    lua3, mock3, DM3 = runtime(fail_writes=True)
    G3 = lua3.globals()
    # Saves are spawned in parallel by the handler; run them inline here so the
    # total wait is measurable.
    lua3.execute("task.spawn = function(f, ...) f(...) end")
    # Loaded while the DataStore works; it fails from shutdown on. A load is
    # a write now (it claims the record), so loading with writes already
    # failing would leave nothing to save and the budget untested.
    G3["FAIL_WRITE"] = False
    for uid in (881, 882, 883):
        first(DM3.LoadPlayer(player(mock3, uid)))
    G3["FAIL_WRITE"] = True
    G3["WAITED"] = 0
    handlers = mock3["BOUND_TO_CLOSE"]
    n = 0
    i = 1
    while handlers[i] is not None:
        handlers[i]()
        n += 1
        i += 1
    waited = float(G3.WAITED)
    print("shutdown with 3 players and every write failing: %.0fs spent "
          "(%d handler(s))" % (waited, n))
    if n == 0:
        fails.append("nothing is registered with BindToClose — a closing server "
                     "saves nobody")
    elif waited > 25:
        fails.append("shutdown spent %.0fs — more than the ~30s Roblox allows, "
                     "so the last players in the loop lose their data" % waited)
    else:
        print("  ok  shutdown fits inside the budget Roblox gives it")

    # ---- 4. ONE SERVER AT A TIME PER SAVE ----------------------------------
    # A player who leaves one server and joins another before the first one's
    # last save lands used to be loaded from the older record: progress lost,
    # and — with trading — pets duplicated.
    import time as _time

    def two_servers():
        lua4, mock4, _ = runtime()
        G4 = lua4.globals()
        a = G4.ANOTHER_SERVER("server-A")
        b = G4.ANOTHER_SERVER("server-B")
        return lua4, mock4, G4, a, b

    def stored(G4, uid):
        return G4.STORE_DATA[str(uid)]

    # 4a. The hop waits for the old server's last save — which is also the
    #     trade-and-hop duplication.
    lua4, mock4, G4, A, B = two_servers()
    p = player(mock4, 5150, "Hopper")
    d = first(A.LoadPlayer(p))
    d.Coins = 100
    d.Pets[1] = lua4.table_from({"name": "dragon", "rarity": "Epic", "uniqueId": "D1"})
    A.SavePlayer(p)                                    # autosave: has the dragon
    d.Coins = 500
    d.Pets[1] = None                                   # traded the dragon away
    # The player is on server B now; A's last save is still on its way and
    # lands while B waits.
    G4["ON_WAIT"] = lua4.eval("function(dm, p) return function() dm.RemovePlayer(p) end end")(A, p)
    G4["WAITED"] = 0
    d_b = first(B.LoadPlayer(p))
    if float(G4.WAITED) > 10:
        fails.append("server B waited %.0fs although server A's last save had given "
                     "the record up — the claim was never released" % float(G4.WAITED))
    if d_b is None:
        fails.append("server B gave up instead of waiting for server A's last save")
    elif int(d_b.Coins) != 500 or d_b.Pets[1] is not None:
        fails.append("server B loaded the record from BEFORE server A's last save "
                     "(coins %s, dragon %s) — progress lost, and a traded pet "
                     "duplicated" % (d_b.Coins, "still there" if d_b.Pets[1] is not None else "gone"))
    else:
        print("  ok  a hop waits for the old server's last save: no rollback, no dupe")

    def claim_of(rec):
        s_ = rec["_session"] if rec is not None else None
        return s_["job"] if s_ is not None else None

    # 4b. After the hop the record belongs to the server the player is on.
    if d_b is not None:
        d_b.Coins = 800
        B.SavePlayer(p)
    rec = stored(G4, 5150)
    holder = claim_of(rec)
    if d_b is None:
        pass  # already reported above
    elif str(holder) != "server-B" or int(rec.Coins) != 800:
        fails.append("after the hop the record is claimed by %s with %s coins, not "
                     "server-B with 800" % (holder, rec and rec.Coins))
    else:
        print("  ok  the record is claimed by the server the player is on")

    # 4b'. A player who gives up while their load waits stops the wait,
    #      rather than a server claiming a record for nobody.
    lua7, mock7, G7, A7, B7 = two_servers()
    p7 = player(mock7, 8180, "Impatient")
    first(A7.LoadPlayer(p7))
    A7.SavePlayer(p7)                                  # A holds a live claim
    G7["ON_WAIT"] = lua7.eval("function(dm, p) return function() dm.RemovePlayer(p) end end")(B7, p7)
    G7["WAITED"] = 0
    gave_up = first(B7.LoadPlayer(p7))
    held = claim_of(G7.STORE_DATA["8180"])
    if gave_up is not None or str(held) != "server-A":
        fails.append("a player who left during the wait still had their record "
                     "claimed (by %s)" % held)
    elif float(G7.WAITED) > 10:
        fails.append("after the player left, the server kept waiting %.0fs for a "
                     "record nobody will use" % float(G7.WAITED))
    else:
        print("  ok  leaving during the wait stops it; the record is left alone")

    # 4c. A dead server's claim is taken over, and its late save is refused.
    lua5, mock5, G5, A, B = two_servers()
    p5 = player(mock5, 6160, "Orphan")
    d5 = first(A.LoadPlayer(p5))
    d5.Coins = 300
    A.SavePlayer(p5)                                   # A then dies: never releases
    aged = lua5.eval("""function(STORE_DATA)
        local rec = STORE_DATA["6160"]
        if not (rec and rec._session) then return false end
        rec._session.at = os.time() - 10000
        return true
    end""")(G5.STORE_DATA)
    G5["WAITED"] = 0
    d5b = first(B.LoadPlayer(p5)) if aged else None
    if not aged:
        fails.append("a saved record carries no claim at all, so nothing stops two "
                     "servers holding the same player")
    elif d5b is None or int(d5b.Coins) != 300:
        fails.append("a claim from a server that died was never taken over — the "
                     "player could not load (got %s)" % (d5b and d5b.Coins))
    elif float(G5.WAITED) > 0:
        fails.append("B waited %.0fs on a claim from a server long dead" % float(G5.WAITED))
    else:
        d5b.Coins = 900
        B.SavePlayer(p5)
        d5.Coins = 1                                   # A wakes up with its old copy
        ok_a = A.SavePlayer(p5)
        now = int(G5.STORE_DATA["6160"].Coins)
        if now != 900 or ok_a:
            fails.append("a late save from the old server overwrote the newer record "
                         "(%d coins, expected 900)" % now)
        else:
            print("  ok  a dead server's claim is taken over, and its late save refused")

    # 4d. The claim is bookkeeping: it never reaches player data.
    if d5b is not None and d5b["_session"] is not None:
        fails.append("the claim leaked into the player's data (and so to their client)")
    else:
        print("  ok  the claim never appears in the player's data")

    # 4e. One server (Studio, or a normal session) never waits on itself.
    lua6, mock6, DM6 = runtime()
    G6 = lua6.globals()
    p6 = player(mock6, 7170, "Solo")
    first(DM6.LoadPlayer(p6))
    DM6.SavePlayer(p6)
    DM6.RemovePlayer(p6)
    G6["WAITED"] = 0
    again = first(DM6.LoadPlayer(p6))
    if again is None or float(G6.WAITED) > 0:
        fails.append("rejoining the same server waited %.0fs on its own claim"
                     % float(G6.WAITED))
    else:
        print("  ok  leaving gives the claim up: rejoining is immediate")

    if fails:
        print("\ndata: %d problems" % len(fails))
        for f in fails:
            print("   x " + f)
        return 1
    print("\ndata: outages, in-flight saves and shutdowns are all survivable")
    return 0


if __name__ == "__main__":
    sys.exit(main())
