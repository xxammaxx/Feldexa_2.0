#!/usr/bin/env bash
#
# verify.sh — validate a Feldexa corpus manifest and every referenced checksum.
#
# This is the T008 checksum verifier for the frozen recognition corpus
# (constitution Principle IV, plan research decision D-18). It fails closed:
# a missing manifest, an unreadable form, a byte-size drift, a SHA-256 mismatch,
# an unsafe path, an incomplete rights record, a ground-truth rectangle that
# falls outside its source page, or any non-finite/overflowing JSON number is a
# verification failure.
#
# Usage:
#   tools/corpus/verify.sh
#   tools/corpus/verify.sh --manifest tools/corpus/manifest.json --corpus-dir tools/corpus
#   tools/corpus/verify.sh --min-real-forms 0 --json
#
# Exit codes:
#   0  manifest and all referenced files verified
#   1  verification failure (including a missing or invalid manifest)
#   2  invalid command-line usage
#
set -euo pipefail

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export CORPUS_VERIFY_DIR="$SCRIPT_DIR"

if ! command -v python3 >/dev/null 2>&1; then
    echo "verify.sh: python3 is required but was not found" >&2
    exit 2
fi

exec python3 - "$@" <<'PY'
"""Validate a corpus manifest against its JSON Schema and its referenced bytes.

The schema validator below intentionally implements the small JSON Schema
2020-12 subset used by manifest.schema.json, so the verifier has no third-party
dependency and remains runnable in an offline local gate. Semantic checks that
need file access or cross-record reasoning are performed after schema
validation.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import re
import sys
from datetime import date, datetime
from pathlib import Path, PurePosixPath

SCRIPT_DIR = Path(os.environ["CORPUS_VERIFY_DIR"]).resolve()


# ---------------------------------------------------------------------------
# Minimal JSON Schema 2020-12 validator (only the keywords this schema uses)
# ---------------------------------------------------------------------------


def json_type_name(value: object) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "boolean"
    if isinstance(value, dict):
        return "object"
    if isinstance(value, list):
        return "array"
    if isinstance(value, str):
        return "string"
    if isinstance(value, int):
        return "integer"
    if isinstance(value, float):
        return "number"
    return type(value).__name__


def type_matches(value: object, expected: str) -> bool:
    if expected == "object":
        return isinstance(value, dict)
    if expected == "array":
        return isinstance(value, list)
    if expected == "string":
        return isinstance(value, str)
    if expected == "boolean":
        return isinstance(value, bool)
    if expected == "null":
        return value is None
    if expected == "integer":
        return isinstance(value, int) and not isinstance(value, bool)
    if expected == "number":
        return isinstance(value, (int, float)) and not isinstance(value, bool)
    return False


def resolve_ref(root: dict, ref: str) -> dict:
    if not ref.startswith("#/"):
        raise ValueError(f"only local JSON pointers are supported, got {ref!r}")
    node: object = root
    for raw in ref[2:].split("/"):
        token = raw.replace("~1", "/").replace("~0", "~")
        if not isinstance(node, dict) or token not in node:
            raise KeyError(token)
        node = node[token]
    if not isinstance(node, dict):
        raise ValueError(f"{ref!r} does not resolve to an object")
    return node


def finite_number(value: object) -> bool:
    """Return True only for numbers representable as a finite IEEE-754 double."""
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return False
    try:
        return math.isfinite(float(value))
    except (OverflowError, ValueError):
        return False


def reject_json_constant(token: str) -> None:
    """Reject the non-standard NaN/Infinity/-Infinity tokens accepted by Python's json."""
    raise ValueError(f"non-finite JSON number {token!r} is not allowed")


