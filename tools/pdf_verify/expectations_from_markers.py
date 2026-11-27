#!/usr/bin/env python3
"""Build a T105 verifier expectations file from integration-test markers.

The test prints the *real* display-space field rectangles it exported, so the
harness never receives a guessed geometry. Two marker families exist:

  T334_FIELD_RECT:PAGE=n:X_MPT=..:Y_MPT=..:W_MPT=..:H_MPT=..
      the drawn text field of export cycles 1 and 2 (value ``Müller``);

  T109_EXPECT:ID=<id>:PAGE=n:X_MPT=..:Y_MPT=..:W_MPT=..:H_MPT=..
      the T109 mark leg: ``text`` (value ``Müller``), ``checkbox-checked``,
      ``checkbox-empty``, ``signature-a`` and ``signature-b``.

Output shape is the one documented by ``verify_artifact.py``:

    {"fields": [...], "marks": [...], "masks": [...]}

Every rectangle also becomes a mask, so the masked appearance diff excludes
exactly the regions the export is allowed to change.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

MT_FIELDS = ("X_MPT", "Y_MPT", "W_MPT", "H_MPT")
T334_PATTERN = re.compile(
    r"^T334_FIELD_RECT:PAGE=(\d+):X_MPT=(-?\d+):Y_MPT=(-?\d+):"
    r"W_MPT=(-?\d+):H_MPT=(-?\d+)$"
)
T109_PATTERN = re.compile(
    r"^T109_EXPECT:ID=([a-z0-9-]+):PAGE=(\d+):X_MPT=(-?\d+):"
    r"Y_MPT=(-?\d+):W_MPT=(-?\d+):H_MPT=(-?\d+)$"
)

# The synthetic value the journey enters; it is not personal data.
TEXT_VALUE = "Müller"

MARK_KINDS = {
    "checkbox-checked": ("checkbox", "marked"),
    "checkbox-empty": ("checkbox", "empty"),
    "signature-a": ("signature", "marked"),
    "signature-b": ("signature", "marked"),
}


def _rect(groups: tuple[str, ...]) -> list[float]:
    return [int(value) / 1000.0 for value in groups]


def build(markers: list[str], index: int) -> dict:
    fields: list[dict] = []
    marks: list[dict] = []
    masks: list[dict] = []
    if index in (1, 2):
        found = [m for m in markers if (match := T334_PATTERN.match(m))]
        if len(found) != 1:
            raise ValueError(f"index {index}: expected one T334_FIELD_RECT, found {len(found)}")
        match = T334_PATTERN.match(found[0])
        assert match is not None
        page = int(match.group(1))
        rect = _rect(match.groups()[1:])
        fields.append({"page": page, "rect": rect, "type": "text", "value": TEXT_VALUE})
        masks.append({"page": page, "rect": rect})
    elif index == 4:
        for marker in markers:
            match = T109_PATTERN.match(marker)
            if not match:
                continue
            identifier = match.group(1)
            page = int(match.group(2))
            rect = _rect(match.groups()[2:])
            masks.append({"page": page, "rect": rect})
            if identifier == "text":
                fields.append(
                    {"page": page, "rect": rect, "type": "text", "value": TEXT_VALUE}
                )
            elif identifier in MARK_KINDS:
                kind, expected = MARK_KINDS[identifier]
                marks.append(
                    {
                        "page": page,
                        "rect": rect,
                        "type": kind,
                        "expected": expected,
                    }
                )
            else:
                raise ValueError(f"unknown T109_EXPECT id {identifier!r}")
        if len(fields) != 1 or len(marks) != 4 or len(masks) != 5:
            raise ValueError(
                f"index 4: expected 1 text field, 4 marks, 5 masks; got "
                f"{len(fields)}, {len(marks)}, {len(masks)}"
            )
    else:
        raise ValueError(f"no expectations are defined for artifact index {index}")
    return {
        "note": (
            f"T105 expectations for export artifact {index}, derived from the "
            "integration test's own T334_FIELD_RECT/T109_EXPECT markers; every "
            "rect is also an appearance mask"
        ),
        "fields": fields,
        "marks": marks,
        "masks": masks,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--markers", required=True, type=Path)
    parser.add_argument("--index", required=True, type=int)
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args(argv)
    try:
        markers = args.markers.read_text(encoding="utf-8").splitlines()
        payload = build(markers, args.index)
    except (OSError, ValueError) as exc:
        print(f"expectations_from_markers: {exc}", file=sys.stderr)
        return 2
    args.out.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps(payload["note"], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    sys.exit(main())
