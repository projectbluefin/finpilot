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
| `pr-validation.yml` | pull request | The `validate` check: shellcheck and hadolint. |
| `pr-build.yml` | pull request, merge queue | The `PR image build` check: builds the image (no push, no signing) when the Containerfile, Justfile, `.dockerignore`, `build/`, `custom/` or the workflow itself changes; passes in seconds otherwise. |
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

The release's SBOM is generated at build time, not scanned on the release run.
`build-image.yml` installs Syft and scans the already-built local image. Syft's
`podman:` source talks to the Podman API socket, which this rootful build has no
rootful instance of (finpilot #683), so the image is mounted read-only with
`podman image mount` and scanned as a directory (`dir:`) instead. That reads the
layers from the btrfs podman storage this build already used, with no daemon and
no second copy of the ~3 GB image, and the SBOM still describes the exact digest
that is pushed. It catalogs with `rpm-db-cataloger`, `--parallelism 1`, and
uploads it as the `sbom-finpilot` artifact. `execute-release.yml`'s release job passes `build_workflow:
build-image.yml`, `build_branch: main`, and `sbom_artifact: sbom-finpilot` so it
downloads that artifact instead of scanning the promoted image inline. Scanning
inline pulls and unpacks the ~3 GB image on a bare ubuntu-24.04 runner, where the
runner is evicted before the scan finishes (finpilot #678) and the release ships
an empty package list. The build-time catalog reads the layers from the btrfs
podman storage this build already used, so there is no second pull and the SBOM
describes the exact digest that is pushed. The artifact includes an image-digest
file. The local release-from-build.yml consumer selects a successful build whose
artifact matches the promoted digest and stops release publication if no match
is retained or its download fails. There is no empty-SBOM fallback on this path.
A build-time scan failure does not fail the build: the SBOM steps are
`continue-on-error`, each runs only after the previous one succeeded, so the
image is still pushed and signed, no partial artifact is uploaded, and the
release for that digest then stops instead of shipping an empty package list.
The artifact is kept for 90 days, because main only builds when it changes and
the promoted build can be weeks old when the promotion PR merges.

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

The promotion gate is the *only* enforcement point. Nothing checks the signature
on an installed system, so `00-image-info.sh` writes an unverified update
transport (`ostree-unverified-image:docker://…`) and the README says so.
`ostree-image-signed:` would send the client to `/etc/containers/policy.json`,
which Common supplies with no scope for this namespace — it would verify against
the `""` catch-all, `insecureAcceptAnything`, and report success having checked
nothing. Adding a scope does not rescue it while signing stays keyless:
containers/image matches a Fulcio certificate on `subjectEmail` alone
(mandatory, exact, with a standing FIXME for URI SANs in
`signature/fulcio_cert.go`), and a GitHub Actions certificate names its workflow
in a URI SAN with no email to match. Device-side verification is a key-based
signing change first, a policy change second.
`tests/contract/image-signing_test.bats` fails if either side moves alone.

The identity regexp the release workflows pass to the reusables is scoped with
`github.repository`, not `github.repository_owner`. Matching the owner and then
any repository accepts a signature minted by any repository in the org, and
`github.repository` keeps the scope correct in a fork without hardcoding it.

## Renovate

Self-hosted through `projectbluefin/actions`, running every six hours. It pins
GitHub Actions to SHAs and updates image digests. The policy lives in
`.github/renovate.json`: updates below a major automerge once checks pass;
majors wait for a pull request — except `quay.io/fedora-ostree-desktops/*`,
where cross-major bumps do not open a PR at all (the rule is `enabled: false`).
A Fedora major rebase for that namespace is a deliberate manual step: bump the
tag in `Containerfile` by hand when the next major is released and validated.

Renovate needs the `RENOVATE_TOKEN` secret and auto-merge enabled. Both are
onboarding steps. The secret is optional: with it unset the workflow logs a skip
and the run stays green, which is how upstream runs, where an org-wide app does
the work instead. The check sits in its own `token` job because a job that calls
a reusable workflow cannot hold steps, and `jobs.<job_id>.if` cannot read the
secrets context — `secrets` in a job-level `if` is a parse error, not a skip.

Automerge deliberately covers GitHub Actions SHA bumps, which reverses a guard
upstream kept. Those SHAs run in jobs holding `packages: write`,
`id-token: write`, and `secrets: inherit`, and the PR image build runs only when
the image's inputs change, which an action bump does not, so a bump merges with
only shellcheck, hadolint, and the test suite having run. Putting the
guard back is one rule — `matchManagers: ["github-actions"]` with
`automerge: false`.

## Making a change

1. Open a pull request against `main`.
2. Wait for `validate` and the image build.
3. Merge. `main` publishes `:stable-testing`.
4. Review and merge the promotion PR to publish `:stable`.

## Apt mirror resilience

The `unit-tests.yml` `Install bats` step runs `apt-get` against the runner
image's stock Ubuntu mirrors. A slow mirror can leave apt waiting past the
10-minute job timeout, cancelling a run whose diff cannot have caused the
stall (issue #497, observed on PR #492 head 5769c24, job 112944421448). The
step fronts both `apt-get update` and `apt-get install` with `timeout 180`,
passes `-o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o
Acquire::Retries=2` to each so a stalled socket fails fast from either
half, and `--no-install-recommends` to skip the `bats-doc` package the
workflow never reads. The wall-clock cap is what catches a slow-but-alive
mirror; the per-call timeouts only fire on inactivity.

## Skipped cases pass the job

bats reports a skipped case as `ok … # skip`, so `unit-tests.yml` stays green
when a whole file skips. `ubuntu-latest` has no unprivileged user namespaces, so
a case gated on `unshare -r` never runs in CI. Stub privileged commands on PATH
instead: `sudoif` resolves `sudo` with `command -v` and the recipes call it by
name, so one recording stub catches both, and setting `SUDO_USER`
short-circuits `_rootful_load_image`. The installer-build file was
namespace-gated and skipped all 24 cases until issue #660. Only the `run-vm`
cases still need a namespace, for the tmpfs over firmware paths.
