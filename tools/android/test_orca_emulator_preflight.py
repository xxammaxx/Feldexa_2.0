"""Regression tests for the Orca integrated Android emulator preflight.

Each case reproduces one of the confirmed failure modes with a small fixture,
so the guard is proven to fail on the defective baseline and pass on the
repaired one without needing a live emulator.
"""

import os
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import orca_emulator_preflight as preflight

GOOD_CONFIG = """\
abi.type=x86_64
hw.device.name=pixel_7
hw.ramSize=4096
image.sysdir.1=system-images/android-35/google_apis/x86_64/
"""

DEFECTIVE_CONFIG_3GB = GOOD_CONFIG.replace("hw.ramSize=4096", "hw.ramSize=3072")


def devices_payload(state="booted", name="T025_Pixel7_API35_KVM_20261115", did="emulator-5554"):
    return {
        "ok": True,
        "result": [
            {
                "backend": "android",
                "id": name if state == "shutdown" else did,
                "name": name,
                "state": state,
                "apiLevel": "35",
            }
        ],
    }


def sessions_payload(worktree_id, serial, stream="scrcpy", codec="h264"):
    return {
        "ok": True,
        "result": {
            "sessions": [
                {
                    "worktreeId": worktree_id,
                    "backend": "android",
                    "deviceUdid": serial,
                    "streamUrl": f"{stream}://{serial}" if stream else "",
                    "streamCodec": codec,
                }
            ]
        },
    }


class AvdProfileRegression(unittest.TestCase):
    def test_pinned_pixel7_api35_x86_64_4gb_profile_passes(self):
        self.assertEqual(preflight.avd_profile_problems(GOOD_CONFIG), [])

    def test_three_gb_ram_is_rejected(self):
        problems = preflight.avd_profile_problems(DEFECTIVE_CONFIG_3GB)
        self.assertTrue(any("hw.ramSize=3072" in p for p in problems))

    def test_wrong_api_level_is_rejected(self):
        config = GOOD_CONFIG.replace("android-35", "android-31")
        self.assertTrue(
            any("android-35" in p for p in preflight.avd_profile_problems(config))
        )

    def test_32_bit_image_is_rejected(self):
        config = GOOD_CONFIG.replace("x86_64", "x86")
        self.assertTrue(
            any("x86_64" in p for p in preflight.avd_profile_problems(config))
        )


class DeviceAndBindingRegression(unittest.TestCase):
    AVD = "T025_Pixel7_API35_KVM_20261115"
    WT = "5cfd8bbd::/home/user/repo"

    def test_booted_device_is_found(self):
        self.assertEqual(
            len(preflight.booted_devices(devices_payload(), self.AVD)), 1
        )

    def test_shutdown_device_is_not_treated_as_booted(self):
        self.assertEqual(
            preflight.booted_devices(devices_payload(state="shutdown"), self.AVD), []
        )

    def test_wrong_worktree_binding_is_detected(self):
        problems = preflight.session_problems(
            sessions_payload("other-worktree::/tmp/x", "emulator-5554"),
            self.WT,
            "emulator-5554",
        )
        self.assertTrue(any("no Orca emulator session" in p for p in problems))

    def test_wrong_device_serial_is_detected(self):
        problems = preflight.session_problems(
            sessions_payload(self.WT, "emulator-5556"), self.WT, "emulator-5554"
        )
        self.assertTrue(any("emulator-5556" in p for p in problems))

    def test_duplicate_emulator_start_is_detected(self):
        ps = (
            "user 1 ... qemu-system-x86_64-headless -avd AVD -no-window\n"
            "user 2 ... qemu-system-x86_64-headless -avd AVD -no-window\n"
        )
        problems = preflight.duplicate_emulator_problems(ps, "AVD")
        self.assertTrue(any("2 qemu processes" in p for p in problems))

    def test_single_emulator_is_allowed(self):
        ps = "user 1 ... qemu-system-x86_64-headless -avd AVD -no-window\n"
        self.assertEqual(preflight.duplicate_emulator_problems(ps, "AVD"), [])


