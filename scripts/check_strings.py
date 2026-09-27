#!/usr/bin/env python3
"""Validates the String Catalogs (``*.xcstrings``) of the KARINEX app.

Every catalog under ``App/`` and ``Packages/`` is checked for:

* well-formed JSON with ``sourceLanguage`` ``de``;
* a translator ``comment`` on every key and lowercase dot-path key names;
* a translated, non-empty value (``state`` ``translated``) in all 11 app languages
  (de en pl nl pt-PT sv da es fr it fi), including every plural, device and substitution
  variation;
* complete plural variations for each language's CLDR cardinal categories (pl: one, few,
  many, other; pt-PT, es, fr, it may add many; everything else one, other; zero is always
  allowed);
* format-specifier parity with the German source (``%lld``, ``%@``, ``%d``, positional
  ``%1$@`` and ``%#@name@`` substitutions): the same arguments with the same types at the
  same positions in every language;
* consistency with the Swift code of the module that owns the catalog: every key referenced
  through ``Text("key", bundle: .module)`` or ``String(localized: "key", bundle: .module)``
  (in the App target: ``Text("key")`` / ``String(localized: "key")`` and SwiftUI titles such
  as ``Label("key", systemImage:)``) exists, package code never forgets ``bundle: .module``
  and never passes a key to a SwiftUI title that resolves it in the main bundle, and catalog
  keys that are never referenced are errors.

A key also counts as referenced when it appears verbatim as a string literal in the module
(for example ``static let titleKey: String.LocalizationValue = "home.title"``), so keys
that are selected through constants remain valid.

Catalogs named ``InfoPlist.xcstrings`` or ``AppShortcuts.xcstrings`` hold Info.plist and
App Shortcut phrases; they get the content checks but no code-reference checks.

Usage::

    python3 scripts/check_strings.py                      # what CI runs
    python3 scripts/check_strings.py --allow-missing-languages   # only de and en required
    python3 scripts/check_strings.py --root /path/to/repo

Exit status: 0 when everything passes, 1 when errors were found, 2 on usage errors.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# MARK: - Configuration

SOURCE_LANGUAGE = "de"
APP_LANGUAGES = ("de", "en", "pl", "nl", "pt-PT", "sv", "da", "es", "fr", "it", "fi")
MINIMUM_LANGUAGES = ("de", "en")

PLURAL_CATEGORY_NAMES = frozenset({"zero", "one", "two", "few", "many", "other"})
DEFAULT_REQUIRED_PLURALS = frozenset({"one", "other"})
REQUIRED_PLURALS = {"pl": frozenset({"one", "few", "many", "other"})}
# CLDR cardinal categories per language. `zero` is accepted everywhere because Apple's
# plural rules support an explicit zero case in every language.
ALLOWED_PLURALS = {
    "de": frozenset({"one", "other"}),
    "en": frozenset({"one", "other"}),
    "pl": frozenset({"one", "few", "many", "other"}),
    "nl": frozenset({"one", "other"}),
    "pt-PT": frozenset({"one", "many", "other"}),
    "sv": frozenset({"one", "other"}),
    "da": frozenset({"one", "other"}),
    "es": frozenset({"one", "many", "other"}),
    "fr": frozenset({"one", "many", "other"}),
    "it": frozenset({"one", "many", "other"}),
    "fi": frozenset({"one", "other"}),
}

SEARCH_ROOTS = ("App", "Packages")
EXCLUDED_DIRECTORIES = frozenset(
    {".build", ".swiftpm", ".spm", "SourcePackages", "DerivedData", "build", "checkouts", "__Snapshots__", ".git"}
)
# Test targets do not own catalogs and never show user-facing strings.
EXCLUDED_MODULE_DIRECTORIES = frozenset({"Tests", "UITests"})
NON_CODE_TABLES = frozenset({"InfoPlist", "AppShortcuts"})
DEFAULT_TABLE = "Localizable"
# SwiftUI initializers and modifiers whose string-literal title is a LocalizedStringKey that
# is always resolved against the main bundle (correct in the App target, a bug in packages).
MAIN_BUNDLE_APIS = frozenset(
    {
        "Label",
        "Button",
        "Toggle",
        "Link",
        "Section",
        "Picker",
        "Menu",
        "NavigationLink",
        "TextField",
        "SecureField",
        "Tab",
        "navigationTitle",
        "accessibilityLabel",
        "accessibilityHint",
        "accessibilityValue",
        "help",
        "badge",
    }
)

KEY_NAME = re.compile(r"^[a-z0-9]+(?:[._-][a-z0-9]+)*$")
KEY_LIKE_LITERAL = re.compile(r"^[a-z][a-z0-9_]*\.[a-z]")
FORMAT_SPECIFIER = re.compile(
    r"%%"
    r"|%arg\b"
    r"|%#@(?P<substitution>[A-Za-z0-9_]+)@"
    r"|%(?:(?P<position>\d+)\$)?[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?"
    r"(?P<length>hh|h|ll|l|q|L|z|t|j)?(?P<conversion>[@dDiuUxXoOfFeEgGcCsSpaA])"
)
# Stands for a string interpolation `\(...)` inside an extracted literal (a private-use
# character, so it can never collide with real key text).
INTERPOLATION = "\ue000"
SWIFT_ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", '"': '"', "'": "'", "\\": "\\"}
# Any single printf-style specifier; used to match interpolated Swift literals against keys.
SPECIFIER_PATTERN = (
    r"%(?:\d+\$)?[-+ #0']*(?:\d+|\*)?(?:\.(?:\d+|\*))?"  # position, flags, width, precision
    r"(?:hh|h|ll|l|q|L|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA]"  # length modifier and conversion
)


# MARK: - Reporting


@dataclass
class Report:
    """Collects errors and prints them, with GitHub annotations when running in Actions."""

    root: Path
    errors: list[str] = field(default_factory=list)

    def error(self, path: Path, message: str, line: int | None = None) -> None:
        """Records one error for `path` (optionally at `line`)."""
        relative = self.relative(path)
        location = f"{relative}:{line}" if line else relative
        self.errors.append(f"{location}: error: {message}")
        if os.environ.get("GITHUB_ACTIONS") == "true":
            line_part = f",line={line}" if line else ""
            escaped = message.replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
            print(f"::error file={relative}{line_part}::{escaped}")

    def relative(self, path: Path) -> str:
        """Returns `path` relative to the repository root when possible."""
        try:
            return str(path.resolve().relative_to(self.root))
        except ValueError:
            return str(path)


# MARK: - Catalog model


@dataclass
class Catalog:
    """A parsed String Catalog and the module that owns it."""

    path: Path
    table: str
    module: Path | None
    strings: dict
    lines: list[str]

    def line_of_key(self, key: str) -> int | None:
        """Best-effort line number of `key` in the JSON source."""
        needle = json.dumps(key, ensure_ascii=False) + " :"
        compact = json.dumps(key, ensure_ascii=False) + ":"
        for index, text in enumerate(self.lines, start=1):
            stripped = text.strip()
            if stripped.startswith(needle) or stripped.startswith(compact):
                return index
        return None


def is_excluded(path: Path, root: Path) -> bool:
    """Whether `path` lies inside a build, checkout or snapshot directory."""
    try:
        parts = path.relative_to(root).parts
    except ValueError:
        parts = path.parts
    return any(part in EXCLUDED_DIRECTORIES for part in parts)


def module_directory(path: Path, root: Path) -> Path | None:
    """Returns the Swift module directory that owns `path`, or None for test/unknown paths.

    `Packages/<Package>/Sources/<Target>/...` belongs to that target; everything under `App/`
    except the test bundles belongs to the App target (module directory `App`).
    """
    parts = path.relative_to(root).parts
    if len(parts) >= 4 and parts[0] == "Packages" and parts[2] == "Sources":
        return root.joinpath(*parts[:4])
    if parts and parts[0] == "App":
        if len(parts) > 1 and parts[1] in EXCLUDED_MODULE_DIRECTORIES:
            return None
        return root / "App"
    return None


def find_files(root: Path, suffix: str) -> list[Path]:
    """All files with `suffix` below the search roots, excluding build directories."""
    found: list[Path] = []
    for search_root in SEARCH_ROOTS:
        base = root / search_root
        if not base.is_dir():
            continue
        for directory, subdirectories, files in os.walk(base):
            subdirectories[:] = sorted(d for d in subdirectories if d not in EXCLUDED_DIRECTORIES)
            for name in sorted(files):
                if name.endswith(suffix):
                    found.append(Path(directory) / name)
    return found


def load_catalog(path: Path, root: Path, report: Report) -> Catalog | None:
    """Parses one catalog and validates its top-level structure."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as error:
        report.error(path, f"cannot read catalog: {error}")
        return None
    try:
        document = json.loads(text)
    except json.JSONDecodeError as error:
        report.error(path, f"invalid JSON: {error.msg}", error.lineno)
        return None
    if not isinstance(document, dict):
        report.error(path, "the catalog must be a JSON object")
        return None
    source_language = document.get("sourceLanguage")
    if source_language != SOURCE_LANGUAGE:
        report.error(path, f"sourceLanguage must be '{SOURCE_LANGUAGE}', found {source_language!r}")
    if "version" not in document:
        report.error(path, "missing 'version'")
    strings = document.get("strings")
    if not isinstance(strings, dict):
        report.error(path, "missing or invalid 'strings' object")
        return None
    return Catalog(
        path=path,
        table=path.name[: -len(".xcstrings")],
        module=module_directory(path, root),
        strings=strings,
        lines=text.splitlines(),
    )


