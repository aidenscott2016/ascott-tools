# Zoom Transcript Auto-Save

Automatically clicks Zoom's **Save transcript** button during meetings and keeps saving at a fixed interval.

For agent-specific operating instructions, see `AGENTS.md` in this directory.

## What It Does

1. Detects Zoom launch/quit events.
2. Detects meeting window start/end events.
3. Opens the transcript panel when a meeting starts.
4. Re-opens the panel if it gets closed during a meeting.
5. Clicks **Save transcript** every `N` seconds (default: `10`).

## Requirements

- macOS 13+
- Zoom desktop app (`us.zoom.xos`)
- Live transcript available in the meeting
- Accessibility permission for the exact `zoom-transcript-save` binary path

## Build

Always clean first to avoid stale module cache errors (especially after moving or cloning the repo):

```bash
cd zoom-transcript-button
swift package clean && swift build -c release
```

Binary output:

`./.build/release/zoom-transcript-save`

## Quick Start

### 1) Grant Accessibility Permission

macOS will not show the binary in the System Settings file picker reliably. The correct approach is to **run the binary directly** — this triggers the native permission dialog:

```bash
./.build/release/zoom-transcript-save --debug
```

Click **Allow** in the dialog that appears. Then stop the process (`Ctrl+C`).

> If no dialog appears, open System Settings → Privacy & Security → Accessibility, click `+`, and navigate to the binary manually.

### 2) Run a One-Shot Test

Join a Zoom meeting first, then run:

```bash
./.build/release/zoom-transcript-save --test --debug
```

Expected output includes:

```text
Zoom meeting detected
Transcript saved at ...
SUCCESS: Transcript saved!
```

### 3) Run Continuously

```bash
./.build/release/zoom-transcript-save --debug
```

Press `Ctrl+C` to stop.

## CLI Options

```bash
./.build/release/zoom-transcript-save --interval 10
./.build/release/zoom-transcript-save --debug
./.build/release/zoom-transcript-save --no-debug
./.build/release/zoom-transcript-save --test
./.build/release/zoom-transcript-save --help
```

- `--interval SECONDS`, `-i SECONDS`: save interval in seconds (default `10`)
- `--debug`, `-d`: also print logs to stdout for interactive runs
- `--no-debug`: disable stdout debug output
- `--test`, `-t`: run once and exit
- `--help`, `-h`: show help

## LaunchAgent (Auto-Start at Login)

**You can run the install commands below manually, but the easiest path is: ask your coding agent to install it for you.**

### 1) Update the Binary Path in the plist

The plist contains a hardcoded absolute path that must match the binary location on your machine. Run this from the repo root to update it in one step:

```bash
BINARY="$(pwd)/zoom-transcript-button/.build/release/zoom-transcript-save"
/usr/libexec/PlistBuddy -c "Set :ProgramArguments:0 $BINARY" zoom-transcript-button/com.user.zoomtranscript.plist
```

### 2) Grant Accessibility Permission

Run the binary directly to trigger the macOS permission dialog:

```bash
zoom-transcript-button/.build/release/zoom-transcript-save --debug
```

Click **Allow**, then stop with `Ctrl+C`.

### 3) Install and Load

```bash
cp zoom-transcript-button/com.user.zoomtranscript.plist ~/Library/LaunchAgents/com.user.zoomtranscript.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist
```

### 4) Verify

```bash
launchctl list | rg "com.user.zoomtranscript"
```

A running agent shows a PID in the first column. Confirm permission was accepted in the logs:

```bash
/usr/bin/log show --predicate 'subsystem == "com.user.zoomtranscript"' --last 1m --info
```

Look for `Permission OK, monitoring for meetings...`. If you still see the Accessibility warning, re-run step 2 and restart the agent.

### 5) Manage

```bash
# Restart
launchctl kickstart -k gui/$(id -u)/com.user.zoomtranscript

# Disable (keep plist installed)
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist

# Uninstall completely
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/com.user.zoomtranscript.plist
```

## Logs and Output

Transcript file location (written by Zoom):

`~/Documents/Zoom/[Meeting Name]/meeting_saved_closed_caption.txt`

Unified logs (use `/usr/bin/log` explicitly to avoid shell alias conflicts):

```bash
/usr/bin/log stream --level info --predicate 'subsystem == "com.user.zoomtranscript"'
/usr/bin/log stream --level debug --predicate 'subsystem == "com.user.zoomtranscript"'
/usr/bin/log show --predicate 'subsystem == "com.user.zoomtranscript"' --last 1h --info
```

## Troubleshooting

### No meeting detected

- Confirm Zoom is running and you are in an active meeting.
- Confirm the meeting window title appears as `Zoom Meeting`.
- Re-check Accessibility permission for the current binary path.

### Transcript panel does not open

- Ensure live transcript is enabled in Zoom.
- Host settings may prevent transcript access in some meetings.
- Keep the app running; it retries on subsequent save ticks.

### Save clicks fail early in meeting

- This can happen before transcript content is available.
- The app keeps retrying every interval and recovers automatically.

### LaunchAgent not running

- Verify plist binary path is absolute and correct.
- Re-run the `launchctl bootstrap` command.
- Check logs with the unified logging commands above.

### Accessibility warning keeps appearing in logs

The permission was not accepted. Run the binary directly in a terminal to trigger the native dialog, click Allow, then restart the LaunchAgent:

```bash
zoom-transcript-button/.build/release/zoom-transcript-save --debug
# Click Allow in the dialog, then Ctrl+C
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist
```

### Build fails with "PCH was compiled with module cache path" error

The module cache is stale from a previous build location. Clean and rebuild:

```bash
swift package clean && swift build -c release
```

## How It Works

The executable runs on a single `RunLoop` and uses event-driven APIs:

- `NSWorkspace` notifications for Zoom app launch/terminate
- `AXObserver` notifications for meeting window create/destroy
- `Timer` for periodic save ticks

High-level lifecycle:

```text
wait for Zoom -> attach AX observer -> wait for meeting window
-> open panel + start timer -> save every N seconds
-> meeting ends -> stop timer -> wait for next meeting
```

## Limitations

- macOS only
- Zoom UI structure/labels must remain compatible
- English Zoom labels are assumed for element matching
- Single instance expected (do not run multiple monitors at once)

## Privacy

- Uses macOS Accessibility APIs to click UI elements only
- Does not read transcript content
- Does not send network requests
- Transcript files remain in Zoom-managed local folders
