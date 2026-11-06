# Security reporting

This is experimental privileged system software, with known architectural limitations documented in `docs/security-review.md`. There is no independent security certification or response SLA.

Do not publish Wi-Fi passwords, Keychain data, raw session/display logs, or unredacted settings in an issue. If GitHub private vulnerability reporting is enabled, use **Security → Report a vulnerability**. Otherwise request a private contact from the maintainer without posting sensitive details publicly. No private reporting email is configured in this source package.

Before opening a public repository to reports, enable an appropriate private reporting channel. A stuck sleep prohibition should first be handled using `docs/recovery.md`; reporting an issue is not a recovery action.

The source-publication scan checks selected patterns, not every possible secret or privilege bug. The prepared 0.6.2 branch contains a targeted acknowledgement-file hardening change but has not undergone a full adversarial audit or privileged race test.