# MARK: - Content checks


@dataclass(frozen=True)
class Unit:
    """One leaf string of a localization, with the variation path that leads to it."""

    variation_path: str
    value: str
    state: str | None


def collect_units(
    catalog: Catalog,
    key: str,
    language: str,
    node: object,
    *,
    variation_path: str,
    report: Report,
) -> list[Unit]:
    """Walks a localization node (stringUnit, variations, substitutions) and returns its leaves.

    Plural completeness is validated on the way.
    """
    line = catalog.line_of_key(key)
    where = f"key '{key}' [{language}{variation_path}]"
    if not isinstance(node, dict):
        report.error(catalog.path, f"{where}: localization must be an object", line)
        return []
    units: list[Unit] = []
    string_unit = node.get("stringUnit")
    variations = node.get("variations")
    if string_unit is None and variations is None:
        report.error(catalog.path, f"{where}: neither 'stringUnit' nor 'variations'", line)
    if string_unit is not None:
        if not isinstance(string_unit, dict):
            report.error(catalog.path, f"{where}: 'stringUnit' must be an object", line)
        else:
            value = string_unit.get("value")
            units.append(Unit(variation_path, value if isinstance(value, str) else "", string_unit.get("state")))
    if variations is not None:
        if not isinstance(variations, dict) or not variations:
            report.error(catalog.path, f"{where}: 'variations' must be a non-empty object", line)
        else:
            for kind, cases in sorted(variations.items()):
                if not isinstance(cases, dict) or not cases:
                    report.error(catalog.path, f"{where}: variations '{kind}' must be a non-empty object", line)
                    continue
                if kind == "plural":
                    check_plural_categories(
                        catalog, key, language, variation_path=variation_path, categories=set(cases), report=report
                    )
                for case, child in sorted(cases.items()):
                    units += collect_units(
                        catalog, key, language, child, variation_path=f"{variation_path}/{kind}.{case}", report=report
                    )
    substitutions = node.get("substitutions")
    if substitutions is not None:
        if not isinstance(substitutions, dict):
            report.error(catalog.path, f"{where}: 'substitutions' must be an object", line)
        else:
            for name, substitution in sorted(substitutions.items()):
                if not isinstance(substitution, dict):
                    report.error(catalog.path, f"{where}: substitution '{name}' must be an object", line)
                    continue
                units += collect_units(
                    catalog,
                    key,
                    language,
                    substitution,
                    variation_path=f"{variation_path}/substitution.{name}",
                    report=report,
                )
    return units


