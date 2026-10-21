#!/usr/bin/env python3
"""Verify stable-key ko/en coverage for every runtime content display field."""
import json
import re
import sys
from pathlib import Path

HANGUL = re.compile(r"[\uac00-\ud7a3]")
PLACEHOLDER = re.compile(r"%(?:[-+0 #]*\d*(?:\.\d+)?)?[sdif]")


def unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError(f"duplicate JSON key: {key}")
        result[key] = value
    return result


def read(path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=unique_object)


def expected_content(root):
    entries = {}
    groups = {
        "actions": ("id", ("label", "place", "description")),
        "events": ("id", ("title", "body")),
        "endings": ("code", ("title", "summary", "shareText", "hint")),
        "npcs": ("id", ("name", "role", "look", "blurb")),
    }
    for group, (identifier, fields) in groups.items():
        document = read(root / "data" / f"{group}.json")
        for item in document[group]:
            base = f"{group}.{item[identifier]}"
            for field in fields:
                entries[f"{base}.{field}"] = item[field]
            for requirement in item.get("requirements", []):
                if "label" in requirement:
                    req_id = requirement.get("flag", requirement["type"])
                    entries[f"{base}.requirements.{req_id}.label"] = requirement["label"]
            for choice in item.get("choices", []):
                choice_key = f"{base}.choices.{choice['id']}"
                entries[f"{choice_key}.label"] = choice["label"]
                if "locked_reason" in choice:
                    entries[f"{choice_key}.locked_reason"] = choice["locked_reason"]
                for outcome in choice["outcomes"]:
                    entries[f"{choice_key}.outcomes.{outcome['kind']}.result_text"] = outcome["result_text"]
        for path in document.get("paths", []):
            entries[f"paths.{path['id']}.label"] = path["label"]
        for band in document.get("affinity_bands", []):
            entries[f"affinity_bands.{band['id']}.name"] = band["name"]
        for key, value in document.get("bands", {}).items():
            entries[f"bands.{key}"] = value
    return entries


def check(root):
    catalogs = {locale: read(root / "data/i18n" / f"{locale}.json") for locale in ("ko", "en")}
    expected = expected_content(root)
    errors = []
    for locale, catalog in catalogs.items():
        for key, value in catalog.items():
            if HANGUL.search(key) or not re.fullmatch(r"[A-Za-z0-9_.:-]+", key):
                errors.append(f"{locale}: key is not a stable ID: {key}")
            if not isinstance(value, str) or not value.strip():
                errors.append(f"{locale}: empty or invalid text: {key}")
            if locale == "en" and isinstance(value, str) and HANGUL.search(value):
                errors.append(f"en: untranslated Korean: {key}")
        for key, original in expected.items():
            if key not in catalog:
                errors.append(f"{locale}: missing content key: {key}")
            elif locale == "ko" and catalog[key] != original:
                errors.append(f"ko: source text changed: {key}")
        other = catalogs["en" if locale == "ko" else "ko"]
        for key in catalog.keys() - other.keys():
            errors.append(f"{locale}: key absent from other locale: {key}")
    for key in catalogs["ko"].keys() & catalogs["en"].keys():
        ko, en = catalogs["ko"][key], catalogs["en"][key]
        if not isinstance(ko, str) or not isinstance(en, str):
            continue
        if PLACEHOLDER.findall(ko) != PLACEHOLDER.findall(en):
            errors.append(f"format placeholder mismatch: {key}")
        # Displayed numeric thresholds must survive translation unchanged.
        if re.findall(r"\d+", ko) != re.findall(r"\d+", en):
            errors.append(f"numeric text mismatch: {key}")
    # Runtime UI calls with literal keys must be covered as well as content.
    for file in (root / "src/ui").glob("*.gd"):
        source = file.read_text(encoding="utf-8")
        keys = re.findall(r'_tr\("([^"\n]+)"\)', source)
        keys += re.findall(r'SaLocalization\.text\("ui\.([^"\n]+)"\s*,', source)
        for suffix in keys:
            key = "ui." + suffix
            if key not in catalogs["ko"]:
                errors.append(f"missing UI key in {file.name}: {key}")
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print(f"Localization OK: {len(expected)} content strings, {len(catalogs['ko'])} keys per locale, ko/en complete")
    return 0


if __name__ == "__main__":
    sys.exit(check(Path(sys.argv[1] if len(sys.argv) > 1 else ".")))
