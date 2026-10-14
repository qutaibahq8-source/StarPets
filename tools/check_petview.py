#!/usr/bin/env python3
"""The inventory and the Pet Index show pets, not letters and coloured discs.

Every place the UI drew a pet drew something else:

  INVENTORY   a 3D model only if an imported mesh existed in PetMeshes. None
              ship, so every pet in every inventory was the first letter of
              its name. The equipped bar showed the first three.
  PET INDEX   a disc in the pet's colour, and "?" for anything not yet found.

Both now build the real model through PetView, the same builder as the hatch
reveal. Undiscovered species in the Index are silhouettes: the real shape, in
near-black, with nothing on them that names them.

And two things it must NOT do:

  - leave a spinner running. The inventory can hold a hundred pets; a hundred
    models turning every frame is a cost a phone notices. Only the reveal
    spins, and it stops when the reveal closes.
  - give the secret away. A silhouette that keeps its name tag, its colours or
    its sparkle is not a silhouette.
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
import check_map  # noqa: E402

FAILURES = []
SILHOUETTE = (14, 12, 22)


def check(label, fn):
    try:
        print("   ok  %-36s %s" % (label, fn() or ""))
    except AssertionError as e:
        print("   x   %-36s %s" % (label, e))
        FAILURES.append(label)
    except Exception as e:  # noqa: BLE001
        print("   x   %-36s crashed: %r" % (label, e))
        FAILURES.append(label)


def kids(inst):
    return list(inst["GetChildren"](inst).values())


def desc(inst):
    return list(inst["GetDescendants"](inst).values())


def cls(inst):
    return str(inst._p.ClassName)


def named(inst, name):
    return [d for d in desc(inst) if str(d._p.Name) == name]


def model_in(icon):
    """The Model inside an icon's ViewportFrame, or None."""
    vf = icon["FindFirstChild"](icon, "PetView")
    if vf is None or cls(vf) != "ViewportFrame":
        return None
    return vf["FindFirstChildOfClass"](vf, "Model")


def parts(model):
    return [d for d in desc(model) if cls(d) in ("Part", "WedgePart", "MeshPart")]


def letters(icon):
    # The fallback label sits directly in the icon. Text further down belongs
    # to the model (a name tag), which is a different failure with its own test.
    return [d for d in kids(icon) if cls(d) == "TextLabel"
            and 0 < len(str(d._p.Text or "")) <= 3]


def rgb(c):
    return tuple(round(float(c[k]) * 255) for k in ("R", "G", "B"))


