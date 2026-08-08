---
name: finpilot-ci
description: >-
  GitHub Actions workflows, projectbluefin/actions composite actions,
  Renovate configuration, and PR validation for finpilot.
  Use when changing .github/workflows/, .github/renovate.json, or .hadolint.yaml.
---

# finpilot CI

## When to Use

- Editing any `.github/workflows/*.yml`
- Editing `renovate.json`
- Adding new tooling to `build-image.yml`
- Debugging CI failures
- Deciding what to automerge vs require review

## When NOT to Use

- Containerfile / Justfile / build script changes — use `finpilot-build`
- Runtime customisations — use `finpilot-custom`

## Core Process

1. **Identify the workflow responsible** for your change (see table below)
2. **Check `projectbluefin/actions`** to confirm the composite action exists and what inputs it takes
3. **Pin any new tool** with a specific version + Renovate tracking comment
4. **Validate** locally: `actionlint .github/workflows/*.yml`
5. **Do not widen automerge scope** beyond `digest/pin/pinDigest` for the broad rule

## Workflow Map

| File                          | Trigger                           | Purpose                                                       |
| ----------------------------- | --------------------------------- | ------------------------------------------------------------- |
| `build-image.yml`             | push main + stable, manual        | Publish `:stable-testing` (main) or `:stable` (stable)        |
| `promote-main-to-stable.yml`  | push main, manual                 | Squash promotion PR `main` → `stable` via factory reusable    |
| `sync-stable-to-main.yml`     | push stable                       | Merge direct `stable` hotfixes back to `main` (usually no-op) |
| `pr-validation.yml`           | PR → main                         | shellcheck + hadolint + pre-commit via `validate-pr`          |
| `renovate.yml`                | schedule 6h, push renovate config | Self-hosted Renovate runner                                   |
| `clean.yml`                   | schedule weekly                   | Delete GHCR images older than 90 days                         |
| `validate-brewfiles.yml`      | PR paths: `custom/brew/**`        | Homebrew Brewfile syntax check                                |
| `validate-flatpaks.yml`       | PR paths: `custom/flatpaks/**`    | Flathub app ID existence check                                |
| `validate-justfiles.yml`      | PR paths: `Justfile`              | `just --list` syntax check                                    |
| `validate-renovate.yml`       | PR paths: `.github/renovate.json` | `renovate-config-validator`                                   |

## Branch Promotion and Tags

- `main` is the testing branch and publishes `:stable-testing` (plus bare
  `:testing`, which the promotion release gate resolves).
