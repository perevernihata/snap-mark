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

4. Tag the exact release commit as `vMAJOR.MINOR.PATCH` and push the tag.

The Release workflow checks that the tag matches the bundle version, rebuilds a universal package, verifies it, and publishes `SnapMark.zip` with `SnapMark.zip.sha256`.

## Signing

The public workflow uses an explicit ad-hoc signature because repository secrets do not contain an Apple certificate. It never pretends that build is notarized. Users can inspect the source, verify the checksum, and build locally.

Maintainers can create a stable local package with:

```sh
SNAPMARK_UNIVERSAL=1 make app
```

`scripts/build-app.sh` first uses `SNAPMARK_SIGNING_IDENTITY` when set. Otherwise it looks for the persistent local signer and certificate under `~/Library/Application Support/SnapMark`. It refuses an accidental ad-hoc fallback because that would change the designated requirement and invalidate an existing Screen Recording grant.

A broadly distributed binary should use a Developer ID Application certificate, hardened runtime, Apple notarization, and a stapled ticket. Keep the certificate, password, App Store Connect key, and notary profile outside Git. Do not publish a release as notarized until `spctl --assess --type execute` and `xcrun stapler validate` both pass on the final app bundle.
