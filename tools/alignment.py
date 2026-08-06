"""
Which exercises are aligned, and which still need /vsportprop.

Reads the real catalogue through a Lua interpreter, so the answer cannot drift from the file.
An exercise counts as ALIGNED when its placement values are no longer all at their defaults.
"""
import re
import sys
from pathlib import Path

import lupa
from lupa import LuaRuntime

ROOT = Path(__file__).resolve().parent.parent

# Every model still in the catalogue exists in the game files - the 85 that did not were removed
# after IsModelValid rejected them - so "confirmed" is no longer the useful distinction.
#
# What matters now is whether a model is actually PLACED somewhere, because that is what decides
# whether you can go and look at it. These came out of a real whole-map /vsportfind sweep.
LOCATED = {
    "prop_freeweight_01", "prop_freeweight_02",
    "prop_barbell_01", "prop_barbell_02", "prop_curl_bar_01",
    "prop_barbell_20kg", "prop_barbell_30kg", "prop_barbell_60kg", "prop_barbell_100kg",
    "prop_weight_squat",
    "prop_beach_bars_01", "prop_beach_bars_02", "prop_beach_rings_01",
    "prop_beach_dip_bars_01",
    "prop_yoga_mat_01", "prop_yoga_mat_02", "prop_yoga_mat_03",
    "prop_exer_bike_01", "prop_skip_rope_01",
    "prop_beach_volball01", "prop_beach_volball02",
    "prop_bench_01a", "prop_bench_02", "prop_bench_03", "prop_bench_04", "prop_bench_05",
    "prop_bench_06", "prop_bench_07", "prop_bench_08", "prop_bench_09", "prop_bench_10",
    "prop_bench_11", "prop_fib_3b_bench",
    # Used in game against the tuner, so placed, even though the sweep's grid missed it. A sweep
    # proves presence and never absence - this is the entry that keeps proving it.
    "prop_muscle_bench_03", "prop_muscle_bench_05", "prop_muscle_bench_06",
}

# LOCATED IS NOW AN ANNOTATION, NOT A FILTER, and that changed what this script reports.
#
# It used to skip any model the whole-map sweep had not found placed, on the reasoning that you
# cannot align what you cannot walk up to. Two things killed that reasoning:
#
#   * the alignment studio spawns the prop in the sky, so every model is reachable whether or
#     not the map places one anywhere
#   * /vsportmissing confirmed that EVERY model this catalogue claims exists in the game files
#
# So a model being unplaced is no longer a reason to leave it off the work list, and treating it
# as one meant the script reported 29 of 29 settled while two freshly added benches had never
# been looked at. A work list that hides work is worse than no work list.
CONFIRMED = LOCATED

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute("""
    function GetHashKey(s)
        local h = 5381
        for i = 1, #s do h = (h * 33 + string.byte(s, i)) % 4294967296 end
        return h
    end
    joaat = GetHashKey
    function IsDuplicityVersion() return true end
    function GetCurrentResourceName() return 'v-sport' end
    function GetConvar(_, d) return d end
    function CreateThread(fn) end
    function Wait(_) end
    function vector3(x, y, z) return setmetatable({x=x,y=y,z=z}, {__name='vector3'}) end
    json = { encode = function() return '{}' end, decode = function() return {} end }
""")

for rel in ("bridge/shared/sport.lua", "bridge/shared/locale.lua", "locales/en.lua",
            "locales/fr.lua", "config.lua", "shared/equipment.lua"):
    src = (ROOT / rel).read_text(encoding="utf-8")
    lua.execute(re.sub(r"`([A-Za-z0-9_]+)`", r'GetHashKey("\1")', src))


def seq(t):
    if t is None:
        return []
    out, i = [], 1
    while t[i] is not None:
        out.append(t[i])
        i += 1
    return out


def zeroish(v):
    """A vector3 that is all zeros, or nil."""
    if v is None:
        return True
    return abs(v.x) < 1e-6 and abs(v.y) < 1e-6 and abs(v.z) < 1e-6


