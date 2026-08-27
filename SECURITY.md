# Security policy

## Supported versions

Security fixes target the latest published SnapMark release and the `main` branch.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/perevernihata/snap-mark/security/advisories/new). Do not open a public issue for a vulnerability, leaked capture, signing credential, or path that exposes private information.

Include the affected version, macOS version, reproduction steps, impact, and a minimal redacted proof when possible. Do not send real credentials or an unredacted private screenshot.

## What SnapMark protects

- SnapMark processes screenshots locally. It has no account, analytics, cloud upload, network client, or third-party runtime dependency.
- Screen Recording is its only privacy-sensitive permission. Accessibility permission is not required.
- Temporary capture directories are created owner-only and removed after decoding.
- Recent history is stored under `~/Library/Application Support/SnapMark/Captures`. The directory is mode `0700`, saved PNGs are mode `0600`, and older PNGs are normalized when loaded.
- Blackout replaces the selected pixels in copied, saved, and shared output. Privacy edits run last during rendering so another annotation cannot reveal pixels beneath a blackout.
- Release workflows use least-privilege jobs, full-SHA action pins, a protected-main check, provenance attestation, and a manually approved publish environment. The job that runs repository code has no write token, and the job that publishes does not check out or execute repository code.
- Signing certificates, passwords, notarization keys, and provisioning files are excluded from source control. Public CI has no Apple signing secret.

## Boundaries and residual risks

- Pixelation is visual obfuscation, not reliable secret redaction. Use Blackout for credentials, personal information, or anything that must be removed.
- Edits are non-destructive in the editor. A raw Recent capture retains every original pixel even when the export is blacked out. Disable history before sensitive work or remove the raw capture afterward.
- Mode `0700`/`0600` prevents access by other local user accounts, not by malware or another application already running as the same macOS user. FileVault and a well-maintained macOS installation remain important.
- Copy places a PNG on the general macOS pasteboard, which may participate in Universal Clipboard. Save writes to the location the user chooses. Share hands the rendered image to the selected macOS sharing service. Those destinations are outside SnapMark's control.
- GitHub checksums detect accidental or post-download changes but are served beside the archive. Provenance verification additionally proves that GitHub Actions produced the archive for this repository. Neither control can make a compromised maintainer account or GitHub platform impossible; the maintainer account still needs strong phishing-resistant MFA and tightly scoped credentials.
- Community releases are ad-hoc signed and are not Apple-notarized. Hardened runtime is enabled, but users should verify provenance or build from source. A future Developer ID release must be notarized and stapled before it is described as such.

## Verifying a release

Download `SnapMark.zip` and `SnapMark.zip.sha256` from the same release, then run:

```sh
shasum -a 256 -c SnapMark.zip.sha256
gh attestation verify SnapMark.zip \
  --repo perevernihata/snap-mark \
  --signer-workflow perevernihata/snap-mark/.github/workflows/release.yml
```

The attestation command applies to releases published after provenance was enabled. Inspect the verified workflow identity and commit before opening the app.
