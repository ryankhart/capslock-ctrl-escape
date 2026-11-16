; Caps Lock to Escape (tap) and left Ctrl (hold)
; Bare physical Escape toggles Caps Lock
; AutoHotkey v2 version
#Requires AutoHotkey v2.0
#SingleInstance Force

class CapsCtrlState {
    __New(tapThresholdMs := 250) {
        this.TapThresholdMs := tapThresholdMs
        this.IsHeld := false
        this.WasUsed := false
        this.DownAt := 0
    }

    Press(now) {
        if (this.IsHeld)
            return false

        this.IsHeld := true
        this.WasUsed := false
        this.DownAt := now
        return true
    }

    MarkUsed() {
        if (this.IsHeld)
            this.WasUsed := true
    }

    Release(now) {
        if (!this.IsHeld)
            return {ReleaseCtrl: false, SendEsc: false, ElapsedMs: 0}

        elapsed := CapsCtrlState.ElapsedMs(this.DownAt, now)
        sendEsc := !this.WasUsed && elapsed <= this.TapThresholdMs
        this.IsHeld := false
        this.WasUsed := false
        return {ReleaseCtrl: true, SendEsc: sendEsc, ElapsedMs: elapsed}
    }

    Reset() {
        wasHeld := this.IsHeld
        this.IsHeld := false
        this.WasUsed := false
        this.DownAt := 0
        return wasHeld
    }

    static ElapsedMs(startTick, endTick) {
        return endTick >= startTick
            ? endTick - startTick
            : 0x100000000 - startTick + endTick
    }
}

