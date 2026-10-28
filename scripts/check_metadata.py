#!/usr/bin/env python3
"""Checks the App Store metadata in `fastlane/metadata` against App Store Connect limits and the
KARINEX copy rules (PROMPT.md sections 2 and 3).

* Every locale has every file, and the 13 app languages are all present.
* Limits: name and subtitle 30 characters, keywords 100, promotional text 170, description
  and release notes 4000.
* No en or em dashes, no PayPal, Hotline, Telefon, phone number or `tel:`, and no license
  claims ("100% legal", "Original-Lizenz", "geprüfte Lizenz"). Statements about prices,
  ratings or sales figures do not belong in metadata either; reviewers check those by hand.

Usage: python3 scripts/check_metadata.py [--root /path/to/repo]
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

LOCALES = ["de-DE", "en-GB", "pl", "nl-NL", "pt-PT", "sv", "da", "es-ES", "fr-FR", "it", "fi", "ro", "el"]
LIMITS = {
    "name.txt": 30,
    "subtitle.txt": 30,
    "keywords.txt": 100,
    "promotional_text.txt": 170,
    "description.txt": 4000,
    "release_notes.txt": 4000,
    "privacy_url.txt": 255,
    "support_url.txt": 255,
    "marketing_url.txt": 255,
}
FORBIDDEN = [
    ("en or em dash", re.compile("[–—]")),
    ("PayPal", re.compile(r"paypal", re.I)),
    ("Hotline", re.compile(r"hotline", re.I)),
    ("Telefon", re.compile(r"telefon", re.I)),
    ("phone number", re.compile(r"phone\s+numbers?", re.I)),
    ("tel: URL scheme", re.compile(r"(?<![A-Za-z0-9])tel:", re.I)),
    ("100% legal", re.compile(r"100\s*%\s*legal", re.I)),
    ("Original-Lizenz", re.compile(r"original[\s -]*lizenz", re.I)),
    ("geprüfte Lizenz", re.compile(r"gepr(?:ü|ue)fte[\s -]*lizenz", re.I)),
]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parent.parent)
    root = parser.parse_args().root / "fastlane" / "metadata"
    errors: list[str] = []
    for locale in LOCALES:
        for name, limit in LIMITS.items():
            path = root / locale / name
            if not path.is_file():
                errors.append(f"{path}: missing")
                continue
            text = path.read_text(encoding="utf-8").strip()
            if not text:
                errors.append(f"{path}: empty")
            if len(text) > limit:
                errors.append(f"{path}: {len(text)} characters, limit {limit}")
            if name.endswith("_url.txt") and not text.startswith("https://"):
                errors.append(f"{path}: not an https URL")
            for label, pattern in FORBIDDEN:
                if pattern.search(text):
                    errors.append(f"{path}: forbidden: {label}")
        keywords = root / locale / "keywords.txt"
        if keywords.is_file() and ", " in keywords.read_text(encoding="utf-8"):
            errors.append(f"{keywords}: separate keywords with commas only (spaces count as characters)")
    for error in errors:
        print(f"error: {error}")
    print(f"check_metadata: {len(LOCALES)} locale(s): {'OK' if not errors else f'{len(errors)} violation(s)'}")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
