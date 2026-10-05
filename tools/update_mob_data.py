"""Build offline mob data from pinned LSB/Phoenix YAML and Horizon overrides."""

import argparse
from copy import deepcopy
import io
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import tempfile
from urllib.request import Request, urlopen
import zipfile

import yaml


ROOT = Path(__file__).resolve().parents[1]
SOURCES = ROOT / "tools/mob_data_sources.json"
OUTPUT = ROOT / "XIUI/data/mobs"
LOADER = getattr(yaml, "CSafeLoader", yaml.SafeLoader)
ELEMENTS = {
    "fire": "Fire", "ice": "Ice", "wind": "Wind", "earth": "Earth",
    "thunder": "Lightning", "water": "Water", "light": "Light", "dark": "Dark",
}
PHYSICAL = {"slashing": "Slashing", "piercing": "Piercing", "blunt": "Impact", "h2h": "H2H"}
PHYSICAL_MODS = {"slashing": "slash_sdt", "piercing": "pierce_sdt", "blunt": "impact_sdt", "h2h": "hth_sdt"}


def read_yaml(path):
    return yaml.load(path.read_text(encoding="utf-8"), Loader=LOADER) or {}


def merge_attributes(base, override):
    """Maps override individual entries; arrays and scalars replace inherited values."""
    result = deepcopy(base)
    for key, value in override.items():
        if value is None:
            continue
        if isinstance(value, dict):
            result[key] = merge_attributes(result.get(key, {}), value)
        else:
            result[key] = deepcopy(value)
    return result


def merge_patch(base, patch):
    """YAML modules use JSON merge-patch semantics, including null deletions."""
    if not isinstance(patch, dict):
        return deepcopy(patch)
    result = deepcopy(base) if isinstance(base, dict) else {}
    for key, value in patch.items():
        if value is None:
            result.pop(key, None)
        else:
            result[key] = merge_patch(result.get(key), value)
    return result


def module_roots(source):
    init = source / "modules/init.txt"
    if not init.exists():
        raise ValueError("Phoenix source is missing modules/init.txt")
    roots = []
    for raw in init.read_text(encoding="utf-8").splitlines():
        entry = raw.split("#", 1)[0].strip().rstrip("/")
        parts = PurePosixPath(entry).parts
        if len(parts) >= 2 and parts[1] == "data":
            path = source / "modules" / entry
            if not path.is_dir():
                raise ValueError(f"Enabled YAML module is missing: {entry}")
            # A parent entry supplies its own data; nested modules are listed separately.
            if path not in roots:
                roots.append(path)
    return roots


def load_document(source, relative, modules):
    document = read_yaml(source / "data" / relative)
    for module in modules:
        patch = module / relative
        if patch.exists():
            document = merge_patch(document, read_yaml(patch))
    return document


def species_attributes(document):
    species = {}
    for ecosystem in document["ecosystems"].values():
        for family_name, family in ecosystem["families"].items():
            family_attributes = merge_attributes(ecosystem.get("attributes", {}), family.get("attributes", {}))
            for name, entry in family["species"].items():
                if name in species:
                    raise ValueError(f"Duplicate species: {name}")
                species[name] = (family_name, merge_attributes(family_attributes, entry.get("attributes", {})))
    return species


def multiplier(value):
    return round(max(0, min(3, 1 + value / 10000)), 6)


def make_record(template_name, template, spawn, species, jobs, immunities, detects):
    family, inherited = species[template["species"]]
    attributes = merge_attributes(inherited, template.get("attributes", {}))
    attributes = merge_attributes(attributes, spawn.get("attributes", {}))
    behavior = attributes.get("behaviors", {})
    resists = attributes.get("resists", {})
    mods = attributes.get("mods", {})
    detection = attributes.get("detects", [])
    if "detection" in attributes.get("mob_mods", {}):
        mask = attributes["mob_mods"]["detection"]
        detection = [name for name, flag in detects.items() if flag and mask & flag]
    true_detection = behavior.get("true_detection", False)
    record = {
        "Name": template.get("display_name", template_name).replace("_", " "),
        "Family": family,
        "Job": jobs[attributes.get("jobs", ["none", "none"])[0]],
        "Notorious": "notorious" in template.get("type", []),
        "Aggro": behavior.get("aggressive", False),
        "Link": behavior.get("links", False),
        "Sight": "sight" in detection and not true_detection,
        "TrueSight": "sight" in detection and true_detection,
        "Sound": "hearing" in detection and not true_detection,
        "TrueSound": "hearing" in detection and true_detection,
        "Blood": "lowhp" in detection,
        "Magic": "magic" in detection,
        "JA": "ability" in detection,
        "Scent": "scent" in detection,
        "Immunities": 0,
        "Modifiers": {},
    }
    level = spawn.get("level", [0, 0])
    if level != [0, 0]:
        record.update(MinLevel=level[0], MaxLevel=level[1])
    for status in resists.get("immune_status", []):
        record["Immunities"] |= immunities[status]
    for source_key, target_key in PHYSICAL.items():
        value = resists.get("dmg_physical", {}).get(source_key, 0) + mods.get(PHYSICAL_MODS[source_key], 0)
        record["Modifiers"][target_key] = multiplier(value)
    magic = resists.get("dmg_magic", {})
    all_magic = multiplier(magic.get("all", 0) + mods.get("udmgmagic", 0))
    ranks = {}
    for source_key, target_key in ELEMENTS.items():
        value = magic.get(source_key, 0) + mods.get(source_key + "_sdt", 0)
        record["Modifiers"][target_key] = round(multiplier(value) * all_magic, 6)
        ranks[target_key] = resists.get("rank_element", {}).get(source_key, 0) + mods.get(source_key + "_res_rank", 0)
    record["ElementRanks"] = ranks
    # Resistance ranks affect accuracy/resist tiers, not damage percentages or immunity.
    return record