; Windows where a Caps Lock tap still sends Escape while other keys or mouse
; buttons are already held. In a game a movement key or a mouse button is
; almost always down, so the usual rule ("something else is held, so this
; press means Ctrl") would swallow every Escape. Add one entry per game.
g_TapWhileHoldingWindows := ["ahk_exe Wow.exe"]

g_State := CapsCtrlState(250)
g_KeyMonitor := 0
g_HeldBeforePress := Map()
g_PressWasPhysical := false
g_CapsEventDown := false

if (A_Args.Length && A_Args[1] = "--self-test") {
    RunSelfTests()
    ExitApp 0
}

if (A_Args.Length && A_Args[1] = "--verify-hotkeys") {
    InstallRemap(false)
    FileAppend("CapsLockCtrlEscape hotkey verification: passed`n", "*")
    ExitApp 0
}

InstallRemap()

InstallRemap(enableHotkeys := true) {
    enabledOption := enableHotkeys ? "On" : "Off"
    Hotkey("*CapsLock", CapsLockGesture, enabledOption)
    Hotkey("*CapsLock Up", CapsLockReleased, enabledOption)
    Hotkey("$Esc", ToggleCapsLock, enabledOption)
    Hotkey("~*LCtrl Up", PhysicalLCtrlUp, enabledOption)

    for keyName in [
        "~*LButton", "~*RButton", "~*MButton", "~*XButton1", "~*XButton2",
        "~*WheelUp", "~*WheelDown", "~*WheelLeft", "~*WheelRight"
    ]
        Hotkey(keyName, MarkPointerUse, enabledOption)

    if (enableHotkeys)
        OnExit(ReleaseRemappedCtrl)
}

CapsLockGesture(*) {
    global g_State, g_HeldBeforePress, g_PressWasPhysical, g_CapsEventDown

    ; Keep this hotkey thread alive so default thread limits prevent
    ; typematic/repeated down events from starting another gesture.
    if (!g_State.Press(A_TickCount))
        return

    g_CapsEventDown := true
    g_PressWasPhysical := GetKeyState("CapsLock", "P")
    g_HeldBeforePress := OtherInputDownNow()
    if (ShouldCountHeldInputAsUse(g_HeldBeforePress.Count, TapWhileHoldingWindowIsActive()))
        g_State.MarkUsed()

    StartKeyMonitor()
    Send("{Blind}{LCtrl DownR}")
    result := 0
    try {
        if (!WaitForCapsRelease())
            g_State.MarkUsed()
        result := g_State.Release(A_TickCount)
    } finally {
        StopKeyMonitor()
        if (g_State.IsHeld)
            g_State.Reset()
        ReleaseScriptCtrl()
    }

    if (IsObject(result) && result.SendEsc)
        SendTapEscape()
}

; Returns true when Caps Lock was released normally, false when the wait was
; abandoned because this script could no longer see the keyboard.
WaitForCapsRelease() {
    polls := 0
    while CapsIsHeld() {
        ; Every ~100 ms: if an elevated window or the secure desktop took
        ; over, the key-up will never be seen, so stop holding Ctrl now.
        polls += 1
        if (Mod(polls, 10) = 0 && KeyboardHookIsBlind())
            return false
        Sleep(10)
    }
    return true
}

CapsIsHeld() {
    global g_PressWasPhysical, g_CapsEventDown

    ; A physical press: ask AutoHotkey's keyboard hook, which records the real
    ; key even though this script blocks it. Windows' own GetAsyncKeyState is
    ; no use here: it never learns about a key-down that a hook blocked, so it
    ; reports Caps Lock as up for the whole hold.
    ; A press injected by other software (remote control, a macro device) has
    ; no physical state, so follow its key-up event instead.
    return g_PressWasPhysical
        ? GetKeyState("CapsLock", "P")
        : g_CapsEventDown
}

CapsLockReleased(*) {
    global g_CapsEventDown
    g_CapsEventDown := false
}

ReleaseScriptCtrl() {
    ; Do not force a real left Ctrl logically up while it is physically held.
    if (GetKeyState("LCtrl", "P"))
        return

    Send("{Blind}{LCtrl Up}")
    ; Windows drops input sent toward an elevated window or the secure
    ; desktop, so that release may have gone nowhere. Retry once a normal
    ; window is back in front.
    if (KeyboardHookIsBlind())
        SetTimer(RetryCtrlRelease, 250)
}

RetryCtrlRelease() {
    global g_State

    if (g_State.IsHeld) {
        ; A new gesture owns Ctrl now and will release it itself.
        SetTimer(RetryCtrlRelease, 0)
        return
    }
    if (KeyboardHookIsBlind())
        return

    SetTimer(RetryCtrlRelease, 0)
    if (WindowsSeesKeyDown(0xA2) && !GetKeyState("LCtrl", "P")) ; 0xA2 = left Ctrl
        Send("{Blind}{LCtrl Up}")
}

; True while this script cannot see or send keys: an elevated window is in
; front (and the script is not elevated), or the secure desktop is showing
; (UAC prompt, lock screen, Ctrl+Alt+Del).
KeyboardHookIsBlind() {
    desktop := DllCall("OpenInputDesktop", "UInt", 0, "Int", 0, "UInt", 0x0001, "Ptr")
    if (!desktop)
        return true
    DllCall("CloseDesktop", "Ptr", desktop)

    return !A_IsAdmin && ActiveWindowIsElevated()
}

ActiveWindowIsElevated() {
    hwnd := DllCall("GetForegroundWindow", "Ptr")
    if (!hwnd)
        return false

    pid := 0
    DllCall("GetWindowThreadProcessId", "Ptr", hwnd, "UInt*", &pid)
    return pid ? ProcessIsElevated(pid) : false
}

; Only a definite "elevated" answer counts. Games with anti-cheat refuse
; these queries, and an unknown answer must not cut a Ctrl hold short.
ProcessIsElevated(pid) {
    hProcess := DllCall("OpenProcess", "UInt", 0x1000, "Int", 0, "UInt", pid, "Ptr")
    if (!hProcess)
        return false

    elevated := false
    hToken := 0
    if (DllCall("advapi32\OpenProcessToken", "Ptr", hProcess, "UInt", 0x0008, "Ptr*", &hToken)) {
        isElevated := 0
        returned := 0
        if (DllCall("advapi32\GetTokenInformation", "Ptr", hToken, "Int", 20
            , "UInt*", &isElevated, "UInt", 4, "UInt*", &returned))
            elevated := isElevated != 0
        DllCall("CloseHandle", "Ptr", hToken)
    }
    DllCall("CloseHandle", "Ptr", hProcess)
    return elevated
}

; Windows' global key state. It includes injected keys and misses any key a
; keyboard hook blocked, so it is right for "is anything else down" and for
; the Ctrl this script sends, and wrong for Caps Lock itself.
WindowsSeesKeyDown(vk) {
    return (DllCall("GetAsyncKeyState", "Int", vk, "Short") & 0x8000) != 0
}

SendTapEscape() {
    ; Keep the physical-Escape interceptor from swallowing this synthetic tap.
    Hotkey("$Esc", "Off")
    try Send("{Esc}")
    finally Hotkey("$Esc", "On")
}

StartKeyMonitor() {
    global g_KeyMonitor

    g_KeyMonitor := InputHook("V L0 I1")
    g_KeyMonitor.KeyOpt("{All}", "N")
    g_KeyMonitor.KeyOpt("{CapsLock}", "-N")
    g_KeyMonitor.OnKeyDown := MarkKeyboardUse
    g_KeyMonitor.OnKeyUp := NoteKeyReleased
    g_KeyMonitor.Start()
}

StopKeyMonitor() {
    global g_KeyMonitor

    if (IsObject(g_KeyMonitor) && g_KeyMonitor.InProgress)
        g_KeyMonitor.Stop()
    g_KeyMonitor := 0
}

MarkKeyboardUse(hook, vk, sc) {
    global g_State, g_HeldBeforePress

    ; A key that was already down before Caps Lock keeps auto-repeating while
    ; it is held. Those repeats are not a new press.
    if (g_HeldBeforePress.Has(vk))
        return
    g_State.MarkUsed()
}

NoteKeyReleased(hook, vk, sc) {
    global g_HeldBeforePress

    ; Once released, pressing that key again is a new press.
    if (g_HeldBeforePress.Has(vk))
        g_HeldBeforePress.Delete(vk)
}

MarkPointerUse(*) {
    global g_State
    g_State.MarkUsed()
}

PhysicalLCtrlUp(*) {
    global g_State

    if (!g_State.IsHeld)
        return

    g_State.MarkUsed()
    if (CapsIsHeld())
        Send("{Blind}{LCtrl DownR}")
}

; Every other key or mouse button that is down right now, as a Map of
; virtual-key codes. These are not blocked by this script, so Windows'
; global state sees them.
OtherInputDownNow() {
    return CollectOtherVirtualKeysDown(
        vk => WindowsSeesKeyDown(vk)
    )
}

CollectOtherVirtualKeysDown(isDown) {
    held := Map()
    Loop 254 {
        vk := A_Index
        if (vk = 0x14) ; CapsLock
            continue
        if (isDown.Call(vk))
            held[vk] := true
    }
    return held
}

; Input already held when Caps Lock goes down normally makes the press count
; as Ctrl, never as a tap. Windows listed in g_TapWhileHoldingWindows are the
; exception.
ShouldCountHeldInputAsUse(heldCount, tapWhileHoldingWindowIsActive) {
    return heldCount > 0 && !tapWhileHoldingWindowIsActive
}

TapWhileHoldingWindowIsActive() {
    global g_TapWhileHoldingWindows

    for winTitle in g_TapWhileHoldingWindows {
        if (WinActive(winTitle))
            return true
    }
    return false
}

ToggleCapsLock(*) {
    SetCapsLockState(!GetKeyState("CapsLock", "T"))
}

ReleaseRemappedCtrl(*) {
    global g_State

    StopKeyMonitor()
    if (g_State.Reset() && !GetKeyState("LCtrl", "P"))
        Send("{Blind}{LCtrl Up}")
}

RunSelfTests() {
    passed := 0

    state := CapsCtrlState(250)
    Assert(state.Press(100), "initial press must be accepted")
    Assert(state.IsHeld, "initial press must enter held state")
    passed += 1

    state.MarkUsed()
    Assert(!state.Press(200), "repeated down must be ignored")
    Assert(state.DownAt = 100 && state.WasUsed, "repeat must preserve time and usage")
    passed += 1

    held := CollectOtherVirtualKeysDown(vk => vk = 0x41)
    Assert(held.Count = 1 && held.Has(0x41), "pre-held ordinary key must be collected as other input")
    passed += 1

    Assert(CollectOtherVirtualKeysDown(vk => vk = 0x14).Count = 0, "CapsLock itself must be excluded from overlap detection")
    passed += 1

    Assert(ShouldCountHeldInputAsUse(1, false), "held input must count as use in an ordinary window")
    Assert(!ShouldCountHeldInputAsUse(1, true), "held input must not block a tap in a tap-while-holding window")
    Assert(!ShouldCountHeldInputAsUse(0, false), "no held input must leave the press unused")
    passed += 1

    Assert(ProcessIsElevated(ProcessExist()) = A_IsAdmin, "elevation check must agree with this script's own elevation")
    Assert(!ProcessIsElevated(0), "an unreadable process must not count as elevated")
    passed += 1

    state := CapsCtrlState(250)
    state.Press(100)
    result := state.Release(350)
    Assert(result.ReleaseCtrl && result.SendEsc, "250 ms unused press must be a tap")
    passed += 1

    state := CapsCtrlState(250)
    state.Press(100)
    state.MarkUsed()
    result := state.Release(150)
    Assert(result.ReleaseCtrl && !result.SendEsc, "used press must not send Escape")
    passed += 1

    state := CapsCtrlState(250)
    state.Press(100)
    result := state.Release(351)
    Assert(result.ReleaseCtrl && !result.SendEsc, "press over threshold must not send Escape")
    passed += 1

    state := CapsCtrlState(250)
    state.Press(0xFFFFFFF0)
    result := state.Release(0x20)
    Assert(result.ElapsedMs = 48 && result.SendEsc, "tick rollover must preserve elapsed time")
    passed += 1

    state := CapsCtrlState(250)
    result := state.Release(100)
    Assert(!result.ReleaseCtrl && !result.SendEsc, "stray up must have no effect")
    passed += 1

    state := CapsCtrlState(250)
    state.Press(100)
    Assert(state.Reset(), "reset must report an active held state")
    Assert(!state.IsHeld && !state.WasUsed && state.DownAt = 0, "reset must clear state")
    passed += 1

    FileAppend("CapsLockCtrlEscape self-test: " passed " passed`n", "*")
}

Assert(condition, message) {
    if (!condition)
        throw Error("Self-test failed: " message)
}