def reject_non_finite_numbers(value: object, path: str = "$") -> None:
    """Reject non-finite floats and integers that overflow a finite double, recursively."""
    if isinstance(value, bool) or value is None or isinstance(value, str):
        return
    if isinstance(value, float):
        if not math.isfinite(value):
            raise ValueError(f"{path}: non-finite number {value!r} is not allowed")
        return
    if isinstance(value, int):
        try:
            converted = float(value)
        except OverflowError as exc:
            raise ValueError(
                f"{path}: integer is too large to represent as a finite JSON number"
            ) from exc
        if not math.isfinite(converted):
            raise ValueError(
                f"{path}: integer is too large to represent as a finite JSON number"
            )
        return
    if isinstance(value, dict):
        for key, item in value.items():
            reject_non_finite_numbers(item, f"{path}.{key}")
        return
    if isinstance(value, list):
        for index, item in enumerate(value):
            reject_non_finite_numbers(item, f"{path}[{index}]")


def _check_number(value: object, schema: dict, path: str, errors: list[str]) -> None:
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return
    if not finite_number(value):
        errors.append(f"{path}: must be a finite number representable as an IEEE-754 double")
        return
    if "minimum" in schema and value < schema["minimum"]:
        errors.append(f"{path}: must be >= {schema['minimum']}")
    if "maximum" in schema and value > schema["maximum"]:
        errors.append(f"{path}: must be <= {schema['maximum']}")
    if "exclusiveMinimum" in schema and value <= schema["exclusiveMinimum"]:
        errors.append(f"{path}: must be > {schema['exclusiveMinimum']}")
    if "exclusiveMaximum" in schema and value >= schema["exclusiveMaximum"]:
        errors.append(f"{path}: must be < {schema['exclusiveMaximum']}")


def _check_string(value: object, schema: dict, path: str, errors: list[str]) -> None:
    if not isinstance(value, str):
        return
    if "minLength" in schema and len(value) < schema["minLength"]:
        errors.append(f"{path}: must contain at least {schema['minLength']} character(s)")
    if "maxLength" in schema and len(value) > schema["maxLength"]:
        errors.append(f"{path}: must contain at most {schema['maxLength']} character(s)")
    if "pattern" in schema:
        try:
            if re.search(schema["pattern"], value) is None:
                errors.append(f"{path}: does not match pattern {schema['pattern']!r}")
        except re.error as exc:
            errors.append(f"{path}: schema pattern is invalid: {exc}")
    fmt = schema.get("format")
    if fmt == "date":
        if re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value) is None:
            errors.append(f"{path}: must be an ISO date (YYYY-MM-DD)")
        else:
            try:
                date.fromisoformat(value)
            except ValueError:
                errors.append(f"{path}: must be a real calendar date")
    elif fmt == "date-time":
        if re.fullmatch(
            r"[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}(?:\.[0-9]+)?(?:Z|[+-][0-9]{2}:[0-9]{2})",
            value,
        ) is None:
            errors.append(f"{path}: must be an RFC 3339 date-time with a timezone")
        else:
            try:
                datetime.fromisoformat(value.replace("Z", "+00:00"))
            except ValueError:
                errors.append(f"{path}: must be a valid RFC 3339 date-time")


