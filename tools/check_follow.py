#!/usr/bin/env python3
"""Pets follow their owners on each client, and the server never moves them.

The server used to PivotTo every equipped pet on every Heartbeat. A pet is an
anchored model of up to thirty parts; every part's CFrame was replicated to
every player, sixty times a second — over fifty thousand updates a second to
each client on a busy server. Roblox throttles that, so pets arrived late and
in steps, and a player's own pets trailed them by a full round trip.

  SERVER   places a pet once, behind its owner, and never moves it again
  CLIENT   moves every pet, for every owner, toward its place each frame:
           your pets follow you, theirs follow them, a teleport is a jump not
           a flight across the map, a pet that is removed is simply dropped,
           and pets far from the camera cost nothing
"""
import sys
from pathlib import Path

try:
    import lupa  # noqa: F401
except ImportError:
    sys.exit("lupa is not installed (pip install lupa)")

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
import check_client  # noqa: E402
import check_session  # noqa: E402

FAILURES = []


def check(label, fn):
    try:
        print("   ok  %-36s %s" % (label, fn() or ""))
    except AssertionError as e:
        print("   x   %-36s %s" % (label, e))
        FAILURES.append(label)
    except Exception as e:  # noqa: BLE001
        print("   x   %-36s crashed: %r" % (label, e))
        FAILURES.append(label)


def xyz(cf):
    p = cf.Position
    return (float(p.X), float(p.Y), float(p.Z))


def dist(a, b):
    return sum((a[i] - b[i]) ** 2 for i in range(3)) ** 0.5


# ---------------------------------------------------------------- server
def server_half():
    print("server:")
    srv = check_session.Server()
    lua = srv.lua
    PS = srv.mod("PetService")
    alice, _ = srv.join(7001, "Alice")
    root = alice.Character["FindFirstChild"](alice.Character, "HumanoidRootPart")
    start = xyz(root.CFrame)
    for i in range(3):
        PS.GrantPet(alice, lua.eval(
            '{name="cat", rarity="Common", uniqueId="a-%d"}' % i))
        PS.EquipPet(alice, "a-%d" % i)
    folder = lua.eval('workspace.Pets["7001"]')
    models = list(folder["GetChildren"](folder).values()) if folder else []

    def t_spawned_behind():
        assert len(models) == 3, "three equipped pets made %d models" % len(models)
        off = [round(dist(xyz(m["GetPivot"](m)), start), 1) for m in models]
        bad = [d for d in off if not 2 <= d <= 8]
        assert not bad, ("pets spawned %s studs from their owner — inside them, "
                         "or nowhere near" % off)
        return "3 pets placed %s studs behind the owner" % off

    def t_server_moves_nothing():
        before = [xyz(m["GetPivot"](m)) for m in models]
        root.CFrame = lua.eval("CFrame.new(80, 5, -60)")
        fire = lua.eval("function(rs) rs.Heartbeat:Fire(1/60) end")
        rs = lua.eval('game:GetService("RunService")')
        for _ in range(120):
            fire(rs)
        after = [xyz(m["GetPivot"](m)) for m in models]
        moved = sum(1 for a, b in zip(before, after) if dist(a, b) > 1e-6)
        assert moved == 0, ("the server moved %d pet(s) over 120 Heartbeats — "
                            "every part of every one is replicated to every "
                            "player, every frame" % moved)
        return "owner walked 100 studs, 120 Heartbeats, 0 pets moved"

    check("a pet spawns behind its owner", t_spawned_behind)
    check("the server never moves a pet", t_server_moves_nothing)


