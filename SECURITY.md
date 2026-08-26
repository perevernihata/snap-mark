# Security policy

## Supported versions

Security fixes target the latest published SnapMark release and the `main` branch.

## Reporting a vulnerability

Use [GitHub private vulnerability reporting](https://github.com/perevernihata/snap-mark/security/advisories/new). Do not open a public issue for a vulnerability, leaked capture, signing credential, or path that exposes private information.

Include the affected version, macOS version, reproduction steps, impact, and a minimal redacted proof when possible. Do not send real credentials or an unredacted private screenshot.

## Security boundaries

- SnapMark processes screenshots locally and has no analytics, account, cloud upload, or network client.
- Screen Recording permission is required for capture. Accessibility permission is not required.
- Pixelate and blackout edits are flattened into copied and saved output.
- Raw captures may remain in local Recent history. Disable history before capturing sensitive information or remove the original from SnapMark's capture folder.
- Signing certificates, passwords, notarization keys, and provisioning files are excluded from source control.
