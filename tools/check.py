"""
v-sport checks.

Phase 1  parse every .lua file
Phase 2  load the shared chain in a real Lua 5.4 and assert on it
Phase 3  locale parity, and every L() key used in the code exists
"""
import re
import sys
from pathlib import Path

# Relative to this file, not absolute. An absolute path here would carry the author's own directory
# layout - and their account name - into a public repository, and would make the script unusable for
# anybody who cloned it.
ROOT = Path(__file__).resolve().parent.parent

errors = []
warnings = []


def fail(msg):
    errors.append(msg)


def warn(msg):
    warnings.append(msg)


# --------------------------------------------------------------------------- phase 1
from luaparser import ast as lua_ast

lua_files = sorted(ROOT.rglob("*.lua"))
print(f"phase 1: parsing {len(lua_files)} lua files")

# CFX Lua adds `string` as a compile-time joaat hash literal. Plain Lua parsers do not know
# it, so it is rewritten to a call for the parse only. The files on disk keep the backticks:
# they are the idiomatic and cheaper form in FiveM.
BACKTICK = re.compile(r"`([A-Za-z0-9_]+)`")

for path in lua_files:
    src = path.read_text(encoding="utf-8")

    if src.startswith("﻿"):
        fail(f"BOM {path.relative_to(ROOT)} starts with a UTF-8 BOM")
        src = src.lstrip("﻿")

    try:
        lua_ast.parse(BACKTICK.sub(r'GetHashKey("\1")', src))
    except Exception as exc:  # noqa: BLE001
        fail(f"SYNTAX {path.relative_to(ROOT)}: {exc}")

if errors:
    for e in errors:
        print("  " + e)
    print("\nstopping: fix syntax before the runtime checks")
    sys.exit(1)
print("  all parsed")


# --------------------------------------------------------------------------- phase 2
import lupa
from lupa import LuaRuntime

print("phase 2: loading the shared chain in real Lua 5.4")
print(f"  {lupa.LuaRuntime().lua_implementation} {lupa.LuaRuntime().lua_version}")

lua = LuaRuntime(unpack_returned_tuples=True)

# FiveM natives the shared files touch at load time.
lua.execute("""
    _G.__hashes = {}
    function GetHashKey(s)
        -- Not the real joaat; only uniqueness matters for the index test.
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
    json = {
        encode = function(t) return '{}' end,
        decode = function(s) return {} end,
    }
""")

order = [
    "bridge/shared/sport.lua",
    "bridge/shared/locale.lua",
    "locales/en.lua",
    "locales/fr.lua",
    "config.lua",
    "shared/equipment.lua",
    "shared/stats.lua",
]

