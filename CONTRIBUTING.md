# Contributing

Keep changes focused on the three modes, recovery behavior and explicit network policy. Read architecture, recovery and security-review documentation before modifying privileged code.

Use synthetic tests and temporary directories. Never add Wi-Fi passwords, personal SSIDs, raw JSONL recordings, Keychain exports, power-session files, signing credentials or private deployment notes.

Run `python3 scripts/audit-source.py`, `./scripts/check.sh` and `./scripts/build.sh`. A normal contribution must not require enabling a privileged session to run its unit checks. Hardware tests are separate, explicit and documented with their limits.

Changes to Guardian, filesystem access, AppleScript authorization, command execution, password handling or global restoration must describe the trust boundary, failure behavior and recovery path in the PR. Do not claim a pure policy test validates real lid, thermal or privileged crash behavior.

Contributions use the MIT license. This project has no CLA. The app UI is Russian; documentation includes an English entry point.
