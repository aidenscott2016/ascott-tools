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

Run from repo root:

```bash
cd zoom-transcript-button
swift build -c release
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

### 1) Ensure plist ProgramArguments path is correct

Set `ProgramArguments[0]` in `zoom-transcript-button/com.user.zoomtranscript.plist` to the absolute path of the built binary on the target machine.

### 2) Install and load

```bash
cp zoom-transcript-button/com.user.zoomtranscript.plist ~/Library/LaunchAgents/com.user.zoomtranscript.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist
```

### 3) Verify

```bash
launchctl list | rg "com.user.zoomtranscript"
```

If loaded, it should appear with label `com.user.zoomtranscript`.

## Accessibility Permission

On first use, add the binary path to:

**System Settings -> Privacy & Security -> Accessibility**

If the binary path changes (new workspace/location), macOS may treat it as a different app and require re-approval.

## Logs and Diagnostics

Unified logging commands:

```bash
log stream --level info --predicate 'subsystem == "com.user.zoomtranscript"'
log stream --level debug --predicate 'subsystem == "com.user.zoomtranscript"'
log show --predicate 'subsystem == "com.user.zoomtranscript"' --last 1h
```

## Acceptance Test Flow (Agent)

1. Build release binary.
2. Run `--test --debug` while user is in a Zoom meeting.
3. Confirm output contains meeting detection and successful save.
4. Run continuous mode (`--debug`).
5. Ask user to close transcript panel once.
6. Confirm panel reopens and subsequent save succeeds.
7. Optionally install LaunchAgent and verify with `launchctl list`.

## Uninstall / Disable

```bash
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.user.zoomtranscript.plist
```

## Agent Guardrails

- Do not edit files outside this repository unless explicitly requested.
- Do not assume plist binary paths are portable across machines.
- Always rebuild after source edits before installation steps.
- Prefer unified logs over ad hoc log files.
- If testing fails, capture runtime evidence first (build output + `log stream`) before making changes.
