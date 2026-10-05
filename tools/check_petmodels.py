#!/usr/bin/env python3
"""Build every pet the game can give out, and look at what came out.

Two things, both of which fail silently.

NOTHING GLOWS. Every pet used to carry a PointLight, Neon on wings, horns,
crests and a phoenix's whole body, and particles with LightEmission that
bloom. The owner has asked for no glow more than once, and a full server of
equipped pets was sixty dynamic lights — real cost on a low-end phone.

EVERY SPECIES GETS ITS OWN MODEL. The builder table falls back to a generic
blob for any species it does not recognise:

    local builder = builders[petData.name] or buildGeneric

So a builder that goes missing is not an error. A Dragon quietly turns into a
lump with no wings, every Dragon in every inventory changes shape, and nothing
anywhere says so. That nearly happened while this check was being written: a
regex meant to remove one-line light calls spanned newlines and deleted
buildHorse, buildDragon and most of the file, which would have shipped as
"the pets look a bit plain now".

So the special species are checked for the parts that make them special.
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

LIGHTS = ("PointLight", "SpotLight", "SurfaceLight")

# A species, and a part its own builder makes that the generic model does not.
# If the builder goes missing — or the species is renamed out from under it —
# the species falls back to generic and loses this part.
#
# These are REAL roster names. The first version of this check keyed on
# "Dragon", "Unicorn" and "Phoenix", none of which are species any more, so
# every one of these lookups missed and the check passed against a game where
# 51 of 52 pets were the same blob. Names here are checked against the roster
# below, so a rename fails loudly instead of quietly checking nothing.
SIGNATURE = {
    "dragon": "Spine",
    "cat": "Snout", "dog": "Snout", "fox": "TailTip", "wolf": "Neck",
    "rabbit": "CottonTail",
    "owl": "Beak", "eagle": "Beak", "parrot": "Beak",
    "bear": "Patch", "panda": "Patch",
    "horse": "Mane", "Reindeer": "Mane",
    "peacock": "Crest", "goldenpeacock": "Crest",
    "snake": "Seg", "Void Serpent": "Seg",
}

# Below this share of species on their own model, the pets are mostly blobs
# again — whatever the reason.
MIN_OWN_MODEL = 0.55


def main():
    lua, mock, cfg = check_map.build()
    sss = mock["ServerScriptService"]
    holder = sss["FindFirstChild"](sss, "Server", True)
    # Shared, not Server: the client builds the same models for the reveal.
    rs = mock["ReplicatedStorage"]
    shared = rs["FindFirstChild"](rs, "Shared")
    PM = mock["MODULES"][shared["FindFirstChild"](shared, "PetModels")]
    if PM is None:
        print("   x PetModels did not load")
        return 1

    species = []
    i = 1
    while cfg.Pets[i] is not None:
        species.append(cfg.Pets[i])
        i += 1
    mutations = []
    i = 1
    while cfg.Mutations[i] is not None:
        mutations.append(cfg.Mutations[i])
        i += 1

    built, broken, lit, neon, bloom, missing = 0, [], [], [], [], []
    walk = lua.eval("function(m) return m:GetDescendants() end")

    roster = {str(p.name) for p in species}
    stale = sorted(k for k in SIGNATURE if k not in roster)
    if stale:
        print("   x this check names species that are not in the roster, so it "
              "would check nothing for them: %s" % ", ".join(stale))
        return 1

    # What the generic model is made of, so "has its own model" is measured
    # against it rather than assumed.
    generic_parts = None
    own_model = []

    for pet in species:
        name = str(pet.name)
        rarity = cfg.Rarities[pet.rarity]
        for mut in [None] + mutations:
            try:
                res = PM.Build(pet, "check-%d" % built, rarity, mut)
            except Exception as e:  # noqa: BLE001
                broken.append("%s: %s" % (name, str(e).splitlines()[0][:90]))
                continue
            model = res[0] if isinstance(res, tuple) else res
            if model is None:
                broken.append("%s returned no model" % name)
                continue
            built += 1
            parts = list(walk(model).values())
            names = [str(p._p.Name) for p in parts]
            for p in parts:
                cls = str(p._p.ClassName)
                if cls in LIGHTS:
                    lit.append(name)
                if p._p.Material is not None and "Neon" in str(p._p.Material):
                    neon.append("%s/%s" % (name, str(p._p.Name)))
                if cls == "ParticleEmitter" and float(p._p.LightEmission or 0) > 0:
                    bloom.append(name)
            if mut is None:
                shape = frozenset(n for n in names
                                  if n not in ("NameTag", "Attachment")
                                  and not n.startswith(("Eye", "Pupil", "Label")))
                own_model.append((name, shape))
            if mut is None and name in SIGNATURE:
                want = SIGNATURE[name]
                if not any(want in n for n in names):
                    missing.append("%s has no %s — it fell back to the generic "
                                   "blob, so its builder is gone" % (name, want))

    total = len(species) * (1 + len(mutations))
    print("built %d of %d models (%d species x %d variants)"
          % (built, total, len(species), 1 + len(mutations)))

    bad = 0

    # Colour. Every species in the roster was Color3.fromRGB(200,200,200) —
    # one placeholder grey for all fifty-two — so even with a shape of its own,
    # a cat and a dog and a bear came out the same colour. A shared colour is
    # fine for a few; most of the roster sharing one is a placeholder nobody
    # replaced.
    from collections import Counter as _C
    palette = _C((round(float(p.color.R) * 255), round(float(p.color.G) * 255),
                  round(float(p.color.B) * 255)) for p in species if p.color is not None)
    worst, worst_n = palette.most_common(1)[0] if palette else ((0, 0, 0), 0)
    if worst_n > max(3, len(species) // 8):
        bad += 1
        print("   x %d of %d species share one body colour rgb%s — a placeholder "
              "nobody replaced" % (worst_n, len(species), worst))
    else:
        print("   ok  %d distinct body colours across %d species"
              % (len(palette), len(species)))

    # How many species actually get a shape of their own. The generic model is
    # the most common shape in the roster by construction, so anything that
    # shares its part set is on the fallback.
    from collections import Counter
    shapes = Counter(shape for _, shape in own_model)
    generic_shape = shapes.most_common(1)[0][0] if shapes else frozenset()
    distinct = [n for n, shape in own_model if shape != generic_shape]
    share = len(distinct) / max(1, len(own_model))
    if share < MIN_OWN_MODEL:
        bad += 1
        print("   x only %d of %d species (%.0f%%) have a model of their own — "
              "the rest are the same generic lump in a different colour"
              % (len(distinct), len(own_model), share * 100))
    else:
        print("   ok  %d of %d species (%.0f%%) have a model of their own"
              % (len(distinct), len(own_model), share * 100))
    for label, items, why in (
        ("broken", broken, "species that throw while building — every one of "
                           "these is an invisible pet"),
        ("lit", sorted(set(lit)), "carry a light source"),
        ("neon", sorted(set(neon))[:8], "parts are Neon"),
        ("bloom", sorted(set(bloom)), "particles have LightEmission, so they glow"),
        ("missing", missing, "lost their own model"),
    ):
        if items:
            bad += 1
            print("   x %d %s:" % (len(items), why))
            for it in items[:8]:
                print("        %s" % it)
    if not bad:
        print("   ok  every species builds, at every rarity and mutation")
        print("   ok  no lights, no Neon, no glowing particles on any of them")
        print("   ok  the %d special species keep their own models (wings, horns)"
              % len(SIGNATURE))
        print("\npet models: all %d build, none glow" % built)
        return 0
    print("\npet models: %d problem(s)" % bad)
    return 1


if __name__ == "__main__":
    sys.exit(main())
