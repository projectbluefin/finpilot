---
name: finpilot-onboarding
description: >-
  Fork bootstrap agent playbook. Covers the 7 rename locations, first green build,
  README "What Makes this Raptor Different" section, optional signing setup, and
  branch protection configuration. Use when creating a new fork from this template.
metadata:
  context7-sources: []
---

# finpilot Onboarding

## When to Use

- Creating a new fork from the finpilot template
- Bootstrapping a new bootc-based custom image repository
- Setting up GitHub Actions, Renovate, and branch protection for the first time
- Onboarding a new contributor who needs to understand the fork-to-first-build pipeline

## When NOT to Use

- The repository is already initialized and has had a successful build
- You are adding packages or changing build logic — see `finpilot-packages.md` or `finpilot-build.md`
- You are updating CI workflows — see `finpilot-ci.md`

## Core Process

1. **Fork the template**: Use "Use this template" on GitHub to create a new repository
2. **Rename all 7 locations** (see table below)
3. **Enable GitHub Actions** in the new repository
4. **Add `RENOVATE_TOKEN` secret** (Classic PAT with `repo` + `workflow` scopes)
5. **Create `stable` from `main`**
6. **Replace `OWNER` in `.github/pull.yml` and install the pull GitHub App**
7. **Configure branch protection and auto-merge**
8. **Trigger the first testing build and approve promotion**
9. **Add the "What Makes this Raptor Different" section to README**
10. **Enable signing** (optional, recommended for production)

## The Seven Rename Locations

When forking, change `finpilot` → your image name in exactly these files:

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

## Enable GitHub Actions

1. Go to the **Actions** tab in your new fork
2. Click **"I understand my workflows, go ahead and enable them"**
3. Verify that `.github/workflows/build-image.yml` and others appear

## Add RENOVATE_TOKEN Secret

1. Generate a **Classic Personal Access Token (PAT)** with these scopes: `repo`, `workflow`
2. In your fork: **Settings → Secrets and variables → Actions → New repository secret**
3. Name: `RENOVATE_TOKEN`
4. Value: the PAT token string

This token allows Renovate to open PRs for digest bumps and dependency updates.

## Branch Protection + Auto-Merge

### Enable Auto-Merge

1. **Settings → General → Pull Requests**
2. Check **"Allow auto-merge"**

### Configure Branch Protection for `main`

1. **Settings → Branches → Add rule**
2. Branch name pattern: `main`
3. Enable:
   - **Require a pull request before merging**
   - **Require status checks to pass before merging**
   - Add `validate` as a required status check (from `pr-validation.yml`)
   - (Optional) **Require branches to be up to date before merging**

This ensures PRs are validated before merging and Renovate can auto-merge safe digest updates.

### Configure `stable` Promotion

