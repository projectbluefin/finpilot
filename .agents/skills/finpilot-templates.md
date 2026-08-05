---
name: finpilot-templates
description: >-
  Template initialization, fork setup, renaming conventions, and the
  seven files that must be updated when creating a new image from finpilot.
  Use when initializing a fork, updating AGENTS.md, or documenting setup.
metadata:
  context7-sources: []
---

# finpilot Templates & Fork Setup

## When to Use

- Initializing a new custom OS image from this template
- Updating AGENTS.md or copilot instructions
- Updating README.md setup sections or SETUP_CHECKLIST.md
- Documenting new mandatory setup steps for forks

## When NOT to Use

- Build system changes — see `finpilot-build.md`
- CI workflow changes — see `finpilot-ci.md`

## Core Process: Creating a New Fork

1. **Click "Use this template"** on GitHub → create new repository
2. **Rename `finpilot` in exactly 7 files** (see table below)
3. **Enable GitHub Actions** in the Actions tab
4. **Add `RENOVATE_TOKEN` secret** (Classic PAT, `repo` + `workflow` scopes)
5. **Enable auto-merge** (Settings → General → Pull Requests → Allow auto-merge)
6. **Create `stable` from `main` and protect it from direct pushes**
7. **Replace `OWNER` in `.github/pull.yml` and install the pull GitHub App**
8. **Protect `main`** with `validate` as a required check
9. **Trigger the first `:stable-testing` build and approve promotion**
10. **Enable signing** (optional) — uncomment `sign-and-publish` step in `build-image.yml`

## The Seven Rename Locations

When forking, change `finpilot` → your image name in exactly these locations:

| #   | File                          | What to change                                                      |
| --- | ----------------------------- | ------------------------------------------------------------------- |
| 1   | `Containerfile`               | `ARG IMAGE_NAME="finpilot"` and `ARG IMAGE_VENDOR="projectbluefin"` |
| 2   | `Justfile`                    | `export IMAGE_NAME := env("IMAGE_NAME", "finpilot")`                |
| 3   | `README.md`                   | Title `# finpilot`                                                  |
| 4   | `artifacthub-repo.yml`        | `repositoryID: finpilot`                                            |
| 5   | `custom/ujust/README.md`      | `localhost/finpilot:stable` in the bootc switch example             |
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

## AGENTS.md Update Rules

`AGENTS.md` is the Copilot instructions file. When updating it:

- **Line-number references are fragile** — use semantic references (`ARG IMAGE_NAME`, `FROM`) not line numbers
- **Keep the `## Start here` section pointing to the skills router table** — this is the factory pattern
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
- `## Start here` section removed or not pointing to skill files
- `RENOVATE_TOKEN` not set but Renovate workflow is enabled (fails silently on first run)
- `.github/pull.yml` still contains `OWNER` or `stable` accepts direct pushes

## Verification

- [ ] All 7 rename locations updated?
- [ ] GitHub Actions enabled in the fork?
- [ ] `RENOVATE_TOKEN` secret added?
- [ ] Auto-merge enabled in repository settings?
- [ ] Branch protection for `main` configured with `validate` as required check?
- [ ] `stable` created and protected from direct pushes?
- [ ] pull GitHub App installed and `OWNER` replaced?
- [ ] `:stable-testing` tested before promotion to `:stable`?
- [ ] `AGENTS.md` `Last Updated` date current?