def main():
    lua, mock, gui, _ = check_client.boot()
    print()
    lua.execute("task.delay = function(t, f, ...) if f and (t or 0) < 3 then f(...) end end")

    ui = lua.eval('game:GetService("StarterPlayer").StarterPlayerScripts.Client.UI')
    mods = mock["MODULES"]
    Pets = mods[ui["FindFirstChild"](ui, "PetsPanel")]
    Index = mods[ui["FindFirstChild"](ui, "PetIndexPanel")]
    View = mods[ui["FindFirstChild"](ui, "PetView")]
    assert Pets is not None and Index is not None, "the panels did not load"

    roster = [str(p.name) for p in lua.eval(
        "_G.MysticPets.GameConfig.Pets").values()]
    rs = lua.eval('game:GetService("RunService")')
    spinners = lua.eval("function(rs) return rs.RenderStepped:Count() end")

    def close(name):
        old = gui["FindFirstChild"](gui, name)
        while old is not None:
            old["Destroy"](old)
            old = gui["FindFirstChild"](gui, name)

    def open_inventory(pets_src, equipped_src="{}"):
        close("PetsPanel")
        data = lua.eval("{ Pets = %s, EquippedPets = %s, Discovered = {} }"
                        % (pets_src, equipped_src))
        Pets.Build(data)
        return gui["FindFirstChild"](gui, "PetsPanel")

    def open_index(discovered):
        close("PetIndexPanel")
        disc = ",".join('["%s"]=true' % n for n in discovered)
        Index.Build(lua.eval("{ Pets = {}, Discovered = {%s} }" % disc))
        return gui["FindFirstChild"](gui, "PetIndexPanel")

    # ------------------------------------------------------------ PetView
    def t_every_species_has_a_model():
        bad = []
        for name in roster:
            holder = lua.eval('Instance.new("Frame")')
            vf = View.Show(holder, name, lua.eval("{}"))
            m = vf and vf["FindFirstChildOfClass"](vf, "Model")
            if m is None or len(parts(m)) < 4:
                bad.append(name)
            holder["Destroy"](holder)
        assert not bad, ("%d of %d species fall back to a letter: %s"
                         % (len(bad), len(roster), ", ".join(bad[:6])))
        return "all %d species build a model" % len(roster)

    def t_unknown_leaves_nothing():
        holder = lua.eval('Instance.new("Frame")')
        vf = View.Show(holder, "NoSuchPetAnywhere", lua.eval("{}"))
        assert vf is None, "an unknown species returned something"
        assert not kids(holder), "an unknown species left an empty frame behind"
        return "nil, and the caller's fallback is untouched"

    # ------------------------------------------------------------ inventory
    def t_inventory_shows_models():
        s = open_inventory('{ {name="dragon", rarity="Epic", uniqueId="a"},'
                           '  {name="cat", rarity="Common", uniqueId="b"},'
                           '  {name="owl", rarity="Uncommon", uniqueId="c"} }')
        icons = named(s, "PetIcon")
        assert len(icons) == 3, "three pets made %d icons" % len(icons)
        empty = [i for i in icons if model_in(i) is None]
        assert not empty, "%d of 3 inventory icons have no model" % len(empty)
        lettered = [i for i in icons if letters(i)]
        assert not lettered, "the letter fallback is showing on %d icons" % len(lettered)
        n = sum(len(parts(model_in(i))) for i in icons)
        return "3 pets, 3 models, %d parts, no letters" % n

    def t_equipped_bar_shows_models():
        s = open_inventory('{ {name="wolf", rarity="Rare", uniqueId="w"},'
                           '  {name="cat", rarity="Common", uniqueId="k"} }',
                           '{ "w" }')
        slots = named(s, "EquippedSlot")
        assert slots, "the equipped bar has no slots"
        filled = [sl for sl in slots if model_in(sl) is not None]
        assert len(filled) == 1, ("one equipped pet, %d slots showing a model"
                                  % len(filled))
        assert not letters(filled[0]), "the equipped slot still shows letters"
        return "the equipped wolf is a model, not \"wol\""

    def t_inventory_does_not_spin():
        before = spinners(rs)
        pets = ",".join('{name="%s", rarity="Common", uniqueId="s%d"}'
                        % (roster[i % len(roster)], i) for i in range(40))
        open_inventory("{%s}" % pets)
        added = spinners(rs) - before
        assert added == 0, ("opening a 40-pet inventory started %d per-frame "
                            "connections" % added)
        return "40 pets, 0 per-frame connections"

    # ------------------------------------------------------------ index
    def t_index_found_in_colour():
        s = open_index(["dragon"])
        cards = [c for c in desc(s) if str(c._p.Name) == "PetIcon"]
        assert len(cards) == len(roster), \
            "%d species, %d icons in the Index" % (len(roster), len(cards))
        found = None
        for icon in cards:
            card = icon._p.Parent
            labels = [str(d._p.Text) for d in desc(card) if cls(d) == "TextLabel"]
            if "dragon" in labels:
                found = icon
        assert found is not None, "the discovered dragon card is not labelled"
        m = model_in(found)
        assert m is not None, "the discovered dragon is a disc, not a model"
        colours = {rgb(p._p.Color) for p in parts(m)}
        assert colours - {SILHOUETTE}, "the discovered dragon is drawn as a silhouette"
        return "a %d-part dragon in %d colours" % (len(parts(m)), len(colours))

    def t_index_unfound_are_silhouettes():
        s = open_index(["dragon"])
        sil, qmarks, leaks = 0, 0, []
        for icon in named(s, "PetIcon"):
            card = icon._p.Parent
            labels = [str(d._p.Text) for d in desc(card) if cls(d) == "TextLabel"]
            if "dragon" in labels:
                continue
            if any(t == "?" for t in labels):
                qmarks += 1
            m = model_in(icon)
            if m is None:
                continue
            sil += 1
            off = {rgb(p._p.Color) for p in parts(m)} - {SILHOUETTE}
            visible = [p for p in parts(m) if float(p._p.Transparency or 0) < 1]
            if off and any(rgb(p._p.Color) != SILHOUETTE for p in visible):
                leaks.append("colour")
            for d in desc(m):
                if cls(d) in ("BillboardGui", "ParticleEmitter", "Decal", "Texture"):
                    leaks.append(cls(d))
            if any(n in labels for n in roster):
                leaks.append("name on card")
        want = len(roster) - 1
        assert sil == want, ("%d undiscovered species, %d drawn as silhouettes"
                             " (%d still \"?\")" % (want, sil, qmarks))
        assert not leaks, "silhouettes give the species away: %s" % sorted(set(leaks))
        return "%d silhouettes, no colour, tag, sparkle or name" % sil

    def t_index_does_not_spin():
        before = spinners(rs)
        open_index([])
        added = spinners(rs) - before
        assert added == 0, "opening the Index started %d per-frame connections" % added
        return "%d models, 0 per-frame connections" % len(roster)

    print("pet view:")
    check("every species builds a model", t_every_species_has_a_model)
    check("an unknown species leaves nothing", t_unknown_leaves_nothing)
    print("\ninventory:")
    check("shows models, not letters", t_inventory_shows_models)
    check("equipped bar shows models", t_equipped_bar_shows_models)
    check("nothing spins", t_inventory_does_not_spin)
    print("\npet index:")
    check("found species in colour", t_index_found_in_colour)
    check("unfound species are silhouettes", t_index_unfound_are_silhouettes)
    check("nothing spins", t_index_does_not_spin)

    print()
    check("no script wrote a global", lambda: check_map.no_global_writes(lua))

    if FAILURES:
        print("\n%d check(s) failed: %s" % (len(FAILURES), ", ".join(FAILURES)))
        return 1
    print("\npet view: every panel shows the pet itself")
    return 0


if __name__ == "__main__":
    sys.exit(main())