1. Create and push `stable` from the current `main`.
2. Replace each `OWNER` placeholder in `.github/pull.yml` with your GitHub username.
3. Install the [pull GitHub App](https://github.com/apps/pull) for the repository.
4. Protect `stable` from direct pushes and require promotion pull requests and successful checks.

All feature and Renovate pull requests target `main`. Never make independent commits on `stable`.

## First Green Build

After the rename and secret setup, trigger a build:

- **Option A**: Push any commit to `main` (e.g., edit `README.md` with the raptor section)
- **Option B**: Go to **Actions -> Build and Push Image -> Run workflow -> main**

Monitor the workflow. A successful first build:

- Passes `bootc container lint --fatal-warnings`
- Publishes the `:stable-testing` candidate to GHCR
- Appears under **Packages** in your repository

Test the candidate, then approve the pull[bot] promotion PR. The resulting build on `stable` publishes the production `:stable` image.

## README "What Makes this Raptor Different" Section

**CRITICAL**: Add this section near the top of `README.md` (after the title/intro, before detailed docs):

```markdown
## What Makes this Raptor Different?

Here are the changes from [Base Image Name]. This image is based on [Bluefin/Bazzite/Aurora/etc] and includes these customizations:

### Added Packages (Build-time)

- **System packages**: tmux, micro, mosh - [brief explanation of why]

### Added Applications (Runtime)

- **CLI Tools (Homebrew)**: neovim, helix - [brief explanation]
- **GUI Apps (Flatpak)**: Spotify, Thunderbird - [brief explanation]

### Removed/Disabled

- List anything removed from base image

### Configuration Changes

- Any systemd services enabled/disabled
- Desktop environment changes
- Other notable modifications

_Last updated: [date]_
```

**Maintenance requirement**:

- **ALWAYS update this section when you modify packages or configuration**
- Keep descriptions brief and user-focused (explain "why", not just "what")
- Write for typical Linux users, not developers
- Update the "Last updated" date with each change

## Optional Signing Setup

Signing is **disabled by default** so first builds succeed immediately. Enable later for production.

This template uses **keyless OIDC signing** via Cosign + Fulcio. No `cosign.key` or static keys are needed.

**To enable:**

1. Edit `.github/workflows/build-image.yml`
2. Find the `# OPTIONAL: Sign and attest` section
3. Uncomment the `Sign and publish` step

**Verification:**

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/YOUR_ORG/YOUR_REPO/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/YOUR_ORG/YOUR_REPO:stable
```

**Never commit `cosign.key` to the repository.** It is listed in `.gitignore` as a safety net.

## Agent Playground Setup

When setting up the fork, do not over-customize on day one. Use an **iterative approach**:

1. **Phase 1**: Rename, enable Actions, add token, configure `stable` and pull[bot]
2. **Phase 2**: Add one or two packages, run `just build`, verify locally
3. **Phase 3**: Merge to `main`, test `:stable-testing`, and approve promotion
4. **Phase 4**: Enable signing, verify `:stable`, production-ready

Resist the urge to change everything at once. Each phase validates the previous.

## Common Rationalizations

| Rationalization                                                | Reality                                                                                                    |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| "I'll rename the obvious places and fix the rest later."       | Missing `.github/workflows/clean.yml` or `iso/iso.toml` causes silent failures months later. Do all 7 now. |
| "I don't need branch protection for a personal fork."          | Without it, Renovate auto-merge won't work, and digest PRs sit unmerged.                                   |
| "I'll add the raptor section to README after I have packages." | Add the section immediately with placeholders. Update it iteratively.                                      |
| "Signing is too much work for a first build."                  | Signing is disabled by default. First builds succeed immediately. Enable later.                            |
| "I'll use my fine-grained PAT for Renovate."                   | Renovate requires a **Classic PAT** with `repo` + `workflow` scopes. Fine-grained PATs do not work.        |

## Red Flags

- Fork repo still has `finpilot` in any of the 7 locations
- `RENOVATE_TOKEN` not set but Renovate workflow is enabled (fails silently or errors on first run)
- `cosign.pub` or `cosign.key` added to the repo
- Auto-merge not enabled, causing Renovate digest PRs to sit unmerged
- Branch protection missing `validate` as a required check
- `stable` missing, receiving direct commits, or diverging from `main`
- pull GitHub App not installed or `.github/pull.yml` still contains `OWNER`
- README missing the "What Makes this Raptor Different" section entirely

## Verification

- [ ] All 7 rename locations updated with the new image name?
- [ ] GitHub Actions enabled in the fork?
- [ ] `RENOVATE_TOKEN` secret added (Classic PAT, `repo` + `workflow`)?
- [ ] Auto-merge enabled in repository settings?
- [ ] Branch protection for `main` configured with `validate` as required check?
- [ ] `stable` created and protected from direct pushes?
- [ ] pull GitHub App installed and `OWNER` replaced?
- [ ] First green `:stable-testing` build promoted to `:stable`?
- [ ] README contains the "What Makes this Raptor Different" section?
- [ ] Optional signing enabled (or deferred for later)?
