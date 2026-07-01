#!/usr/bin/env python3
import argparse
import json
import re
import sys
import urllib.request
import zipfile
from io import BytesIO
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_OUTPUT = ROOT / "Kaji" / "Resources" / "WorkspaceIgnore" / "generated-ignore-catalog.json"
USER_AGENT = "KajiIgnoreCatalog/1.0"

FORCED_NAMES = {
    ".git", ".kaji", ".build", ".cache", ".next", ".nuxt", ".parcel-cache", ".swiftpm", ".turbo",
    "DerivedData", "Pods", "__pycache__", "build", "coverage", "dist", "node_modules", "target", "vendor", "Vendor",
}
BLOCKED_NAMES = {
    "App", "Assets", "Build", "Configuration", "Debug", "Dependencies", "Docs", "Examples", "Export", "Generated Files",
    "Libraries", "Library", "Package", "Page", "Release", "Resource", "Resources", "Runtime", "Service", "Sources", "System",
    "Temp", "Test", "Tests", "Tools", "Upload", "Uploads", "src", "source", "tmp",
}
SAFE_WORDS = (
    "build", "cache", "coverage", "debug", "dependency", "deps", "dist", "generated", "intermediate", "module",
    "package", "release", "target", "temp", "tmp", "vendor",
)


def fetch(url):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return response.read()


def clean_pattern(raw):
    line = raw.strip()
    if not line or line.startswith("#") or line.startswith("!"):
        return None
    line = line.split("#", 1)[0].strip().replace("\\ ", " ")
    if not line or line.startswith("!"):
        return None
    directory = line.endswith("/") or line.endswith("/**") or line.endswith("/*")
    if not directory:
        return None
    line = line.lstrip("/")
    while line.endswith("/**") or line.endswith("/*"):
        line = line[:-3]
    line = line.rstrip("/")
    if not line or any(character in line for character in "*?[]{}"):
        return None
    return line.split("/")[-1]


def is_safe_name(name):
    if not name or name in (".", "..") or len(name) > 80:
        return False
    if name in BLOCKED_NAMES:
        return False
    if not re.match(r"^[A-Za-z0-9._+@ -]+$", name):
        return False
    if name.startswith("."):
        return True
    lower = name.lower()
    return name in FORCED_NAMES or any(word in lower for word in SAFE_WORDS)


def names_from_template(content):
    names = set()
    for line in content.splitlines():
        name = clean_pattern(line)
        if name and is_safe_name(name):
            names.add(name)
    return names


def github_templates():
    archive = fetch("https://codeload.github.com/github/gitignore/zip/refs/heads/main")
    templates = []
    with zipfile.ZipFile(BytesIO(archive)) as bundle:
        for name in bundle.namelist():
            if not name.endswith(".gitignore"):
                continue
            templates.append(bundle.read(name).decode("utf-8", "replace"))
    return templates


def toptal_templates():
    payload = json.loads(fetch("https://www.toptal.com/developers/gitignore/api/list?format=json"))
    return [entry.get("contents", "") for entry in payload.values()]


def build_catalog():
    sources = {
        "github": github_templates(),
        "toptal": toptal_templates(),
    }
    directory_names = set(FORCED_NAMES)
    for templates in sources.values():
        for content in templates:
            directory_names.update(names_from_template(content))
    return {
        "schemaVersion": 1,
        "sourceTemplateCounts": {name: len(templates) for name, templates in sorted(sources.items())},
        "directoryNames": sorted(directory_names, key=lambda value: (value.lower(), value)),
    }


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", default=str(DEFAULT_OUTPUT))
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()

    catalog = build_catalog()
    encoded = json.dumps(catalog, indent=2, sort_keys=True) + "\n"
    output = Path(args.output)
    if args.verify:
        existing = output.read_text() if output.exists() else ""
        if existing != encoded:
            print(f"{output} is stale. Run scripts/update-ignore-catalog.py", file=sys.stderr)
            return 1
        return 0
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(encoded)
    print(f"Wrote {output} with {len(catalog['directoryNames'])} directory names")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
