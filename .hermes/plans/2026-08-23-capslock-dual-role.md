# Caps Lock dual-role hardening plan

1. **RED, AC-014:** Add a command-line test that runs the real script with `--self-test`; confirm the current script fails by remaining resident.
2. **GREEN, AC-001 to AC-006:** Add a pure state object and built-in self-tests covering tap, hold, chord use, repeated down, and tick rollover.
3. **GREEN, AC-007 to AC-013:** Replace static/manual key handlers with one Win32 async-state-polled Caps Lock gesture, an all-key visible InputHook, mouse-use handlers, remap-grade left Ctrl, and exit cleanup.
4. **VERIFY, AC-014:** Run the command-line test and a clean AHK self-test.
5. **DEPLOY, AC-015:** Copy the verified source to Startup, restart it, compare hashes, and verify the live command line.
6. **REVIEW:** Stage explicit paths, verify the exact staged snapshot, obtain independent read-only review, then commit the coherent change.

Risks and mitigations:

- Tests must not inject keys into the active app. Self-test mode exits before hotkey installation and tests only pure transitions.
- A failed candidate must not replace the working Startup script. Deploy only after the tracked source passes.
- Existing untracked repository content is unrelated. Leave it untouched and never stage it.
