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

g_State := CapsCtrlState(250)
g_KeyMonitor := 0

if (A_Args.Length && A_Args[1] = "--self-test") {
    RunSelfTests()
    ExitApp 0
}

if (A_Args.Length && A_Args[1] = "--verify-hotkeys") {
    InstallRemap()
    FileAppend("CapsLockCtrlEscape hotkey verification: passed`n", "*")
    ExitApp 0
}

InstallRemap()

InstallRemap() {
    Hotkey("*CapsLock", CapsLockDown)
    Hotkey("*CapsLock Up", CapsLockUp)
    Hotkey("$Esc", ToggleCapsLock)
    Hotkey("~*LCtrl Up", PhysicalLCtrlUp)

    for keyName in [
        "~*LButton", "~*RButton", "~*MButton", "~*XButton1", "~*XButton2",
        "~*WheelUp", "~*WheelDown", "~*WheelLeft", "~*WheelRight"
    ]
        Hotkey(keyName, MarkPointerUse)

    OnExit(ReleaseRemappedCtrl)
}

CapsLockDown(*) {
    global g_State

    ; Ignore typematic/repeated down events so they cannot reset tap state.
    if (!g_State.Press(A_TickCount))
        return

    if (OtherPhysicalInputIsDown())
        g_State.MarkUsed()

    StartKeyMonitor()
    Send("{Blind}{LCtrl DownR}")
    SetTimer(RecoverLostCapsUp, 50)
}

CapsLockUp(*) {
    global g_State

    SetTimer(RecoverLostCapsUp, 0)
    StopKeyMonitor()
    result := g_State.Release(A_TickCount)
    if (!result.ReleaseCtrl)
        return

    ; Do not force a real left Ctrl logically up while it is physically held.
    if (!GetKeyState("LCtrl", "P"))
        Send("{Blind}{LCtrl Up}")

    if (result.SendEsc)
        SendTapEscape()
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
    g_KeyMonitor.Start()
}

StopKeyMonitor() {
    global g_KeyMonitor

    if (IsObject(g_KeyMonitor) && g_KeyMonitor.InProgress)
        g_KeyMonitor.Stop()
    g_KeyMonitor := 0
}

MarkKeyboardUse(*) {
    global g_State
    g_State.MarkUsed()
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
    if (GetKeyState("CapsLock", "P"))
        Send("{Blind}{LCtrl DownR}")
    else
        CapsLockUp()
}

RecoverLostCapsUp() {
    global g_State

    if (g_State.IsHeld && !GetKeyState("CapsLock", "P"))
        CapsLockUp()
}

OtherPhysicalInputIsDown() {
    return AnyOtherVirtualKeyIsDown(
        vk => GetKeyState(Format("vk{:02X}", vk), "P")
    )
}

AnyOtherVirtualKeyIsDown(isDown) {
    Loop 254 {
        vk := A_Index
        if (vk = 0x14) ; CapsLock
            continue
        if (isDown.Call(vk))
            return true
    }
    return false
}

ToggleCapsLock(*) {
    SetCapsLockState(!GetKeyState("CapsLock", "T"))
}

ReleaseRemappedCtrl(*) {
    global g_State

    SetTimer(RecoverLostCapsUp, 0)
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

    Assert(AnyOtherVirtualKeyIsDown(vk => vk = 0x41), "pre-held ordinary key must count as other input")
    passed += 1

    Assert(!AnyOtherVirtualKeyIsDown(vk => vk = 0x14), "CapsLock itself must be excluded from overlap detection")
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
