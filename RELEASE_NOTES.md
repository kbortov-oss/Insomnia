# Insomnia v0.6.2 — draft experimental prerelease

Native macOS menu-bar source prototype for temporary closed-lid sessions, separate Server/Travel timers, a Guardian watchdog and optional iPhone hotspot recovery.

## Important scope

Active modes request administrator authorization and change a global sleep setting. Read recovery instructions and the security review before running the app. This is not a broadly audited privileged utility; do not market it as an unconditional keep-awake or recovery guarantee.

The public edition uses `local.insomnia` and does not migrate private-edition settings or passwords. Do not run both editions together. It is unrelated to the Insomnia API client.

## Publication changes

Sanitized source export, no personal/historical logs, neutral identifiers, no automatic screen diagnostic, exclusive acknowledgement-file creation with regression checks, MIT license, documentation and CI.

## Validation and distribution

Offline checks and a local arm64 build are recorded in `docs/validation.md`. They do not include a new real-root closed-lid/reboot/hotspot matrix. The preview bundle targets Apple Silicon and macOS 13+ and is ad-hoc signed, not Developer ID signed or notarized. Hosted CI is prepared but not yet run.

## Assets after maintainer review

- `Insomnia-v0.6.2-source.zip`
- Optional `Insomnia-v0.6.2-macOS-arm64-preview.zip` and matching `.sha256`

Keep this a draft prerelease until the maintainer reviews the source, disclosures, signing decision and hardware-test limits. No GitHub publication is performed by the packaging scripts.
