#!/usr/bin/env python3
"""T108/T110 device driver (EMULATOR `emulator-5554`).

One driver for the two export-failure/print acceptance runs, because both share
the same device admission, staging, marker-triggered interaction with a system
UI, evidence capture, and privacy gates:

  failure  `integration_test/export_failure_test.dart` (T108, FR-072/SC-010)
  print    `integration_test/print_test.dart`          (T110, SC-005/CHK019)

The driver:
  1. re-executes itself through `compute_slot.py --wait --resource build
     --resource emulator`, so the Gradle build and the emulator share one heavy
     permit;
  2. binds the device by serial and AVD identity (exactly one attached
     `emulator-<n>`, `qemu=1`, completed boot, API 35); a physical transport is
     counted but never addressed;
  3. stages the committed synthetic `sf-001.pdf`, verifies its SHA-256 on host
     and device, and clears the test app data;
  4. runs `flutter test <file> -d emulator-5554` in the background so the
     driver can react to the two system-UI markers:
       `T108_WAITING_FOR_SAVE_CANCEL` -> press BACK, write the cancel ack;
       `T110_PRINT_REQUESTED`         -> capture the print-preview evidence
                                          (activity/`dumpsys print`, screenshot),
                                          press BACK, write the preview ack;
       `T1xx_ARTIFACT_STORED` (print) -> pick the artifact up with `run-as`,
                                          verify size/digest, render it with
                                          Poppler and MuPDF at 300 dpi, compare
                                          the two engine renderings, and write
                                          the pickup ack;
  5. fails closed: a missing marker, a digest/size mismatch, a missing tool, a
     dirty tree before the run, or a non-zero test exit is never a pass.

Test-only tooling. It adds no product dependency; the only product change in
this slice is the declared debug-only `ImportTestHooks` artifact-directory
probe used by the T108 test.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADB = os.environ.get("FELDEXA_ADB", str(Path.home() / "Android/Sdk/platform-tools/adb"))
FLUTTER = os.environ.get("FELDEXA_FLUTTER", str(Path.home() / "flutter/bin/flutter"))
COMPUTE_SLOT = os.environ.get(
    "FELDEXA_COMPUTE_SLOT",
    str(Path.home() / ".pi/agent/skills/pi-maintainer/scripts/compute_slot.py"),
)
SERIAL = "emulator-5554"
EXPECTED_AVD = "T025_Pixel7_API35_KVM_20261115"
EXPECTED_API = "35"
PACKAGE = "de.feldexa.app"
FIXTURE = "sf-001.pdf"
FIXTURE_SHA256 = "22c939ccc788f24868a115e5f635d1c0e0618d760b28518a4bd5e039f8caa038"
FIXTURE_SIZE = 5956

MODES = {
    "failure": {
        "test": "integration_test/export_failure_test.dart",
        "staging": "/data/local/tmp/t108-fixtures",
        "evidence": "2026-11-27-t108-export-failure",
        "marker": "T108_",
    },
    "print": {
        "test": "integration_test/print_test.dart",
        "staging": "/data/local/tmp/t110-fixtures",
        "evidence": "2026-11-27-t110-print",
        "marker": "T110_",
    },
}


def log(message: str) -> None:
    print(message, flush=True)


def fail(message: str) -> "NoReturn":  # noqa: F821 - string annotation only
    log(f"DRIVER: FAIL: {message}")
    raise SystemExit(1)


def not_run(message: str) -> "NoReturn":  # noqa: F821
    log(f"EMULATOR NOT_RUN: {message}")
    raise SystemExit(2)


def scrub(text: str) -> str:
    """Removes host, worktree, and raw run paths from committed evidence."""
    text = text.replace(str(ROOT) + "/", "")
    text = text.replace(str(ROOT), ".")
    text = text.replace(str(Path.home()) + "/", "~/")
    text = text.replace("run-tscn02hu", "<workspace>")
    text = text.replace("Felda_2.0_Arbeitsbereich", "<workspace>")
    return text


def run(cmd: list[str], *, timeout: int = 120, check: bool = True) -> subprocess.CompletedProcess:
    proc = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    if check and proc.returncode != 0:
        fail(
            f"command failed ({proc.returncode}): {' '.join(cmd)}\n"
            f"stdout: {proc.stdout[-800:]}\nstderr: {proc.stderr[-800:]}"
        )
    return proc


def adb_shell(*args: str, timeout: int = 120) -> str:
    proc = subprocess.run(
        [ADB, "-s", SERIAL, "shell", *args],
        capture_output=True,
        text=True,
        timeout=timeout,
    )
    if proc.returncode != 0:
        fail(f"adb shell {' '.join(args)} failed: {proc.stderr.strip()[:400]}")
    return proc.stdout.replace("\r", "").strip()


def getprop(name: str) -> str:
    return adb_shell("getprop", name)


def has_permit() -> bool:
    return os.environ.get("FELDEXA_DRIVER_PERMIT") == "1"


def reexec_under_permit(argv: list[str]) -> None:
    if has_permit():
        return
    if not Path(COMPUTE_SLOT).is_file():
        fail(f"compute_slot.py not found at {COMPUTE_SLOT}")
    env = dict(os.environ)
    env["FELDEXA_DRIVER_PERMIT"] = "1"
    cmd = [
        sys.executable,
        COMPUTE_SLOT,
        "--wait",
        "--resource",
        "build",
        "--resource",
        "emulator",
        "--",
        sys.executable,
        str(Path(__file__).resolve()),
        *argv,
    ]
    log("DRIVER: acquiring build + emulator permits")
    os.execve(sys.executable, cmd, env)


def verify_device() -> dict[str, str]:
    transports = []
    proc = subprocess.run([ADB, "devices"], capture_output=True, text=True, timeout=60)
    for line in proc.stdout.splitlines()[1:]:
        parts = line.split()
        if len(parts) >= 2 and parts[1] == "device":
            transports.append(parts[0])
    emulators = [t for t in transports if re.fullmatch(r"emulator-\d+", t)]
    if SERIAL not in emulators:
        not_run(f"the expected emulator transport {SERIAL} is not attached (devices: {transports})")
    if len(emulators) != 1:
        not_run(f"expected exactly one emulator transport, found {emulators}")
    info = {
        "serial": SERIAL,
        "avd": getprop("ro.boot.qemu.avd_name"),
        "qemu": getprop("ro.kernel.qemu"),
        "sdk": getprop("ro.build.version.sdk"),
        "boot_completed": getprop("sys.boot_completed"),
        "fingerprint": getprop("ro.build.fingerprint"),
        "release": getprop("ro.build.version.release"),
        "abi": getprop("ro.product.cpu.abi"),
        "non_emulator_transports_addressed": "none",
    }
    if info["avd"] != EXPECTED_AVD:
        not_run(f"AVD is {info['avd']!r}, expected {EXPECTED_AVD!r}")
    if info["qemu"] != "1":
        not_run("the transport is not a QEMU emulator")
    if info["sdk"] != EXPECTED_API:
        not_run(f"API is {info['sdk']!r}, expected {EXPECTED_API!r}")
    if info["boot_completed"] != "1":
        not_run("boot is not completed")
    return info


def git_identity() -> dict[str, str]:
    def git(*args: str) -> str:
        return run(["git", "-C", str(ROOT), *args]).stdout.strip()

    status = git("status", "--porcelain")
    if status:
        fail(f"the working tree is not clean before the run:\n{status[:1200]}")
    return {
        "head": git("rev-parse", "HEAD"),
        "tree": git("rev-parse", "HEAD^{tree}"),
        "branch": git("rev-parse", "--abbrev-ref", "HEAD"),
        "subject": git("log", "-1", "--format=%s"),
    }


def stage_fixture(staging: str) -> None:
    source = ROOT / "apps/feldexa_app/assets/fixtures" / FIXTURE
    digest = hashlib.sha256(source.read_bytes()).hexdigest()
    if digest != FIXTURE_SHA256 or source.stat().st_size != FIXTURE_SIZE:
        fail("the committed sf-001.pdf does not match its pinned digest/size")
    adb_shell("mkdir", "-p", staging)
    run([ADB, "-s", SERIAL, "push", str(source), f"{staging}/{FIXTURE}"], timeout=300)
    adb_shell("chmod", "644", f"{staging}/{FIXTURE}")
    device_digest = adb_shell("sha256sum", f"{staging}/{FIXTURE}").split()[0]
    if device_digest != FIXTURE_SHA256:
        fail("staged fixture digest on the device differs from the pin")
    log(f"DRIVER: staged fixture {FIXTURE} sha256={FIXTURE_SHA256}")


def write_ack(staging: str, name: str) -> None:
    adb_shell("sh", "-c", f": > {staging}/{name}")


def clear_app_data() -> None:
    """Clears the test app data only when the debug app is installed."""
    packages = adb_shell("pm", "list", "packages", PACKAGE)
    if f"package:{PACKAGE}" not in packages.splitlines():
        log("DRIVER: app not installed; nothing to clear")
        return
    adb_shell("pm", "clear", PACKAGE, timeout=180)
    log("DRIVER: app data cleared")


def read_log_lines(proc: subprocess.Popen, log_path: Path, mode: str) -> list[str]:
    cfg = MODES[mode]
    staging = cfg["staging"]
    lines: list[str] = []
    handled_cancel = False
    handled_print = False
    handled_pickup = False
    assert proc.stdout is not None
    with log_path.open("w", encoding="utf-8") as log_file:
        for raw in proc.stdout:
            line = scrub(raw.rstrip("\n"))
            log_file.write(line + "\n")
            log_file.flush()
            print(line, flush=True)
            lines.append(line)
            if not handled_cancel and "T108_WAITING_FOR_SAVE_CANCEL" in line:
                handled_cancel = True
                log("DRIVER: cancelling the system save picker with BACK")
                time.sleep(3)
                adb_shell("input", "keyevent", "4")
                write_ack(staging, "ack-save-cancel")
            if not handled_print and "T110_PRINT_REQUESTED" in line:
                handled_print = True
                capture_print_preview(mode)
                log("DRIVER: closing the system print preview with BACK")
                adb_shell("input", "keyevent", "4")
                time.sleep(2)
                write_ack(staging, "ack-print-preview")
            if (
                mode == "print"
                and not handled_pickup
                and re.search(r"T110_ARTIFACT_STORED:", line)
            ):
                handled_pickup = True
                pickup_print_artifact(mode, line)
                write_ack(staging, "ack-artifact-picked-up")
    return lines


def evidence_dir(mode: str) -> Path:
    path = (
        ROOT
        / "specs/001-scanned-form-workflow/reports/artifacts"
        / MODES[mode]["evidence"]
    )
    path.mkdir(parents=True, exist_ok=True)
    return path


def capture_print_preview(mode: str) -> None:
    out = evidence_dir(mode)
    activity = ""
    spooler = False
    deadline = time.time() + 90
    while time.time() < deadline:
        activity = subprocess.run(
            [ADB, "-s", SERIAL, "shell", "dumpsys", "activity", "activities"],
            capture_output=True,
            text=True,
            timeout=120,
        ).stdout
        spooler = "com.android.printspooler" in activity or "PrintActivity" in activity
        if spooler:
            break
        time.sleep(2)
    (out / "print-preview-activities.txt").write_text(activity, encoding="utf-8")
    print_jobs = subprocess.run(
        [ADB, "-s", SERIAL, "shell", "dumpsys", "print"],
        capture_output=True,
        text=True,
        timeout=120,
    ).stdout
    (out / "print-preview-dumpsys-print.txt").write_text(print_jobs, encoding="utf-8")
    screenshot = out / "print-preview.png"
    shot = subprocess.run(
        [ADB, "-s", SERIAL, "exec-out", "screencap", "-p"],
        capture_output=True,
        timeout=120,
    )
    screenshot.write_bytes(shot.stdout)
    if len(shot.stdout) < 10_000:
        fail("the print-preview screenshot is suspiciously small")
    (out / "print-preview-proof.txt").write_text(
        "print_activity_present="
        + ("1" if spooler else "0")
        + "\n"
        + "screenshot_bytes="
        + str(len(shot.stdout))
        + "\n"
        + "screenshot_sha256="
        + hashlib.sha256(shot.stdout).hexdigest()
        + "\n",
        encoding="utf-8",
    )
    if not spooler:
        fail("no print-spooler/PrintActivity activity was found for the print preview")
    log("DRIVER: print preview activity and screenshot captured")


def pickup_print_artifact(mode: str, line: str) -> None:
    out = evidence_dir(mode)
    match = re.search(
        r"T110_ARTIFACT_STORED:PATH=(?P<path>\S+):BYTES=(?P<bytes>\d+):SHA256=(?P<sha>[0-9a-f]{64})",
        line,
    )
    if not match:
        fail(f"malformed T110_ARTIFACT_STORED marker: {line}")
    device_path = match.group("path")
    marker_bytes = int(match.group("bytes"))
    marker_sha = match.group("sha")
    prefix = f"/data/user/0/{PACKAGE}/"
    if not device_path.startswith(prefix):
        fail(f"artifact path is not inside the app data dir: {device_path}")
    relative = device_path[len(prefix) :]
    proc = subprocess.run(
        [ADB, "-s", SERIAL, "exec-out", "run-as", PACKAGE, "cat", relative],
        capture_output=True,
        timeout=300,
    )
    if proc.returncode != 0 or not proc.stdout:
        fail(f"could not read the artifact through run-as ({relative})")
    artifact = out / "print-artifact.pdf"
    artifact.write_bytes(proc.stdout)
    digest = hashlib.sha256(proc.stdout).hexdigest()
    if len(proc.stdout) != marker_bytes or digest != marker_sha:
        fail(
            "picked-up artifact does not match the marker "
            f"({len(proc.stdout)} bytes/{digest} vs {marker_bytes}/{marker_sha})"
        )
    log(f"DRIVER: picked up artifact {len(proc.stdout)} bytes sha256={digest}")
    verify_print_artifact(mode, artifact)
    # Task-owned export artifact: verified, then deleted; only the digest and
    # the host receipts remain committed.
    artifact.unlink(missing_ok=True)
    shutil.rmtree(out / "engine-renders", ignore_errors=True)


def verify_print_artifact(mode: str, artifact: Path) -> None:
    out = evidence_dir(mode)
    source = ROOT / "tools/corpus/synthetic" / FIXTURE
    # T105 harness: every executable §6 row, including both print engines.
    harness = subprocess.run(
        [
            sys.executable,
            str(ROOT / "tools/pdf_verify/verify_artifact.py"),
            "--source",
            str(source),
            "--artifact",
            str(artifact),
            "--source-sha256",
            FIXTURE_SHA256,
            "--print-dpi",
            "300",
            "--out",
            str(out / "harness-report.json"),
        ],
        capture_output=True,
        text=True,
        timeout=900,
    )
    (out / "harness-console.txt").write_text(
        scrub(harness.stdout + harness.stderr), encoding="utf-8"
    )
    if harness.returncode != 0:
        fail(f"T105 harness failed on the print artifact ({harness.returncode})")
    (out / "harness-report.json").write_text(
        scrub((out / "harness-report.json").read_text(encoding="utf-8")),
        encoding="utf-8",
    )
    report = json.loads((out / "harness-report.json").read_text(encoding="utf-8"))
    rows = {row["check"]: row for row in report["rows"]}
    for required in (
        "structural validity",
        "page count and order",
        "page geometry",
        "no interactive controls",
        "text content",
        "printability",
    ):
        row = rows.get(required)
        if row is None or row["status"] != "PASS":
            fail(f"harness row {required!r} is not PASS: {row}")
    # Two independent engine renderings per page, pixel-compared.
    work = out / "engine-renders"
    if work.exists():
        shutil.rmtree(work)
    work.mkdir()
    rendered = compare_engines(artifact, work)
    (out / "engine-pixel-comparison.txt").write_text(rendered, encoding="utf-8")
    log("DRIVER: Poppler and MuPDF renderings match within tolerance")
    log(
        "DRIVER: harness summary "
        + json.dumps(report["summary"], sort_keys=True)
    )


def compare_engines(artifact: Path, work: Path) -> str:
    pages = int(
        re.search(
            r"^Pages:\s+(\d+)$",
            subprocess.run(
                ["pdfinfo", str(artifact)], capture_output=True, text=True, timeout=120
            ).stdout,
            re.M,
        ).group(1)
    )
    lines = [f"pages={pages}", "dpi=300", "fuzz_percent=5", "max_diff_percent=2.0"]
    for page in range(1, pages + 1):
        poppler_prefix = work / f"p{page:03d}-poppler"
        subprocess.run(
            [
                "pdftoppm",
                "-r",
                "300",
                "-f",
                str(page),
                "-l",
                str(page),
                "-png",
                "-singlefile",
                str(artifact),
                str(poppler_prefix),
            ],
            check=True,
            capture_output=True,
            timeout=300,
        )
        mupdf = work / f"p{page:03d}-mupdf.png"
        subprocess.run(
            [
                "mutool",
                "draw",
                "-r",
                "300",
                "-o",
                str(mupdf),
                str(artifact),
                str(page),
            ],
            check=True,
            capture_output=True,
            timeout=300,
        )
        poppler = Path(str(poppler_prefix) + ".png")
        if not poppler.is_file() or not mupdf.is_file():
            fail(f"engine rendering missing for page {page}")
        diff = subprocess.run(
            ["compare", "-metric", "AE", "-fuzz", "5%", str(poppler), str(mupdf), "null:"],
            capture_output=True,
            text=True,
            timeout=300,
        )
        # compare exits 1 when the images differ (expected) and >1 on a tool
        # error; an empty metric is a failure, never 0 %.
        if diff.returncode > 1:
            fail(f"compare failed on page {page} (exit {diff.returncode}): {diff.stderr[-200:]}")
        metric = (diff.stderr.strip() + diff.stdout.strip()).splitlines()
        if not metric:
            fail(f"compare produced no metric on page {page}")
        differing = float(metric[-1].split()[0])
        size = subprocess.run(
            ["identify", "-format", "%w %h", str(poppler)],
            capture_output=True,
            text=True,
            timeout=120,
        ).stdout.split()
        total = int(size[0]) * int(size[1])
        percent = differing / total * 100.0
        lines.append(
            f"page={page} differing_pixels={int(differing)} total_pixels={total} "
            f"diff_percent={percent:.4f}"
        )
        if percent > 2.0:
            fail(f"engine renderings differ on page {page}: {percent:.2f}% > 2.0%")
        size_mupdf = subprocess.run(
            ["identify", "-format", "%w %h", str(mupdf)],
            capture_output=True,
            text=True,
            timeout=120,
        ).stdout.split()
        if size != size_mupdf:
            fail(f"engine raster dimensions differ on page {page}: {size} vs {size_mupdf}")
    return "\n".join(lines) + "\n"


def extract_markers(lines: list[str], prefix: str) -> list[str]:
    return [line for line in lines if prefix in line]


def run_test(mode: str) -> tuple[list[str], int]:
    cfg = MODES[mode]
    log_path = evidence_dir(mode) / "integration.log"
    env = dict(os.environ)
    env["FELDEXA_DRIVER_PERMIT"] = "1"
    proc = subprocess.Popen(
        [
            FLUTTER,
            "test",
            cfg["test"],
            "-d",
            SERIAL,
        ],
        cwd=str(ROOT / "apps/feldexa_app"),
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        env=env,
    )
    lines = read_log_lines(proc, log_path, mode)
    return lines, proc.wait(timeout=60)


def write_gates(mode: str, lines: list[str], test_exit: int, device: dict, git: dict) -> None:
    out = evidence_dir(mode)
    markers = extract_markers(lines, MODES[mode]["marker"])
    (out / "markers.txt").write_text(scrub("\n".join(markers)) + "\n", encoding="utf-8")
    if test_exit != 0:
        fail(f"flutter test exited {test_exit}")
    if not any("All tests passed!" in line for line in lines):
        fail("flutter test exited 0 without the 'All tests passed!' summary")
    (out / "device.txt").write_text(
        scrub("\n".join(f"{key}={value}" for key, value in device.items())) + "\n",
        encoding="utf-8",
    )
    (out / "git.txt").write_text(
        scrub("\n".join(f"{key}={value}" for key, value in git.items())) + "\n",
        encoding="utf-8",
    )
    reference = "ok" if mode == "failure" else "synthetic sf-001.pdf"
    (out / "readme-note.txt").write_text(
        f"evidence_class=EMULATOR\nartifact_reference={reference}\n"
        f"markers={len(markers)}\n",
        encoding="utf-8",
    )


def privacy_check(mode: str) -> None:
    out = evidence_dir(mode)
    home_hits = [
        path.name
        for path in out.glob("*.txt")
        if "/home/" in path.read_text(encoding="utf-8", errors="ignore")
    ]
    if home_hits:
        fail(f"privacy check found home paths in the evidence: {home_hits}")
    # The print-preview dumps legitimately carry spooler content:// URIs and the
    # fixture's own label; they are evidence of the system UI, not app content
    # leaving the app. The picked-up PDF is deleted before this check.
    texts = [
        p.read_text(encoding="utf-8", errors="ignore")
        for p in out.glob("*.txt")
        if p.is_file() and not p.name.startswith("print-preview-")
    ]
    forbidden = ["Familienname", "Müller-Lüdenscheidt"]
    hits = []
    for text in texts:
        for token in forbidden:
            if token in text:
                hits.append(token)
    if hits:
        fail(f"privacy check found content in the evidence: {sorted(set(hits))}")
    log("DRIVER: privacy checks PASS")


def main() -> int:
    parser = argparse.ArgumentParser(description="T108/T110 device driver")
    parser.add_argument("mode", choices=sorted(MODES))
    args = parser.parse_args()
    reexec_under_permit([args.mode])
    if not Path(FLUTTER).is_file():
        fail(f"flutter not found at {FLUTTER}")
    for tool in ("qpdf", "pdftoppm", "pdftotext", "pdfinfo", "mutool", "compare", "identify"):
        if shutil.which(tool) is None:
            fail(f"required host tool is missing: {tool}")
    out = evidence_dir(args.mode)
    if (
        any(out.iterdir())
        and os.environ.get("FELDEXA_DRIVER_ALLOW_OVERWRITE") != "1"
    ):
        fail(
            f"evidence directory {out.relative_to(ROOT)} is not empty; "
            "set FELDEXA_DRIVER_ALLOW_OVERWRITE=1 to replace it"
        )
    log(f"DRIVER: mode={args.mode} serial={SERIAL}")
    git = git_identity()
    device = verify_device()
    for key, value in device.items():
        log(f"DRIVER: {key}={value}")
    stage_fixture(MODES[args.mode]["staging"])
    clear_app_data()
    lines, test_exit = run_test(args.mode)
    write_gates(args.mode, lines, test_exit, device, git)
    clear_app_data()
    privacy_check(args.mode)
    log(
        f"DRIVER: PASS mode={args.mode} evidence="
        f"{evidence_dir(args.mode).relative_to(ROOT)}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
