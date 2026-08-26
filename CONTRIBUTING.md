# Contributing

Thanks for improving SnapMark. Small, testable changes are easiest to review.

## Before you start

- Search the issue tracker before opening a duplicate report.
- Open an issue before a large feature or architectural change.
- Never attach a private screenshot without redacting it first.
- Report security problems through GitHub's private vulnerability reporting page, not a public issue.

## Development setup

You need macOS 14 or later and Swift 6 from Xcode or Apple Command Line Tools.

```sh
git clone https://github.com/perevernihata/snap-mark.git
cd snap-mark
make check
make test
```

`make test` builds with warnings treated as errors and runs SnapMark's self-test executable. The suite covers capture geometry, multi-display overlay lifecycle, every editor tool, privacy edit flattening, history, timeout handling, process locking, and export.

To create a universal package for local testing:

```sh
make package
make verify-package
```

`make package` uses an explicit ad-hoc signature. macOS may treat each rebuild as a new Screen Recording app. Maintainers with the stable local signing files use `make app` so permission survives rebuilds. Signing credentials live outside the repository and must never be committed.

## Pull requests

1. Keep the change focused.
2. Add a regression test for a bug when the existing test seam can reproduce it.
3. Run `make check` and `make test`.
4. Test UI or capture changes in the installed app, not only the self-test executable.
5. Update `CHANGELOG.md`, the README, or privacy documentation when behavior changes.

By contributing, you agree that your contribution is licensed under the MIT License.
