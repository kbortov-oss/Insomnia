# Local validation — 2026-11-06

This report is for the prepared 0.6.2 public source edition. It does not import private historical hardware logs as evidence for the new build.

| Check | Local result |
| --- | --- |
| Pure network policy tests | Passed |
| Session/deadline/power/watchdog policy tests | Passed |
| Mock restoration and child-command timeout checks | Passed |
| Display-delay policy tests | Passed on synthetic states |
| Exclusive acknowledgement and symlink/refusal tests | Passed as an ordinary user in temporary directories |
| Guardian `--self-test` | Passed; returns before root-only code |
| Full arm64 GUI and Guardian build | Passed |
| Ad-hoc bundle and helper signatures | Verified |
| Preview zip and SHA-256 file | Created |
| Python helper syntax and `--help` | Passed; no agent installation or recorder execution |
| Binary scan for personal home path / old private namespace | No matches in the two app executables |
| Source selected-pattern scan | Passed |
| Source archive boundaries, Markdown links and SVG XML | Verified |
| Audit refusal fixtures (raw log, settings, signing material, synthetic token) | Rejected without printing file contents |
| Offline checks and arm64 release build from a natively extracted source archive in a path containing spaces | Passed |
| Live administrator authorization, `pmset` changes, lid closure and actual Wi-Fi tests | Not performed during publication preparation |
| GitHub-hosted CI | Prepared, not run |
| Developer ID signing and notarization | Not performed |
| Full privileged adversarial audit / root race stress test | Not performed |

The local toolchain is Apple Swift 6.2.3 on arm64. Tests use synthetic state and local temporary files. They do not access stored passwords, associate with Wi-Fi, install/remove login items, launch the GUI, or change global power settings.

Older private hardware notes and raw display/network recordings are not included in the public repository or source archive. Compatibility and recovery on another Mac/OS remain explicit manual work.
