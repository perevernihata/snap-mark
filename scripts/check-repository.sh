#!/bin/zsh

set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
cd "$PROJECT_DIR"

git diff --check -- .
/usr/bin/plutil -lint Packaging/Info.plist Packaging/PrivacyInfo.xcprivacy
zsh -n scripts/*.sh
swift package dump-package >/dev/null

typeset -a CANDIDATES
CANDIDATES=("${(@f)$(git ls-files --cached --others --exclude-standard)}")

typeset -a PROHIBITED
for path in "${CANDIDATES[@]}"; do
    if [[ "$path" == ".DS_Store" || "$path" == */.DS_Store ||
          "$path" == dist/* ||
          "$path" == *.p12 || "$path" == *.p8 || "$path" == *.cer ||
          "$path" == *.crt || "$path" == *.key || "$path" == *.mobileprovision ||
          "$path" == ".env" || "$path" == .env.* ]]; then
        PROHIBITED+=("$path")
    fi
done

if (( ${#PROHIBITED[@]} > 0 )); then
    print -u2 "Refusing repository files that can contain build output or credentials:"
    print -u2 -l -- "${PROHIBITED[@]}"
    exit 1
fi

SECRET_PATTERN='(gh[pousr]_[A-Za-z0-9_]{20,}|sk-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----)'
FOUND_SECRET=0
for path in "${CANDIDATES[@]}"; do
    [[ "$path" == "scripts/check-repository.sh" || ! -f "$path" ]] && continue
    if MATCHES="$(LC_ALL=C /usr/bin/grep -IEn "$SECRET_PATTERN" "$path")"; then
        print -u2 -- "$path:$MATCHES"
        FOUND_SECRET=1
    fi
done

if (( FOUND_SECRET != 0 )); then
    print -u2 "A repository file matches a credential pattern. Remove it before committing."
    exit 1
fi

UNPINNED_ACTIONS="$(
    /usr/bin/grep -RHE '^[[:space:]]*-?[[:space:]]*uses:[[:space:]]+' .github/workflows 2>/dev/null |
        /usr/bin/grep -Ev 'uses:[[:space:]]+((\./)|[^[:space:]#]+@[0-9a-f]{40})([[:space:]]+#.*)?$' || true
)"
if [[ -n "$UNPINNED_ACTIONS" ]]; then
    print -u2 "Every external GitHub Action must be pinned to a full commit SHA:"
    print -u2 -- "$UNPINNED_ACTIONS"
    exit 1
fi

UNSAFE_TRIGGERS="$(
    /usr/bin/grep -RHE '^[[:space:]]*(pull_request_target|workflow_run):' .github/workflows 2>/dev/null || true
)"
if [[ -n "$UNSAFE_TRIGGERS" ]]; then
    print -u2 "Privileged follow-up and pull-request-target workflows require a separate security review:"
    print -u2 -- "$UNSAFE_TRIGGERS"
    exit 1
fi

PERSISTED_CREDENTIALS="$(
    /usr/bin/grep -RHE '^[[:space:]]*persist-credentials:[[:space:]]*true([[:space:]]*#.*)?$' .github/workflows 2>/dev/null || true
)"
if [[ -n "$PERSISTED_CREDENTIALS" ]]; then
    print -u2 "Workflow checkouts must not persist repository credentials:"
    print -u2 -- "$PERSISTED_CREDENTIALS"
    exit 1
fi

if /usr/bin/grep -q 'gh release create' .github/workflows/release.yml &&
   ! /usr/bin/grep -q -- '--repo "${GITHUB_REPOSITORY}"' .github/workflows/release.yml; then
    print -u2 "The checkout-free release publisher must pass an explicit repository to gh."
    exit 1
fi

print "Repository checks passed."
