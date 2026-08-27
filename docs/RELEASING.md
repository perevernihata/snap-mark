# Releasing

## Version and notes

1. Update `CFBundleShortVersionString` and `CFBundleVersion` in `Packaging/Info.plist`.
2. Move the release notes from `Unreleased` into a dated section in `CHANGELOG.md`.
3. Run the complete local gate:

   ```sh
   make check
   make test
   make package
   make verify-package
   ```

4. Merge the release commit to protected `main`. Tag the current `main` tip as `vMAJOR.MINOR.PATCH` and push the tag.

The Release workflow refuses any tag that is not the current protected `main` tip or does not match the bundle version. A read-only job builds and verifies the universal package. A separate no-checkout job rechecks the immutable workflow artifact and creates a Sigstore-backed GitHub provenance attestation. Only then can the manually approved `release` environment give a final no-checkout job `contents: write` long enough to publish `SnapMark.zip` and `SnapMark.zip.sha256`.

All workflow actions are pinned to full commit SHAs and updated by Dependabot. Repository policy rejects unpinned actions, write-by-default workflow tokens, unapproved external pull-request workflows, mutable version tags, and releases without environment approval.

Verify a published archive with both controls:

```sh
shasum -a 256 -c SnapMark.zip.sha256
gh attestation verify SnapMark.zip \
  --repo perevernihata/snap-mark \
  --signer-workflow perevernihata/snap-mark/.github/workflows/release.yml
```

## Signing

The public workflow uses an explicit ad-hoc signature with the hardened runtime because repository secrets do not contain an Apple certificate. It never pretends that build is notarized. Users can inspect the source, verify the checksum and provenance, and build locally.

Maintainers can create a stable local package with:

```sh
SNAPMARK_UNIVERSAL=1 make app
```

`scripts/build-app.sh` first uses `SNAPMARK_SIGNING_IDENTITY` when set. Otherwise it looks for the persistent local signer and certificate under `~/Library/Application Support/SnapMark`. It refuses an accidental ad-hoc fallback because that would change the designated requirement and invalidate an existing Screen Recording grant.

A broadly distributed binary should use a Developer ID Application certificate, hardened runtime, Apple notarization, and a stapled ticket. Keep the certificate, password, App Store Connect key, and notary profile outside Git. Do not publish a release as notarized until `spctl --assess --type execute` and `xcrun stapler validate` both pass on the final app bundle.