for rel in order:
    path = ROOT / rel
    try:
        lua.execute(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        fail(f"LOAD {rel}: {exc}")
        for e in errors:
            print("  " + e)
        sys.exit(1)

print("  shared chain loaded")

g = lua.globals()


def seq(lua_table):
    """A Lua array as a Python list. `.values()` on a lupa table is the table's own
    iterator, which collides with any Lua function called `keys`, so sequences are walked
    by index instead."""
    if lua_table is None:
        return []
    out = []
    i = 1
    while lua_table[i] is not None:
        out.append(lua_table[i])
        i += 1
    return out


def hashmap(lua_table):
    """A Lua hash map as a Python dict."""
    if lua_table is None:
        return {}
    return {k: v for k, v in lua_table.items()}


# --- config sanity ---------------------------------------------------------
cfg = g.Config
required_sections = [
    "General", "Compat", "Persistence", "Stats", "Progression", "Allowance",
    "Items", "Decay", "Effects", "Detection", "Spots", "ExtraEquipment",
    "Anywhere", "Interaction", "Minigame", "UI", "Passive", "Buffs",
    "Notifications", "Commands", "Security", "Performance", "Debug",
]
for name in required_sections:
    if cfg[name] is None:
        fail(f"CONFIG Config.{name} is missing")

# And the list must be COMPLETE. It had gone stale by one - Config.Anywhere existed and was not
# listed - which means a section could have been deleted outright without this noticing. A
# hand-maintained list of what to check has to be checked against reality itself.
declared = set(re.findall(r"(?m)^Config\.(\w+)\s*=",
                          (ROOT / "config.lua").read_text(encoding="utf-8")))
unlisted = sorted(declared - set(required_sections))
if unlisted:
    fail("CONFIG required_sections in this script is stale, missing: " + ", ".join(unlisted))

print(f"  {len(required_sections)} config sections present, list is complete")

# --- stats -----------------------------------------------------------------
stat_keys = seq(lua.eval("Stats.keys()"))
print(f"  stats: {', '.join(stat_keys)}")
if len(stat_keys) != 3:
    warn(f"expected 3 stats, found {len(stat_keys)}")

for key in stat_keys:
    if lua.eval(f"Stats.def('{key}')") is None:
        fail(f"STATS Stats.def('{key}') returned nil")

# --- equipment -------------------------------------------------------------
# lua.eval, not g.Equipment.keys: attribute access on a lupa table hits the wrapper's own
# `.keys` method before it looks at the Lua field.
eq_keys = seq(lua.eval("Equipment.keys"))
model_count = lua.eval("Sport.count(Equipment.byModel)")
print(f"  equipment: {len(eq_keys)} exercises across {model_count} model hashes")

for key in eq_keys:
    gains = hashmap(lua.eval(f"Equipment.catalogue['{key}'].gains"))
    if not gains:
        fail(f"EQUIPMENT {key} has no gains table")
        continue
    for stat in gains:
        if stat not in stat_keys:
            fail(f"EQUIPMENT {key} trains unknown stat '{stat}'")

    models = seq(lua.eval(f"Equipment.catalogue['{key}'].models"))
    if not models and not lua.eval(f"Equipment.catalogue['{key}'].mloOnly"):
        warn(f"equipment {key} lists no models (only reachable as a Config.Spots entry)")

    # difficulty must resolve
    diff = lua.eval(f"Equipment.difficulty(Equipment.get('{key}'))")
    if diff is None:
        fail(f"EQUIPMENT {key}: difficulty did not resolve")
    else:
        if not (diff.goodZone[1] <= diff.perfectZone[1] and diff.perfectZone[2] <= diff.goodZone[2]):
            fail(f"EQUIPMENT {key}: perfectZone is not inside goodZone")

    mind = lua.eval(f"Equipment.minimumDurationMs(Equipment.get('{key}'))")
    if mind is None or mind <= 0:
        fail(f"EQUIPMENT {key}: minimumDurationMs returned {mind}")

# --- what ships switched off must stay switched off, on every rebuild --------------------
#
# Five exercises are `enabled = false` because no base-game animation matches them, and one of them -
# park_bench - carries FIFTEEN street-bench models. If it ever came back on by itself, a server that
# enabled nothing would find every bench in the city offering sit-ups.
#
# The rebuild is what makes this worth asserting rather than reading. Equipment.build() runs again on
# every /vsportadd, /vsportremove and /vsportreload, and a rebuild does NOT re-read the file: it
# restores from a snapshot taken at boot. So a snapshot that dropped a `false` would look perfect at
# boot and turn five exercises on the first time an admin touched anything. Build twice and compare.
OFF_BY_DEFAULT = {"dip_bars", "skipping_rope", "park_bench", "basketball", "volleyball"}

for key in sorted(OFF_BY_DEFAULT):
    if lua.eval(f"Equipment.catalogue['{key}'] ~= nil") is not True:
        fail(f"DEFAULTS '{key}' is documented as off by default but is not in the catalogue")
    elif key in eq_keys:
        fail(f"DEFAULTS '{key}' ships enabled - it must stay off until an operator asks for it")

lua.execute("Equipment.build(); Equipment.build()")
rebuilt = seq(lua.eval("Equipment.keys"))

if set(rebuilt) != set(eq_keys):
    added = sorted(set(rebuilt) - set(eq_keys))
    lost = sorted(set(eq_keys) - set(rebuilt))
    fail(f"DEFAULTS a rebuild changes the catalogue: +{added} -{lost}"
         " - Equipment.shipped is not a faithful snapshot, so /vsportadd would flip these")
else:
    print(f"  defaults: {len(OFF_BY_DEFAULT)} exercises off, and still off after a rebuild  OK")

# Config.ExtraEquipment is the file an operator edits to turn one back on. It has to ship empty,
# or they inherit somebody else's decision without making one.
if lua.eval("Sport.count(Config.ExtraEquipment)") != 0:
    fail("DEFAULTS Config.ExtraEquipment ships non-empty - every install would get its entries")
else:
    print("  Config.ExtraEquipment: ships empty  OK")

# --- model overrides and staging -------------------------------------------
#
# Per-model positioning is written by NAME in the config and looked up by HASH at runtime, so
# the re-keying is worth asserting: a typo there silently falls back to the generic offset and
# the player stands next to the squat rack instead of in it.
override_count = 0
for key in eq_keys:
    overrides = lua.eval(f"Equipment.catalogue['{key}'].modelOverrides")
    if overrides is None:
        continue

    by_hash = lua.eval(f"Equipment.catalogue['{key}'].overridesByHash")
    if by_hash is None:
        fail(f"EQUIPMENT {key} has modelOverrides but no overridesByHash was built")
        continue

    for model in hashmap(overrides):
        override_count += 1

        # The model an override names must also be in that entry's `models` list, or the
        # override can never fire.
        models = seq(lua.eval(f"Equipment.catalogue['{key}'].models"))
        if model not in models:
            fail(f"EQUIPMENT {key} overrides '{model}', which is not in its own models list")

        staged = lua.eval(
            f"Equipment.staging(Equipment.get('{key}'), GetHashKey('{model}'))")
        if staged is None:
            fail(f"EQUIPMENT staging({key}, {model}) returned nil")
            continue

        want = lua.eval(f"Equipment.catalogue['{key}'].modelOverrides['{model}']")
        if want.heading is not None and staged.heading != want.heading:
            fail(f"EQUIPMENT staging({key}, {model}) heading is "
                 f"{staged.heading}, expected {want.heading}")

# A model with no override must fall back to the entry's own values.
generic = lua.eval("Equipment.staging(Equipment.get('bench_press'), GetHashKey('prop_gym_bench_01'))")
own = lua.eval("Equipment.catalogue['bench_press'].heading")
if generic.heading != own:
    fail(f"EQUIPMENT staging fell back to {generic.heading}, expected the entry's {own}")

entries_with_overrides = sum(
    1 for k in eq_keys
    if lua.eval("Equipment.catalogue['%s'].modelOverrides" % k) is not None
)
print(f"  model overrides: {override_count} across {entries_with_overrides} "
      f"exercises, all resolve")

# --- key labels ------------------------------------------------------------
#
# GetControlInstructionalButton answers with an internal token for several controls - `b_1004`
# for BACKSPACE - so every key label has to go through UI.keyLabel, which rejects those and
# falls back to a table. Three separate places grew their own copy of the raw lookup and each
# one shipped "[b_1004]" on screen before it was noticed.
BLOCK_COMMENT = re.compile(r"--\[\[.*?\]\]", re.S)
LINE_COMMENT = re.compile(r"(?m)^\s*--.*$")


def strip_comments(text):
    """Blank out Lua comments, keeping line numbers intact so a hit still points somewhere.

    Both forms matter: the guard below first fired on its own explanatory `--[[ ]]` block, whose
    inner lines do not start with `--` and so survived a naive filter."""
    text = BLOCK_COMMENT.sub(lambda m: re.sub(r"[^\n]", " ", m.group(0)), text)
    return LINE_COMMENT.sub(lambda m: " " * len(m.group(0)), text)


raw_lookups = []
for path in (ROOT / "client").glob("*.lua"):
    # ui.lua owns the one legitimate call, inside UI.keyLabel itself.
    if path.name == "ui.lua":
        continue

    code = strip_comments(path.read_text(encoding="utf-8"))
    for num, line in enumerate(code.splitlines(), 1):
        if "GetControlInstructionalButton" in line:
            raw_lookups.append(f"{path.name}:{num}")

if raw_lookups:
    fail("KEYLABEL raw GetControlInstructionalButton outside UI.keyLabel at "
         + ", ".join(raw_lookups)
         + " - it returns tokens like b_1004; use UI.keyLabel")
else:
    print("  key labels: all go through UI.keyLabel  OK")

# --- the developer commands must be gated ----------------------------------
#
# Config.Commands.restrictDevCommands shipped declared, documented in two places, and read by
# NOTHING. Every dev command was open to every player, and two of them teleport - `goto_` across
# the map and `tune` into the sky. A player could type /vsportgoto and cross Los Santos.
#
# So it is asserted rather than trusted: every command in DEV_COMMANDS must call State.devGate()
# inside its handler. `stats` is deliberately absent - the panel is for players - and `dev` is the
# command that re-asks, whose answer comes from the server.
#
# `export`, `reload` and `reset` are registered through one shared `relay` helper in
# client/custom.lua, which gates once for all three - so they are deliberately not listed here,
# because the pattern below reads an inline Config.Commands.<key> and would not find them. Their
# real protection is on the server: every one of those events re-checks Bridge.isAdmin.
DEV_COMMANDS = ["info", "scan", "spot", "offset", "tune", "goto_", "find", "missing", "tour",
                "add", "remove", "custom"]

ungated = []
seen_dev = set()

for path in (ROOT / "client").glob("*.lua"):
    code = strip_comments(path.read_text(encoding="utf-8"))
    lines = code.splitlines()

    for num, line in enumerate(lines):
        if "RegisterCommand(" not in line:
            continue

        # Which config key is being registered? Either inline as Config.Commands.x, or via a
        # local that was assigned from one, which is how tune.lua does it.
        inline = re.search(r"Config\.Commands\.(\w+)", line)
        if inline:
            which = inline.group(1)
        else:
            # Walk back for `local name = Config.Commands.<key>` in the enclosing thread.
            which = None
            for back in range(num - 1, max(-1, num - 8), -1):
                found = re.search(r"=\s*Config\.Commands\.(\w+)", lines[back])
                if found:
                    which = found.group(1)
                    break

        if which not in DEV_COMMANDS:
            continue

        seen_dev.add(which)

        # The gate has to be the first thing the handler does. Six lines is generous.
        body = "\n".join(lines[num:num + 6])
        if "State.devGate()" not in body:
            ungated.append(f"{path.name}:{num + 1} ({which})")

if ungated:
    fail("ADMIN developer command without State.devGate() at " + ", ".join(ungated)
         + " - it would be open to every player, and two of them teleport")
elif seen_dev != set(DEV_COMMANDS):
    # A guard that can only ever pass is not a guard. If the pattern match above stops finding a
    # command - renamed local, restructured registration - this says so instead of reporting a
    # clean run over nothing, which is how the height readout in the tuner lied for a week.
    fail("ADMIN the dev-command guard did not find " +
         ", ".join(sorted(set(DEV_COMMANDS) - seen_dev)) +
         " - the guard is broken, not the code")
else:
    print(f"  dev commands: {len(seen_dev)} found, all gated by State.devGate()  OK")

# --- the framework object must never be indexed raw --------------------------------------
#
# ox_core's core object IS its exports table, and in FiveM indexing an export that does not exist
# RAISES rather than returning nil. `field(object, name)` exists for exactly that, and server/items.lua
# forgot: `core.Functions` threw on ox_core and killed the whole item-registration loop. The file that
# defines `field` documented the hazard, which is what makes a second place getting it wrong worth an
# assertion rather than a comment.
raw_core = []
for path in list((ROOT / "server").glob("*.lua")) + list((ROOT / "bridge" / "server").glob("*.lua")):
    code = strip_comments(path.read_text(encoding="utf-8"))
    for num, line in enumerate(code.splitlines(), 1):
        if re.search(r"\bcore\.[A-Z]\w*", line) and "pcall" not in line and "field(" not in line:
            raw_core.append(f"{path.name}:{num}")

if raw_core:
    fail("BRIDGE the framework object is indexed raw at " + ", ".join(raw_core)
         + " - use field(object, name) or a pcall; ox_core's core object RAISES on a missing key")
else:
    print("  core object: never indexed raw  OK")

# --- a framework method is never gated on type() == 'function' ---------------------------
#
# FiveM hands an object across a resource boundary as a proxy: qb-core's Functions.GetPlayer arrives
# as a TABLE with a __call metamethod. `type(fn) ~= 'function' then return nil` therefore rejected a
# perfectly callable object, every retry answered nil identically, and on stock qb-core - which does
# not export GetPlayer, so the fallback is the only path - no player was ever resolved and nobody's
# stats ever loaded. Sport.callable asks the question that can be answered; the pcall around the call
# is the guard.
#
# Scoped to bridge/ and server/, which is every line that touches somebody else's object. The one
# legitimate type test lives in client/session.lua and is about a NATIVE existing on a game build,
# where the value really is a function or really is nil.
type_gates = []
for path in list((ROOT / "bridge").rglob("*.lua")) + list((ROOT / "server").glob("*.lua")):
    code = strip_comments(path.read_text(encoding="utf-8"))
    for num, line in enumerate(code.splitlines(), 1):
        if re.search(r"type\([^)]*\)\s*[=~]=\s*'function'", line):
            type_gates.append(f"{path.name}:{num}")

if type_gates:
    fail("CALLABLE a framework value is gated on type() == 'function' at " + ", ".join(type_gates)
         + " - use Sport.callable(); a method read across a resource boundary is a callable table")
else:
    print("  callable: no framework value gated on type() == 'function'  OK")

# --- a player's F8 is not a log file -----------------------------------------------------
#
# Sport.print and Sport.warn are gated on the client by Sport.consoleAllowed, so diagnostics reach
# admins and not players. A raw print() bypasses that gate. Allowed only in the files that ARE the
# developer commands, where the output is the command's answer to whoever ran it.
DEV_OUTPUT_FILES = {"commands.lua", "tune.lua", "custom.lua"}

leaks = []
for path in (ROOT / "client").glob("*.lua"):
    if path.name in DEV_OUTPUT_FILES:
        continue
    code = strip_comments(path.read_text(encoding="utf-8"))
    for num, line in enumerate(code.splitlines(), 1):
        if re.search(r"(?<!Sport\.)(?<!\w)print\(", line):
            leaks.append(f"{path.name}:{num}")

if leaks:
    fail("CONSOLE raw print() on a gameplay client path at " + ", ".join(leaks)
         + " - use Sport.warn/Sport.debug so it does not reach every player's F8")
else:
    print("  client console: every gameplay line goes through Sport  OK")

# --- every roles() answer must carry the same keys ---------------------------------------
#
# The server's requirement check reads roles.jobType. It was missing from every client branch and
# from the ox adapter entirely, so `require = { job = 'leo' }` passed the server and was refused by
# the client, and job-gated equipment was closed to everyone on ox_core.
roles_sources = {
    "bridge/server/framework.lua": r"roles = function.*?end,",
    "bridge/client/compat.lua": r"function Compat\.roles\(\).*?\nend",
}
missing_jobtype = []
for rel, pattern in roles_sources.items():
    src = (ROOT / rel).read_text(encoding="utf-8")
    for block in re.findall(pattern, src, re.S):
        # Every `return {` inside a roles implementation must mention jobType.
        for ret in re.findall(r"return \{[^}]*\}", block, re.S):
            if "job" in ret and "jobType" not in ret:
                missing_jobtype.append(f"{rel}: {' '.join(ret.split())[:70]}")

if missing_jobtype:
    fail("BRIDGE a roles() result omits jobType, which the requirement check reads: "
         + "; ".join(missing_jobtype))
else:
    print("  roles(): every answer carries jobType  OK")

# --- every framework adapter must implement every method the bridge calls ---------------
#
# The bridge resolves ONE adapter at boot and then calls methods on it blindly. A method the
# bridge calls and an adapter does not define is a runtime error on that framework and nowhere
# else - which is exactly the bug that never shows up in testing, because you test on the
# framework you run. Checked statically instead.
bridge_src = (ROOT / "bridge" / "server" / "framework.lua").read_text(encoding="utf-8")

bridge_calls = sorted(set(re.findall(r"\badapter\.(\w+)\s*\(", bridge_src)))

adapter_keys = {}
for match in re.finditer(r"ADAPTERS\.(\w+)\s*=\s*\{", bridge_src):
    name, start = match.group(1), match.end()
    depth, index = 1, start
    while depth and index < len(bridge_src):
        if bridge_src[index] == "{":
            depth += 1
        elif bridge_src[index] == "}":
            depth -= 1
        index += 1
    adapter_keys[name] = set(
        re.findall(r"(?m)^\s{4}(\w+)\s*=", bridge_src[start:index]))

if not bridge_calls or not adapter_keys:
    fail("BRIDGE could not read the adapters out of bridge/server/framework.lua")
else:
    gaps = []
    for name, keys in sorted(adapter_keys.items()):
        missing = [call for call in bridge_calls if call not in keys]
        if missing:
            gaps.append(f"{name} lacks {', '.join(missing)}")

    if gaps:
        fail("BRIDGE " + "; ".join(gaps)
             + " - the bridge calls those, so that framework errors at runtime")
    else:
        print(f"  frameworks: {', '.join(sorted(adapter_keys))} each implement all "
              f"{len(bridge_calls)} bridge methods  OK")

# --- every export must appear in API.md ---------------------------------------------------
#
# The import/export surface is the whole point of the resource for anybody writing a drug or a
# smoking script, and an export nobody can find might as well not exist. Two client exports had
# shipped undocumented before this check existed.
api_doc = (ROOT / "API.md").read_text(encoding="utf-8")

api_src = (ROOT / "server" / "api.lua").read_text(encoding="utf-8")
api_table = re.search(r"local API = \{(.*?)\n\}", api_src, re.S)

server_exports = set(re.findall(r"(?m)^\s{4}(\w+)\s*=", api_table.group(1))) if api_table else set()

# server/items.lua registers two of its own, and any other file may as well.
direct_exports = set()
for path in list((ROOT / "server").glob("*.lua")) + list((ROOT / "client").glob("*.lua")):
    direct_exports |= set(
        re.findall(r"(?m)^\s*exports\('(\w+)'", path.read_text(encoding="utf-8")))

all_exports = server_exports | direct_exports

if not all_exports:
    fail("API could not find any exports to check against API.md")
else:
    undocumented = sorted(name for name in all_exports if name not in api_doc)
    if undocumented:
        fail(f"API {len(undocumented)} export(s) missing from API.md: "
             + ", ".join(undocumented))
    else:
        print(f"  api: {len(all_exports)} exports, every one named in API.md  OK")

    # And the other direction: API.md must not promise something that does not exist.
    promised = set(re.findall(r"exports\['v-sport'\]:(\w+)", api_doc))
    ghosts = sorted(promised - all_exports)
    if ghosts:
        fail("API API.md documents exports that do not exist: " + ", ".join(ghosts))

# --- PROPS.md is generated, so it must be current ----------------------------------------
#
# A hand-written list of supported props is wrong the first time somebody adds one and nothing
# complains. PROPS.md is generated from the catalogue; this makes it a build error to change the
# catalogue and forget.
# --- every Config section must be documented ---------------------------------------------
#
# "100% configurable" is only true if an operator can find the switch. Four sections - Anywhere,
# Commands, Notifications and Persistence - were complete in config.lua and absent from CONFIG.md,
# including the one that decides who may teleport.
config_src = (ROOT / "config.lua").read_text(encoding="utf-8")
config_doc = (ROOT / "CONFIG.md").read_text(encoding="utf-8")
items_doc = (ROOT / "ITEMS.md").read_text(encoding="utf-8")

config_sections = sorted(set(re.findall(r"(?m)^Config\.(\w+)\s*=", config_src)))

if not config_sections:
    fail("CONFIG could not find any Config sections to check")
else:
    # A section counts as documented if CONFIG.md names it, or if a more specific document does -
    # the items live in ITEMS.md and the buff bounds in API.md, and duplicating them would rot.
    elsewhere = api_doc + items_doc
    undocumented_sections = [
        name for name in config_sections
        if f"Config.{name}" not in config_doc and f"Config.{name}" not in elsewhere
    ]
    if undocumented_sections:
        fail(f"CONFIG {len(undocumented_sections)} section(s) undocumented: "
             + ", ".join(f"Config.{n}" for n in undocumented_sections))
    else:
        print(f"  config: {len(config_sections)} sections, every one documented  OK")

# --- data/custom.json must ship empty ----------------------------------------------------
#
# It is a RUNTIME file that happens to be committed, because fxmanifest lists it in files{} and a
# missing entry there logs a warning at boot. The consequence is that testing fills it, and a
# release would then ship the maintainer's test props to every server that downloads it - which
# would look exactly like the resource inventing equipment nobody asked for.
custom_file = ROOT / "data" / "custom.json"
if not custom_file.exists():
    fail("MANIFEST data/custom.json is listed in fxmanifest but missing")
else:
    import json as _json

    try:
        stored = _json.loads(custom_file.read_text(encoding="utf-8"))
    except ValueError as exc:
        fail(f"MANIFEST data/custom.json is not valid JSON: {exc}")
        stored = {}

    entries = stored.get("equipment") or {}
    if entries:
        fail(f"RELEASE data/custom.json holds {len(entries)} test entr"
             f"{'y' if len(entries) == 1 else 'ies'} ({', '.join(sorted(entries))}). "
             f"Run /vsportexport to keep them, then /vsportreset before releasing.")
    else:
        print("  data/custom.json: empty, safe to release  OK")

props_tool = ROOT / "tools" / "props.py"
if not props_tool.exists():
    warn("tools/props.py is missing, so PROPS.md cannot be checked")
else:
    import subprocess

    done = subprocess.run([sys.executable, str(props_tool), "--check"],
                          cwd=str(ROOT), capture_output=True, text=True)
    if done.returncode != 0:
        fail("PROPS PROPS.md is out of date - run: python tools/props.py")
    else:
        print(done.stdout.strip() or "  PROPS.md: current  OK")

# --- animations ------------------------------------------------------------
#
# The complaint that started this check was "every machine plays the same animation". So it is
# asserted: every exercise has one, and they are actually different from each other.
anim_of = {}
for key in eq_keys:
    anim = lua.eval(f"Equipment.catalogue['{key}'].anim")
    scenario = lua.eval(f"Equipment.catalogue['{key}'].scenario")

    if anim is None and scenario is None:
        fail(f"ANIM {key} has neither an anim nor a scenario - it will play nothing")
        continue

    if anim is None:
        warn(f"{key} has no anim, only the scenario '{scenario}' - less reliable")
        continue

    if not anim.dict or not anim.clip:
        fail(f"ANIM {key} has an anim table without both dict and clip")
        continue

    # A clip named 'base' on a dictionary whose real clip is something else is a silent no-op,
    # which is the single easiest mistake to make here.
    if anim.dict.endswith("@base") and anim.clip not in ("base", "base_a", "base_b"):
        warn(f"{key}: dict ends '@base' but clip is '{anim.clip}' - verify it")

    anim_of[key] = (anim.dict, anim.clip)

distinct = set(anim_of.values())
print(f"  animations: {len(anim_of)}/{len(eq_keys)} exercises, "
      f"{len(distinct)} distinct dict+clip")

shared_anims = {}
for key, pair in anim_of.items():
    shared_anims.setdefault(pair, []).append(key)

for pair, keys in sorted(shared_anims.items(), key=lambda kv: -len(kv[1])):
    if len(keys) > 1:
        print(f"    x{len(keys)}  {pair[0]} [{pair[1]}]  <- {', '.join(sorted(keys))}")

if len(distinct) < 8:
    fail(f"ANIM only {len(distinct)} distinct animations across {len(eq_keys)} exercises; "
         "the point of the ANIMS table is that they differ")

# The bench press must be the real lying one, not the standing dumbbell scenario.
bench = anim_of.get("bench_press")
if bench and "bench_press" not in bench[0]:
    fail(f"ANIM bench_press uses {bench[0]}, not the lying bench-press dictionary")
bench_scenario = lua.eval("Equipment.catalogue['bench_press'].scenario")
if bench_scenario != "PROP_HUMAN_SEAT_MUSCLE_BENCH_PRESS":
    fail(f"ANIM bench_press scenario is {bench_scenario}, "
         "expected PROP_HUMAN_SEAT_MUSCLE_BENCH_PRESS")

# --- PROP_ scenarios must never be the first choice ---------------------------------------
#
# A PROP_ scenario expects a real scenario POINT baked into the map. Started at a position
# handed to it instead, it does something worse than fail: it reports itself as running,
# teleports the ped to the coordinates and animates nothing. The player stands on the bench,
# and because the verification sees a live scenario, nothing falls back.
#
# This cost two rounds of "he is standing there doing nothing", so it is asserted rather than
# remembered.
for key in eq_keys:
    prefers = lua.eval(f"Equipment.catalogue['{key}'].preferScenario")
    scenario = lua.eval(f"Equipment.catalogue['{key}'].scenario")

    if prefers and isinstance(scenario, str) and scenario.startswith("PROP_"):
        fail(f"SCENARIO {key} prefers {scenario}, a PROP_ scenario. Placed by hand these "
             "teleport the ped and animate nothing - prefer the animation and keep the "
             "scenario as the fallback")

prop_scenarios = [
    (k, lua.eval(f"Equipment.catalogue['{k}'].scenario"))
    for k in eq_keys
    if isinstance(lua.eval(f"Equipment.catalogue['{k}'].scenario"), str)
    and lua.eval(f"Equipment.catalogue['{k}'].scenario").startswith("PROP_")
]
print(f"    {len(prop_scenarios)} PROP_ scenarios, all as fallback only  OK")

# --- the key pool ----------------------------------------------------------
#
# Six keys, all under the left hand, and every one carrying a letter for both layouts.
pool = seq(lua.eval("Config.Minigame.keyPool"))
print(f"  key pool: {len(pool)} keys")
if len(pool) != 6:
    warn(f"the key pool has {len(pool)} keys; the design is six under the left hand")

seen_controls = set()
for entry in pool:
    control = entry.control
    if control is None:
        fail("KEYPOOL an entry has no control")
        continue
    if control in seen_controls:
        fail(f"KEYPOOL control {control} appears twice")
    seen_controls.add(control)

    for layout in ("azerty", "qwerty"):
        label = entry[layout]
        if not label or not isinstance(label, str):
            fail(f"KEYPOOL control {control} has no {layout} label")
        elif len(label) > 3:
            fail(f"KEYPOOL {layout} label '{label}' is too long for the box")

azerty = "".join(e["azerty"] for e in pool)
qwerty = "".join(e["qwerty"] for e in pool)
print(f"    azerty {azerty}   qwerty {qwerty}")
if sorted(azerty) != sorted("AZEQSD"):
    fail(f"KEYPOOL azerty letters are {azerty}, expected A Z E Q S D")

# --- progression maths -----------------------------------------------------
print("  progression:")
for key in stat_keys:
    pps = lua.eval(f"Stats.pointsPerSession('{key}')")
    print(f"    {key:<10} one perfect session = {pps:.2f} points")
    if pps <= 0:
        fail(f"STATS pointsPerSession('{key}') is {pps}")

# a full-quality bench press with no fatigue and no allowance spent
gains = lua.eval("""
    Stats.sessionGains(Equipment.get('bench_press'), {
        current = Stats.blank(), quality = 1.0, recent = 0, restedHours = 10,
        multipliers = {}, allowance = { total = 0, stats = {} },
    })
""")
gd = dict(gains) if gains is not None else {}
print(f"    perfect bench press -> {', '.join(f'{k} +{v:.2f}' for k, v in gd.items())}")
if not gd:
    fail("STATS a perfect bench press paid nothing")

# the allowance must actually block
blocked = lua.eval("""
    Stats.sessionGains(Equipment.get('bench_press'), {
        current = Stats.blank(), quality = 1.0, recent = 0, restedHours = 10,
        multipliers = {},
        allowance = { total = Config.Allowance.total, stats = {} },
    })
""")
if blocked is not None and len(dict(blocked)) > 0:
    fail("ALLOWANCE a spent allowance still paid out")
else:
    print("    spent allowance -> pays nothing  OK")

# per-stat allowance
per_stat = lua.eval("""
    Stats.sessionGains(Equipment.get('bench_press'), {
        current = Stats.blank(), quality = 1.0, recent = 0, restedHours = 10,
        multipliers = {},
        allowance = { total = 0, stats = { strength = Config.Allowance.perStat } },
    })
""")
psd = dict(per_stat) if per_stat is not None else {}
if psd.get("strength"):
    fail("ALLOWANCE a maxed per-stat allowance still paid strength")
else:
    print("    per-stat cap    -> strength blocked, others free  OK")

# fatigue curve
print("    fatigue:", ", ".join(
    f"{n}={lua.eval(f'Stats.fatigue({n}, 0)'):.2f}" for n in range(0, 6)))

# --- The headline number: days to take all three stats to 100% ------------------------
#
# A full day-by-day simulation against the REAL shared functions, honouring the rolling
# allowance ledger and the decay rules. This is the figure the README and CONFIG.md quote, so
# it is measured rather than estimated.
#
# The player trains in blocks of three sessions two hours apart, cycling bench press,
# treadmill and yoga so all three stats advance, at 90% form.
lua.execute("""
function SimulateDaysToMax(sessionsPerDay, restDayEvery, quality)
    local stats = Stats.blank()
    local ledger = {}              -- { at, stat, amount }, the allowance
    local sessionTimes = {}        -- for fatigue
    local now = 0
    local lastSession = 0
    local anchors = {}
    local peak = {}
    local exercises = { 'bench_press', 'treadmill', 'yoga' }
    local totalSessions = 0

    local function spent()
        local window = Stats.allowanceWindow(false)
        local out = { total = 0.0, stats = {} }
        for k in pairs(Config.Stats) do out.stats[k] = 0.0 end
        for i = #ledger, 1, -1 do
            if (now - ledger[i].at) >= window then
                table.remove(ledger, i)
            else
                out.total = out.total + ledger[i].amount
                out.stats[ledger[i].stat] = out.stats[ledger[i].stat] + ledger[i].amount
            end
        end
        return out
    end

    local function done()
        for k, d in pairs(Config.Stats) do
            if (stats[k] or 0) < (d.max or 100.0) - 0.01 then return false end
        end
        return true
    end

    --[[
        A DAY IS TWENTY-FOUR HOURS, AND THE SIMULATOR USED TO FORGET IT.

        The schedule below puts 2 hours between blocks of three sessions, so twenty blocks is 53
        hours - and `now = math.max(now, day * 86400)` then kept the larger value, silently letting a
        "day" run long. Any scenario dense enough to overflow reported days that were not days: the
        60-a-day grinder's "5 days" was really about eleven, and that was the exact figure being
        quoted to show that grinding is bounded.

        So the clock is the authority now. `sessionsPerDay` is a CEILING: sessions are placed until
        the day is full and the rest are dropped, which is also the physically honest answer, because
        nobody performs sixty workouts two hours apart inside one day.
    ]]
    local dropped = 0

    for day = 1, 400 do
        local resting = restDayEvery > 0 and (day % restDayEvery == 0)
        local dayEnds = day * 86400

        if not resting then
            local blocks = math.ceil(sessionsPerDay / 3)
            local placed = 0

            for b = 1, blocks do
                for s = 1, 3 do
                    if placed >= sessionsPerDay then break end

                    -- 20 minutes between sessions in a block, 2 hours between blocks
                    local gap = (s == 1 and (b == 1 and 0 or 7200) or 1200)

                    -- Would this session land in tomorrow? Then it does not happen at all.
                    if now + gap > dayEnds then
                        dropped = dropped + (sessionsPerDay - placed)
                        placed = sessionsPerDay
                        break
                    end

                    placed = placed + 1
                    totalSessions = totalSessions + 1
                    now = now + gap

                    -- fatigue context, from the real window
                    local window = Config.Progression.fatigue.window
                    local recent = 0
                    for i = #sessionTimes, 1, -1 do
                        if (now - sessionTimes[i]) > window then
                            table.remove(sessionTimes, i)
                        else
                            recent = recent + 1
                        end
                    end
                    local rested = lastSession > 0 and (now - lastSession) / 3600.0 or 10.0

                    local entry = Equipment.get(exercises[((totalSessions - 1) % 3) + 1])
                    local gains = Stats.sessionGains(entry, {
                        current = stats, quality = quality,
                        recent = recent, restedHours = rested,
                        multipliers = {}, allowance = spent(),
                    })

                    for k, v in pairs(gains) do
                        stats[k] = (stats[k] or 0) + v
                        if (stats[k] or 0) > (peak[k] or 0) then peak[k] = stats[k] end
                        ledger[#ledger + 1] = { at = now, stat = k, amount = v }
                        anchors[k] = now + Stats.decayConfig(k).grace
                    end

                    sessionTimes[#sessionTimes + 1] = now
                    lastSession = now
                end
            end
        end

        -- Advance to the same time next day, then charge whatever decay is owed. `now` can no
        -- longer be past this: the placement loop above refuses to cross the boundary.
        now = dayEnds

        for _, k in ipairs(Stats.keys()) do
            local periods, anchor = Stats.decayPeriods(k, now, lastSession, anchors[k])
            anchors[k] = anchor
            if periods > 0 then
                stats[k] = Stats.applyDecay(k, stats[k], periods, peak[k], 1.0)
            end
        end

        if done() then return day, totalSessions, stats, dropped end
    end

    return -1, totalSessions, stats, dropped
end
""")

print("  days to take ALL THREE stats to 100%:")
scenarios = [
    ("casual, 9/day, rest 1 day in 3, 85% form", 9, 3, 0.85),
    ("dedicated, 18/day, rest 1 in 7, 90% form", 18, 7, 0.90),
    ("dedicated, 21/day, no rest, 90% form", 21, 0, 0.90),
    ("dedicated, 21/day, no rest, perfect form", 21, 0, 1.00),
    ("no-life, 60/day, perfect form", 60, 0, 1.00),
]

headline = None
for label, per_day, rest, quality in scenarios:
    days, sessions, final, dropped = lua.eval(
        f"SimulateDaysToMax({per_day}, {rest}, {quality})")
    got = dict(final)
    shown = ", ".join(f"{k[:3]} {got[k]:.0f}" for k in stat_keys)

    # A scenario asking for more sessions than fit in a day is reported, not silently truncated:
    # "60 a day" that only ever managed 27 is a different claim from the one in the label.
    note = ""
    if dropped and dropped > 0:
        note = f"   ({dropped} asked for and dropped - the day was full)"

    if days < 0:
        print(f"    {label:<44} NEVER  ({shown})")
        warn(f"'{label}' never reaches 100% in 400 days")
    else:
        print(f"    {label:<44} {days:>3} days, {sessions} sessions{note}")
    if per_day == 21 and rest == 0 and quality == 1.00:
        headline = days

if headline is None or headline < 0:
    fail("the headline scenario never reached 100%")
elif not (12 <= headline <= 17):
    fail(f"BALANCE a dedicated player at perfect form maxes in {headline} days; target ~14")
else:
    print(f"    -> headline: dedicated + perfect form maxes everything in {headline} days")

# --- Passive training must stay well behind the equipment ------------------------------
#
# The whole point of section 13 is that swimming and cycling are worth something and never worth
# as much as a gym. That is a claim about numbers, so it gets checked rather than asserted in a
# comment. The comparison is the best possible passive day against one dedicated gym day.
if lua.eval("Config.Passive.enabled") is not False:
    scale = lua.eval("Config.Passive.globalScale") or 1.0
    total_cap = lua.eval("Config.Passive.dailyCapTotal") or 0

    print("  passive training:")

    activities = ["running", "cycling", "swimming", "diving"]
    uncapped_best = 0.0

    for name in activities:
        cfg = lua.eval(f"Config.Passive.{name}")
        if cfg is None or not cfg["enabled"]:
            print(f"    {name:<10} off")
            continue

        gains = cfg["gains"]
        per_unit = sum(v for _, v in gains.items()) * scale
        own_cap = cfg["dailyCap"] or 0
        ceiling = cfg["ceiling"] or lua.eval("Config.Passive.ceiling") or 100.0
        unit = "minute" if name == "diving" else "km"

        uncapped_best += own_cap if own_cap > 0 else per_unit * 100

        stats = ", ".join(f"{k} {v * scale:+.3f}" for k, v in gains.items())
        print(f"    {name:<10} {stats} per {unit}, cap {own_cap}/day, ceiling {ceiling:.0f}")

    # The gym figure comes from the simulation above: 100 points per stat, three stats, over the
    # headline number of days.
    gym_per_day = (300.0 / headline) if headline and headline > 0 else 0.0
    passive_per_day = min(total_cap, uncapped_best) if total_cap > 0 else uncapped_best
    ratio = (passive_per_day / gym_per_day) if gym_per_day > 0 else 0.0

    print(f"    best passive day {passive_per_day:.2f} points"
          f"  vs  dedicated gym day {gym_per_day:.2f}"
          f"  =  {ratio * 100:.0f}%")

    if ratio > 0.5:
        fail(f"BALANCE passive training is worth {ratio * 100:.0f}% of a gym day; "
             f"the equipment stops being the point above 50%")
    else:
        print(f"    -> the equipment stays ahead: passive is {ratio * 100:.0f}% of a gym day  OK")

    # Decay must outrun the passive cap, or a player can hold condition without ever training.
    decay = lua.eval("Config.Decay.amount") or 0
    if lua.eval("Config.Passive.countsAsTraining") is True:
        print("    countsAsTraining is ON: passive activity resets the decay clock")
    elif passive_per_day >= decay:
        warn(f"passive pays {passive_per_day:.2f}/day against a decay of {decay:.2f}/day, "
             f"so a player who never trains still gains")
    else:
        print(f"    -> decay {decay:.0f}/day beats the passive cap {passive_per_day:.2f}/day, "
              f"so passive alone loses ground  OK")

# an imposed ceiling stops training
capped = lua.eval("""
    Stats.sessionGains(Equipment.get('bench_press'), {
        current = { strength = 60.0, breath = 0, stamina = 0 }, quality = 1.0,
        recent = 0, restedHours = 10, multipliers = {},
        allowance = { total = 0, stats = {} },
        ceilings = { strength = 60.0 },
    })
""")
cd = dict(capped) if capped is not None else {}
if cd.get("strength"):
    fail(f"CEILING strength gained {cd['strength']} at an imposed ceiling of 60")
else:
    print("    imposed ceiling -> strength blocked at the cap  OK")

# a partial ceiling pays only the room left
partial = lua.eval("""
    Stats.sessionGains(Equipment.get('bench_press'), {
        current = { strength = 59.5, breath = 0, stamina = 0 }, quality = 1.0,
        recent = 0, restedHours = 10, multipliers = {},
        allowance = { total = 0, stats = {} },
        ceilings = { strength = 60.0 },
    })
""")
pv = dict(partial).get("strength", 0)
print(f"    0.5 below the ceiling -> pays {pv}")
if abs(pv - 0.5) > 0.001:
    fail(f"CEILING expected exactly 0.5 of headroom, paid {pv}")

# accelerated decay
base = lua.eval("Stats.applyDecay('strength', 100.0, 1, 0, 1.0)")
fast = lua.eval("Stats.applyDecay('strength', 100.0, 1, 0, 2.0)")
print(f"    decay one period: x1.0 -> {base}, x2.0 -> {fast}")
if abs((100.0 - base) * 2 - (100.0 - fast)) > 0.001:
    fail(f"DECAY x2.0 did not cost twice x1.0: {100.0 - base} vs {100.0 - fast}")

# and it is bounded
insane = lua.eval("Stats.applyDecay('strength', 100.0, 1, 0, 999.0)")
bound = lua.eval("Config.Buffs.maxDecayMultiplier")
print(f"    a x999 request is clamped to x{bound} -> {insane}")
if insane < 0.0:
    fail("DECAY a huge multiplier went below zero")

# peak protection
protected = lua.eval("Stats.applyDecay('strength', 80.0, 20, 80.0, 1.0)")
expected_floor = lua.eval("80.0 - Config.Decay.peakProtection")
print(f"    20 periods against a peak of 80 lands at {protected} (floor {expected_floor})")
if abs(protected - expected_floor) > 0.001:
    fail(f"DECAY peak protection: expected {expected_floor}, got {protected}")

# decay is idempotent
lua.execute("""
    __now = 1000000
    __last = __now - (10 * 86400)
    __p1, __a1 = Stats.decayPeriods('strength', __now, __last, 0)
    __p2, __a2 = Stats.decayPeriods('strength', __now, __last, __a1)
""")
p1, p2 = lua.eval("__p1"), lua.eval("__p2")
print(f"    decay after 10 idle days: {p1} periods, then {p2} on a second call")
if p1 <= 0:
    fail("DECAY 10 idle days charged nothing")
if p2 != 0:
    fail(f"DECAY not idempotent: a second call charged {p2} more periods")

# effects stay modest
print("  effects at 100%:")
for stat, name in [("strength", "meleeDamage"), ("strength", "meleeDefense"),
                   ("breath", "underwaterTime"), ("breath", "swimSpeed"),
                   ("stamina", "sprintSpeed"), ("stamina", "healthRecharge")]:
    v = lua.eval(f"Stats.bonus('{stat}', Config.Effects.{stat}.{name}, 100.0)")
    if v is None:
        print(f"    {name:<16} disabled")
        continue
    print(f"    {name:<16} {v:.3f}")
    if name in ("swimSpeed", "sprintSpeed") and v > 1.49:
        fail(f"EFFECTS {name} at 100% is {v}, above the engine ceiling of 1.49")
    if name == "meleeDamage" and v > 1.6:
        warn(f"meleeDamage at 100% is {v} - that is superhero territory")

# effective values honour the overcap
eff = lua.eval("""
    Stats.effective({ strength = 100.0, breath = 0, stamina = 0 },
        { { stat = 'strength', amount = 500, expires = 0 } }, 1000)
""")
top = dict(eff)["strength"]
limit = lua.eval("100.0 + Config.Buffs.overcap")
print(f"    a +500 buff on a maxed stat lands at {top} (cap {limit})")
if top > limit + 0.001:
    fail(f"BUFFS overcap not enforced: {top} > {limit}")

# --- NOBODY BECOMES A SUPERHERO ---------------------------------------------------------
#
# The section 7 ceilings have to be HARD: no stack of buffs, drugs or admin commands may take an
# effect past its configured `max`. That holds because Stats.bonus clamps the value to the stat's
# own max before interpolating - so it is asserted, because removing that clamp would look like a
# harmless simplification and would quietly hand every buffed player superhuman melee.
print("  the effect ceilings are hard:")
breached = []
for stat, name in [("strength", "meleeDamage"), ("strength", "meleeDefense"),
                   ("breath", "underwaterTime"), ("breath", "swimSpeed"),
                   ("stamina", "sprintSpeed"), ("stamina", "healthRecharge")]:
    at_max = lua.eval(f"Stats.bonus('{stat}', Config.Effects.{stat}.{name}, 100.0)")
    if at_max is None:
        continue

    # Every route somebody could try: the buff overcap, a wild admin value, and an absurd one.
    for pushed in (limit, 500.0, 100000.0):
        got = lua.eval(f"Stats.bonus('{stat}', Config.Effects.{stat}.{name}, {pushed})")
        if got is not None and got > at_max + 1e-6:
            breached.append(f"{name} reaches {got:.3f} at a value of {pushed:.0f}, "
                            f"above its max of {at_max:.3f}")

    configured = lua.eval(f"Config.Effects.{stat}.{name}.max")
    if at_max > configured + 1e-6:
        breached.append(f"{name} at 100% is {at_max:.3f}, above its configured {configured}")

if breached:
    fail("SUPERMAN " + "; ".join(breached))
else:
    print("    -> no value of any stat, buffed or forced, takes an effect past its max  OK")


# --------------------------------------------------------------------------- phase 3
print("phase 3: locales")

en = dict(g.Locales.en)
fr = dict(g.Locales.fr)

missing_fr = sorted(set(en) - set(fr))
missing_en = sorted(set(fr) - set(en))

print(f"  en: {len(en)} keys, fr: {len(fr)} keys")
for k in missing_fr:
    fail(f"LOCALE '{k}' is in en.lua but not fr.lua")
for k in missing_en:
    fail(f"LOCALE '{k}' is in fr.lua but not en.lua")

# Format specifier parity. `%%` is a literal percent and must be stripped BEFORE the search:
# the flag class contains a space, so "%% f" in "at %d%% for this" would otherwise match as
# a bogus "% f" specifier.
spec = re.compile(r"%[-+ #0]*[\d.]*[a-zA-Z]")
for k in sorted(set(en) & set(fr)):
    a = spec.findall(str(en[k]).replace("%%", ""))
    b = spec.findall(str(fr[k]).replace("%%", ""))
    if a != b:
        fail(f"LOCALE '{k}' format specifiers differ: en={a} fr={b}")

# every L('...') used in code must exist
used = set()
call = re.compile(r"""\bL\(\s*['"]([\w.]+)['"]""")
for path in lua_files:
    for m in call.finditer(path.read_text(encoding="utf-8")):
        used.add(m.group(1))

for key in sorted(used):
    if key not in en:
        fail(f"LOCALE L('{key}') is used in code but not defined in en.lua")

print(f"  {len(used)} distinct L() keys used in code, all resolved")

unused = sorted(set(en) - used)
# labels referenced through Config/Equipment rather than a literal L() call
indirect = {k for k in unused if k.startswith(("stat.", "equip.", "item."))}
really_unused = [k for k in unused if k not in indirect]
if really_unused:
    warn(f"{len(really_unused)} locale keys are never used: {', '.join(really_unused[:12])}"
         + (" ..." if len(really_unused) > 12 else ""))


# --------------------------------------------------------------------------- phase 4
print("phase 4: manifest")

manifest = (ROOT / "fxmanifest.lua").read_text(encoding="utf-8")
listed = set(re.findall(r"'([\w/]+\.lua)'", manifest))
on_disk = {
    str(p.relative_to(ROOT)).replace("\\", "/")
    for p in lua_files
    if p.name != "fxmanifest.lua"
}

for f in sorted(on_disk - listed):
    fail(f"MANIFEST {f} exists but is not listed in fxmanifest.lua")
for f in sorted(listed - on_disk):
    fail(f"MANIFEST fxmanifest.lua lists {f}, which does not exist")

print(f"  {len(listed)} files listed, {len(on_disk)} on disk")


# --------------------------------------------------------------------------- report
print()
if warnings:
    print(f"{len(warnings)} warning(s):")
    for w in warnings:
        print("  ! " + w)
if errors:
    print(f"\n{len(errors)} ERROR(S):")
    for e in errors:
        print("  x " + e)
    sys.exit(1)

print("all checks passed")