def check_plural_categories(
    catalog: Catalog,
    key: str,
    language: str,
    *,
    variation_path: str,
    categories: set[str],
    report: Report,
) -> None:
    """Checks that a plural variation covers exactly the CLDR categories of `language`."""
    line = catalog.line_of_key(key)
    where = f"key '{key}' [{language}{variation_path}]"
    unknown = sorted(categories - PLURAL_CATEGORY_NAMES)
    if unknown:
        report.error(catalog.path, f"{where}: unknown plural categories {unknown}", line)
    allowed = ALLOWED_PLURALS.get(language, DEFAULT_REQUIRED_PLURALS) | {"zero"}
    unused = sorted((categories & PLURAL_CATEGORY_NAMES) - allowed)
    if unused:
        report.error(catalog.path, f"{where}: plural categories {unused} are not used by '{language}'", line)
    missing = sorted(REQUIRED_PLURALS.get(language, DEFAULT_REQUIRED_PLURALS) - categories)
    if missing:
        report.error(catalog.path, f"{where}: missing plural categories {missing}", line)


def specifier_signature(value: str) -> frozenset[tuple[str, str]]:
    """The arguments a format string consumes, as (position, type) pairs.

    Non-positional specifiers are numbered in order of appearance; positional ones keep
    their explicit position. `%ld`, `%lld` and `%qd` are the same 64-bit integer type;
    `%i` equals `%d`. `%#@name@` substitutions are recorded by name; `%arg` inside a
    substitution variant refers to that substitution's argument and is skipped.
    """
    signature: set[tuple[str, str]] = set()
    sequential = 0
    for match in FORMAT_SPECIFIER.finditer(value):
        if match.group(0) in {"%%", "%arg"}:
            # A literal percent sign, or the placeholder of a substitution's own argument.
            continue
        substitution = match.group("substitution")
        if substitution:
            signature.add(("substitution", substitution))
            continue
        conversion = match.group("conversion")
        length = match.group("length") or ""
        if conversion in "iD":
            conversion = "d"
        if conversion in "dDuUxXoO" and length in {"l", "ll", "q"}:
            length = "ll"
        position = match.group("position")
        if position is None:
            sequential += 1
            position = str(sequential)
        signature.add((position, length + conversion))
    return frozenset(signature)