def lua(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, dict):
        return "{" + ",".join(
            (str(k) if isinstance(k, str) and re.fullmatch(r"[A-Za-z][A-Za-z0-9_]*", k) else "[" + lua(k) + "]")
            + "=" + lua(v) for k, v in value.items()
        ) + "}"
    raise TypeError(type(value))


def compile_zone(document, species, jobs, immunities, detects):
    templates = document.get("templates", {})
    indices = {}
    names = {}
    for entity_id, spawn in sorted(document["spawns"].items()):
        template_name = spawn.get("template")
        if not template_name:
            continue  # Reserved IDs carry no mob data.
        template = templates[template_name]
        record = make_record(template_name, template, spawn, species, jobs, immunities, detects)
        index = int(entity_id) & 0xFFF
        if index in indices:
            raise ValueError(f"Duplicate entity index: {index}")
        indices[index] = record
        aliases = {record["Name"], template_name.replace("_", " ")}
        for alias in sorted(aliases):
            if alias not in names:
                names[alias] = deepcopy(record)
            else:
                generic = names[alias]
                if "MinLevel" in record:
                    generic["MinLevel"] = min(generic.get("MinLevel", record["MinLevel"]), record["MinLevel"])
                    generic["MaxLevel"] = max(generic.get("MaxLevel", record["MaxLevel"]), record["MaxLevel"])
                if generic["Job"] != record["Job"]:
                    generic["Job"] = 0
    return names, indices


def render_zone(names, indices, source):
    rows = []
    row_ids = {}

    def row_id(record):
        encoded = lua(record)
        if encoded not in row_ids:
            row_ids[encoded] = len(rows) + 1
            rows.append(encoded)
        return row_ids[encoded]

    name_refs = [(name, row_id(record)) for name, record in sorted(names.items())]
    index_refs = [(index, row_id(record)) for index, record in sorted(indices.items())]
    lines = [f"-- Generated from {source['repository']} @ {source['commit']}. {source.get('license', 'GPL-3.0-or-later')}.", "local records = {"]
    lines.extend("    " + row + "," for row in rows)
    lines.extend(["};", "return {", "    Names = {"])
    lines.extend(f"        [{lua(name)}] = records[{ref}]," for name, ref in name_refs)
    lines.extend(["    },", "    Indices = {"])
    lines.extend(f"        [{index}] = records[{ref}]," for index, ref in index_refs)
    lines.extend(["    },", "};", ""])
    return "\n".join(lines)