def places_the_body(override):
    """Does this modelOverrides entry actually say where the BODY goes?

    An override may exist and say nothing relevant. free_weights carried
    `{ offset = ..., heading = ... }` on two barbells, which positioned the player for the old
    scenario path and has no bearing on a placed animation - counting those as measured reported
    two pairs settled that nobody had ever looked at. Presence of an override is not coverage.
    """
    if override is None:
        return False
    return (override["animOffset"] is not None
            or override["animRot"] is not None
            or override["animHeading"] is not None)


keys = seq(lua.eval("Equipment.keys"))

done, todo, no_prop = [], [], []

for key in keys:
    e = lua.eval(f"Equipment.catalogue['{key}']")
    models = seq(lua.eval(f"Equipment.catalogue['{key}'].models"))
    confirmed = models

    place = bool(e.placeAnim)
    prefer = bool(e.preferScenario)
    in_place = bool(e.inPlace)
    props = seq(lua.eval(f"Equipment.catalogue['{key}'].props"))

    # Placement that has actually been set, rather than left at its default.
    tuned_body = place and (not zeroish(e.animOffset) or (e.animHeading or 0.0) != 0.0
                            or not zeroish(e.animRot))
    tuned_prop = False
    for p in props:
        if not zeroish(p.pos) or not zeroish(p.rot) or not zeroish(p.rotOffset):
            tuned_prop = True

    # An exercise with no confirmed model has nothing to stand in front of.
    if not confirmed:
        no_prop.append((key, len(models)))
        continue

    label = confirmed[0] + (f"  (+{len(confirmed) - 1} more)" if len(confirmed) > 1 else "")

    if in_place:
        done.append((key, label, "in place"))
    elif tuned_body or tuned_prop:
        marks = []
        if tuned_body:
            marks.append("body")
        if tuned_prop:
            marks.append("prop")
        done.append((key, label, "+".join(marks)))
    else:
        # Why it still needs a pass.
        if place:
            why = "placed anim, offsets still zero"
        elif prefer:
            why = "scenario only - check it looks right, tune if not"
        elif props:
            why = "has a prop, offsets still zero"
        else:
            why = "animation in place - usually fine as-is"
        todo.append((key, label, why))

print()
print(f"ALIGNED  ({len(done)})")
for key, model, what in done:
    print(f"  {key:<16} {what:<10} {model}")


# --------------------------------------------------------------------------------------
# PER-MODEL coverage.
#
# "bench_press is aligned" hides the question that actually matters: aligned against WHICH of
# its six bench models? Only a `placeAnim` exercise is position-sensitive per model - it
# attaches the body at an offset in that prop's own space - so a sibling model with different
# geometry needs its own modelOverrides entry or the body lands wrong on it.
#
# An exercise driven by a scenario or by an animation in place does not care which model it is
# standing at, so those are not listed.
print()
print("PER-MODEL, for the position-sensitive exercises")

any_gap = False

for key in keys:
    e = lua.eval(f"Equipment.catalogue['{key}']")
    if not e.placeAnim:
        continue

    models = seq(lua.eval(f"Equipment.catalogue['{key}'].models"))
    confirmed = models
    if not confirmed:
        continue

    reference = e.tunedAgainst
    overrides = lua.eval(f"Equipment.catalogue['{key}'].modelOverrides")
    covered = set()
    if overrides is not None:
        covered = {k for k, v in overrides.items() if places_the_body(v)}

    print(f"\n  {key}")
    for model in confirmed:
        if model == reference:
            mark, note = "OK", "measured against this one"
        elif model in covered:
            mark, note = "OK", "has its own modelOverrides entry"
        else:
            mark, note = "??", "uses the reference numbers - LOOK AT IT"
            any_gap = True
        print(f"    [{mark}] {model:<26} {note}")

if not any_gap:
    print("\n  every confirmed model is either measured or overridden.")

print()
print(f"TO DO, with a confirmed prop to stand at  ({len(todo)})")
for key, model, why in todo:
    print(f"  {key:<16} {model:<34} {why}")

