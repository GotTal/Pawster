"""Validate bundled language packs and their contributor mapping contract (no dependencies)."""
import json
from pathlib import Path
import re
import sys

REPO = Path(__file__).resolve().parents[1]
PACKS = REPO / "App/Resources/Localization"
LEGAL = REPO / "App/Resources/Legal"
TOKEN = re.compile(r"\{\d+\}")
RESOURCE = re.compile(r"[A-Za-z0-9][A-Za-z0-9.-]*\Z")
KEY = re.compile(r"[a-z][A-Za-z0-9]*(?:\.[A-Za-z0-9]+)+\Z")


def load(path):
    def unique(pairs):
        result = {}
        for key, value in pairs:
            if key in result:
                raise ValueError(f"Duplicate JSON key in {path.name}: {key}")
            result[key] = value
        return result
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique)


def validate():
    manifest = load(PACKS / "LanguagePacks.json")
    assert manifest["schemaVersion"] == 1
    assert manifest["fallback"] == "en-US" and manifest["chineseFallback"] == "zh-Hans"
    baseline = load(PACKS / "en-US.json")
    assert baseline and all(KEY.fullmatch(k) and isinstance(v, str) and v.strip() for k, v in baseline.items())
    catalogs, tags, files, warnings = {}, {}, set(), []
    for pack in manifest["languages"]:
        assert re.fullmatch(r"[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*", pack["id"]), pack["id"]
        assert pack["nativeName"].strip()
        assert RESOURCE.fullmatch(pack["file"]) and pack["file"] not in files
        files.add(pack["file"])
        for tag in [pack["id"]] + pack["aliases"]:
            assert re.fullmatch(r"[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*", tag), tag
            normalized = tag.lower()
            assert normalized not in tags, f"Ambiguous language mapping: {tag}"
            assert tag.split('-')[0].lower() == pack["id"].split('-')[0], f"Cross-language alias: {tag}"
            tags[normalized] = pack["id"]
        values = load(PACKS / (pack["file"] + ".json"))
        assert isinstance(values, dict) and values
        assert not (set(values) - set(baseline)), f"Unknown keys in {pack['id']}"
        missing = set(baseline) - set(values)
        if pack["id"] in ("en-US", "zh-Hans"):
            assert not missing, f"Missing base translation keys in {pack['id']}: {sorted(missing)}"
        elif missing:
            warnings.append(f"{pack['id']}: {len(missing)} keys use fallback")
        for key, value in values.items():
            assert isinstance(value, str) and value.strip(), (pack["id"], key)
            assert set(TOKEN.findall(value)) == set(TOKEN.findall(baseline[key])), (pack["id"], key, "placeholder mismatch")
            assert not re.search(r"\{[^{}]*\}", TOKEN.sub("", value)), (pack["id"], key, "invalid placeholder")
        for name, resource in pack["documents"].items():
            assert name in ("Terms", "Privacy", "OpenSourceNotices", "ThirdPartySources", "RustDependencies")
            assert RESOURCE.fullmatch(resource) and (LEGAL / (resource + ".md")).is_file(), resource
        catalogs[pack["id"]] = values
    assert {"en-US", "zh-Hans"} <= set(catalogs)
    for base, target in manifest["languageDefaults"].items():
        assert re.fullmatch(r"[a-z]{2,3}", base) and target in catalogs
        assert base == target.split('-')[0]
    assert manifest["languageDefaults"]["zh"] == "zh-Hans"
    assert manifest["languageDefaults"]["en"] == "en-US"
    source_keys = set()
    for source in (REPO / "App").glob("*.swift"):
        text = source.read_text(encoding="utf-8")
        source_keys.update(re.findall(r'L10n\.text\("([A-Za-z0-9.]+)"', text))
        source_keys.update(re.findall(r'"((?:vpn|neoSpring|onboarding)\.[A-Za-z0-9]+)"', text))
        assert not re.search(r"[\u4e00-\u9fff]", text), f"Unexternalized Chinese text in {source.name}"
    assert source_keys <= set(baseline), sorted(source_keys - set(baseline))
    for resource in ("Terms", "Privacy", "OpenSourceNotices", "ThirdPartySources", "RustDependencies"):
        assert resource in next(p for p in manifest["languages"] if p["id"] == "en-US")["documents"]
    for policy in ("Terms", "Privacy"):
        policy_version = re.search(r'static let policyVersion = "([^"]+)"',
                                   (REPO / "App/AppPreferences.swift").read_text(encoding="utf-8"))[1]
        for resource in (policy, policy + ".en-US"):
            document = (LEGAL / (resource + ".md")).read_text(encoding="utf-8")
            assert policy_version in document and "xkstudio@icloud.com" in document
    english_documents = list(LEGAL.glob("*.en-US.md"))
    assert all(not re.search(r"[\u4e00-\u9fff]", p.read_text(encoding="utf-8")) for p in english_documents)
    for folder in PACKS.glob("*.lproj"):
        text = (folder / "InfoPlist.strings").read_text(encoding="utf-8")
        names = re.findall(r'^"([A-Za-z]+)"\s*=', text, re.MULTILINE)
        assert set(names) == {"CFBundleDisplayName", "PawsterTestDisplayName", "NSLocalNetworkUsageDescription"}
    print(f"Validated {len(catalogs)} language packs, {len(baseline)} keys, {len(source_keys)} referenced keys, "
          f"{len(english_documents)} English documents, and localized app metadata.")
    for warning in warnings:
        print("Notice: " + warning)


if __name__ == "__main__":
    try:
        validate()
    except (AssertionError, ValueError, KeyError, OSError) as error:
        print(f"Localization check failed: {error}", file=sys.stderr)
        sys.exit(1)