def generate(source, config, output):
    modules = module_roots(source) if config["modules"] else []
    species = species_attributes(load_document(source, "ecosystems.yaml", modules))
    zones = read_yaml(source / "data/enums/zone.yaml")["values"]
    jobs = read_yaml(source / "data/enums/job.yaml")["values"]
    immunities = read_yaml(source / "data/enums/immunity.yaml")["values"]
    detects = read_yaml(source / "data/enums/detects.yaml")["values"]
    files = {}
    count = 0
    for zone_name, zone_id in sorted(zones.items(), key=lambda entry: entry[1]):
        relative = Path("zones") / zone_name / "mobs.yaml"
        if not (source / "data" / relative).exists():
            continue
        document = load_document(source, relative, modules)
        names, indices = compile_zone(document, species, jobs, immunities, detects)
        if indices:
            files[f"{zone_id}.lua"] = render_zone(names, indices, config)
            count += len(indices)
    if not files:
        raise ValueError("Source produced no mob data")
    output.mkdir(parents=True, exist_ok=True)
    for filename, content in files.items():
        (output / filename).write_text(content, encoding="utf-8", newline="\n")
    for old in output.glob("[0-9]*.lua"):
        if old.name not in files:
            old.unlink()
    manifest = dict(config, zones=len(files), spawns=count,
                    yaml_modules=[str(p.relative_to(source)).replace("\\", "/") for p in modules])
    (output / "source.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"{config['repository']}: {len(files)} zones, {count} spawns", flush=True)


LUA_STRING = r"'(?:\\.|[^'\\])*'|\"(?:\\.|[^\"\\])*\""
HORIZON_ENTRY = re.compile(r"\s*\[(" + LUA_STRING + r"|\d+)\]\s*=\s*\{(.*)\}\s*,?\s*")


def decode_lua_string(value):
    escapes = {"\\": "\\", "'": "'", '"': '"', "n": "\n", "r": "\r", "t": "\t"}
    content = value[1:-1]
    if re.search(r"\\(?![\\'\"nrt])", content):
        raise ValueError(f"Unsupported Lua string escape: {value}")
    return re.sub(r"\\(.)", lambda match: escapes[match[1]], content)


def compile_horizon(text):
    """Read the generated table format without executing upstream Lua."""
    sections = {}
    section = None
    for line in text.splitlines():
        start = re.fullmatch(r"\s*(Names|Indices)\s*=\s*\{\s*", line)
        if start:
            section = sections.setdefault(start[1], {})
            continue
        if section is None or not line.lstrip().startswith("["):
            continue
        entry = HORIZON_ENTRY.fullmatch(line)
        if not entry:
            raise ValueError(f"Unrecognized Horizon record: {line}")
        raw_key, fields = entry.groups()
        key = int(raw_key) if raw_key.isdigit() else decode_lua_string(raw_key)
        name = re.search(r"(?:^|,)\s*Name\s*=\s*(" + LUA_STRING + r")", fields)
        if not name:
            raise ValueError(f"Horizon record has no name: {key}")
        record = {"Name": decode_lua_string(name[1])}
        for field in ("Job", "MinLevel", "MaxLevel"):
            value = re.search(r"(?:^|,)\s*" + field + r"\s*=\s*(\d+)(?=\s*[,}]|\s*$)", fields)
            if not value:
                raise ValueError(f"Horizon record has no {field}: {key}")
            record[field] = int(value[1])
        if key in section:
            raise ValueError(f"Duplicate Horizon record: {key}")
        section[key] = record
    if set(sections) != {"Names", "Indices"}:
        raise ValueError("Horizon data must include Names and Indices")
    return sections["Names"], sections["Indices"]


def generate_horizon(source, config, output):
    files = {}
    for path in sorted((source / "mobdb/data").glob("[0-9]*.lua")):
        names, indices = compile_horizon(path.read_text(encoding="utf-8"))
        files[path.name] = render_zone(names, indices, config)
    if not files:
        raise ValueError("Source produced no Horizon overrides")
    output.mkdir(parents=True, exist_ok=True)
    for filename, content in files.items():
        (output / filename).write_text(content, encoding="utf-8", newline="\n")
    for old in output.glob("[0-9]*.lua"):
        if old.name not in files:
            old.unlink()
    manifest = dict(config, zones=len(files))
    (output / "source.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(f"{config['repository']}: {len(files)} Horizon overlays", flush=True)


def fetch_source(config, destination):
    url = f"https://codeload.github.com/{config['repository']}/zip/{config['commit']}"
    with urlopen(url, timeout=60) as response:
        archive = zipfile.ZipFile(io.BytesIO(response.read()))
    with archive:
        for entry in archive.infolist():
            relative = PurePosixPath(*PurePosixPath(entry.filename).parts[1:])
            if entry.is_dir() or ".." in relative.parts:
                continue
            if config.get("format") == "horizon":
                include = str(relative).startswith("mobdb/data/") and relative.suffix == ".lua" and relative.stem.isdigit()
            else:
                include = str(relative).startswith("data/") or (str(relative).startswith("modules/") and relative.suffix in (".yaml", ".txt"))
            if not include:
                continue
            target = destination.joinpath(*relative.parts)
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(archive.read(entry))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--provider", choices=("all", "lsb", "phoenix", "horizon"), default="all")
    parser.add_argument("--source", type=Path, help="Use a local checkout for one provider")
    parser.add_argument("--output", type=Path, default=OUTPUT, help="Generated data directory (default: XIUI/data/mobs)")
    parser.add_argument("--refresh", action="store_true", help="Resolve the configured upstream branch and update its pin")
    args = parser.parse_args()
    if args.source and args.provider == "all":
        parser.error("--source requires a single --provider")
    if args.source and args.refresh:
        parser.error("--source and --refresh cannot be combined")
    configs = json.loads(SOURCES.read_text(encoding="utf-8"))
    selected = configs if args.provider == "all" else {args.provider: configs[args.provider]}
    output = args.output.resolve()
    for name, config in selected.items():
        if args.refresh:
            request = Request(f"https://api.github.com/repos/{config['repository']}/commits/{config['branch']}",
                              headers={"User-Agent": "XIUI-mob-data"})
            with urlopen(request, timeout=30) as response:
                config["commit"] = json.load(response)["sha"]
        generator = generate_horizon if config.get("format") == "horizon" else generate
        if args.source:
            generator(args.source.resolve(), config, output / name)
        else:
            with tempfile.TemporaryDirectory(prefix="xiui-mobs-") as temp:
                source = Path(temp)
                fetch_source(config, source)
                generator(source, config, output / name)
    shutil.copyfile(ROOT / "LICENSE", output / "COPYING")
    if args.refresh:
        SOURCES.write_text(json.dumps(configs, indent=2) + "\n", encoding="utf-8", newline="\n")


if __name__ == "__main__":
    main()