# ---------------------------------------------------------------- client
def client_half():
    lua, mock, gui, _ = check_client.boot()
    print("\nclient:")
    me = mock["Players"].LocalPlayer
    my_root = me.Character["FindFirstChild"](me.Character, "HumanoidRootPart")

    # Someone else, standing elsewhere.
    other = mock["newInst"]("Player"); other.Name = "Other"; other.UserId = 8888
    oc = mock["newInst"]("Model"); oc.Name = "Other"
    o_root = mock["newInst"]("Part"); o_root.Name = "HumanoidRootPart"; o_root.Parent = oc
    o_root.CFrame = lua.eval("CFrame.new(60, 5, 0)")
    other.Character = oc
    mock["PlayerList"][2] = other

    pets = lua.eval("workspace.Pets")
    assert pets is not None, "the server made no workspace.Pets"

    def make(owner_id, n, at):
        f = mock["newInst"]("Folder"); f.Name = str(owner_id); f.Parent = pets
        out = []
        for i in range(n):
            m = mock["newInst"]("Model"); m.Name = "cat_%d_%d" % (owner_id, i)
            body = mock["newInst"]("Part"); body.Name = "HumanoidRootPart"; body.Parent = m
            m.PrimaryPart = body
            m["PivotTo"](m, lua.eval("CFrame.new(%f, %f, %f)" % at))
            m.Parent = f
            out.append(m)
        return f, out

    _, mine = make(7777, 3, (0, 5, 0))
    _, theirs = make(8888, 2, (60, 5, 0))

    rs = lua.eval('game:GetService("RunService")')
    step = lua.eval("function(rs, n) for _ = 1, n do rs.RenderStepped:Fire(1/60) end end")
    cam_at = lua.eval("""function(x, y, z)
        local cam = workspace.CurrentCamera or Instance.new("Camera")
        cam.CFrame = CFrame.new(x, y, z)
        workspace.CurrentCamera = cam
    end""")

    def near_owner(models, root_cf, lo=2.5, hi=6.5):
        r = xyz(root_cf)
        return [round(dist(xyz(m["GetPivot"](m)), r), 1) for m in models], \
            all(lo <= dist(xyz(m["GetPivot"](m)), r) <= hi for m in models)

    def t_mine_follow_me():
        cam_at(0, 20, 30)
        my_root.CFrame = lua.eval("CFrame.new(30, 5, 0)")
        step(rs, 180)
        d, ok = near_owner(mine, my_root.CFrame)
        assert ok, "after 3 s your pets are %s studs from you" % d
        return "walked 30 studs; pets %s studs behind" % d

    def t_places_kept():
        ps = [xyz(m["GetPivot"](m)) for m in mine]
        gaps = [dist(ps[i], ps[j]) for i in range(3) for j in range(i + 1, 3)]
        assert min(gaps) > 1.0, ("pets are stacked on one another (closest pair "
                                 "%.2f studs apart)" % min(gaps))
        return "closest pair %.1f studs apart" % min(gaps)

    def t_theirs_follow_them():
        d, ok = near_owner(theirs, o_root.CFrame)
        assert ok, "another player's pets are %s studs from their owner" % d
        mine_d = [dist(xyz(m["GetPivot"](m)), xyz(my_root.CFrame)) for m in theirs]
        assert min(mine_d) > 10, "another player's pets are following YOU"
        return "their pets %s studs from them, not you" % d

    def t_teleport_jumps():
        my_root.CFrame = lua.eval("CFrame.new(900, 5, 400)")
        cam_at(900, 20, 430)
        step(rs, 1)
        d, ok = near_owner(mine, my_root.CFrame, 0, 8)
        assert ok, ("one frame after a teleport your pets are %s studs away — "
                    "flying across the map" % d)
        return "one frame later: %s studs" % d

    def t_removed_pet_dropped():
        gone = mine.pop()
        gone["Destroy"](gone)
        step(rs, 120)
        d, ok = near_owner(mine, my_root.CFrame)
        assert ok, "after one pet was removed the others are %s studs away" % d
        return "removed one; the other two carry on (%s)" % d

    def t_far_pets_cost_nothing():
        cam_at(-3000, 20, -3000)
        before = [xyz(m["GetPivot"](m)) for m in theirs]
        o_root.CFrame = lua.eval("CFrame.new(70, 5, 10)")
        step(rs, 30)
        after = [xyz(m["GetPivot"](m)) for m in theirs]
        moved = sum(1 for a, b in zip(before, after) if dist(a, b) > 1e-6)
        assert moved == 0, "%d pets 3,000 studs from the camera were still moved" % moved
        cam_at(70, 20, 40)
        step(rs, 120)
        d, ok = near_owner(theirs, o_root.CFrame)
        assert ok, "pets did not resume once back in view (%s)" % d
        return "skipped while out of range, resumed in view"

    check("your pets follow you", t_mine_follow_me)
    check("each pet keeps its own place", t_places_kept)
    check("their pets follow them", t_theirs_follow_them)
    check("a teleport is a jump", t_teleport_jumps)
    check("a removed pet is dropped", t_removed_pet_dropped)
    check("far pets cost nothing", t_far_pets_cost_nothing)


def main():
    server_half()
    client_half()
    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\npet follow: smooth on every screen, nothing on the wire")
    return 0


if __name__ == "__main__":
    sys.exit(main())