def schema_errors(instance: object, schema: object, root: dict, path: str = "$") -> list[str]:
    """Return validation errors for instance against the supported schema subset."""
    errors: list[str] = []
    if not isinstance(schema, dict):
        return [f"{path}: invalid schema node (expected an object)"]

    if "$ref" in schema:
        try:
            errors.extend(schema_errors(instance, resolve_ref(root, schema["$ref"]), root, path))
        except (KeyError, ValueError) as exc:
            errors.append(f"{path}: unresolvable $ref {schema['$ref']!r}: {exc}")

    expected_type = schema.get("type")
    if expected_type is not None:
        expected_types = expected_type if isinstance(expected_type, list) else [expected_type]
        if not any(isinstance(t, str) and type_matches(instance, t) for t in expected_types):
            errors.append(
                f"{path}: expected {' or '.join(str(t) for t in expected_types)}, "
                f"got {json_type_name(instance)}"
            )
            return errors

    if "const" in schema and instance != schema["const"]:
        errors.append(f"{path}: must equal {schema['const']!r}")
    if "enum" in schema and instance not in schema["enum"]:
        errors.append(f"{path}: must be one of {schema['enum']!r}")

    if isinstance(instance, dict):
        for key in schema.get("required", []):
            if key not in instance:
                errors.append(f"{path}: missing required property {key!r}")
        properties = schema.get("properties", {})
        additional = schema.get("additionalProperties", True)
        for key, value in instance.items():
            if key in properties:
                errors.extend(schema_errors(value, properties[key], root, f"{path}.{key}"))
            elif additional is False:
                errors.append(f"{path}: unexpected property {key!r}")
            elif isinstance(additional, dict):
                errors.extend(schema_errors(value, additional, root, f"{path}.{key}"))

    if isinstance(instance, list):
        if "minItems" in schema and len(instance) < schema["minItems"]:
            errors.append(f"{path}: must contain at least {schema['minItems']} item(s)")
        if "maxItems" in schema and len(instance) > schema["maxItems"]:
            errors.append(f"{path}: must contain at most {schema['maxItems']} item(s)")
        if schema.get("uniqueItems"):
            seen: dict[str, int] = {}
            for index, item in enumerate(instance):
                canonical = json.dumps(item, sort_keys=True, ensure_ascii=False, separators=(",", ":"))
                if canonical in seen:
                    errors.append(f"{path}: duplicate item at positions {seen[canonical]} and {index}")
                else:
                    seen[canonical] = index
        items = schema.get("items")
        if isinstance(items, dict):
            for index, item in enumerate(instance):
                errors.extend(schema_errors(item, items, root, f"{path}[{index}]"))

    if isinstance(instance, str):
        _check_string(instance, schema, path, errors)
    _check_number(instance, schema, path, errors)

    if "allOf" in schema:
        for sub_schema in schema["allOf"]:
            errors.extend(schema_errors(instance, sub_schema, root, path))

    if "anyOf" in schema:
        if not any(not schema_errors(instance, sub, root, path) for sub in schema["anyOf"]):
            errors.append(f"{path}: does not satisfy any allowed alternative")

    if "oneOf" in schema:
        matches = sum(1 for sub in schema["oneOf"] if not schema_errors(instance, sub, root, path))
        if matches != 1:
            errors.append(f"{path}: must satisfy exactly one alternative (matched {matches})")

    if "not" in schema and not schema_errors(instance, schema["not"], root, path):
        errors.append(f"{path}: must not satisfy the forbidden schema")

    if "if" in schema:
        if not schema_errors(instance, schema["if"], root, path):
            if "then" in schema:
                errors.extend(schema_errors(instance, schema["then"], root, path))
        elif "else" in schema:
            errors.extend(schema_errors(instance, schema["else"], root, path))

    return errors


# ---------------------------------------------------------------------------
# Semantic verification
# ---------------------------------------------------------------------------


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parse_datetime(value: object) -> datetime | None:
    if not isinstance(value, str):
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def rect_outside_page(rect: object, page: object) -> str | None:
    if not isinstance(rect, dict) or not isinstance(page, dict):
        return "missing rectangle or page"
    values = [rect.get(key) for key in ("xPt", "yPt", "widthPt", "heightPt")]
    if not all(isinstance(v, (int, float)) and not isinstance(v, bool) for v in values):
        return "non-numeric rectangle"
    if not all(finite_number(v) for v in values):
        return "non-finite or overflowing rectangle coordinate"
    width = page.get("widthPt")
    height = page.get("heightPt")
    if not isinstance(width, (int, float)) or not isinstance(height, (int, float)):
        return "non-numeric page size"
    if not finite_number(width) or not finite_number(height):
        return "non-finite or overflowing page size"
    x, y, w, h = (float(v) for v in values)
    epsilon = 1e-6
    if x < -epsilon or y < -epsilon:
        return "negative origin"
    if x + w > float(width) + epsilon or y + h > float(height) + epsilon:
        return f"extends beyond the {width}x{height} pt page"
    return None


