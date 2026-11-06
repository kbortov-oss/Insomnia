# Development and offline checks

## Toolchain

The application targets arm64 and macOS 13. Source is compiled with Apple `swiftc` in Swift 5 language mode; the local preparation uses Swift 6.2.3. There is no Swift Package Manager dependency graph or third-party Swift library. Frameworks include AppKit, IOKit, ServiceManagement, CoreWLAN, CoreLocation, Network and Security.

```sh
python3 scripts/audit-source.py
./scripts/check.sh
./scripts/build.sh
```

Build output/cache goes to ignored `.build/`; app and release output goes to ignored `dist/`. `INSOMNIA_BUILD_DIR` and `INSOMNIA_OUTPUT_DIR` can override those paths. Relative paths resolve from the project root, and scripts work from another current directory or a checkout path containing spaces. No `HOME` override is needed.

`VERSION` controls bundle/archive version. Human-readable about text and connectivity user-agent are source constants; update them deliberately when advancing the version.

## Test suites

- `NetworkPolicyTests`: working wired-route preservation, iPhone preference, hotspot outage handling, permission/Wi-Fi-off handling, bounded retry backoff and saved-network return ordering.
- `SessionPolicyTests`: deadline and live timer replacement, stale/corrupt lease, AC-only Server, Travel cutoff, missing power data, external flag changes, bounded restore behavior, command output and timeout, and display countdown rules.
- `ReadyAcknowledgementTests`: exclusive creation and refusal of existing/symlink/public-directory paths in normal-user temporary fixtures.
- Guardian `--self-test`: pure stop-policy fixtures; it returns before root-only execution.

The check script compiles test executables for the current Mac host architecture. It does not invoke privileged sessions, real `pmset` changes, Wi-Fi association, Keychain reads or login-item changes. A brief ordinary `/bin/sleep` child and a printf fixture exercise command handling.

The app/packaged helper are always built for arm64. On an Intel CI host, host-native policy checks can still run, but the resulting app is a cross-compiled arm64 preview, not an Intel or universal release.

## Optional Python tools

`macos/autostart.py --help` and `macos/check_display.py --help` are safe syntax/help checks. Installing a LaunchAgent, recording hardware state or enabling a privileged session is a separate explicit manual task. Never add those operations to CI.

## CI and validation boundaries

GitHub CI uses `macos-latest`, read-only repository permissions and no credentials. It audits source, runs offline checks, builds the app and validates Python help/syntax. It does not open the application. The hosted workflow is prepared but has not run during local preparation.

The [validation report](validation.md) distinguishes current local checks from earlier private hardware notes. Those raw notes are intentionally not packaged. Passing policy tests is not a closed-lid, hotspot or privileged recovery verification on a real device.
