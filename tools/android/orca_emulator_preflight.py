#!/usr/bin/env python3
"""Orca integrated Android emulator preflight for this repository.

The maintainer preflight in the Orca maintainer skill requires the effective
runtime, SDK, emulator and device/worktree binding to be verified before a
device test.  This script performs that check against the *documented* Orca
CLI surface (``orca emulator devices|list``, ``orca worktree list``) and the
Android SDK ``adb``/``emulator`` binaries.  It adds no orchestration and owns
no state.

Exit codes:
  0  every check passed
  1  at least one check failed (details in the report)
  2  usage or resolution error (no meaningful check could run)

Usage (inside an Orca worktree terminal):

  tools/android/orca_emulator_preflight.py \
      --avd T025_Pixel7_API35_KVM_20261115 --json

The worktree id defaults to ``$ORCA_WORKTREE_ID`` and falls back to the
worktree whose path equals the current directory.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path

EXPECTED_AVD = {
    "hw.device.name": "pixel_7",
    "abi.type": "x86_64",
    "hw.ramSize": "4096",
    "api": "android-35",
    "tag": "google_apis",
    "sysimg_abi": "x86_64",
}


# ---------------------------------------------------------------------------
# Pure helpers (unit-tested without a device)
# ---------------------------------------------------------------------------


def parse_ini(text: str) -> dict[str, str]:
    values: dict[str, str] = {}
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip()
    return values


def avd_profile_problems(config_text: str, expected: dict[str, str] | None = None) -> list[str]:
    """Return every deviation from the pinned Pixel 7 / API 35 / x86_64 / 4 GB profile."""
    expected = expected or EXPECTED_AVD
    values = parse_ini(config_text)
    problems: list[str] = []
    for key in ("hw.device.name", "abi.type", "hw.ramSize"):
        want = expected[key]
        got = values.get(key, "<missing>")
        if got != want:
            problems.append(f"{key}={got} (expected {want})")
    sysdir = values.get("image.sysdir.1", "")
    for token in (expected["api"], expected["tag"], expected["sysimg_abi"]):
        if token not in sysdir:
            problems.append(f"image.sysdir.1={sysdir or '<missing>'} lacks {token}")
    return problems


def booted_devices(payload: object, avd: str) -> list[dict]:
    devices: list[dict] = []
    if isinstance(payload, dict):
        devices = payload.get("result") or []
    return [
        device
        for device in devices
        if device.get("backend") == "android"
        and device.get("name") == avd
        and device.get("state") == "booted"
    ]


def device_entries(payload: object, avd: str) -> list[dict]:
    if isinstance(payload, dict):
        return [
            device
            for device in (payload.get("result") or [])
            if device.get("backend") == "android" and device.get("name") == avd
        ]
    return []


def session_problems(payload: object, worktree_id: str, serial: str) -> list[str]:
    """Check the Orca session is bound to exactly this worktree and device."""
    sessions = []
    if isinstance(payload, dict):
        result = payload.get("result")
        if isinstance(result, dict):
            sessions = result.get("sessions") or []
    matches = [s for s in sessions if s.get("worktreeId") == worktree_id]
    if not matches:
        return [f"no Orca emulator session for worktree {worktree_id}"]
    problems = []
    for session in matches:
        if session.get("deviceUdid") != serial:
            problems.append(
                f"session device {session.get('deviceUdid')} != expected {serial}"
            )
    return problems


def live_view_problems(
    payload: object, worktree_id: str, serial: str, device_ps: str, host_ps: str
) -> list[str]:
    """A visible Orca pane needs a scrcpy stream, not only a booted adb device."""
    problems: list[str] = []
    sessions = []
    if isinstance(payload, dict):
        result = payload.get("result")
        if isinstance(result, dict):
            sessions = result.get("sessions") or []
    session = next((s for s in sessions if s.get("worktreeId") == worktree_id), None)
    if session is None:
        return ["no session to stream"]
    if session.get("streamUrl") != f"scrcpy://{serial}":
        problems.append(f"streamUrl={session.get('streamUrl')!r}")
    if not session.get("streamCodec"):
        problems.append("streamCodec is empty")
    if "com.genymobile.scrcpy.Server" not in device_ps:
        problems.append("scrcpy server not running on the device")
    if "com.genymobile.scrcpy.Server" not in host_ps:
        problems.append("Orca scrcpy helper not running on the host")
    return problems


def duplicate_emulator_problems(host_ps: str, avd: str) -> list[str]:
    """More than one qemu for the same AVD is an accidental duplicate start."""
    count = sum(
        1
        for line in host_ps.splitlines()
        if "qemu-system-x86_64" in line and f"-avd {avd}" in line
    )
    if count > 1:
        return [f"{count} qemu processes for {avd} (expected at most 1)"]
    return []


def adb_probe_problems(returncode: int, stdout: str, stderr: str) -> list[str]:
    """Map an adb shell probe to a precise, actionable failure."""
    combined = f"{stdout}\n{stderr}"
    if "smartsocket" in combined and "Operation not permitted" in combined:
        return [
            "adb server cannot bind tcp:5037 here (EPERM). This is a sandboxed "
            "worker environment, not the host: start/reuse the host adb server "
            "and run the device test from the Orca worktree terminal."
        ]
    if returncode == 124:
        return ["adb probe timed out (interrupted transport)"]
    if returncode != 0:
        return [f"adb probe exited {returncode}: {combined.strip()[:400]}"]
    return []


def unreachable_problems(get_state: str, boot_completed: str) -> list[str]:
    problems: list[str] = []
    if get_state.strip() != "device":
        problems.append(f"adb get-state={get_state.strip()!r} (expected 'device')")
    if boot_completed.strip() != "1":
        problems.append(
            f"sys.boot_completed={boot_completed.strip()!r} (expected '1')"
        )
    return problems


def temp_dir_problems(directory: Path, probe_bytes: int = 8 * 1024 * 1024) -> list[str]:
    """A quota-exhausted TMPDIR breaks Gradle asset compression mid-build.

    ``statvfs`` free blocks can look healthy while the tmpfs user quota is
    already exhausted, so probe with a real bounded write and remove it.
    """
    problems: list[str] = []
    if not directory.is_dir():
        return [f"TMPDIR {directory} is not a directory"]
    try:
        usage = shutil.disk_usage(directory)
        if usage.free < 2 * 1024 * 1024 * 1024:
            problems.append(
                f"TMPDIR {directory} has only {usage.free // (1024 * 1024)} MiB free"
            )
    except OSError as exc:
        problems.append(f"TMPDIR {directory} is not readable: {exc}")
    probe = directory / f".feldexa-preflight-{os.getpid()}.bin"
    try:
        with open(probe, "wb") as handle:
            handle.write(b"\0" * probe_bytes)
            handle.flush()
            os.fsync(handle.fileno())
    except OSError as exc:
        problems.append(
            f"TMPDIR {directory} cannot accept a {probe_bytes // (1024 * 1024)} MiB "
            f"probe (quota/space): {exc}; set TMPDIR and java.io.tmpdir to a "
            "worktree build directory"
        )
    finally:
        try:
            probe.unlink()
        except OSError:
            pass
    return problems


# ---------------------------------------------------------------------------
# Live checks
# ---------------------------------------------------------------------------


def run(cmd: list[str], timeout: int = 30) -> tuple[int, str, str]:
    try:
        completed = subprocess.run(
            cmd, capture_output=True, text=True, timeout=timeout, check=False
        )
        return completed.returncode, completed.stdout, completed.stderr
    except FileNotFoundError as exc:
        return 127, "", str(exc)
    except subprocess.TimeoutExpired as exc:
        out = exc.stdout if isinstance(exc.stdout, str) else ""
        err = exc.stderr if isinstance(exc.stderr, str) else ""
        return 124, out, f"{err}\ntimeout after {timeout}s"


def resolve_orca() -> str | None:
    explicit = os.environ.get("ORCA_CLI_COMMAND")
    if explicit and Path(explicit).is_file():
        return explicit
    for name in ("orca-ide",):
        found = shutil.which(name)
        if found:
            return found
    # Never fall through to bare `orca` on Linux outside an Orca terminal:
    # that name resolves to the GNOME screen reader.
    return None


def resolve_worktree_id(orca: str, cwd: Path) -> str | None:
    env_id = os.environ.get("ORCA_WORKTREE_ID")
    if env_id:
        return env_id
    code, out, _ = run([orca, "worktree", "list", "--json"], timeout=30)
    if code != 0:
        return None
    try:
        worktrees = json.loads(out)["result"]["worktrees"]
    except (KeyError, TypeError, json.JSONDecodeError):
        return None
    for worktree in worktrees:
        if Path(worktree.get("path", "")).resolve() == cwd.resolve():
            return worktree.get("id")
    return None


def resolve_sdk() -> Path | None:
    for name in ("ANDROID_HOME", "ANDROID_SDK_ROOT"):
        value = os.environ.get(name)
        if value and Path(value).is_dir():
            return Path(value)
    default = Path.home() / "Android" / "Sdk"
    return default if default.is_dir() else None


def resolve_avd_dir(avd: str) -> Path:
    return Path.home() / ".android" / "avd" / f"{avd}.avd"


def check_sdk(sdk: Path) -> list[str]:
    problems: list[str] = []
    required = [
        sdk / "platform-tools" / "adb",
        sdk / "emulator" / "emulator",
        sdk / "platforms" / "android-35",
        sdk / "system-images" / "android-35" / "google_apis" / "x86_64",
    ]
    for path in required:
        if not path.exists():
            problems.append(f"missing {path}")
    build_tools = sdk / "build-tools"
    if not build_tools.is_dir() or not any(build_tools.iterdir()):
        problems.append(f"missing build-tools under {build_tools}")
    return problems


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--avd", required=True, help="AVD name, e.g. Pixel7_API35")
    parser.add_argument("--serial", help="adb serial, defaults to emulator-5554")
    parser.add_argument("--worktree-id", help="full Orca worktree id")
    parser.add_argument("--json", action="store_true", help="machine-readable report")
    parser.add_argument(
        "--avd-config",
        help="override config.ini path (used to rehearse the profile regression)",
    )
    parser.add_argument(
        "--skip-device",
        action="store_true",
        help="only check host/SDK/AVD profile (no running device needed)",
    )
    parser.add_argument(
        "--tmpdir",
        default=tempfile.gettempdir(),
        help="directory Gradle/java.io.tmpdir will use (default: TMPDIR or /tmp)",
    )
    args = parser.parse_args(argv)

    report: dict[str, object] = {"avd": args.avd, "checks": []}
    failures = 0

    def add(name: str, problems: list[str], detail: str = "") -> None:
        nonlocal failures
        status = "PASS" if not problems else "FAIL"
        if problems:
            failures += 1
            text = "; ".join(problems)
            if detail:
                text = f"{detail}: {text}"
        else:
            text = detail
        report["checks"].append({"name": name, "status": status, "detail": text})

    orca = resolve_orca()
    add(
        "orca_cli",
        [] if orca else ["ORCA_CLI_COMMAND/orca-ide not found"],
        orca or "",
    )
    if not orca:
        _emit(report, args.json)
        return 1

    code, version, version_err = run([orca, "--version"], timeout=20)
    add(
        "orca_runtime",
        [] if code == 0 else [f"orca --version exited {code}: {version_err}"],
        version.strip(),
    )

    kvm = Path("/dev/kvm")
    kvm_problems: list[str] = []
    if not kvm.exists():
        kvm_problems.append("/dev/kvm is missing")
    elif not stat.S_ISCHR(kvm.stat().st_mode):
        kvm_problems.append("/dev/kvm is not a character device")
    else:
        try:
            fd = os.open(kvm, os.O_RDWR)
            os.close(fd)
        except OSError as exc:
            kvm_problems.append(f"/dev/kvm is not accessible: {exc}")
    add(
        "kvm",
        kvm_problems,
        "host kernel KVM device is accessible from this command environment",
    )

    add(
        "temp_space",
        temp_dir_problems(Path(args.tmpdir)),
        f"Gradle/java.io.tmpdir {args.tmpdir}",
    )

    sdk = resolve_sdk()
    if sdk is None:
        add("android_sdk", ["Android SDK not found (ANDROID_HOME/~/Android/Sdk)"])
        adb = None
        emulator = None
    else:
        sdk_problems = check_sdk(sdk)
        add("android_sdk", sdk_problems, str(sdk))
        adb = sdk / "platform-tools" / "adb"
        emulator = sdk / "emulator" / "emulator"
        if emulator.is_file():
            accel_code, accel_out, accel_err = run(
                [str(emulator), "-accel-check"], timeout=60
            )
            add(
                "kvm_usable_by_emulator",
                []
                if accel_code == 0 and "usable" in (accel_out + accel_err)
                else [f"emulator -accel-check failed: {accel_out}{accel_err}"],
                accel_out.strip(),
            )
    if adb is None or not adb.is_file():
        _emit(report, args.json)
        return 1

    avd_dir = resolve_avd_dir(args.avd)
    config_path = Path(args.avd_config) if args.avd_config else avd_dir / "config.ini"
    if not config_path.is_file():
        add("avd_profile", [f"{config_path} is missing"])
    else:
        add(
            "avd_profile",
            avd_profile_problems(config_path.read_text(encoding="utf-8")),
            str(config_path),
        )

    worktree_id = args.worktree_id or resolve_worktree_id(orca, Path.cwd())
    report["worktreeId"] = worktree_id
    if not worktree_id:
        add("worktree_binding", ["worktree id could not be resolved"])

    serial = args.serial
    code, devices_out, devices_err = run(
        [orca, "emulator", "devices", "--json"], timeout=60
    )
    devices_payload: object = {}
    if code == 0:
        try:
            devices_payload = json.loads(devices_out)
        except json.JSONDecodeError:
            add("orca_devices", [f"invalid devices JSON: {devices_out[:300]}"])
    else:
        add("orca_devices", [f"orca emulator devices exited {code}: {devices_err}"])

    entries = device_entries(devices_payload, args.avd)
    if serial is None and entries:
        serial = entries[0].get("id")
    report["serial"] = serial

    host_ps_code, host_ps, host_ps_err = run(["ps", "aux"], timeout=30)
    host_ps = host_ps if host_ps_code == 0 else ""
    add(
        "single_emulator_instance",
        duplicate_emulator_problems(host_ps, args.avd),
        "one qemu process for the AVD",
    )

    if args.skip_device:
        _emit(report, args.json)
        return 1 if failures else 0

    if not serial:
        add("device_reachable", ["no booted device serial resolved"])
        _emit(report, args.json)
        return 1

    booted = booted_devices(devices_payload, args.avd)
    add(
        "device_booted",
        [] if booted else [f"{args.avd} is not booted in Orca devices"],
        serial,
    )

    state_code, state_out, state_err = run(
        [str(adb), "-s", serial, "get-state"], timeout=20
    )
    boot_code, boot_out, boot_err = run(
        [str(adb), "-s", serial, "shell", "getprop", "sys.boot_completed"],
        timeout=20,
    )
    reach_problems = unreachable_problems(state_out, boot_out)
    reach_problems += adb_probe_problems(state_code, state_out, state_err)
    reach_problems += adb_probe_problems(boot_code, boot_out, boot_err)
    add("transport", reach_problems, f"{args.avd} adb transport")

    # Two more probes: the confirmed failure was a transport that died after
    # the first successful command.
    transport_problems = list(reach_problems)
    for _ in range(2):
        probe_code, probe_out, probe_err = run(
            [str(adb), "-s", serial, "shell", "echo", "feldexa-preflight"],
            timeout=20,
        )
        transport_problems += adb_probe_problems(probe_code, probe_out, probe_err)
        if probe_code == 0 and "feldexa-preflight" not in probe_out:
            transport_problems.append("adb echo probe returned no marker")
    add("transport_stability", transport_problems, "three sequential adb probes")

    code, sessions_out, sessions_err = run(
        [orca, "emulator", "list", "--json"], timeout=60
    )
    sessions_payload: object = {}
    if code == 0:
        try:
            sessions_payload = json.loads(sessions_out)
        except json.JSONDecodeError:
            add("worktree_binding", [f"invalid session JSON: {sessions_out[:300]}"])
    else:
        add("worktree_binding", [f"orca emulator list exited {code}: {sessions_err}"])

    if worktree_id and serial:
        add(
            "worktree_binding",
            session_problems(sessions_payload, worktree_id, serial),
            f"{worktree_id} -> {serial}",
        )
        device_ps_code, device_ps, _ = run(
            [
                str(adb),
                "-s",
                serial,
                "shell",
                "ps",
                "-A",
                "-o",
                "PID,NAME,ARGS",
            ],
            timeout=30,
        )
        add(
            "live_view",
            live_view_problems(
                sessions_payload,
                worktree_id,
                serial,
                device_ps if device_ps_code == 0 else "",
                host_ps,
            ),
            "scrcpy stream bound to this worktree",
        )

    _emit(report, args.json)
    return 1 if failures else 0


def _emit(report: dict[str, object], as_json: bool) -> None:
    if as_json:
        print(json.dumps(report, indent=2, ensure_ascii=False))
        return
    print(f"Orca Android emulator preflight: {report.get('avd')}")
    for check in report.get("checks", []):  # type: ignore[union-attr]
        print(f"[{check['status']}] {check['name']}: {check['detail']}")
    failed = sum(
        1 for check in report.get("checks", []) if check["status"] != "PASS"  # type: ignore[union-attr]
    )
    print(f"{'PASS' if failed == 0 else 'FAIL'} ({failed} failed checks)")


if __name__ == "__main__":
    sys.exit(main())
