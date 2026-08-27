# GitHub CI/CD security hardening

Research date: 2026-08-27

This note covers the public `perevernihata/snap-mark` repository. It focuses on ways an untrusted pull request, a moved action tag, a compromised build step, or a person with ordinary write access could affect CI or publish a release. All external references point to GitHub's documentation, API documentation, CLI manual, or GitHub-owned action repositories.

No repository setting can make malicious publication impossible. A compromised repository administrator can change repository rules, workflows, and environments. The controls below remove the easy publication paths, keep write credentials away from code that builds the app, and make published artifacts verifiable. A second independent release reviewer is still needed for real two-person control.

## Baseline reviewed

The baseline was commit [`8b59bc9`](https://github.com/perevernihata/snap-mark/tree/8b59bc9c4488f418041b81d95150b9d4945f4148).

- [`ci.yml`](https://github.com/perevernihata/snap-mark/blob/8b59bc9c4488f418041b81d95150b9d4945f4148/.github/workflows/ci.yml) used mutable major-version action tags.
- [`release.yml`](https://github.com/perevernihata/snap-mark/blob/8b59bc9c4488f418041b81d95150b9d4945f4148/.github/workflows/release.yml) granted `contents: write` to its only job. That job checked out the repository with persisted credentials, installed Homebrew packages, and ran repository scripts before publishing.
- Read-only API checks returned `allowed_actions: all`, `sha_pinning_required: false`, default workflow permissions of `read`, pull-request approval disabled for Actions, fork approval for first-time contributors only, no environments, no tag rulesets, and immutable releases disabled. The relevant settings are exposed by GitHub's [Actions permissions API](https://docs.github.com/en/rest/actions/permissions?apiVersion=2026-03-10), [environment API](https://docs.github.com/en/rest/deployments/environments?apiVersion=2026-03-10), [ruleset API](https://docs.github.com/en/rest/repos/rules?apiVersion=2026-03-10), and [immutable releases API](https://docs.github.com/en/rest/repos/repos?apiVersion=2026-03-10#check-if-immutable-releases-are-enabled-for-a-repository).

The most serious baseline issue was the release job's credential boundary. `actions/checkout` persists its token by default so later Git commands can authenticate. Its own documentation says to set `persist-credentials: false` to opt out. With a workflow-wide write token, repository build scripts could use those credentials before the intended publish step. See the pinned [`actions/checkout` documentation](https://github.com/actions/checkout/blob/3d3c42e5aac5ba805825da76410c181273ba90b1/README.md#checkout-v4).

## Required control set

### Pin every action and enforce the policy

GitHub says a full-length commit SHA is the only immutable way to reference an action. A version tag can be moved after a workflow has been reviewed. GitHub also supports a repository policy that rejects action references that are not full SHAs. Dependabot can update SHA-pinned actions when the release comment stays on the same line. See GitHub's [secure use reference](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions) and [Dependabot notes for GitHub Actions](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories#github-actions).

These were the current first-party releases and their resolved commits on the research date:

| Workflow reference | Release | Full commit SHA |
| --- | --- | --- |
| `actions/checkout` | `v7.0.1` | [`3d3c42e5aac5ba805825da76410c181273ba90b1`](https://github.com/actions/checkout/commit/3d3c42e5aac5ba805825da76410c181273ba90b1) |
| `actions/upload-artifact` | `v7.0.1` | [`043fb46d1a93c77aae656e7c1c64a875d1fc6a0a`](https://github.com/actions/upload-artifact/commit/043fb46d1a93c77aae656e7c1c64a875d1fc6a0a) |
| `actions/download-artifact` | `v8.0.1` | [`3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c`](https://github.com/actions/download-artifact/commit/3e5f45b2cfb9172054b4087a40e8e0b5a5461e7c) |
| `actions/attest` | `v4.2.2` | [`1e69f48acb82d1966a394da916b4c1698aa569d6`](https://github.com/actions/attest/commit/1e69f48acb82d1966a394da916b4c1698aa569d6) |
| `github/codeql-action` | `v4.37.9` | [`cdf488f595d80d6e07e03d4674febd5ab45fa938`](https://github.com/github/codeql-action/commit/cdf488f595d80d6e07e03d4674febd5ab45fa938) |

Use a version comment so Dependabot can keep each pin current:

```yaml
- uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1
  with:
    persist-credentials: false
```

After every `uses:` entry has a full SHA, turn on the server-side check:

```sh
gh api --method PUT \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/actions/permissions \
  -F enabled=true \
  -f allowed_actions=selected \
  -F sha_pinning_required=true
```

The endpoint and fields are documented under [Set GitHub Actions permissions for a repository](https://docs.github.com/en/rest/actions/permissions?apiVersion=2026-03-10#set-github-actions-permissions-for-a-repository). The policy covers GitHub-authored actions too. GitHub's settings documentation notes that reusable workflows can still be referenced by tag, so any reusable workflow should also be reviewed and pinned by policy in code. See [Managing GitHub Actions settings](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#requiring-actions-to-be-pinned-to-a-full-length-commit-sha).

### Allow only GitHub-owned actions

This repository currently needs only actions owned by `actions` or `github`. Set selected actions to GitHub-owned, do not allow every verified publisher, and do not add wildcard exceptions:

```sh
printf '%s' '{"github_owned_allowed":true,"verified_allowed":false,"patterns_allowed":[]}' | \
  gh api --method PUT \
    -H "X-GitHub-Api-Version: 2026-03-10" \
    repos/perevernihata/snap-mark/actions/permissions/selected-actions \
    --input -
```

GitHub documents this payload in [Set allowed actions and reusable workflows for a repository](https://docs.github.com/en/rest/actions/permissions?apiVersion=2026-03-10#set-allowed-actions-and-reusable-workflows-for-a-repository). The endpoint returns `409` until `allowed_actions` is set to `selected`.

This policy filters `uses:` references. It does not freeze software fetched by a shell command. That follows from the API's stated scope, which is actions and reusable workflows. Do not run `brew install` or another mutable package installation in the release build. If a tool is needed only for CI linting, keep it in a read-only job with no secrets and never promote that job's package to a release.

### Keep the default token read-only

Set the repository default to read and keep Actions unable to create or approve pull requests:

```sh
gh api --method PUT \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/actions/permissions/workflow \
  -f default_workflow_permissions=read \
  -F can_approve_pull_request_reviews=false
```

GitHub recommends granting `GITHUB_TOKEN` only the access a job needs. Once any permission is declared, unspecified permissions become `none`. See [workflow permission syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#permissions) and [the repository workflow-permissions API](https://docs.github.com/en/rest/actions/permissions?apiVersion=2026-03-10#set-default-workflow-permissions-for-a-repository).

The repository default is a fallback, not a ceiling. A workflow file can request more access at job level. Branch protection, tag rules, and the release environment therefore matter as much as this setting.

### Require approval for every external fork

Use the strongest public-fork approval setting:

```sh
gh api --method PUT \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/actions/permissions/fork-pr-contributor-approval \
  -f approval_policy=all_external_contributors
```

GitHub warns that a contributor stops being treated as new after any commit or pull request is merged. `all_external_contributors` avoids that trust-on-first-merge gap. Public-fork workflows still receive a read-only token and no repository secrets. See [Managing GitHub Actions settings for public forks](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/enabling-features-for-your-repository/managing-github-actions-settings-for-a-repository#controlling-changes-from-forks-to-workflows-in-public-repositories) and the [fork approval API](https://docs.github.com/en/rest/actions/permissions?apiVersion=2026-03-10#set-fork-pr-contributor-approval-permissions-for-a-repository).

Keep using `pull_request`, not `pull_request_target`, for code from forks. GitHub warns that checking out untrusted pull-request code under `pull_request_target` or `workflow_run` can expose write access, secrets, privileged caches, or runner access. See the [secure use reference](https://docs.github.com/en/actions/reference/security/secure-use#mitigating-the-risks-of-untrusted-code-checkout).

### Split build, attestation, and publication

Use `permissions: {}` at workflow level, then grant each job only what it needs:

1. `build` gets `contents: read`. It checks out the exact tag commit with `persist-credentials: false`, verifies the tag points to the current protected `main` tip, checks the bundle version, runs tests, builds the ZIP, verifies it, and uploads it as a short-lived workflow artifact.
2. `attest` gets `contents: read`, `id-token: write`, and `attestations: write`. It does not check out the repository or execute the ZIP. It downloads the build artifact, validates the checksum and ZIP structure, and calls `actions/attest`.
3. `publish` gets only `contents: write`. It has `needs: [build, attest]`, targets the protected `release` environment, does not check out the repository, does not run project code, revalidates the payload, and creates the GitHub release.

GitHub creates a separate short-lived `GITHUB_TOKEN` for each job. Job-level permissions let the workflow isolate the write token from the compiler and project scripts. See [GITHUB_TOKEN](https://docs.github.com/en/actions/concepts/security/github_token) and [job-level permission syntax](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idpermissions).

`actions/upload-artifact` returns an artifact digest, and `actions/download-artifact` recalculates it during download. A mismatch is reported as a warning, so the workflow should also fail on its own package checksum before attestation and publication. See [validating workflow artifacts](https://docs.github.com/actions/configuring-and-managing-workflows/persisting-workflow-data-using-artifacts#validating-artifacts). A checksum created by the same build is an integrity check for transfer, not proof that the builder was honest.

For this personal-account repository, set `create-storage-record: false` on `actions/attest` and do not grant `artifact-metadata: write`. GitHub's binary-attestation example requires only `contents: read`, `id-token: write`, and `attestations: write`. The action's storage-record feature is for organization-owned artifacts. See [GitHub's attestation guide](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations#generating-build-provenance-for-binaries) and the first-party [`actions/attest` README](https://github.com/actions/attest/tree/1e69f48acb82d1966a394da916b4c1698aa569d6#usage).

The `actions/attest-build-provenance` repository now tells new users to use `actions/attest`; version 4 of the old action is a wrapper. See the first-party [`attest-build-provenance` repository](https://github.com/actions/attest-build-provenance#usage).

### Gate the write-token job with a release environment

A job that references an environment waits for that environment's protection rules before it starts. Required reviewers can approve or reject it, and environment secrets remain unavailable until approval. Public repositories can use required reviewers on current GitHub plans. See [Deployments and environments](https://docs.github.com/en/actions/reference/workflows-and-actions/deployments-and-environments#deployment-protection-rules).

Create a `release` environment with the owner as reviewer and allow only version tags:

```sh
reviewer_id=$(gh api users/perevernihata --jq .id)

jq -n --argjson reviewer_id "$reviewer_id" '{
  wait_timer: 0,
  prevent_self_review: false,
  reviewers: [{type: "User", id: $reviewer_id}],
  deployment_branch_policy: {
    protected_branches: false,
    custom_branch_policies: true
  }
}' | gh api --method PUT \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/environments/release \
  --input -

printf '%s' '{"name":"v*","type":"tag"}' | \
  gh api --method POST \
    -H "X-GitHub-Api-Version: 2026-03-10" \
    repos/perevernihata/snap-mark/environments/release/deployment-branch-policies \
    --input -
```

The environment API accepts up to six reviewers and only one must approve. Custom branch policies must be enabled before creating a tag policy. See [Create or update an environment](https://docs.github.com/en/rest/deployments/environments?apiVersion=2026-03-10#create-or-update-an-environment) and [Create a deployment branch policy](https://docs.github.com/en/rest/deployments/branch-policies?apiVersion=2026-03-10#create-a-deployment-branch-policy).

`prevent_self_review: false` is deliberate while this is a one-person project. Setting it to `true` would prevent the sole maintainer from approving a tag workflow they initiated. If an independent maintainer is added, list that person as a reviewer and set `prevent_self_review: true`. GitHub describes that option as the way to require someone other than the initiator. Also deselect "Allow administrators to bypass configured protection rules" in the environment's web settings if emergency bypass is not wanted. See [Managing environments](https://docs.github.com/en/actions/how-tos/deploy/configure-and-manage-deployments/manage-environments#configuring-an-environment).

With one reviewer who can approve their own run, this is a deliberate confirmation step, not two-person authorization.

### Protect version tags before a release exists

Immutable releases lock a tag only after publication. A tag ruleset covers the earlier gap and limits who may create, move, or delete a `v*` tag. GitHub's ruleset rules named `creation`, `update`, and `deletion` restrict those operations to bypass actors. See [available rules](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets#restrict-creations) and the [repository ruleset API schema](https://docs.github.com/en/rest/repos/rules?apiVersion=2026-03-10#create-a-repository-ruleset).

For a personal repository, use a `User` bypass actor. `OrganizationAdmin` is not valid for personal repositories.

```sh
owner_id=$(gh api users/perevernihata --jq .id)

jq -n --argjson owner_id "$owner_id" '{
  name: "Protect release tags",
  target: "tag",
  enforcement: "active",
  bypass_actors: [{
    actor_id: $owner_id,
    actor_type: "User",
    bypass_mode: "always"
  }],
  conditions: {
    ref_name: {
      include: ["refs/tags/v*"],
      exclude: []
    }
  },
  rules: [
    {type: "creation"},
    {type: "update", parameters: {update_allows_fetch_and_merge: false}},
    {type: "deletion"}
  ]
}' | gh api --method POST \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/rulesets \
  --input -
```

The release workflow should still reject a tag unless all of these checks pass:

- The name matches exact semantic-version syntax such as `^v[0-9]+\.[0-9]+\.[0-9]+$`.
- The tag resolves to `GITHUB_SHA`.
- `GITHUB_SHA` equals the fetched `origin/main` tip.
- `v<CFBundleShortVersionString>` equals the tag.

The ruleset controls who can manipulate a tag. The workflow checks what commit the tag names.

### Enable immutable releases

Immutable releases prevent changes to a published release's tag and assets. GitHub also creates a release attestation containing the tag, commit SHA, and release assets. Deleting an immutable release does not let anyone reuse its tag name. See [Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases).

Enable the repository setting with an admin token:

```sh
gh api --method PUT \
  -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/immutable-releases
```

The endpoint takes no request body. See [Enable immutable releases](https://docs.github.com/en/rest/repos/repos?apiVersion=2026-03-10#enable-immutable-releases). The live endpoint currently returns an `enabled` boolean even though the generated API page still describes `404` for a disabled repository, so verify `.enabled` rather than relying only on the status code.

Immutability applies only to releases published after it is enabled. Existing releases remain outside this guarantee. GitHub documents that limit in [Preventing changes to your releases](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/establish-provenance-and-integrity/prevent-release-changes).

When files are passed to `gh release create`, the CLI creates a draft, uploads the files, then publishes it. That sequence is compatible with immutable releases because the lock begins after publication. See the [GitHub CLI release-create manual](https://cli.github.com/manual/gh_release_create#immutable-releases).

### Add CodeQL for Swift

Code scanning is available for public GitHub repositories. CodeQL supports Swift on macOS with `autobuild` or `manual` build mode, and both `swift build` and `xcodebuild` are supported. GitHub recommends building one architecture. See [advanced setup eligibility](https://docs.github.com/en/code-security/how-tos/find-and-fix-code-vulnerabilities/configure-code-scanning/configuring-advanced-setup-for-code-scanning#prerequisites) and [Swift build options](https://docs.github.com/en/code-security/reference/code-scanning/codeql/build-options-for-compiled-languages#building-swift).

For this Swift package, use a GitHub-hosted `macos-15` job with:

- `contents: read` and `security-events: write` only.
- The pinned `actions/checkout` commit with `persist-credentials: false`.
- `github/codeql-action/init` and `github/codeql-action/analyze` at the same pinned `v4.37.9` commit.
- `languages: swift`, `build-mode: manual`, and the normal `swift build` command between init and analyze.
- Triggers for pull requests to `main`, pushes to `main`, a weekly schedule, and manual dispatch.

GitHub requires `security-events: write` for advanced CodeQL workflows. The CodeQL repository warns that SHA-pinned versions need regular updates because old versions can lose compatibility with server-side changes. The existing Dependabot GitHub Actions configuration should handle those update pull requests. See the first-party [`github/codeql-action` documentation](https://github.com/github/codeql-action#workflow-permissions).

CodeQL is a useful scanner. It does not prove that a binary is benign and should not replace review, tests, release gating, or provenance.

## Verification checklist

Run these read-only checks after configuration:

```sh
gh api -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/actions/permissions

gh api -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/actions/permissions/selected-actions

gh api -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/actions/permissions/workflow

gh api -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/actions/permissions/fork-pr-contributor-approval

gh api -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/environments/release

gh api -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/environments/release/deployment-branch-policies

gh api -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/rulesets

gh api -H "X-GitHub-Api-Version: 2026-03-10" \
  repos/perevernihata/snap-mark/immutable-releases
```

Expected values are:

- Actions enabled, `allowed_actions` set to `selected`, and `sha_pinning_required` set to `true`.
- GitHub-owned actions allowed, verified publishers disabled, and no allowed wildcard patterns.
- Default workflow permissions set to `read`, with pull-request approval disabled.
- Fork approval set to `all_external_contributors`.
- The `release` environment has a reviewer and a `v*` tag deployment policy.
- An active tag ruleset targets `refs/tags/v*` and restricts creation, update, and deletion.
- Immutable releases report `enabled: true`.

Also check every remote action reference:

```sh
rg 'uses:' .github/workflows
```

Every non-local reference should end in exactly 40 hexadecimal characters before its version comment. Run `actionlint`, the repository's tests, packaging verification, secret scanning, and CodeQL. Confirm the protected `main` branch requires the intended checks before merging.

After the next release, consumers can verify both kinds of provenance:

```sh
gh release verify v1.0.23 -R perevernihata/snap-mark
gh release verify-asset v1.0.23 SnapMark.zip -R perevernihata/snap-mark
gh attestation verify SnapMark.zip -R perevernihata/snap-mark \
  --signer-workflow perevernihata/snap-mark/.github/workflows/release.yml
```

`gh release verify` and `verify-asset` validate GitHub's immutable-release attestation. `gh attestation verify` validates the build-provenance attestation generated by `actions/attest`. See GitHub's [release verification guide](https://docs.github.com/en/code-security/how-tos/secure-your-supply-chain/secure-your-dependencies/verify-release-integrity) and [artifact-attestation verification guide](https://docs.github.com/en/actions/how-tos/secure-your-work/use-artifact-attestations/use-artifact-attestations#verifying-artifact-attestations-with-the-github-cli).

## Limits that remain

- A repository administrator can change these controls. Protect the owner account with 2FA, a passkey, securely stored recovery codes, and a review of authorized OAuth apps, GitHub Apps, SSH keys, deploy keys, and personal access tokens. GitHub calls passkeys phishing-resistant and recommends reviewing unfamiliar account access. See [Preventing unauthorized access](https://docs.github.com/en/authentication/keeping-your-account-and-data-secure/preventing-unauthorized-access).
- A sole reviewer can approve their own release and cannot provide two-person integrity. Add an independent maintainer before switching `prevent_self_review` to `true`.
- SHA pinning prevents a tag from being moved. It does not make the pinned action's code trustworthy. Review action changes in Dependabot pull requests, as GitHub's [secure use reference](https://docs.github.com/en/actions/reference/security/secure-use#using-third-party-actions) recommends.
- An attestation proves which workflow and commit produced an artifact. It does not prove the source or compiler was free of malicious behavior.
- GitHub-hosted runners and GitHub's Actions service remain trusted dependencies. Avoid self-hosted runners for public pull requests. GitHub notes that self-hosted runners do not have the same clean-VM guarantee and can remain compromised after untrusted code runs. See the [secure use reference](https://docs.github.com/en/actions/reference/security/secure-use#hardening-for-self-hosted-runners).
- Releases published before immutable releases were enabled remain mutable under that feature. Publish a new release after hardening rather than presenting an older release as immutable.
