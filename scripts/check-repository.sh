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

print "Repository checks passed."