def describe_signature(signature: frozenset[tuple[str, str]]) -> str:
    """Human-readable form of a specifier signature."""
    if not signature:
        return "no arguments"
    parts = []
    for position, kind in sorted(signature):
        parts.append(f"%#@{kind}@" if position == "substitution" else f"%{position}${kind}")
    return ", ".join(parts)


def check_catalog_content(catalog: Catalog, required_languages: tuple[str, ...], report: Report) -> None:
    """Runs the per-key content checks on one catalog."""
    checks_key_names = catalog.table not in NON_CODE_TABLES
    for key, entry in sorted(catalog.strings.items()):
        line = catalog.line_of_key(key)
        if not isinstance(entry, dict):
            report.error(catalog.path, f"key '{key}': entry must be an object", line)
            continue
        if checks_key_names and not KEY_NAME.match(key.split(" ", 1)[0]):
            report.error(catalog.path, f"key '{key}': keys are lowercase dot paths (e.g. 'home.hero.title')", line)
        comment = entry.get("comment")
        if not isinstance(comment, str) or not comment.strip():
            report.error(catalog.path, f"key '{key}': missing translator comment", line)
        if entry.get("shouldTranslate") is False:
            continue
        localizations = entry.get("localizations")
        if not isinstance(localizations, dict):
            report.error(catalog.path, f"key '{key}': missing 'localizations'", line)
            continue
        unsupported = sorted(set(localizations) - set(APP_LANGUAGES))
        if unsupported:
            report.error(catalog.path, f"key '{key}': unsupported languages {unsupported}", line)
        missing = [language for language in required_languages if language not in localizations]
        if missing:
            report.error(catalog.path, f"key '{key}': missing languages {missing}", line)
        signatures: dict[str, frozenset[tuple[str, str]]] = {}
        for language in APP_LANGUAGES:
            if language not in localizations:
                continue
            units = collect_units(catalog, key, language, localizations[language], variation_path="", report=report)
            for unit in units:
                where = f"key '{key}' [{language}{unit.variation_path}]"
                if unit.state != "translated":
                    report.error(catalog.path, f"{where}: state is {unit.state!r}, expected 'translated'", line)
                if not unit.value.strip():
                    report.error(catalog.path, f"{where}: empty value", line)
            signature: frozenset[tuple[str, str]] = frozenset()
            for unit in units:
                signature |= specifier_signature(unit.value)
            signatures[language] = signature
        reference_language = SOURCE_LANGUAGE if SOURCE_LANGUAGE in signatures else next(iter(signatures), None)
        if reference_language is None:
            continue
        expected = signatures[reference_language]
        for language, signature in signatures.items():
            if signature != expected:
                report.error(
                    catalog.path,
                    f"key '{key}' [{language}]: format specifiers ({describe_signature(signature)}) differ from "
                    f"'{reference_language}' ({describe_signature(expected)}); use positional specifiers "
                    "such as %1$@ when the word order changes",
                    line,
                )


