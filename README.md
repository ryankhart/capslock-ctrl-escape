# CapsLock Ctrl Escape

A small AutoHotkey v2 script that gives Caps Lock two useful roles:

- Tap Caps Lock within 250 ms to send Escape.
- Hold or use Caps Lock with another input to act as left Ctrl.
- Press bare physical Escape to toggle the real Caps Lock state without also sending Escape to the active application.

## Why this version

Simple dual-role scripts can emit a stray Escape after an unlisted key, lose track of repeated Caps Lock events, or interfere with a physical Ctrl key. This version handles:

- repeated Caps Lock key-down events;
- every physical keyboard virtual key, including keys already held;
- mouse buttons and vertical or horizontal wheel input;
- overlap with the physical left Ctrl key;
- missed Caps Lock release events;
- normal script exit, reload, and replacement cleanup;
- the 32-bit `A_TickCount` rollover.

## Requirements

- Windows
- [AutoHotkey v2](https://www.autohotkey.com/)

## Install

1. Download `CapsLockCtrlEscape.ahk`.
2. Double-click it to run it with AutoHotkey v2.
3. To start it automatically after sign-in, press `Win+R`, enter `shell:startup`, and copy the script into that folder.

## Verify

The script has a nonresident self-test mode. From PowerShell:

```powershell
$ahk = Join-Path $env:ProgramFiles "AutoHotkey\v2\AutoHotkey64.exe"
& $ahk ".\CapsLockCtrlEscape.ahk" --self-test
& $ahk ".\CapsLockCtrlEscape.ahk" --verify-hotkeys
```

Expected output:

```text
CapsLockCtrlEscape self-test: 10 passed
CapsLockCtrlEscape hotkey verification: passed
```

Neither verification mode remains resident. The self-test mode does not install hotkeys or send input.

## Development

The repository includes the development artifacts used to harden and verify the remap:

- [`tests/test_capslock_ctrl_escape.py`](tests/test_capslock_ctrl_escape.py) runs the embedded state tests and hotkey-registration check through the real AutoHotkey executable.
- [`.hermes/specs/capslock-dual-role/SPEC.md`](.hermes/specs/capslock-dual-role/SPEC.md) records the acceptance criteria and traceability.
- [`.hermes/plans/2026-08-23-capslock-dual-role.md`](.hermes/plans/2026-08-23-capslock-dual-role.md) records the implementation and verification plan.

Run the normal development checks from PowerShell:

```powershell
python .\tests\test_capslock_ctrl_escape.py
```

To override AutoHotkey discovery:

```powershell
$env:AUTOHOTKEY_EXE = "D:\path\to\AutoHotkey64.exe"
python .\tests\test_capslock_ctrl_escape.py
```

If the script is installed in your Startup folder and currently running, the optional deployment check also verifies byte identity and requires exactly one matching live process:

```powershell
python .\tests\test_capslock_ctrl_escape.py --deployment
```

## Limitations

- A normally launched script cannot inject input into elevated applications because of Windows UIPI.
- Secure desktop, some games, anti-cheat systems, and raw-input applications may ignore AutoHotkey-generated input.
- Running the remap on both sides of a Remote Desktop session can produce double remapping.

## License

[MIT](LICENSE)