- `stable` is the production branch and publishes `:stable`.
- Promotion uses `reusable-promote-squash.yml` and `reusable-sync-branches.yml`
  from `projectbluefin/actions` — the factory contract. pull[bot] /
  `.github/pull.yml` was rejected (issues #235/#237); do not add it.
- The `Determine image tag` step sets `TAG_STREAM=testing` off the production
  branch; `Finalize branch tags` renames `testing*` tags to `stable-testing-*`
  so they never collide with production `stable-daily*` aliases.
- The release gate verifies cosign signatures on `:testing`; keyless signing
  (optional step in `build-image.yml`) must be enabled for `release/ready`.

## Composite Action Pins

All actions from `projectbluefin/actions` are pinned to a **commit SHA**:

```yaml
uses: projectbluefin/actions/bootc-build/setup-runner@<sha> # v1
```

**Never use a floating tag like `@v1` or `@main`.** Renovate updates the SHA automatically.

The SHA comment (`# v1`) is for human readability only — Renovate ignores it.

## Rechunking

Set `ENABLE_RECHUNKING: "true"` in `build-image.yml` to enable the existing
`bootc-build/chunka` step. Keep the action active behind the feature flag rather
than commenting it out so Renovate continues to update its SHA.

The action is OCI-native and does not use `/usr/libexec/bootc-base-imagectl`.
Finpilot's default Fedora Silverblue image follows the RPM path, where chunkah
discovers components from the RPM database.

Rechunking is not a drop-in switch after replacing the default base with a
BuildStream-produced image. Those images require a generated `xattr-manifest`
because BuildStream strips component xattrs during OCI export.

Package cadence optimization is optional. `bootc-build/apply-pkg-intervals`
requires a maintained `files/pkg-intervals.tsv`; the reusable cadence workflow
also requires GitHub App credentials. Do not present either as a prerequisite
for basic rechunking.

## Adding a New Tool (e.g., jq, cosign)

Always pin to a specific version with a Renovate tracking comment:

```yaml
- name: Install <tool>
  env:
    # renovate: datasource=github-releases depName=owner/repo
    TOOL_VERSION: "1.2.3"
  run: |
    sudo wget -qO /usr/local/bin/<tool> \
      "https://github.com/owner/repo/releases/download/v${TOOL_VERSION}/<tool>-linux-amd64"
    sudo chmod +x /usr/local/bin/<tool>
```

The `renovate.json` custom manager tracks this pattern:

```json
{
  "customType": "regex",
  "description": "Track pinned tool versions in workflow env vars",
  "managerFilePatterns": ["/^\\.github\\/workflows\\/.+\\.yml$/"],
  "matchStrings": [
    "# renovate: datasource=(?<datasource>[^\\s]+) depName=(?<depName>[^\\s]+)\\n\\s+\\w+: \"(?<currentValue>[^\"]+)\""
  ]
}
```

Never use `/releases/latest/` — it is non-reproducible.

## Renovate Automerge Scope

### ✅ Safe to automerge broadly (digest/pin only)

```json
{
  "matchUpdateTypes": ["digest", "pin", "pinDigest"],
  "automerge": true
}
```

Digest-only updates are hash changes with no API surface change. Safe.

### ✅ Safe to automerge for trusted first-party actions

```json
{
  "matchPackageNames": ["projectbluefin/actions"],
  "matchUpdateTypes": ["digest", "pinDigest", "pin", "patch", "minor"],
  "automerge": true
}
```

`projectbluefin/actions` is controlled by the same factory — minor/patch bumps are safe.

### ❌ Do NOT automerge broadly for `minor`/`patch`

Minor and patch updates across all packages can change workflow behaviour or introduce
regressions. They require human review before merging to an OS image template that ships
to users' machines.

## Renovate OCI Digest Tracking

All OCI image digests are pinned inline in `Containerfile` `FROM` lines and
tracked by Renovate's built-in `dockerfile` manager — pinning pattern:
`finpilot-build`.

When Renovate updates a digest it opens a PR that changes only the relevant
`Containerfile` line. The next CI build uses it directly.

## Renovate Workflow Requirements

The self-hosted Renovate runner requires a `RENOVATE_TOKEN` (Classic PAT with
`repo` + `workflow` scopes; creation: `finpilot-onboarding`). The
`check-token-health` composite action validates it at the start of the workflow,
so a missing or expired token fails the workflow **before** running Renovate —
not midway through.

## hadolint Config (.hadolint.yaml)

Suppressions are documented with reasons:

```yaml
ignore:
  - DL3006 # Commented-out alternative FROM lines use ARG interpolation
  - DL3059 # Multiple consecutive RUN — intentional design (cache layering)
  - SC2312 # Style preference — command substitution in conditions
```

Add suppressions sparingly. If you suppress a new rule, document the reason inline.

## Common Rationalizations

| Rationalization                                          | Reality                                                                                |
| -------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| "I'll use `/releases/latest/` for now and pin it later." | You won't. Non-reproducible builds silently fail months later. Pin immediately.        |
| "Minor/patch automerge is fine — it's just a template."  | Templates ship to users' machines. A bad automerge in a CI action can break all forks. |
| "I don't need Renovate tracking for this one tool."      | Unpinned tools silently break when upstream releases a breaking change.                |

## Red Flags

- Tool installed via `/releases/latest/` without version pin
- Automerge rule includes `minor` or `patch` for all packages (`matchPackageNames` not scoped)
- Composite action used with a floating tag (`@v1`, `@main`) instead of a commit SHA
- `GITHUB_TOKEN` used as the Renovate token (it cannot open PRs to other repos)
- `renovate.json` changed without running `renovate-config-validator`

## Verification

- [ ] Every `uses:` in workflows is pinned to a commit SHA with a version comment?
- [ ] Every new tool install has a pinned version + `# renovate: datasource=...` comment?
- [ ] Automerge broad rule is `digest/pin/pinDigest` only (not `minor`/`patch`)?
- [ ] `actionlint .github/workflows/*.yml` passes clean?
- [ ] `renovate-config-validator .github/renovate.json` passes clean?
- [ ] `RENOVATE_TOKEN` secret documented in SETUP_CHECKLIST.md?
