# Privacy and data handling

## Local preferences and credentials

The hotspot SSID, per-mode duration, battery threshold, recovery marker, and menu-bar placement are local preferences. SSIDs can reveal personal information and should not be posted in issues.

The configured hotspot password is stored in macOS Keychain using the public edition’s `local.insomnia.hotspot` service. It is held in memory while needed for an active Travel session or a return attempt. Saved regular-network passwords can be read through the system Keychain API when returning to known Wi-Fi, used in memory, and discarded with that operation. macOS may request permission; a denial stops the relevant operation.

No password is intentionally placed in UserDefaults, command arguments, network probes, or the application’s event log. Error logging in the network controller uses event names and numeric codes rather than arbitrary credential-bearing exception text.

## Location permission

CoreWLAN SSID access on modern macOS requires Location authorization. The source requests that authorization; it does not call for coordinates or start location tracking. The name and visibility of nearby Wi-Fi networks are still sensitive data used locally by the controller.

## Network requests

During active connectivity checks the app performs HTTPS GETs to:

- `https://www.apple.com/library/test/success.html`
- `https://cp.cloudflare.com/generate_204`

The session is ephemeral with no cookie store, URL credential store, or response cache. The probes do not attach Wi-Fi passwords, account tokens, documents, or messages. The remote services still receive ordinary request metadata such as source IP, request timing, TLS/network information, and an Insomnia user-agent. Redirects can be followed by URLSession, but a response is only counted as success if its final URL matches the expected probe address.

These checks confirm the selected resources are reachable, not that every AI service is available. The app does not resume or restart jobs in other applications.

## Local logs and temporary state

`~/Library/Application Support/Insomnia/network-events.jsonl` contains time, event names, selected actions, outage duration and numeric codes. The implementation intentionally avoids passwords and SSIDs in this log, but logs should still be reviewed before sharing. Rotation keeps roughly a 256 KB current file plus one previous file.

The public source does not perform the old automatic menu-bar diagnostic write. Session reason/power-command diagnostics may be emitted to the macOS unified log. A temporary `Insomnia-UUID` directory holds the lease and acknowledgement during an active session. Cleanup is attempted by the GUI; crashes can leave remnants.

`macos/check_display.py` is a manual read-only recorder. Its output includes timestamps, display identifiers, lid state, sleep flag, brightness-related registry information and possible local error details. It takes no screenshots, but output can still fingerprint a device. No recordings from a personal Mac are distributed in this repository.

## Public packaging

The public source starts from an allowlisted copy of source, tests and generic helper scripts. Private deployment notes, raw verification recordings, settings, logs, Keychain exports, older bundles and chat history are excluded. Source packaging omits Git history and generated output. The source audit checks selected accidental token/private-path/email patterns and refuses raw JSONL logs; it is not a proof against every possible secret or a full code-security audit.

This project has no project-owned telemetry server. Apple, Cloudflare, macOS services and Keychain retain their own independent behavior and policies.
