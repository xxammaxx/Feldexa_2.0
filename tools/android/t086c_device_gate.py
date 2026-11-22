#!/usr/bin/env python3
"""T086C emulator-binding gate (called by tools/android/t086c_drive_overflow.sh).

Proves that the emulator the journey runs on is the expected Orca Pixel 7 API 35
emulator, that it is an emulator (never the physical device), and that no other
worktree holds an Orca emulator session for it. Exit 0 only when every check
passes.

Inputs (all produced by `orca emulator`):
  1. `orca emulator devices --json`           device inventory
  2. `orca emulator list --worktree path:...` this worktree's sessions
  3. `orca emulator list --json`              every worktree's sessions

Evidence class: EMULATOR gate only; the journey itself produces the evidence.
"""

import json
import sys


def load(path: str):
    with open(path, encoding='utf-8') as handle:
        return json.load(handle)


def main(argv: list[str]) -> int:
    if len(argv) != 7:
        print('usage: t086c_device_gate.py DEVICES WORKTREE ALL SERIAL AVD API')
        return 2
    devices_path, worktree_path, all_path, serial, avd, api = argv[1:7]

    devices_result = load(devices_path).get('result')
    if not isinstance(devices_result, list):
        print('orca emulator devices result is not a list')
        return 1
    matches = [device for device in devices_result if device.get('id') == serial]
    if len(matches) != 1:
        print(f'expected exactly one Orca device for {serial}')
        return 1
    device = matches[0]
    if device.get('name') != avd:
        print(f"unexpected Orca device name {device.get('name')!r}")
        return 1
    if str(device.get('apiLevel')) != api:
        print(f"unexpected Orca API level {device.get('apiLevel')!r}")
        return 1
    if device.get('state') != 'booted':
        print(f"Orca device is not booted: {device.get('state')!r}")
        return 1
    if device.get('detail') != 'emulator':
        print(f"Orca device is not an emulator: {device.get('detail')!r}")
        return 1
    if not device.get('isAvailable', False):
        print(f'{serial} is not reported available by Orca')
        return 1

    worktree_result = load(worktree_path).get('result')
    if not isinstance(worktree_result, dict):
        print('orca emulator list result is not an object')
        return 1
    worktree_sessions = worktree_result.get('sessions')
    if not isinstance(worktree_sessions, list):
        print('orca emulator list sessions is not a list')
        return 1
    if worktree_sessions and not any(
        serial in json.dumps(session) for session in worktree_sessions
    ):
        print(f'the worktree holds an Orca session that does not reference {serial}')
        return 1

    all_result = load(all_path).get('result')
    if not isinstance(all_result, dict):
        print('global orca emulator list result is not an object')
        return 1
    all_sessions = all_result.get('sessions')
    if not isinstance(all_sessions, list):
        print('global orca emulator list sessions is not a list')
        return 1
    claimed = [session for session in all_sessions if serial in json.dumps(session)]
    if claimed:
        print(f'{serial} is referenced by an Orca session that is not this worktree')
        return 1

    print(
        f'PASS: {serial} is a booted Orca emulator ({avd}, API {api}), '
        f'available and not bound to another worktree '
        f'(worktree sessions={len(worktree_sessions)}, global sessions={len(all_sessions)})'
    )
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