# MARK: - Swift reference scanning


@dataclass(frozen=True)
class Reference:
    """A localized-string lookup found in Swift code."""

    path: Path
    line: int
    literal: str
    has_interpolation: bool
    uses_module_bundle: bool
    table: str
    callee: str

    def matches(self, key: str) -> bool:
        """Whether `key` is the catalog key this lookup resolves to."""
        if not self.has_interpolation:
            return key == self.literal
        return re.fullmatch(self.pattern(), key) is not None

    def pattern(self) -> str:
        """A regular expression for the key of an interpolated literal."""
        parts = self.literal.split(INTERPOLATION)
        return SPECIFIER_PATTERN.join(re.escape(part) for part in parts)


class SwiftScanner:
    """A small lexer that finds string literals and call arguments in Swift source.

    It understands line and nested block comments, single-line, multi-line and raw string
    literals, and string interpolation, which is all that is needed to extract the literal
    first argument of localization calls reliably.
    """

    CALL_START = re.compile(
        r"(?<![\w.])(?P<callee>Text|String|LocalizedStringKey|LocalizedStringResource"
        r"|Label|Button|Toggle|Link|Section|Picker|Menu|NavigationLink|TextField|SecureField|Tab)\s*\("
        r"|\.(?P<modifier>navigationTitle|accessibilityLabel|accessibilityHint|accessibilityValue|help|badge)\s*\("
    )
    # Argument label in front of the literal; None means the literal is the first argument.
    LABELS = {"String": "localized"}

    def __init__(self, source: str) -> None:
        self.source = source
        self.code_mask = self._mask(source, blank_strings=False)
        self.call_mask = self._mask(source, blank_strings=True)

    # Lexing helpers

    def _mask(self, source: str, blank_strings: bool) -> str:
        """Returns `source` with comments (and optionally string literals) replaced by spaces.

        Newlines are kept so that offsets and line numbers stay valid.
        """
        result = list(source)
        index = 0
        length = len(source)
        while index < length:
            if source.startswith("//", index):
                end = source.find("\n", index)
                end = length if end == -1 else end
                for position in range(index, end):
                    result[position] = " "
                index = end
            elif source.startswith("/*", index):
                depth = 0
                position = index
                while position < length:
                    if source.startswith("/*", position):
                        depth += 1
                        position += 2
                    elif source.startswith("*/", position):
                        depth -= 1
                        position += 2
                        if depth == 0:
                            break
                    else:
                        position += 1
                for masked in range(index, min(position, length)):
                    if result[masked] != "\n":
                        result[masked] = " "
                index = position
            elif source[index] == '"' or (source[index] == "#" and self._raw_string_start(source, index)):
                start = index
                _, index = self.read_string(source, index)
                if blank_strings:
                    for masked in range(start, min(index, length)):
                        if result[masked] != "\n":
                            result[masked] = " "
            else:
                index += 1
        return "".join(result)

    @staticmethod
    def _raw_string_start(source: str, index: int) -> bool:
        position = index
        while position < len(source) and source[position] == "#":
            position += 1
        return position < len(source) and source[position] == '"'

    def read_string(self, source: str, index: int) -> tuple[tuple[str, bool] | None, int]:
        """Reads the string literal starting at `index`.

        Returns ((text, has_interpolation), end_index); interpolations become INTERPOLATION.
        Returns (None, end_index) for literals that cannot be keys (multi-line strings).
        """
        hashes = 0
        while source[index] == "#":
            hashes += 1
            index += 1
        multi_line = source.startswith('"""', index)
        delimiter = '"""' if multi_line else '"'
        index += len(delimiter)
        closing = delimiter + "#" * hashes
        escape = "\\" + "#" * hashes
        text: list[str] = []
        interpolated = False
        length = len(source)
        while index < length:
            if source.startswith(closing, index):
                index += len(closing)
                break
            if source.startswith(escape, index):
                index += len(escape)
                if index >= length:
                    break
                marker = source[index]
                if marker == "(":
                    index = self._skip_balanced(source, index)
                    text.append(INTERPOLATION)
                    interpolated = True
                    continue
                if marker == "u" and index + 1 < length and source[index + 1] == "{":
                    end = source.find("}", index)
                    try:
                        text.append(chr(int(source[index + 2 : end], 16)))
                    except ValueError:
                        text.append("?")
                    index = end + 1
                    continue
                text.append(SWIFT_ESCAPES.get(marker, marker))
                index += 1
                continue
            if not multi_line and source[index] == "\n":
                break
            text.append(source[index])
            index += 1
        if multi_line:
            return None, index
        return ("".join(text), interpolated), index

    def _skip_balanced(self, source: str, index: int) -> int:
        """Skips from the `(` at `index` to just after its matching `)`, honoring strings."""
        depth = 0
        length = len(source)
        while index < length:
            character = source[index]
            if character == '"' or (character == "#" and self._raw_string_start(source, index)):
                _, index = self.read_string(source, index)
                continue
            if source.startswith("//", index):
                end = source.find("\n", index)
                index = length if end == -1 else end
                continue
            if source.startswith("/*", index):
                end = source.find("*/", index + 2)
                index = length if end == -1 else end + 2
                continue
            if character == "(":
                depth += 1
            elif character == ")":
                depth -= 1
                if depth == 0:
                    return index + 1
            index += 1
        return length

    # Public API

    def references(self, path: Path) -> list[Reference]:
        """All localization lookups with a literal key in this file."""
        found: list[Reference] = []
        for match in self.CALL_START.finditer(self.call_mask):
            callee = match.group("callee") or match.group("modifier")
            open_paren = match.end() - 1
            end = self._skip_balanced(self.source, open_paren)
            arguments = self.source[open_paren + 1 : end - 1]
            label = self.LABELS.get(callee)
            body = arguments.lstrip()
            if label is not None:
                label_match = re.match(rf"{label}\s*:\s*", body)
                if not label_match:
                    continue
                body = body[label_match.end() :]
            if not body.startswith('"') and not (body.startswith("#") and self._raw_string_start(body, 0)):
                continue
            literal, literal_end = self.read_string(body, 0)
            if literal is None:
                continue
            text, interpolated = literal
            rest = body[literal_end:]
            if rest.strip() and not rest.lstrip().startswith(","):
                # The literal is only part of an expression, e.g. `Text("a" + b)`.
                continue
            table_match = re.search(r"\b(?:table|tableName)\s*:\s*\"([^\"]+)\"", rest)
            uses_module_bundle = re.search(r"\bbundle\s*:\s*\.module\b|\bBundle\.module\b", rest) is not None
            line = self.source.count("\n", 0, match.start()) + 1
            found.append(
                Reference(
                    path=path,
                    line=line,
                    literal=text,
                    has_interpolation=interpolated,
                    uses_module_bundle=uses_module_bundle,
                    table=table_match.group(1) if table_match else DEFAULT_TABLE,
                    callee=callee,
                )
            )
        return found

    def literals(self) -> set[str]:
        """Every single-line, non-interpolated string literal in the file (outside comments)."""
        values: set[str] = set()
        index = 0
        mask = self.code_mask
        length = len(mask)
        while index < length:
            character = mask[index]
            if character == '"' or (character == "#" and self._raw_string_start(mask, index)):
                literal, index = self.read_string(self.source, index)
                if literal is not None and not literal[1]:
                    values.add(literal[0])
                continue
            index += 1
        return values


