# Publish Insomnia source to GitHub

No remote repository, push, tag or GitHub release is created by preparation scripts. This is a separate sanitized copy, not the private project directory or its Git history.

## Source boundary

Upload only this source root. Do not upload the surrounding chat workspace, older project exports, `verification/`, session logs, SSIDs, passwords, preferences, display recordings or personal deployment notes. Include hidden `.github/`, `.gitignore` and `.gitattributes` files.

The MIT notice uses `Insomnia contributors`. If a specific copyright-holder name is desired, edit the notice before the first public commit. The neutral bundle/Keychain namespace does not migrate private-edition data. There is no Git author identity or remote URL baked into the source archive.

## Review locally

```sh
python3 scripts/audit-source.py
./scripts/check.sh
./scripts/build.sh
```

Review [security findings](security-review.md), [privacy](privacy.md), [recovery](recovery.md), and [actual validation](validation.md). Source-pattern scanning is limited; manually inspect any new files and existing Git history before a push. The prepared source starts without private history.

## First commit and remote

If the folder is not initialized, run `git init -b main`. Then:

```sh
git status --short
git add .
git diff --cached --stat
git diff --cached
git commit -m "Prepare Insomnia experimental source release"
```

Choose a Git author name/email you are comfortable making public; preparation does not set or overwrite your identity.

Create an empty GitHub repository with the intended visibility. A descriptive name such as `insomnia-macos` helps distinguish this utility from the unrelated Insomnia API client. Copy your actual remote URL:

```sh
git remote add origin YOUR_GITHUB_REMOTE_URL
git push -u origin main
```

Do not use the placeholder literally. Suggested description:

> Experimental macOS menu-bar utility for temporary closed-lid sessions and iPhone hotspot recovery. Swift/AppKit with an on-demand Guardian.

Suggested topics: `macos`, `swift`, `appkit`, `menu-bar`, `power-management`, `iphone-hotspot`.

After upload, check the hosted CI result and rendered docs. Enable private vulnerability reporting or set a monitored private security contact before inviting security reports. There is no automatic publishing workflow.

## Preview release assets

```sh
./scripts/check.sh
./scripts/release.sh
python3 scripts/package-source.py
```

Output is an explicitly named `Insomnia-vVERSION-macOS-arm64-preview.zip`, its `.sha256`, and a source archive. Source packaging includes the MIT notice and hidden GitHub files but excludes Git history, local runtime and generated bundles.

If preparing a GitHub release, use a **draft prerelease** and [RELEASE_NOTES.md](../RELEASE_NOTES.md). Clearly state the global sleep change, experimental root helper, unverified hardware matrix, ad-hoc signing and lack of notarization. Review that concrete draft before publication.

Opening the reviewed source is distinct from presenting a privileged binary as broadly safe to install. The current security review leaves explicit architecture work before a wider binary release. No Apple credentials, signing keys or GitHub publishing secrets are required in this repository.
