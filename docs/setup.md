# Setup and permissions

## Prerequisites

The app bundle targets Apple Silicon and macOS 13+. Hardware/OS combinations can behave differently under closed-lid conditions. Read recovery and security limitations before an active test. Build and offline checks do not need administrator privileges or saved network credentials.

The source UI is Russian and lives entirely in the menu bar. There is no main window. On launch, Normal mode is selected; it does not automatically begin a privileged session.

## First launch

Build the app, place the copy you intend to use in a stable location, then launch it yourself. Avoid running an older private edition at the same time. The public bundle identifier and password service use the neutral `local.insomnia` namespace. Existing private preferences and credentials are not automatically migrated.

Start any hardware test with the lid open and external power connected. Prefer a short Server timer for an initial explicit test, followed by verification that the mode and global flag return to normal. Physical lid/display tests are separate from the offline test suite.

## Administrator authorization

Choosing Server or Travel asks macOS to authorize launching the bundled Guardian using AppleScript’s administrator-privileged shell flow. This is an on-demand root process, not an installed launch daemon or a modern authenticated SMAppService privileged helper. Inspect and trust the app before granting permission.

The app shell-quotes the helper path and arguments, then AppleScript-quotes the resulting command. A temporary per-session directory and lease carry heartbeat/deadline data. Guardian owns the active session’s display policy and attempts restoration on exit.

## Timers and power

Server requires external power and ends if it is disconnected. Travel can run from battery or power; its battery cutoff is ignored while externally powered. A missing battery/power reading ends an active session rather than treating it as permission to keep running.

Each active mode has independent saved duration. Presets and a custom duration of 1–10080 minutes are available, plus no deadline. The deadline begins after activation acknowledgement, not while the administrator prompt waits. Editing the active duration replaces its deadline from the time of the edit.

## iPhone connection

Set the exact hotspot SSID and password through the app, not a config file. The SSID is a local preference; the password is in a dedicated Keychain item. macOS can request Keychain access.

For Wi-Fi automation, macOS requires Location permission to access SSID information. The app requests authorization but does not ask CLLocationManager for coordinates. Without that permission, Wi-Fi association is unavailable while read-only connectivity checks and a working wired route can still be used.

Enable Personal Hotspot on the iPhone yourself. For USB, connect and complete Apple’s normal trust/connection setup yourself. The application cannot guarantee hotspot visibility, mobile coverage, carrier availability, or that another task resumes after the connection recovers.

Travel prefers the configured iPhone even over an otherwise working Wi-Fi network, but preserves a working wired route. It does not turn Wi-Fi back on after you have turned it off. A normal-mode change attempts return to visible saved networks; corporate 802.1X is not automatically handled.

## Login launch

Prefer the app’s **«Запускать при входе»** control, which uses `SMAppService.mainApp`. macOS may require approval in Login Items.

`macos/autostart.py` is an explicit alternative per-user LaunchAgent manager. It does nothing until invoked with a subcommand. Do not enable both mechanisms for the same app. Read `--help`, use `status` to inspect this script’s own agent, and use `uninstall` to remove only that agent. Repository preparation does not run install/uninstall or touch existing login items.

## Removal

First end the active session and verify restoration using [recovery](recovery.md). Then disable the login mechanism you used, quit the app, and remove its bundle. Removing a bundle during an active session is not a recovery method. The hotspot password and app data are separate; use the app’s forget-hotspot action or Keychain Access if you want to remove stored credentials.
