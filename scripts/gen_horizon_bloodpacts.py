"""
Regenerate modules/hotbar/database/horizon_bloodpacts.lua from:
- Blood pact *names* (and rage vs ward order) in petregistry.lua
- MP + SMN level preserved from the existing horizon_bloodpacts.lua when present

Run from repo root: python scripts/gen_horizon_bloodpacts.py
"""
import pathlib
import re
import sys

root = pathlib.Path(__file__).resolve().parents[1]
pet_path = root / "modules/hotbar/petregistry.lua"
out_path = root / "modules/hotbar/database/horizon_bloodpacts.lua"


def decode_lua_string_literal(lit: str) -> str:
    """Decode a Lua single- or double-quoted string literal (minimal escapes)."""
    q = lit[0]
    if len(lit) < 2 or lit[-1] != q:
        return lit
    body = lit[1:-1]
    out = []
    i = 0
    while i < len(body):
        if body[i] == "\\" and i + 1 < len(body):
            c = body[i + 1]
            if c == "\\":
                out.append("\\")
            elif c == "'" and q == "'":
                out.append("'")
            elif c == '"' and q == '"':
                out.append('"')
            elif c == "n":
                out.append("\n")
            elif c == "t":
                out.append("\t")
            else:
                out.append(c)
            i += 2
        else:
            out.append(body[i])
            i += 1
    return "".join(out)


def parse_bloodpact_names(block: str):
    names = []
    for line in block.splitlines():
        line = line.strip()
        if not line.startswith("{") or "name" not in line:
            continue
        m = re.search(
            r"name\s*=\s*((?:'(?:[^'\\]|\\.)*')|(?:\"(?:[^\"\\]|\\.)*\"))",
            line,
        )
        if m:
            names.append(decode_lua_string_literal(m.group(1)))
    return names


def load_stats_from_existing_lua(src: str) -> dict:
    """Map English name -> (mp_cost, smn_lv, kind)."""
    stats = {}
    for line in src.splitlines():
        m = re.match(
            r"^\s*\[(\d+)\]\s*=\s*row\(\s*\d+\s*,\s*((?:'(?:[^'\\]|\\.)*')|(?:\"(?:[^\"\\]|\\.)*\"))\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*'([^']+)'\s*\)",
            line,
        )
        if not m:
            continue
        en = decode_lua_string_literal(m.group(2))
        mp = int(m.group(3))
        lv = int(m.group(4))
        kind = m.group(5)
        stats[en] = (mp, lv, kind)
    return stats


def lua_quote_name(name: str) -> str:
    """Emit a Lua string literal suitable for row(..., <lit>, ...)."""
    if "'" not in name:
        return "'" + name.replace("\\", "\\\\").replace("'", "\\'") + "'"
    if '"' not in name:
        return '"' + name.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return '"' + name.replace("\\", "\\\\").replace('"', '\\"') + '"'