print()
print(f"No confirmed prop - nothing to align against yet  ({len(no_prop)})")
print("  " + ", ".join(k for k, _ in no_prop))


# --------------------------------------------------------------------------------------
# THE FULL CHECKLIST, one line per (exercise, confirmed model) pair.
#
# Every prop in the game that this resource claims to support, with the command that puts you in
# front of it. Tick them off; the ones already measured say so.
print()
print("=" * 78)
print("FULL CHECKLIST - every confirmed prop, one line each")
print("=" * 78)

tune_cmd, goto_cmd = "vsportprop", "vsportgoto"

pairs_total, pairs_done = 0, 0

for key in keys:
    e = lua.eval(f"Equipment.catalogue['{key}']")
    models = seq(lua.eval(f"Equipment.catalogue['{key}'].models"))
    confirmed = models
    if not confirmed:
        continue

    place = bool(e.placeAnim)

    #[[
    #   An `inPlace` exercise has NO per-model position: the player does not move and is not attached,
    #   so there is nothing to measure against any of its models, and nothing that can be right on one
    #   model and wrong on another. Listing them as work would be inventing work.
    #
    #   Counted as settled rather than skipped, so the total still reflects the whole catalogue. A
    #   tracker whose denominator quietly shrinks is how work gets lost.
    #]]
    if e.inPlace:
        print(f"\n{key}   (IN PLACE - no position to measure on any model)")
        for model in confirmed:
            pairs_total += 1
            pairs_done += 1
            print(f"  [x] {model:<26} in place")
        continue

    reference = e.tunedAgainst
    overrides = lua.eval(f"Equipment.catalogue['{key}'].modelOverrides")
    covered = ({k for k, v in overrides.items() if places_the_body(v)}
               if overrides is not None else set())

    # Checked in game and found correct with the reference numbers. Distinct from having its own
    # override: nothing was needed, and that is worth recording rather than re-checking.
    verified = set(seq(lua.eval(f"Equipment.catalogue['{key}'].verifiedModels")))

    # Swept across the whole map and found nowhere. Nothing to align, and nothing missing - the
    # model stays listed so a server whose MLO places it gets it for free.
    absent = set(seq(lua.eval(f"Equipment.catalogue['{key}'].absentModels")))

    # Position-sensitive exercises need a measurement per model; the rest need eyes on them once.
    kind = "MEASURE" if place else "LOOK"

    print(f"\n{key}   ({kind})")
    for model in confirmed:
        pairs_total += 1

        if model == reference:
            pairs_done += 1
            print(f"  [x] {model:<26} measured")
        elif model in covered:
            pairs_done += 1
            print(f"  [x] {model:<26} own override")
        elif model in verified:
            pairs_done += 1
            print(f"  [x] {model:<26} checked, reference numbers fit")
        elif model in absent:
            # NOT counted as settled. `absentModels` records that the whole-map sweep never found
            # one placed, which used to mean "unreachable, so nothing to do". The studio spawns any
            # model on demand, so it is now only a note about where you will not find one - and
            # counting it as done is how prop_muscle_bench_04 sat unlooked-at while the script
            # reported everything settled.
            print(f"  [ ] {model:<26} not placed on the map - use the studio:"
                  f"   /{tune_cmd} {key} {model}")
        elif place:
            print(f"  [ ] {model:<26} /{goto_cmd} {key} {model}"
                  f"   then /{tune_cmd} {key} {model}")
        else:
            print(f"  [ ] {model:<26} /{goto_cmd} {key} {model}   then /vsport")

print()
print(f"{pairs_done} of {pairs_total} prop/exercise pairs settled.")
print()
print("MEASURE = the body is attached at an offset in that prop's space, so a model with")
print("          different geometry needs its own numbers. Paste what ENTER prints.")
print("LOOK    = a scenario or an animation in place; the model does not change the result.")
print("          One glance each. Only report it if it looks wrong.")
print()
