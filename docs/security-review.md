# Publication security review — scoped, not a full audit

This document records source-publication work on the 0.6.2 edition. It does not certify the application safe for broad privileged deployment.

## Completed preparation

- Exported source/tests/generic tools only; excluded personal deployment/handoff records, full historical verification logs, old archives and Git history.
- Replaced the personal namespace with `local.insomnia`, including the public Keychain service, logger and optional LaunchAgent identity. No automatic migration or login-item change is performed.
- Removed automatic menu-bar/screen diagnostic output from startup.
- Made root acknowledgement creation descriptor-relative and exclusive. The helper pins a private, non-root-owned directory, rejects a final directory symlink, uses `openat` with `O_CREAT | O_EXCL | O_NOFOLLOW`, and never overwrites an existing `ready` entry.
- Added non-root temporary-file tests for normal creation, pre-existing file refusal, final symlink refusal, directory symlink refusal, and the private-directory requirement.
- Kept CI/build/checks off privileged power, networking, saved-credential and login-item paths.

The acknowledgement change reduces the risk of privileged pathname replacement. It does not redesign all filesystem or authorization boundaries of the helper.

## Remaining privileged design limits

The Guardian is launched from a user-managed app bundle through an administrator-authorized AppleScript shell call. It is not an authenticated, separately installed SMAppService privileged daemon with a signed-client protocol. A user-writable bundle is not a security boundary against another process with the same user’s file access. Do not treat this architecture as production privilege separation.

The helper reads a GUI-controlled lease and checks a numeric parent PID. It does not cryptographically authenticate a specific GUI executable or prevent every PID-reuse/configuration race. The user directory remains controlled by its owner. A malicious process already acting as that user can interfere with the session; the app does not promise protection against a compromised user session.

`disablesleep` is global. Another utility can modify it during a session, and a restore can interfere with a later writer. A force-killed helper or machine failure cannot reliably execute cleanup. Normal operation and offline tests do not establish an unconditional recovery guarantee.

The new acknowledgement tests run without root. Privileged race stress tests, adversarial filesystem tests with a real root helper, signed-helper validation, crash/reboot recovery and a broad hardware matrix were not executed during this preparation.

## Before a wider binary release

A maintainer should review the privilege architecture, adopt an appropriately authenticated signed-helper model, verify release signing/notarization, and run a controlled real-device recovery matrix. Keep the source release labeled experimental until that work has been assessed.

Report sensitive findings privately using the project’s [security policy](../SECURITY.md). Do not upload Wi-Fi passwords or raw diagnostic exports to public issues.
