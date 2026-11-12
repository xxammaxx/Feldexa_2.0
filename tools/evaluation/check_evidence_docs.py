#!/usr/bin/env python3
"""Minimal T010 evidence-document check (no third-party dependencies).

Validates the evidence README, the T010 report's artifact rows, and, when an
attestation is supplied, the candidate commit, report hash, and changed files.
Local `.dart_tool/` logs are skipped because they are not in a fresh clone.

Artifact rows are historical records. They are checked against the committed
tree of a Git revision, never against whatever happens to be in the working
directory after a later task. The default flow is:

1. verify the rows at HEAD;
2. if HEAD no longer matches because a later task changed a listed file, search
   the commits reachable from HEAD for a revision where every recorded row
   matches, and verify that revision;
3. fail if no such revision exists.

`--revision` pins step 1/2 explicitly. With `--attestation-ref` or
`--attestation-file`, the attestation's candidate commit is authoritative and
is checked even when it is not HEAD. This keeps later task updates from
invalidating legitimate historical evidence without accepting a changed file
that no recorded revision ever contained.

Usage:
  python3 tools/evaluation/check_evidence_docs.py
  python3 tools/evaluation/check_evidence_docs.py --revision <commit>
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
REPORT = "specs/001-scanned-form-workflow/reports/2026-11-13-t010-evidence.md"
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


def git_commit(repo, ref):
    """Resolve ref to a full commit SHA, or None."""
    try:
        return git(repo, "rev-parse", "--verify", f"{ref}^{{commit}}").decode().strip()
    except subprocess.CalledProcessError:
        return None


def git_bytes(repo, rev, path):
    """Read path from the committed tree at rev, or None."""
    try:
        return subprocess.check_output(
            ["git", "-C", str(repo), "show", f"{rev}:{path}"],
            stderr=subprocess.DEVNULL,
        )
    except subprocess.CalledProcessError:
        return None


def short(rev):
    return rev[:12]


def repo_relative(repo, path):
    """Return a repository-relative path, or None if it escapes the checkout."""
    candidate = pathlib.Path(path)
    if candidate.is_absolute():
        try:
            candidate = candidate.resolve().relative_to(repo)
        except ValueError:
            return None
    if ".." in candidate.parts:
        return None
    return str(candidate)


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


def parse_artifact_rows(repo, report):
    """Parse the artifact table into (path, bytes, sha256) rows."""
    rows = []
    skipped = 0
    errors = []
    if "## 9. Artifacts" not in report or "## 10." not in report:
        return rows, skipped, ["report: missing artifact section"]

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
        if len(cells) != 4 or not all(cells):
            errors.append(f"report: incomplete artifact row {line}")
            continue
        match = re.search(r"`([^`]+)`", cells[1])
        if not match:
            errors.append(f"report: unparseable artifact path {line}")
            continue
        path = match.group(1)
        if path.startswith(".dart_tool/"):
            skipped += 1
            continue
        safe_path = repo_relative(repo, path)
        if safe_path is None:
            errors.append(f"report: artifact path escapes repository {path}")
            continue
        try:
            size = int(cells[2].replace(",", ""))
            sha256 = cells[3].strip("`")
        except ValueError:
            errors.append(f"report: unparseable artifact row {line}")
            continue
        if not re.fullmatch(r"[0-9a-f]{64}", sha256):
            errors.append(f"report: malformed SHA-256 for {path}")
            continue
        rows.append((safe_path, size, sha256))
    return rows, skipped, errors


def verify_artifacts(repo, rev, rows):
    """Errors for rows that do not match the committed tree at rev."""
    failures = []
    for path, size, sha256 in rows:
        data = git_bytes(repo, rev, path)
        if data is None:
            failures.append(f"report: artifact missing at {short(rev)}: {path}")
            continue
        if len(data) != size:
            failures.append(f"report: byte size mismatch at {short(rev)}: {path}")
        if digest(data) != sha256:
            failures.append(f"report: SHA-256 mismatch at {short(rev)}: {path}")
    return failures


def find_historical_revision(repo, head, report_path, rows):
    """Find an ancestor revision where every recorded row and the report match.

    Only commits reachable from HEAD are considered. This prevents an unrelated
    branch with copied old files from satisfying a historical record.
    """
    if not rows:
        return None
    paths = [row[0] for row in rows]
    try:
        commits = git(repo, "rev-list", head, "--", *paths).decode().splitlines()
    except subprocess.CalledProcessError:
        return None
    for rev in commits:
        if rev == head:
            continue
        if git_bytes(repo, rev, report_path) is None:
            continue
        if not verify_artifacts(repo, rev, rows):
            return rev
    return None


def load_attestation(repo, args, errors):
    try:
        if args.attestation_file:
            return json.loads(
                (repo / args.attestation_file).read_text(encoding="utf-8")
            )
        if args.attestation_ref:
            blob = git(repo, "show", f"{args.attestation_ref}:{ATTESTATION}")
            return json.loads(blob)
    except (OSError, subprocess.CalledProcessError, json.JSONDecodeError) as error:
        errors.append(f"attestation: could not load ({error.__class__.__name__})")
        return None
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repo", default=".")
    parser.add_argument("--readme", default=README)
    parser.add_argument("--report", default=REPORT)
    parser.add_argument("--revision")
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

    rows, skipped, row_errors = parse_artifact_rows(repo, report)
    errors.extend(row_errors)
    artifact_rows = len(rows) + skipped + len(row_errors)

    report_git_path = repo_relative(repo, args.report)
    if report_git_path is None:
        errors.append("report: report path escapes repository")
        report_git_path = args.report

    head = git_commit(repo, "HEAD")
    if head is None:
        errors.append("repository: HEAD is not a commit")
        head = ""

    attestation = load_attestation(repo, args, errors)
    artifact_revision = None
    if attestation is not None:
        candidate = attestation["candidate"]["commit"]
        candidate_revision = git_commit(repo, candidate)
        if candidate_revision is None:
            errors.append(f"attestation: candidate commit missing {short(candidate)}")
        else:
            if args.revision and git_commit(repo, args.revision) != candidate_revision:
                errors.append("attestation: candidate.commit differs from --revision")
            artifact_revision = candidate_revision
            candidate_report = git_bytes(repo, candidate_revision, report_git_path)
            if candidate_report is None:
                errors.append(
                    f"attestation: report missing at {short(candidate_revision)}"
                )
            else:
                if attestation["report_self"]["bytes"] != len(candidate_report):
                    errors.append("attestation: report byte size mismatch")
                if attestation["report_self"]["sha256"] != digest(candidate_report):
                    errors.append("attestation: report SHA-256 mismatch")
                candidate_text = candidate_report.decode("utf-8", errors="replace")
                if candidate in candidate_text:
                    errors.append("report: contains its own candidate commit SHA")
            for item in attestation["candidate"]["changed_files"]:
                path = repo_relative(repo, item["path"])
                data = (
                    None
                    if path is None
                    else git_bytes(repo, candidate_revision, path)
                )
                if data is None:
                    errors.append(
                        f"attestation: changed file missing at "
                        f"{short(candidate_revision)}: {item['path']}"
                    )
                    continue
                if len(data) != item["bytes"] or digest(data) != item["sha256"]:
                    errors.append(
                        f"attestation: changed file mismatch at "
                        f"{short(candidate_revision)}: {item['path']}"
                    )
            print(
                f"PASS attestation: candidate {short(candidate_revision)}..., "
                f"{len(attestation['candidate']['changed_files'])} changed files"
            )
    if artifact_revision is not None:
        artifact_errors = verify_artifacts(repo, artifact_revision, rows)
        errors.extend(artifact_errors)
        print(
            f"PASS artifacts: attestation candidate {short(artifact_revision)} "
            f"({len(rows)} recorded)"
        )
    elif args.revision:
        revision = git_commit(repo, args.revision)
        if revision is None:
            errors.append(f"revision: not a commit {args.revision}")
        else:
            artifact_errors = verify_artifacts(repo, revision, rows)
            errors.extend(artifact_errors)
            if not artifact_errors:
                print(f"PASS artifacts: revision {short(revision)} ({len(rows)} recorded)")
    elif head:
        current_errors = verify_artifacts(repo, head, rows)
        if not current_errors:
            print(f"PASS artifacts: HEAD {short(head)} ({len(rows)} recorded)")
        else:
            historical = find_historical_revision(
                repo, head, report_git_path, rows
            )
            if historical is not None:
                print(
                    f"PASS historical artifacts: {short(historical)} "
                    f"({len(rows)} recorded; later task changes accepted only "
                    "at the recorded revision)"
                )
            else:
                errors.extend(current_errors)
                errors.append(
                    "report: no reachable historical revision matches all "
                    "recorded artifact hashes"
                )

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
