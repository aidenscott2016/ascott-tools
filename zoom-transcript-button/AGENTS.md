# AGENTS.md

This file tells coding agents how to build, install, run, and verify the Zoom transcript autosave tool on macOS.

## Project Layout

- Main package directory: `zoom-transcript-button/`
- Executable target: `zoom-transcript-save`
- LaunchAgent plist template: `zoom-transcript-button/com.user.zoomtranscript.plist`
- Main source file: `zoom-transcript-button/Sources/zoom-transcript-save/main.swift`

## What This Tool Does

`zoom-transcript-save` monitors Zoom meetings and clicks **Save transcript** on an interval.

- Event-driven meeting detection (`NSWorkspace` + `AXObserver`)
- Autosave timer (default 10 seconds)
- Automatic transcript panel reopen if user closes it
- macOS unified logging (`OSLog`) with subsystem `com.user.zoomtranscript`

## Prerequisites

- macOS 13+
- Zoom installed (`us.zoom.xos`)
- Xcode command line tools (`swift` available)
- Accessibility permission for the final executable path

## Build

Always clean before building. The module cache encodes the build path; if the repo has moved or was previously built from a different location (e.g., a worktree), a dirty build will fail with a PCH module cache error.

Run from repo root:

```bash
cd zoom-transcript-button
swift package clean && swift build -c release
```

Expected binary path:

`zoom-transcript-button/.build/release/zoom-transcript-save`

## Local Manual Run

```bash
cd zoom-transcript-button
.build/release/zoom-transcript-save --debug
```

One-shot validation:

```bash
cd zoom-transcript-button
.build/release/zoom-transcript-save --test --debug
```

## Install as LaunchAgent

### 1) Update plist binary path

The plist contains a hardcoded absolute path. Update it to the current machine's binary path before installing. Run from repo root:

```bash
BINARY="$(pwd)/zoom-transcript-button/.build/release/zoom-transcript-save"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $BINARY" zoom-transcript-button/com.user.zoomtranscript.plist
```

Do not assume the existing value in the plist is correct — it may reference a previous workspace or worktree.

### 2) Grant Accessibility permission

macOS Accessibility permission is tied to the exact binary path. The only reliable way to grant it is to **run the binary directly** to trigger the native TCC dialog:

```bash
zoom-transcript-button/.build/release/zoom-transcript-save --debug
```

Wait for the permission dialog, click **Allow**, then stop with `Ctrl+C`. Do not skip this step — the LaunchAgent running without direct invocation will not prompt for permission and will loop with a warning instead.

If the binary path changes (repo moved, new worktree, rebuild to different location), the permission must be re-granted.

### 3) Install and load

```bash
cp zoom-transcript-button/com.user.zoomtranscript.plist ~/Library/LaunchAgents/com.user.zoomtranscript.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist
```

### 4) Verify

```bash
launchctl list | rg "com.user.zoomtranscript"
```

A running agent shows a numeric PID in the first column (not `-`). Then confirm the permission was accepted:

```bash
/usr/bin/log show --predicate 'subsystem == "com.user.zoomtranscript"' --last 1m --info
```

Look for `Permission OK, monitoring for meetings...`. If you see `WARNING: Waiting for Accessibility permission` instead, re-run step 2 and restart the agent.

## Logs and Diagnostics

Always use `/usr/bin/log` explicitly — the bare `log` command can be shadowed by shell aliases and will fail with a misleading "too many arguments" error.

```bash
/usr/bin/log stream --level info --predicate 'subsystem == "com.user.zoomtranscript"'
/usr/bin/log stream --level debug --predicate 'subsystem == "com.user.zoomtranscript"'
/usr/bin/log show --predicate 'subsystem == "com.user.zoomtranscript"' --last 1h --info
```

## Acceptance Test Flow (Agent)

1. Clean and build release binary (`swift package clean && swift build -c release`).
2. Update plist path with `PlistBuddy`.
3. Run binary directly to trigger Accessibility permission dialog; confirm user clicks Allow.
4. Install LaunchAgent (bootout + bootstrap).
5. Confirm `launchctl list` shows a numeric PID for `com.user.zoomtranscript`.
6. Confirm logs show `Permission OK, monitoring for meetings...`.
7. If user is in a Zoom meeting: confirm logs show `Waiting for Zoom meeting window...` transitions to save ticks.

## Uninstall / Disable

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.user.zoomtranscript.plist
```

## Agent Guardrails

- Do not edit files outside this repository unless explicitly requested.
- Do not assume plist binary paths are portable across machines — always update before installing.
- Always use `swift package clean` before `swift build -c release` to avoid module cache errors.
- Grant Accessibility by running the binary directly, never by assuming the System Settings file picker will work.
- Use `/usr/bin/log` explicitly, never bare `log`, to avoid shell alias conflicts.
- Always rebuild after source edits before installation steps.
- Prefer unified logs over ad hoc log files.
- If testing fails, capture runtime evidence first (build output + `log show`) before making changes.
