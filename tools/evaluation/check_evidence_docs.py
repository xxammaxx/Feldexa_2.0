#!/usr/bin/env python3
"""Minimal T010 evidence-document check (no third-party dependencies).

Validates the evidence README, the T010 report's artifact rows, and, when an
attestation is supplied, the candidate commit, report hash, and changed files.
Local `.dart_tool/` logs are skipped because they are not in a fresh clone.

Usage:
  python3 tools/evaluation/check_evidence_docs.py
  python3 tools/evaluation/check_evidence_docs.py --attestation-ref <ref>
  python3 tools/evaluation/check_evidence_docs.py --attestation-file <path>
"""
import argparse
import hashlib
import json
import pathlib
import re
import subprocess
import sys

README = "specs/001-scanned-form-workflow/reports/README.md"
REPORT = "specs/001-scanned-form-workflow/reports/2026-11-12-t010-evidence.md"
ATTESTATION = "specs/001-scanned-form-workflow/reports/2026-11-12-t010-candidate-attestation.json"

TOKENS = [
    "SIMULATED", "EMULATOR", "DEVICE", "Evidence class", "Revision",
    "Build identity", "Environment", "Checks / tests", "Performance",
    "Limitations", "Artifacts", "Reproducibility", "Review",
    "Can prove", "Can never prove", "Self-reference", "Privacy and logs",
    "external attestation", "candidate SHA", "Independent review",
    "No self-approval",
]
FORBIDDEN_README = ["allocation ID", "allocation <id>", "<absolute path>", "PASS WITH"]
FORBIDDEN_REPORT = ["/home/", ".dsh/sessions", "term_", "ctx_", "task_", "xxammaxx"]


def digest(data):
    return hashlib.sha256(data).hexdigest()


def slug(heading):
    heading = heading.strip().lower()
    heading = re.sub(r"[^\w\- ]", "", heading)
    return heading.replace(" ", "-")


def git(repo, *args):
    return subprocess.check_output(["git", "-C", str(repo), *args])


def check_fences(text, errors, label):
    fence = None
    for line in text.splitlines():
        match = re.match(r"^(`{3,})", line)
        if not match:
            continue
        if fence is None:
            fence = match.group(1)
        elif match.group(1) == fence:
            fence = None
    if fence is not None:
        errors.append(f"{label}: unclosed code fence {fence!r}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".")
    parser.add_argument("--readme", default=README)
    parser.add_argument("--report", default=REPORT)
    parser.add_argument("--attestation-ref")
    parser.add_argument("--attestation-file")
    args = parser.parse_args()

    repo = pathlib.Path(args.repo).resolve()
    readme_path = repo / args.readme
    report_path = repo / args.report
    errors = []

    readme = readme_path.read_text(encoding="utf-8")
    report = report_path.read_text(encoding="utf-8")

    for token in TOKENS:
        if token not in readme:
            errors.append(f"README: missing token {token!r}")
    for needle in FORBIDDEN_README:
        if needle in readme:
            errors.append(f"README: forbidden phrase {needle!r}")
    for needle in FORBIDDEN_REPORT:
        if needle in report:
            errors.append(f"report: sensitive identifier {needle!r}")
    if "PASS WITH" in report:
        errors.append("report: compound status 'PASS WITH' is not allowed")
    if report.count("| Task / issue |") != 1:
        errors.append("report: expected exactly one Task / issue row")
    if "PARTIAL" not in report:
        errors.append("report: gate PARTIAL status is not stated")

    for label, text in (("README", readme), ("report", report)):
        check_fences(text, errors, label)
        for match in re.finditer(r"\[[^\]]+\]\(([^)]+)\)", text):
            target = match.group(1).split("#", 1)[0]
            if target and not target.startswith(("http://", "https://", "mailto:")):
                if not (readme_path.parent / target).resolve().exists():
                    errors.append(f"{label}: broken link {target}")

    headings = {
        slug(re.sub(r"^#+\s*", "", line))
        for line in readme.splitlines()
        if re.match(r"^#{1,6}\s", line)
    }
    for match in re.finditer(r"\[[^\]]+\]\(#([^)]+)\)", readme):
        if match.group(1) not in headings:
            errors.append(f"README: broken anchor #{match.group(1)}")

    # Artifact rows: verify committed artifacts; skip local git-ignored logs.
    artifact_rows = 0
    skipped = 0
    if "## 9. Artifacts" in report and "## 10." in report:
        section = report.split("## 9. Artifacts", 1)[1].split("## 10.", 1)[0]
        for line in section.splitlines():
            line = line.strip()
            if not line.startswith("|"):
                continue
            cells = [cell.strip() for cell in line.strip("|").split("|")]
            if len(cells) == 4 and all(re.fullmatch(r":?-{3,}:?", cell) for cell in cells):
                continue
            if cells and cells[0] == "Artifact":
                continue
            artifact_rows += 1
            if len(cells) != 4 or not all(cells):
                errors.append(f"report: incomplete artifact row {line}")
                continue
            match = re.search(r"`([^`]+)`", cells[1])
            if not match:
                errors.append(f"report: unparseable artifact path {line}")
                continue
            artifact = repo / match.group(1)
            if str(artifact).startswith(str(repo / ".dart_tool")):
                skipped += 1
                continue
            if not artifact.exists():
                errors.append(f"report: artifact missing {match.group(1)}")
                continue
            data = artifact.read_bytes()
            if len(data) != int(cells[2].replace(",", "")):
                errors.append(f"report: byte size mismatch {match.group(1)}")
            if digest(data) != cells[3].strip("`"):
                errors.append(f"report: SHA-256 mismatch {match.group(1)}")
    else:
        errors.append("report: missing artifact section")

    head = git(repo, "rev-parse", "HEAD").decode().strip()
    attestation = None
    if args.attestation_file:
        attestation = json.loads((repo / args.attestation_file).read_text(encoding="utf-8"))
    elif args.attestation_ref:
        blob = git(repo, "show", f"{args.attestation_ref}:{ATTESTATION}")
        attestation = json.loads(blob)
    if attestation is not None:
        candidate = attestation["candidate"]["commit"]
        if candidate != head:
            errors.append("attestation: candidate.commit does not match HEAD")
        report_bytes = report_path.read_bytes()
        if attestation["report_self"]["bytes"] != len(report_bytes):
            errors.append("attestation: report byte size mismatch")
        if attestation["report_self"]["sha256"] != digest(report_bytes):
            errors.append("attestation: report SHA-256 mismatch")
        for item in attestation["candidate"]["changed_files"]:
            path = repo / item["path"]
            if not path.exists():
                errors.append(f"attestation: changed file missing {item['path']}")
                continue
            data = path.read_bytes()
            if len(data) != item["bytes"] or digest(data) != item["sha256"]:
                errors.append(f"attestation: changed file mismatch {item['path']}")
        if candidate in report:
            errors.append("report: contains its own candidate commit SHA")
        print(f"PASS attestation: candidate {candidate[:12]}..., {len(attestation['candidate']['changed_files'])} changed files")
    elif args.attestation_file or args.attestation_ref:
        errors.append("attestation: could not load")

    print(f"PASS README: {len(TOKENS)} tokens, links, anchors, fences")
    print(f"PASS report: {artifact_rows} artifact rows ({skipped} local logs skipped)")
    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        return 1
    print("OK: evidence documents and attestation are consistent")
    return 0


if __name__ == "__main__":
    sys.exit(main())