# MARK: - Code consistency


@dataclass
class ModuleScan:
    """References and literals found in the Swift sources of one module."""

    directory: Path
    references: list[Reference] = field(default_factory=list)
    literals: set[str] = field(default_factory=set)


def scan_modules(root: Path, report: Report) -> dict[Path, ModuleScan]:
    """Scans every Swift source file of App/ and Packages/ grouped by module."""
    modules: dict[Path, ModuleScan] = {}
    for path in find_files(root, ".swift"):
        if is_excluded(path, root):
            continue
        module = module_directory(path, root)
        if module is None:
            continue
        try:
            source = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError) as error:
            report.error(path, f"cannot read Swift file: {error}")
            continue
        scanner = SwiftScanner(source)
        scan = modules.setdefault(module, ModuleScan(directory=module))
        scan.references += scanner.references(path)
        scan.literals |= scanner.literals()
    return modules


def check_code_consistency(root: Path, catalogs: list[Catalog], report: Report) -> None:
    """Cross-checks catalog keys against the Swift code of the owning module."""
    modules = scan_modules(root, report)
    catalogs_by_module: dict[Path, dict[str, Catalog]] = {}
    for catalog in catalogs:
        if catalog.module is not None and catalog.table not in NON_CODE_TABLES:
            catalogs_by_module.setdefault(catalog.module, {})[catalog.table] = catalog

    for module_path, scan in sorted(modules.items()):
        is_app = module_path == root / "App"
        tables = catalogs_by_module.get(module_path, {})
        for reference in scan.references:
            key_like = KEY_LIKE_LITERAL.match(reference.literal) is not None
            implicit_main_bundle = reference.callee in MAIN_BUNDLE_APIS
            if not is_app and implicit_main_bundle:
                if key_like:
                    report.error(
                        reference.path,
                        f'{reference.callee}("{reference.literal}") looks the key up in the main bundle; '
                        "pass a String(localized:, bundle: .module) or Text(_:bundle:) instead",
                        reference.line,
                    )
                continue
            if not is_app and not reference.uses_module_bundle:
                if key_like and reference.callee in {"Text", "String"}:
                    report.error(
                        reference.path,
                        f"'{reference.literal}' is looked up in the main bundle; add `bundle: .module`",
                        reference.line,
                    )
                continue
            if is_app and implicit_main_bundle and not key_like:
                # e.g. Link("karinex.de", destination:) in the App target: not a catalog lookup.
                continue
            catalog = tables.get(reference.table)
            display = reference.literal.replace(INTERPOLATION, "\\(...)")
            if catalog is None:
                report.error(
                    reference.path,
                    f"'{display}' is referenced but the module has no {reference.table}.xcstrings",
                    reference.line,
                )
                continue
            if not any(reference.matches(key) for key in catalog.strings):
                report.error(
                    reference.path,
                    f"'{display}' is not a key of {report.relative(catalog.path)}",
                    reference.line,
                )

    for module_path, tables in sorted(catalogs_by_module.items()):
        scan = modules.get(module_path, ModuleScan(directory=module_path))
        for catalog in tables.values():
            relevant = [
                reference
                for reference in scan.references
                if reference.table == catalog.table and (reference.uses_module_bundle or module_path == root / "App")
            ]
            for key in sorted(catalog.strings):
                referenced = key in scan.literals or any(reference.matches(key) for reference in relevant)
                if not referenced:
                    report.error(
                        catalog.path,
                        f"key '{key}' is never referenced from the Swift code of {report.relative(module_path)}",
                        catalog.line_of_key(key),
                    )


