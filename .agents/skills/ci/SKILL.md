---
name: ci
description: >-
  GitHub Actions, Renovate, the two-branch release model, signing, and
  promotion. Use when changing workflows, dependency policy, or releasing.
---

# CI

## Workflows

| Workflow | Trigger | Does |
|---|---|---|
| `build-image.yml` | push to `main` or `stable`, dispatch | Builds, signs, and pushes the image. |
| `execute-release.yml` | push to `stable` | Promotes the candidate digest. Does not rebuild. |
| `promote-main-to-stable.yml` | daily schedule, dispatch | Opens the squash promotion PR and runs the release gate on it. |
| `sync-stable-to-main.yml` | push to `stable` | Merges `stable` hotfixes back into `main`. |
| `pr-validation.yml` | pull request | The `validate` check: shellcheck and hadolint. |
| `validate-brewfiles.yml` | pull request | Brewfiles, without evaluating them. |
| `validate-flatpaks.yml` | pull request | Flatpak preinstall files against Flathub. |
| `validate-justfiles.yml` | pull request | `just check`. |
| `validate-renovate.yml` | pull request | Renovate config. |
| `unit-tests.yml` | push, pull request | The bats suite. |
| `renovate.yml` | schedule, config change | Runs Renovate. |
| `clean.yml` | schedule | Deletes images older than 90 days. |

Most are thin callers of reusable workflows in `projectbluefin/actions`.

## The release model

`main` publishes `:stable-testing`. `stable` never rebuilds: promotion is a
squash PR from `main` to `stable`, and `execute-release.yml` copies the digest
`:testing` resolves to. The README owns the release table and the promotion
gate's current limits.

The factory reusable puts its release gate and its auto-merge enrollment behind
one input, `enqueue_promotion`. A personal repository cannot enroll — there is no
merge queue, and `gh pr merge --auto` refuses without a merge method — so
enrollment is off, and `promote-main-to-stable.yml` runs the gate itself in its
own `gate` job to keep the pre-merge check. That gate resolves `:testing` when it
runs, so it attests the current candidate. The binding comes from
`execute-release.yml` passing `source_branch: main`, which makes the reusable
refuse to promote at all once `main` has moved past the promotion commit; a
manual dispatch is exempt, because that path is deliberate recovery.

The same reusable builds the squash branch, and it stages deletions with
`git diff --diff-filter=D`. Git reports a moved file as a rename, so a path `main`
moved survives on its old path and the branch's tree stops matching `main`'s —
the state the guard above refuses, but only after the PR is merged.
`repair-promotion-branch` in `promote-main-to-stable.yml` rebuilds the branch from
`main`'s tree when it has drifted, and the `validate` check fails a promotion PR
whose tree does not match `main`. The sweep belongs to `projectbluefin/actions`;
the one-line fix there is `--no-renames`.

## Signing

Keyless OIDC via Cosign. There are no keys to generate or store; the workflow
needs `id-token: write` and `packages: write`. Unsigned images fail the promotion
gate. The README has the command to verify an image.

The identity regexp the release workflows pass to the reusables is scoped with
`github.repository`, not `github.repository_owner`. Matching the owner and then
any repository accepts a signature minted by any repository in the org, and
`github.repository` keeps the scope correct in a fork without hardcoding it.

## Renovate

Self-hosted through `projectbluefin/actions`, running every six hours. It pins
GitHub Actions to SHAs and updates image digests. The policy lives in
`.github/renovate.json`: updates below a major automerge once checks pass;
majors wait for a pull request.

Renovate needs the `RENOVATE_TOKEN` secret and auto-merge enabled. Both are
onboarding steps. The secret is optional: with it unset the workflow logs a skip
and the run stays green, which is how upstream runs, where an org-wide app does
the work instead. The check sits in its own `token` job because a job that calls
a reusable workflow cannot hold steps, and `jobs.<job_id>.if` cannot read the
secrets context — `secrets` in a job-level `if` is a parse error, not a skip.

Automerge deliberately covers GitHub Actions SHA bumps, which reverses a guard
upstream kept. Those SHAs run in jobs holding `packages: write`,
`id-token: write`, and `secrets: inherit`, and PR builds are disabled, so a bump
merges with only shellcheck, hadolint, and the test suite having run. Putting the
guard back is one rule — `matchManagers: ["github-actions"]` with
`automerge: false`.

## Making a change

1. Open a pull request against `main`.
2. Wait for `validate` and the image build.
3. Merge. `main` publishes `:stable-testing`.
4. Review and merge the promotion PR to publish `:stable`.
