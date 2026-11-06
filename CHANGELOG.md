# Changelog

## 0.6.2 — source-publication preview, 2026-11-06

Based on private 0.6.1 source. This is a separate public edition, not an automatic upgrade of a private installation.

- Exported source/tests/generic tools without personal notes, historical JSONL recordings, old bundles or private Git history.
- Neutral `local.insomnia` namespace for bundle, Keychain, logging and optional LaunchAgent.
- Removed automatic menu-bar/display diagnostic output on startup.
- Hardened root acknowledgement creation using a pinned private directory and exclusive, non-following file creation; added offline regression checks.
- Separated offline checks, arm64 build and preview packaging. No GUI launch or privileged session is part of those steps.
- Added MIT, bilingual README, setup/recovery/privacy/security documentation, project story, CI, issue/PR templates and source audit.

The three-mode behavior, timers, watchdog, display countdown and hotspot policy derive from 0.6.1. Their broad hardware compatibility and real privileged crash recovery are not newly established by this release.