class TransportAndLiveViewRegression(unittest.TestCase):
    AVD = "T025_Pixel7_API35_KVM_20261115"
    WT = "5cfd8bbd::/home/user/repo"
    DEVICE_PS = "1363 app_process app_process / com.genymobile.scrcpy.Server 2.4"
    HOST_PS = "123 adb -s emulator-5554 shell CLASSPATH=... com.genymobile.scrcpy.Server 2.4"

    def test_adb_smartsocket_eperm_is_classified(self):
        problems = preflight.adb_probe_problems(
            1,
            "",
            "adb F main.cpp:168 could not install *smartsocket* listener: "
            "Operation not permitted",
        )
        self.assertTrue(any("sandboxed worker" in p for p in problems))

    def test_adb_timeout_is_classified(self):
        problems = preflight.adb_probe_problems(124, "", "timeout after 20s")
        self.assertTrue(any("interrupted transport" in p for p in problems))

    def test_unreachable_device_is_detected(self):
        problems = preflight.unreachable_problems("offline", "0")
        self.assertEqual(len(problems), 2)

    def test_incomplete_boot_is_detected(self):
        problems = preflight.unreachable_problems("device", "")
        self.assertTrue(any("sys.boot_completed" in p for p in problems))

    def test_missing_live_view_stream_is_detected(self):
        payload = sessions_payload(self.WT, "emulator-5554", stream="")
        problems = preflight.live_view_problems(
            payload, self.WT, "emulator-5554", self.DEVICE_PS, self.HOST_PS
        )
        self.assertTrue(any("streamUrl" in p for p in problems))

    def test_missing_device_scrcpy_server_is_detected(self):
        payload = sessions_payload(self.WT, "emulator-5554")
        problems = preflight.live_view_problems(
            payload, self.WT, "emulator-5554", "", self.HOST_PS
        )
        self.assertTrue(any("scrcpy server" in p for p in problems))

    def test_working_live_view_passes(self):
        payload = sessions_payload(self.WT, "emulator-5554")
        self.assertEqual(
            preflight.live_view_problems(
                payload, self.WT, "emulator-5554", self.DEVICE_PS, self.HOST_PS
            ),
            [],
        )


class SdkComponentRegression(unittest.TestCase):
    def test_missing_sdk_components_are_reported(self):
        with tempfile.TemporaryDirectory() as tmp:
            sdk = Path(tmp)
            (sdk / "platform-tools").mkdir()
            (sdk / "platform-tools" / "adb").write_text("")
            problems = preflight.check_sdk(sdk)
            joined = "\n".join(problems)
            self.assertIn("emulator/emulator", joined)
            self.assertIn("platforms/android-35", joined)
            self.assertIn("system-images/android-35/google_apis/x86_64", joined)
            self.assertIn("build-tools", joined)

    def test_complete_sdk_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            sdk = Path(tmp)
            for rel in (
                "platform-tools/adb",
                "emulator/emulator",
                "platforms/android-35",
                "system-images/android-35/google_apis/x86_64",
                "build-tools/35.0.0",
            ):
                path = sdk / rel
                if rel.endswith(("adb", "emulator")) or rel.endswith("35.0.0"):
                    path.parent.mkdir(parents=True, exist_ok=True)
                    path.write_text("")
                else:
                    path.mkdir(parents=True, exist_ok=True)
            self.assertEqual(preflight.check_sdk(sdk), [])

    def test_parse_ini_ignores_blank_and_comment_lines(self):
        values = preflight.parse_ini("# comment\n\nhw.ramSize=4096\n")
        self.assertEqual(values["hw.ramSize"], "4096")


class TempDirRegression(unittest.TestCase):
    def test_writable_temp_dir_passes(self):
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as tmp:
            self.assertEqual(preflight.temp_dir_problems(Path(tmp)), [])

    def test_missing_temp_dir_is_rejected(self):
        problems = preflight.temp_dir_problems(Path("/nonexistent/feldexa-tmp"))
        self.assertTrue(any("not a directory" in p for p in problems))

    def test_unwritable_temp_dir_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as tmp:
            path = Path(tmp)
            os.chmod(path, 0o500)
            try:
                problems = preflight.temp_dir_problems(path)
            finally:
                os.chmod(path, 0o700)
            self.assertTrue(any("cannot accept" in p for p in problems))

    def test_low_free_space_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=Path.cwd()) as tmp:
            with mock.patch(
                "orca_emulator_preflight.shutil.disk_usage",
                return_value=mock.Mock(free=1024),
            ):
                problems = preflight.temp_dir_problems(Path(tmp))
        self.assertTrue(any("MiB free" in p for p in problems))


if __name__ == "__main__":
    unittest.main()