def verify(
    manifest_path: Path,
    corpus_dir: Path,
    schema_path: Path,
    min_real_forms: int,
    expected_corpus_version: str | None,
) -> tuple[dict | None, list[str]]:
    failures: list[str] = []

    def fail(message: str) -> None:
        failures.append(message)

    if not manifest_path.is_file():
        return None, [f"manifest not found: {manifest_path}"]

    try:
        manifest_text = manifest_path.read_text(encoding="utf-8")
    except OSError as exc:
        return None, [f"cannot read manifest: {exc}"]
    except UnicodeDecodeError as exc:
        return None, [f"manifest is not valid UTF-8: {exc}"]
    try:
        manifest = json.loads(manifest_text, parse_constant=reject_json_constant)
    except ValueError as exc:
        return None, [f"manifest is not valid JSON: {exc}"]
    try:
        reject_non_finite_numbers(manifest)
    except ValueError as exc:
        return None, [f"manifest contains an invalid number: {exc}"]

    try:
        schema_text = schema_path.read_text(encoding="utf-8")
    except OSError as exc:
        return None, [f"cannot read manifest schema: {exc}"]
    except UnicodeDecodeError as exc:
        return None, [f"manifest schema is not valid UTF-8: {exc}"]
    try:
        schema = json.loads(schema_text, parse_constant=reject_json_constant)
    except ValueError as exc:
        return None, [f"manifest schema is not valid JSON: {exc}"]
    try:
        reject_non_finite_numbers(schema)
    except ValueError as exc:
        return None, [f"manifest schema contains an invalid number: {exc}"]

    if not isinstance(manifest, dict):
        return None, ["manifest root must be a JSON object"]

    for error in schema_errors(manifest, schema, schema):
        fail(f"schema: {error}")

    corpus_version = manifest.get("corpusVersion")
    if expected_corpus_version is not None and corpus_version != expected_corpus_version:
        fail(
            "corpusVersion mismatch: manifest declares "
            f"{corpus_version!r}, expected {expected_corpus_version!r}"
        )

    freeze = manifest.get("freeze")
    frozen_at = parse_datetime(freeze.get("frozenAt")) if isinstance(freeze, dict) else None

    root = corpus_dir.resolve()
    if not root.is_dir():
        fail(f"corpus directory not found: {root}")

    forms = manifest.get("forms")
    if not isinstance(forms, list) or not forms:
        fail("manifest must contain a non-empty 'forms' array")
        forms = []

    counts = {"forms": 0, "real": 0, "synthetic": 0, "pages": 0, "fields": 0}
    seen_ids: dict[object, int] = {}
    seen_paths: dict[str, int] = {}
    seen_digests: dict[str, int] = {}

    for index, form in enumerate(forms):
        label = f"forms[{index}]"
        if not isinstance(form, dict):
            fail(f"{label}: form entry must be an object")
            continue

        counts["forms"] += 1
        form_id = form.get("id")
        if isinstance(form_id, str):
            label = f"form {form_id}"
            if form_id in seen_ids:
                fail(f"{label}: duplicate id (also forms[{seen_ids[form_id]}])")
            else:
                seen_ids[form_id] = index

        kind = form.get("kind")
        if kind in ("real", "synthetic"):
            counts[kind] += 1

        path_value = form.get("path")
        target: Path | None = None
        if not isinstance(path_value, str):
            fail(f"{label}: path must be a string")
        else:
            if path_value.startswith("/") or "\\" in path_value:
                fail(f"{label}: unsafe path {path_value!r} (must be relative POSIX)")
            else:
                relative = PurePosixPath(path_value)
                if relative.is_absolute() or ".." in relative.parts or not relative.parts:
                    fail(f"{label}: unsafe path {path_value!r} (parent traversal is forbidden)")
                else:
                    if path_value in seen_paths:
                        fail(f"{label}: duplicate path (also forms[{seen_paths[path_value]}])")
                    else:
                        seen_paths[path_value] = index
                    target = root.joinpath(*relative.parts)
                    try:
                        resolved = target.resolve(strict=False)
                    except OSError as exc:
                        fail(f"{label}: cannot resolve path {path_value!r}: {exc}")
                        target = None
                    else:
                        if resolved != root and root not in resolved.parents:
                            fail(f"{label}: path {path_value!r} escapes the corpus directory")
                            target = None
                        elif target.is_symlink():
                            fail(f"{label}: path {path_value!r} must not be a symlink")

        size_bytes = form.get("sizeBytes")
        digest = form.get("sha256")
        if isinstance(digest, str):
            if digest in seen_digests:
                fail(f"{label}: duplicate sha256 (also forms[{seen_digests[digest]}])")
            else:
                seen_digests[digest] = index

        if target is not None:
            if not target.is_file():
                fail(f"{label}: file not found: {path_value!r}")
            else:
                actual_size = target.stat().st_size
                if isinstance(size_bytes, int) and not isinstance(size_bytes, bool):
                    if actual_size != size_bytes:
                        fail(
                            f"{label}: size mismatch for {path_value!r}: "
                            f"manifest {size_bytes}, actual {actual_size}"
                        )
                else:
                    fail(f"{label}: sizeBytes must be an integer")

                if isinstance(digest, str):
                    actual_digest = sha256_file(target)
                    if actual_digest != digest:
                        fail(
                            f"{label}: checksum mismatch for {path_value!r}: "
                            f"manifest {digest}, actual {actual_digest}"
                        )
                else:
                    fail(f"{label}: sha256 must be a string")

        pages = form.get("pages")
        page_by_index: dict[int, dict] = {}
        if isinstance(pages, list):
            counts["pages"] += len(pages)
            declared_page_count = form.get("pageCount")
            if isinstance(declared_page_count, int) and declared_page_count != len(pages):
                fail(
                    f"{label}: pageCount is {declared_page_count} but {len(pages)} page(s) are recorded"
                )
            indices: list[int] = []
            for page in pages:
                if not isinstance(page, dict):
                    fail(f"{label}: page entry must be an object")
                    continue
                page_index = page.get("index")
                if isinstance(page_index, int) and not isinstance(page_index, bool):
                    indices.append(page_index)
                    page_by_index[page_index] = page
            expected_indices = list(range(len(pages)))
            if sorted(indices) != expected_indices:
                fail(
                    f"{label}: page indices must be exactly 0..{len(pages) - 1}, "
                    f"got {sorted(indices)}"
                )
        else:
            fail(f"{label}: pages must be an array")

        ground_truth = form.get("groundTruth")
        fields = ground_truth.get("fields") if isinstance(ground_truth, dict) else None
        if isinstance(fields, list):
            counts["fields"] += len(fields)
            seen_field_ids: set[str] = set()
            for field_index, field in enumerate(fields):
                if not isinstance(field, dict):
                    fail(f"{label}: groundTruth.fields[{field_index}] must be an object")
                    continue
                field_id = field.get("id")
                if isinstance(field_id, str):
                    if field_id in seen_field_ids:
                        fail(f"{label}: duplicate ground-truth field id {field_id!r}")
                    seen_field_ids.add(field_id)
                page_index = field.get("pageIndex")
                page = page_by_index.get(page_index) if isinstance(page_index, int) else None
                if page is None:
                    fail(
                        f"{label}: ground-truth field {field_id!r} references unknown page "
                        f"{page_index!r}"
                    )
                    continue
                problem = rect_outside_page(field.get("rect"), page)
                if problem is not None:
                    fail(f"{label}: ground-truth field {field_id!r}: {problem}")
        else:
            fail(f"{label}: groundTruth.fields must be an array")

        if kind == "real":
            verification = form.get("verification")
            if not isinstance(verification, dict):
                fail(f"{label}: real forms require an independent verification record")
            else:
                verified_at = parse_datetime(verification.get("verifiedAt"))
                if verified_at is None:
                    fail(f"{label}: verification.verifiedAt is not a valid date-time")
                elif frozen_at is not None:
                    if verified_at.tzinfo is None or frozen_at.tzinfo is None:
                        fail(f"{label}: verification and freeze timestamps must include a timezone")
                    elif verified_at > frozen_at:
                        fail(f"{label}: verification completed after the corpus was frozen")
                provenance = form.get("provenance")
                retrieval = provenance.get("retrievalDate") if isinstance(provenance, dict) else None
                if verified_at is not None and isinstance(retrieval, str):
                    try:
                        retrieved_on = date.fromisoformat(retrieval)
                    except ValueError:
                        pass
                    else:
                        if retrieved_on > verified_at.date():
                            fail(f"{label}: retrievalDate is after verification.verifiedAt")
        elif kind == "synthetic":
            synthetic = form.get("synthetic")
            if not isinstance(synthetic, dict) or not synthetic.get("generator"):
                fail(f"{label}: synthetic forms require synthetic.generator")

    if counts["real"] < min_real_forms:
        fail(
            f"corpus has {counts['real']} real form(s); "
            f"at least {min_real_forms} required by constitution Principle IV"
        )
    if counts["forms"] > 0 and counts["fields"] == 0:
        fail("corpus contains no ground-truth fields, so it cannot score recognition")

    summary = {
        "manifest": str(manifest_path),
        "corpusDir": str(root),
        "schemaVersion": manifest.get("schemaVersion"),
        "corpusVersion": corpus_version,
        "minRealForms": min_real_forms,
        "counts": counts,
    }
    return summary, failures


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="verify.sh",
        description=(
            "Validate a frozen Feldexa corpus manifest and verify every referenced "
            "SHA-256 checksum and byte size. Non-finite and overflowing JSON numbers "
            "are rejected."
        ),
    )
    parser.add_argument(
        "--manifest",
        default=str(SCRIPT_DIR / "manifest.json"),
        help="manifest path (default: tools/corpus/manifest.json)",
    )
    parser.add_argument(
        "--corpus-dir",
        default=None,
        help="directory that manifest paths are relative to (default: the manifest directory)",
    )
    parser.add_argument(
        "--schema",
        default=str(SCRIPT_DIR / "manifest.schema.json"),
        help="JSON Schema path (default: tools/corpus/manifest.schema.json)",
    )
    parser.add_argument(
        "--min-real-forms",
        type=int,
        default=20,
        help="minimum number of rights-cleared real forms (default: 20; use 0 for synthetic-only checks)",
    )
    parser.add_argument(
        "--expected-corpus-version",
        default=None,
        help="fail unless the manifest declares this corpus version",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        dest="as_json",
        help="emit a machine-readable result object",
    )
    args = parser.parse_args(argv)

    if args.min_real_forms < 0:
        parser.error("--min-real-forms must be >= 0")

    manifest_path = Path(args.manifest).expanduser().resolve()
    schema_path = Path(args.schema).expanduser().resolve()
    if args.corpus_dir is None:
        corpus_dir = manifest_path.parent
    else:
        corpus_dir = Path(args.corpus_dir).expanduser().resolve()

    summary, failures = verify(
        manifest_path=manifest_path,
        corpus_dir=corpus_dir,
        schema_path=schema_path,
        min_real_forms=args.min_real_forms,
        expected_corpus_version=args.expected_corpus_version,
    )

    if args.as_json:
        payload = {
            "ok": not failures,
            "schemaVersion": summary.get("schemaVersion") if summary else None,
            "manifest": str(manifest_path),
            "corpusDir": str(corpus_dir),
            "counts": summary["counts"] if summary else {},
            "corpusVersion": summary.get("corpusVersion") if summary else None,
            "minRealForms": args.min_real_forms,
            "failures": failures,
        }
        print(json.dumps(payload, indent=2, ensure_ascii=False))
    else:
        print("Corpus manifest verification")
        print(f"  manifest: {manifest_path}")
        print(f"  corpus:   {corpus_dir}")
        if summary:
            counts = summary["counts"]
            print(f"  version:  {summary.get('corpusVersion')}")
            print(
                "  forms:    "
                f"{counts['forms']} ({counts['real']} real, {counts['synthetic']} synthetic)"
            )
            print(f"  pages:    {counts['pages']}")
            print(f"  fields:   {counts['fields']}")
        if failures:
            print(f"FAIL: {len(failures)} problem(s)")
            for failure in failures:
                print(f"  - {failure}")
        else:
            print("PASS: manifest and all referenced checksums are valid")

    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
PY