# MARK: - Entry point


def parse_arguments(argv: list[str]) -> argparse.Namespace:
    """Parses the command line."""
    parser = argparse.ArgumentParser(description="Validate the String Catalogs of the KARINEX app.")
    parser.add_argument(
        "--allow-missing-languages",
        action="store_true",
        help="only require de and en (for work in progress; CI does not use this flag)",
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parent.parent,
        help="repository root (default: the parent of this script's directory)",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    """Runs all checks and returns the process exit status."""
    arguments = parse_arguments(argv)
    root = arguments.root.resolve()
    if not root.is_dir():
        print(f"error: {root} is not a directory", file=sys.stderr)
        return 2
    report = Report(root=root)
    required_languages = MINIMUM_LANGUAGES if arguments.allow_missing_languages else APP_LANGUAGES

    catalog_paths = [path for path in find_files(root, ".xcstrings") if not is_excluded(path, root)]
    catalogs: list[Catalog] = []
    for path in catalog_paths:
        catalog = load_catalog(path, root, report)
        if catalog is not None:
            catalogs.append(catalog)
            check_catalog_content(catalog, required_languages, report)
    check_code_consistency(root, catalogs, report)

    for message in report.errors:
        print(message)
    key_count = sum(len(catalog.strings) for catalog in catalogs)
    mode = "de+en only" if arguments.allow_missing_languages else f"{len(APP_LANGUAGES)} languages"
    summary = f"check_strings: {len(catalog_paths)} catalog(s), {key_count} key(s), {mode}: "
    if report.errors:
        print(summary + f"{len(report.errors)} error(s)")
        return 1
    print(summary + "OK")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
