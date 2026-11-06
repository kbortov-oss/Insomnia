# Troubleshooting

## No main window

Insomnia is a menu-bar app. Find its icon in the macOS menu bar. The app starts in Normal mode; simply launching it does not start a privileged closed-lid session. Crowded menu bars can hide icons behind the notch.

## Server is unavailable

Server requires external power and valid battery/power information. Plug in power before selecting it. Unplugging ends Server; it does not silently switch to Travel.

## Mode ended unexpectedly

Check the reason in the app menu and whether the deadline, battery cutoff, AC power or heartbeat stopped the session. A transient sleep-state read is tolerated, but persistent unavailable state or an external reset ends the session. This is intentional fail-closed behavior, not automatic re-enabling of someone else’s power change.

## Ordinary sleep is still disabled

Read [recovery](recovery.md). Ending the GUI process alone is not proof that the global flag was cleared. A killed Guardian, reboot, failed system command or another utility may require explicit recovery. Do not start another active session over an unconfirmed global state.

## iPhone hotspot is not selected

Verify its exact SSID, password, visibility and Personal Hotspot setting yourself. A healthy wired route is preserved. Wi-Fi that you turned off is not re-enabled. Location permission is needed for SSID/association behavior; the app does not ask for geographic coordinates.

An already connected hotspot with unconfirmed internet is left connected while waiting for the connection to recover. A working route to probe endpoints does not prove every other service is reachable.

## Return to regular Wi-Fi did not complete

Only visible saved networks are candidates. Forgotten, unknown or corporate 802.1X networks are not automatically joined. A Keychain denial stops credential access. Timer/battery/power termination can restore sleep before the network-return attempt finishes, especially with the lid closed.

## Password or preferences disappeared after switching editions

The public source edition uses `local.insomnia` instead of a personal namespace. This intentionally separates its preferences, Keychain service and optional login-agent label. Configure the public edition explicitly; do not export Keychain data or copy personal preference files into the repository. Avoid duplicate active editions or duplicate autostart mechanisms.

## macOS blocks the preview

The generated bundle is ad-hoc signed and not notarized. Build from reviewed source or follow Apple’s documented local-app approval flow only if you trust it. The project does not disable Gatekeeper or strip quarantine. Before granting administrator access, read the helper design limitations.