def main():
    text = pet_path.read_text(encoding="utf-8")
    m = re.search(r"M\.bloodPactsRage = \{(.*?)\n\};", text, re.S)
    m2 = re.search(r"M\.bloodPactsWard = \{(.*?)\n\};", text, re.S)
    if not m or not m2:
        print("Could not find bloodPactsRage / bloodPactsWard blocks", file=sys.stderr)
        sys.exit(1)

    rage_names = parse_bloodpact_names(m.group(1))
    ward_names = parse_bloodpact_names(m2.group(1))
    ordered = [(n, "rage") for n in rage_names] + [(n, "ward") for n in ward_names]

    prev_stats = {}
    if out_path.is_file():
        prev_stats = load_stats_from_existing_lua(out_path.read_text(encoding="utf-8"))

    header = """--[[
  horizon_bloodpacts.lua — synthetic "spell-shaped" rows for SMN blood pacts (Horizon).

  WHERE THIS FITS
  - petregistry.lua: English name + avatars per pact (shared with retail).
  - This file: MP cost, SMN level gate, rage vs ward — merged into horizonspells.lua for /ma-style DB shape.
  - horizon_bloodpacts_xiui.lua: status text, corner PNG paths, requiresFlow (XIUI UI only).
  - petregistry.GetBloodPactByName() merges: registry row + xiui overlay + numeric fields from here.

  row(id, en, mp_cost, smn_lv, kind)
  - id: Synthetic ids from 10200 upward (not official client spell ids).
  - en: English name; must match petregistry and macro text.
  - mp_cost: MP. -1 = special cases (e.g. level-scaled / astral-flow style costs handled in actions UI).
  - smn_lv: Required Summoner level; stored as levels[15] (job index 15 = SMN in horizon job tables). 0 = no gate / placeholder.
  - kind: 'rage' | 'ward' → row.type BloodPactRage | BloodPactWard (duplicate-name icon pick, etc.).

  OTHER ROW FIELDS (from row() helper)
  - icon_id -1: Placeholder; hotbar may resolve art elsewhere from name/theme.
  - recast_id = id: Fills spell-row shape; BP shared timers 173/174 are resolved in recast.lua by name, not this id.
  - skill 38: Summoner-ish placeholder; eligibility uses levels[15] + actions logic.

  HOOKUPS: macros/crossbar/cooldowns use pact *name* → GetBloodPactByName (merged). MP/level from this file;
  status/corner icons from xiui. recast.lua matches names against petregistry rage/ward lists for timer 173/174.

  Regenerate: python scripts/gen_horizon_bloodpacts.py
]]"""
    out = []
    out.extend(header.strip().split("\n"))
    out.append("local M = {}")
    out.append("local function row(id, en, mp_cost, smn_lv, kind)")
    out.append("    local levels = {}")
    out.append("    if smn_lv and smn_lv > 0 then")
    out.append("        levels[15] = smn_lv")
    out.append("    end")
    out.append('    local t = (kind == "ward") and "BloodPactWard" or "BloodPactRage"')
    out.append("    return {")
    out.append("        id = id,")
    out.append("        en = en,")
    out.append('        ja = "",')
    out.append("        cast_time = 0,")
    out.append("        element = 0,")
    out.append("        icon_id = -1,")
    out.append("        icon_id_nq = 0,")
    out.append("        levels = levels,")
    out.append("        mp_cost = mp_cost,")
    out.append('        prefix = "/pet",')
    out.append("        range = 0,")
    out.append("        recast = 0,")
    out.append("        recast_id = id,")
    out.append("        requirements = 0,")
    out.append("        skill = 38,")
    out.append("        targets = 32,")
    out.append("        type = t,")
    out.append("    }")
    out.append("end")
    out.append("")
    out.append("M.rows = {")

    byname_lines = []
    nid = 10200
    missing = []
    for name, kind in ordered:
        if name in prev_stats:
            mp_n, lv_n, prev_kind = prev_stats[name]
            if prev_kind != kind:
                print(
                    f"warn: kind mismatch for {name!r}: registry {kind} vs file {prev_kind}",
                    file=sys.stderr,
                )
        else:
            mp_n, lv_n = 0, 0
            missing.append(name)

        qn = lua_quote_name(name)
        out.append(f"    [{nid}] = row({nid}, {qn}, {mp_n}, {lv_n}, {kind!r}),")
        byname_lines.append(f"    [{qn}] = M.rows[{nid}],")
        nid += 1

    out.append("}")
    out.append("")
    out.append("M.byName = {")
    out.extend(byname_lines)
    out.append("}")
    out.append("")
    out.append("return M")

    out_path.write_text("\n".join(out) + "\n", encoding="utf-8")
    print("wrote", out_path, "rows", len(ordered))
    if missing:
        print("warn: no prior stats for names (filled 0,0):", ", ".join(missing), file=sys.stderr)


if __name__ == "__main__":
    main()
