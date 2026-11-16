from pathlib import Path
import os
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "inventory" / "exported-configs" / "CapsLockCtrlEscape.ahk"

# The public repository keeps the script at its root.
if not SCRIPT.is_file():
    SCRIPT = ROOT / "CapsLockCtrlEscape.ahk"

PROGRAM_FILES = Path(os.environ.get("ProgramFiles", ""))
DEFAULT_AHK = PROGRAM_FILES / "AutoHotkey" / "v2" / "AutoHotkey64.exe"
AHK = Path(os.environ.get("AUTOHOTKEY_EXE", DEFAULT_AHK))
STARTUP_SCRIPT = (
    Path(os.environ.get("APPDATA", Path.home() / "AppData" / "Roaming"))
    / "Microsoft"
    / "Windows"
    / "Start Menu"
    / "Programs"
    / "Startup"
    / SCRIPT.name
)


def verify_source_contract() -> bool:
    source = SCRIPT.read_text(encoding="utf-8")
    if "InstallRemap(false)" not in source:
        print("FAIL: hotkey verification must register disabled hotkeys")
        return False
    if "InstallRemap(enableHotkeys := true)" not in source:
        print("FAIL: remap installation must support side-effect-free verification")
        return False
    if 'Hotkey("*CapsLock", CapsLockGesture, enabledOption)' not in source:
        print("FAIL: Caps Lock must be owned by one gesture handler")
        return False
    if 'Hotkey("*CapsLock Up", CapsLockReleased, enabledOption)' not in source:
        print("FAIL: the key-up hotkey must only record the release for injected presses")
        return False
    if "RecoverLostCapsUp" in source:
        print("FAIL: the gesture must not be finished from a timer")
        return False
    if "KeyWait(" in source:
        print("FAIL: Caps Lock release must not depend on a key-up event alone")
        return False
    if "WaitForCapsRelease()" not in source:
        print("FAIL: the Caps Lock gesture must poll for release")
        return False
    if '? GetKeyState("CapsLock", "P")' not in source:
        print("FAIL: a physical Caps Lock hold must be read from the keyboard hook")
        return False
    if "WindowsSeesKeyDown(0x14)" in source or "PhysicalCapsIsDown" in source:
        print("FAIL: GetAsyncKeyState cannot see the blocked Caps Lock key; do not poll it")
        return False
    if "KeyboardHookIsBlind()" not in source:
        print("FAIL: the hold must end when an elevated window or secure desktop takes over")
        return False
    if 'g_TapWhileHoldingWindows := ["ahk_exe Wow.exe"]' not in source:
        print("FAIL: games must keep tap-to-Escape while other input is held")
        return False
    if source.count('GetKeyState("LCtrl", "P")') < 2:
        print("FAIL: physical LCtrl checks must distinguish hardware from injected Ctrl")
        return False
    if 'vk => GetKeyState(' in source:
        print("FAIL: the all-key overlap scan must use Windows-global state")
        return False
    if 'Hotkey("$Esc", ToggleCapsLock, enabledOption)' not in source:
        print("FAIL: physical Escape must be blocked while toggling Caps Lock")
        return False
    if 'Hotkey("~$Esc", ToggleCapsLock)' in source:
        print("FAIL: physical Escape must not pass through to the active application")
        return False
    if "SendTapEscape()" not in source:
        print("FAIL: Caps Lock taps must use the isolated Escape sender")
        return False
    if 'Hotkey("$Esc", "Off")' not in source or 'Hotkey("$Esc", "On")' not in source:
        print("FAIL: synthetic Escape must bypass the physical-Escape interceptor")
        return False
    return True


def run_mode(mode: str, expected: str) -> bool:
    try:
        result = subprocess.run(
            [str(AHK), "/ErrorStdOut=UTF-8", str(SCRIPT), mode],
            cwd=ROOT,
            capture_output=True,
            text=True,
            timeout=1,
            check=False,
        )
    except subprocess.TimeoutExpired:
        print(f"FAIL: script did not exit in {mode} mode")
        return False

    output = (result.stdout + result.stderr).strip()
    if result.returncode != 0:
        print(output)
        print(f"FAIL: {mode} exited with code {result.returncode}")
        return False
    if expected not in output:
        print(output)
        print(f"FAIL: expected {mode} summary was not emitted")
        return False

    print(output)
    return True


def verify_deployment() -> bool:
    if not STARTUP_SCRIPT.is_file():
        print(f"FAIL: Startup copy not found: {STARTUP_SCRIPT}")
        return False
    if SCRIPT.read_bytes() != STARTUP_SCRIPT.read_bytes():
        print("FAIL: tracked and Startup script bytes differ")
        return False

    target = str(STARTUP_SCRIPT).replace("'", "''")
    process_name = AHK.name.replace("'", "''")
    command = (
        f"$target='{target}'; $name='{process_name}'; "
        "$matches=@(Get-CimInstance Win32_Process | Where-Object { "
        "$_.Name -eq $name -and "
        "$_.CommandLine -like ('*\"' + $target + '\"*') }); "
        "[Console]::Out.Write($matches.Count)"
    )
    result = subprocess.run(
        ["powershell.exe", "-NoProfile", "-Command", command],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    if result.returncode != 0:
        print((result.stdout + result.stderr).strip())
        print("FAIL: could not query the live AutoHotkey process")
        return False
    try:
        process_count = int(result.stdout.strip())
    except ValueError:
        print(f"FAIL: unexpected process-count output: {result.stdout!r}")
        return False
    if process_count != 1:
        print(f"FAIL: expected 1 live deployed process, found {process_count}")
        return False

    print("CapsLockCtrlEscape deployment verification: source matches Startup; 1 live process")
    return True


def main() -> int:
    if not AHK.is_file():
        print(f"FAIL: AutoHotkey v2 executable not found: {AHK}")
        return 1

    if not verify_source_contract():
        return 1

    if not run_mode("--self-test", "CapsLockCtrlEscape self-test: 12 passed"):
        return 1
    if not run_mode("--verify-hotkeys", "CapsLockCtrlEscape hotkey verification: passed"):
        return 1
    if "--deployment" in sys.argv[1:] and not verify_deployment():
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
