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

```bash
cd zoom-transcript-button
swift build -c release
```

Binary output:

`./.build/release/zoom-transcript-save`

## Quick Start

### 1) Grant Accessibility Permission

Open `System Settings -> Privacy & Security -> Accessibility`.

Add:

`./.build/release/zoom-transcript-save`

Only Accessibility permission is required.

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

### 1) Set the Binary Path in the plist

Edit `com.user.zoomtranscript.plist` and ensure `ProgramArguments[0]` is the absolute path to your built binary.

### 2) Install and Load

```bash
cp com.user.zoomtranscript.plist ~/Library/LaunchAgents/com.user.zoomtranscript.plist
launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist 2>/dev/null || true
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.zoomtranscript.plist
```

### 3) Verify

```bash
launchctl list | rg "com.user.zoomtranscript"
```

### 4) Manage

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

Unified logs:

```bash
log stream --level info --predicate 'subsystem == "com.user.zoomtranscript"'
log stream --level debug --predicate 'subsystem == "com.user.zoomtranscript"'
log show --predicate 'subsystem == "com.user.zoomtranscript"' --last 1h
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
