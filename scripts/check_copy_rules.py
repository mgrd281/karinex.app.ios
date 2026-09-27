#!/usr/bin/env python3
"""Enforces the KARINEX copy rules (PROMPT.md sections 2 and 3, contract rules 5 and 6).

Checks:

* No en dash (U+2013) or em dash (U+2014) in any String Catalog value, in any language,
  including plural, device and substitution variations. Store content rendered from
  Shopify may contain dashes; app-authored copy never does.
* The words "PayPal", "Hotline", "Telefon" and "phone number" and the `tel:` URL scheme
  (all case-insensitive) never appear in Swift files (code and comments), String Catalogs
  or Info.plist files. KARINEX offers no PayPal and no phone support.
* String Catalogs never make license claims: "100% legal", "Original-Lizenz" and
  "geprüfte Lizenz(en)" (with spelling variants).

Ignored: `docs/`, `PROMPT.md`, recorded fixture JSON (store content), build products and
SwiftPM checkouts, and this script itself.

Usage::

    python3 scripts/check_copy_rules.py [--root /path/to/repo]

Exit status: 0 when the repository complies, 1 on violations, 2 on usage errors.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# MARK: - Rules

DASHES = {"–": "en dash (U+2013)", "—": "em dash (U+2014)"}

FORBIDDEN_WORDS = (
    ("PayPal", re.compile(r"paypal", re.IGNORECASE)),
    ("Hotline", re.compile(r"hotline", re.IGNORECASE)),
    ("Telefon", re.compile(r"telefon", re.IGNORECASE)),
    ("phone number", re.compile(r"phone\s+numbers?", re.IGNORECASE)),
    ("tel: URL scheme", re.compile(r"(?<![A-Za-z0-9])tel:", re.IGNORECASE)),
)

FORBIDDEN_CLAIMS = (
    ("100% legal", re.compile(r"100\s*%\s*legal", re.IGNORECASE)),
    ("Original-Lizenz", re.compile(r"original[\s -]*lizenz", re.IGNORECASE)),
    ("geprüfte Lizenz", re.compile(r"gepr(?:ü|ue)fte[\s -]*lizenz", re.IGNORECASE)),
)

EXCLUDED_DIRECTORIES = frozenset(
    {".git", ".build", ".swiftpm", ".spm", "SourcePackages", "DerivedData", "build", "vendor", "node_modules", "docs"}
)
EXCLUDED_FILES = frozenset({"PROMPT.md"})


# MARK: - Reporting


@dataclass
class Report:
    """Collects violations and prints them, with GitHub annotations in Actions."""

    root: Path
    violations: list[str] = field(default_factory=list)

    def add(self, path: Path, line: int | None, message: str) -> None:
        """Records one violation."""
        relative = self.relative(path)
        location = f"{relative}:{line}" if line else relative
        self.violations.append(f"{location}: error: {message}")
        if os.environ.get("GITHUB_ACTIONS") == "true":
            line_part = f",line={line}" if line else ""
            print(f"::error file={relative}{line_part}::{message.replace('%', '%25')}")

    def relative(self, path: Path) -> str:
        """`path` relative to the repository root."""
        try:
            return str(path.resolve().relative_to(self.root))
        except ValueError:
            return str(path)


# MARK: - File discovery


def is_fixture_json(relative_parts: tuple[str, ...]) -> bool:
    """Whether a path is recorded fixture data (JSON inside a `Fixtures` directory)."""
    return relative_parts[-1].endswith(".json") and "Fixtures" in relative_parts[:-1]


def candidate_files(root: Path, script: Path) -> list[Path]:
    """Swift files, String Catalogs and Info.plist files of the repository."""
    files: list[Path] = []
    for directory, subdirectories, names in os.walk(root):
        subdirectories[:] = sorted(name for name in subdirectories if name not in EXCLUDED_DIRECTORIES)
        for name in sorted(names):
            path = Path(directory) / name
            if name in EXCLUDED_FILES or path.resolve() == script:
                continue
            parts = path.relative_to(root).parts
            if is_fixture_json(parts):
                continue
            if name.endswith(".swift") or name.endswith(".xcstrings") or name == "Info.plist":
                files.append(path)
    return files


# MARK: - Checks


def check_forbidden_words(path: Path, text: str, report: Report) -> None:
    """Reports every forbidden word or scheme, line by line."""
    for number, line in enumerate(text.splitlines(), start=1):
        for label, pattern in FORBIDDEN_WORDS:
            if pattern.search(line):
                report.add(path, number, f"forbidden word: {label} (see PROMPT.md section 2)")


def catalog_values(node: object, trail: str) -> list[tuple[str, str]]:
    """All (variation trail, value) pairs of a localization node."""
    values: list[tuple[str, str]] = []
    if not isinstance(node, dict):
        return values
    unit = node.get("stringUnit")
    if isinstance(unit, dict) and isinstance(unit.get("value"), str):
        values.append((trail, unit["value"]))
    variations = node.get("variations")
    if isinstance(variations, dict):
        for kind, cases in variations.items():
            if isinstance(cases, dict):
                for case, child in cases.items():
                    values += catalog_values(child, f"{trail}/{kind}.{case}")
    substitutions = node.get("substitutions")
    if isinstance(substitutions, dict):
        for name, substitution in substitutions.items():
            values += catalog_values(substitution, f"{trail}/substitution.{name}")
    return values


def line_of(lines: list[str], needle: str) -> int | None:
    """First line containing `needle`, or None."""
    for number, line in enumerate(lines, start=1):
        if needle in line:
            return number
    return None


def check_catalog(path: Path, text: str, report: Report) -> None:
    """Dash and claim checks on every value of a String Catalog."""
    lines = text.splitlines()
    try:
        document = json.loads(text)
    except json.JSONDecodeError as error:
        report.add(path, error.lineno, f"invalid JSON: {error.msg}")
        return
    strings = document.get("strings") if isinstance(document, dict) else None
    if not isinstance(strings, dict):
        return
    for key, entry in sorted(strings.items()):
        if not isinstance(entry, dict):
            continue
        localizations = entry.get("localizations")
        if not isinstance(localizations, dict):
            continue
        for language, node in sorted(localizations.items()):
            for trail, value in catalog_values(node, ""):
                encoded = json.dumps(value, ensure_ascii=False)[1:-1]
                line = line_of(lines, encoded) or line_of(lines, json.dumps(key, ensure_ascii=False))
                where = f"key '{key}' [{language}{trail}]"
                for dash, name in DASHES.items():
                    if dash in value:
                        report.add(path, line, f"{where}: {name} in app copy; use a comma, period, colon or 'bis'")
                for label, pattern in FORBIDDEN_CLAIMS:
                    if pattern.search(value):
                        report.add(path, line, f"{where}: forbidden claim '{label}' (see PROMPT.md section 2)")


# MARK: - Entry point


def main(argv: list[str]) -> int:
    """Runs all checks and returns the exit status."""
    parser = argparse.ArgumentParser(description="Check KARINEX copy rules.")
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repository root (default: the parent of this script's directory)",
    )
    arguments = parser.parse_args(argv)
    root = arguments.root.resolve()
    if not root.is_dir():
        print(f"error: {root} is not a directory", file=sys.stderr)
        return 2
    report = Report(root=root)
    files = candidate_files(root, Path(__file__).resolve())
    for path in files:
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            report.add(path, None, f"cannot read file: {error}")
            continue
        check_forbidden_words(path, text, report)
        if path.name.endswith(".xcstrings"):
            check_catalog(path, text, report)

    for violation in report.violations:
        print(violation)
    summary = f"check_copy_rules: {len(files)} file(s) checked: "
    if report.violations:
        print(summary + f"{len(report.violations)} violation(s)")
        return 1
    print(summary + "OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
