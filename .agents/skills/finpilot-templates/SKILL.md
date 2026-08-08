---
name: finpilot-templates
description: >-
  Template identity rules: the seven rename locations, image identity ARGs,
  keyless signing setup, and AGENTS.md update rules. Use when renaming a fork,
  enabling signing, or updating AGENTS.md and setup docs.
metadata:
  context7-sources:
    - /renovatebot/renovate
---

# finpilot Templates & Fork Setup

## When to Use

- Renaming `finpilot` in a fork (the 7 locations)
- Enabling or explaining keyless signing
- Updating AGENTS.md or copilot instructions
- Updating README.md setup sections or SETUP_CHECKLIST.md
- Documenting new mandatory setup steps for forks

## When NOT to Use

- First-time fork bootstrap procedure — use `finpilot-onboarding`
- Build system changes — use `finpilot-build`
- CI workflow changes — use `finpilot-ci`

## Core Process

1. **Rename in the 7 locations** (table below)
2. **Check the image identity ARGs** match the new name (below)
3. **Enable keyless signing** when the fork is production-ready (below)
4. **Update AGENTS.md** per the rules below
5. **Verify** against the checklist at the end of this skill

## Maintaining a Template-Derived Image

`Use this template` creates an independent repository. Renovate updates
tracked dependencies, action pins, and OCI digests, but it does not synchronize
arbitrary template structure or build logic.

For an improvement that should benefit finpilot users:

1. File a scoped issue in `projectbluefin/finpilot`.
2. The issue creator may select the Clanker opt-in to place their new issue in
   `3-clanker-queue`; maintainers may apply that label to any accepted issue.
3. A Hive-connected agent works the queued issue in a focused pull request.
4. Humans review and merge the pull request.

Do not merge a template repository into a derivative with unrelated histories.
Review `Containerfile`, build script, and workflow changes, then port the
needed changes deliberately through a pull request that preserves the
derivative's customizations.

## Sources

- Renovate dependency-update behavior: `/renovatebot/renovate`

## The Seven Rename Locations

When forking, change `finpilot` → your image name in exactly these locations:

| #   | File                          | What to change                                                      |
| --- | ----------------------------- | ------------------------------------------------------------------- |
| 1   | `Containerfile`               | `ARG IMAGE_NAME="finpilot"` and `ARG IMAGE_VENDOR="projectbluefin"` |
| 2   | `Justfile`                    | `export IMAGE_NAME := env("IMAGE_NAME", "finpilot")`                |
| 3   | `README.md`                   | Title `# finpilot`                                                  |
| 4   | `artifacthub-repo.yml`        | `repositoryID: finpilot`                                            |
| 5   | `custom/ujust/README.md`      | `localhost/your-repo-name:stable` in the bootc switch example    |
| 6   | `.github/workflows/clean.yml` | `packages: finpilot`                                                |
| 7   | `iso/iso.toml`                | `ghcr.io/USERNAME/REPO:stable` in the bootc switch URL              |

Missing any of these causes the image to be published or cleaned up under the wrong name.

## Image Identity ARGs

The Containerfile exposes these identity ARGs for downstream branding:

```dockerfile
ARG IMAGE_NAME="finpilot"          # Your image's name (matches rename #1)
ARG IMAGE_VENDOR="projectbluefin"  # Your GitHub org/username
ARG UBLUE_IMAGE_TAG="stable"       # Stream name
ARG BASE_IMAGE_NAME="silverblue"   # Base image for image-info.json
```

These are consumed by `build/00-image-info.sh` to write:

- `/usr/share/ublue-os/image-info.json` (read by the ublue ecosystem)
- `/usr/lib/os-release` branding fields

## Signing Setup (Keyless OIDC)

This template uses **keyless OIDC signing** via Cosign + Fulcio. No `cosign.key`,
`cosign.pub`, or `SIGNING_SECRET` are needed.

To enable:

1. Edit `.github/workflows/build-image.yml`
2. Find the `# OPTIONAL: Sign and attest` section
3. Uncomment the `Sign and publish` step

Users verify images with:

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/YOUR_ORG/YOUR_REPO/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/YOUR_ORG/YOUR_REPO:stable
```

**Never** add a `cosign.pub` file with a placeholder — it is misleading and was removed.
Static-key signing (`SIGNING_SECRET`) is not supported by this template.
**Never commit `cosign.key`** — it is `.gitignore`-d as a safety net.

## AGENTS.md Update Rules

`AGENTS.md` is the Copilot instructions file. When updating it:

- **Line-number references are fragile** — use semantic references (`ARG IMAGE_NAME`, `FROM`) not line numbers
- **Keep the `## Start here` section pointing at the skills and the router** — this is the factory pattern
- **Update `Last Updated` date** on every substantive change
- **Do not add resolved items** (PR numbers, "✅ done" entries) — those belong in git history

## Common Rationalizations

| Rationalization                                                      | Reality                                                                                                                       |
| -------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| "I only need to rename it in the obvious places."                    | There are exactly 7 locations. Missing `.github/workflows/clean.yml` causes old images to never be pruned under the old name. |
| "Keyless signing is complicated — I'll use the static key approach." | Static key approach was removed intentionally. Keyless OIDC is simpler: no secrets, no key rotation.                          |
| "I'll update AGENTS.md later once the build is working."             | AGENTS.md drives Copilot behaviour on every subsequent session. Update it now.                                                |

## Red Flags

- Fork repo still has `finpilot` in `clean.yml` (image cleanup will target wrong package)
- `cosign.pub` placeholder file added to a fork
- AGENTS.md referencing line numbers instead of semantic identifiers
- `## Start here` section removed or not routing tasks to Agent Skills
- `RENOVATE_TOKEN` not set but Renovate workflow is enabled (fails silently on first run)

## Verification

- [ ] All 7 rename locations updated?
- [ ] `IMAGE_NAME` / `IMAGE_VENDOR` ARGs match the fork?
- [ ] Signing enabled only via keyless OIDC (no `cosign.key`/`cosign.pub`)?
- [ ] `AGENTS.md` uses semantic references (no line numbers)?
- [ ] `AGENTS.md` `Last Updated` date current?
