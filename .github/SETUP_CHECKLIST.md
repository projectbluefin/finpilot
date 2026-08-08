# Repository Setup Checklist

## Initial Setup

### 1. Rename Template

- [ ] Update `finpilot` to your name in **7 files** (use the `finpilot-templates` skill):
  1. `Containerfile` — `ARG IMAGE_NAME` and `ARG IMAGE_VENDOR`
  2. `Justfile` — `export IMAGE_NAME`
  3. `README.md` — title
  4. `artifacthub-repo.yml` — `repositoryID`
  5. `custom/ujust/README.md` — bootc switch example
  6. `.github/workflows/clean.yml` — `packages`
  7. `iso/iso.toml` — bootc switch URL

**Agent skills:** `finpilot-templates` (rename rules), `finpilot-onboarding` (fork bootstrap)

### 2. Enable GitHub Actions

- [ ] Settings → Actions → General → Enable workflows
- [ ] Set "Read and write permissions"

### 3. Configure Testing and Production Branches

This template uses a **two-branch model**: `main` publishes `:stable-testing`
candidate images, and `stable` publishes `:stable` production images.
Promotion is a squash PR from `main` to `stable` opened automatically by
`.github/workflows/promote-main-to-stable.yml` (factory reusable workflow —
no external GitHub App required).

Create `stable` as an exact copy of `main`, then return to `main`:

```bash
git switch main
git switch -c stable
git push --set-upstream origin stable
git switch main
```

- [ ] Never commit directly to `stable`; it receives only promotion PRs
- [ ] Enable keyless signing (see "Enable Signing" below) so the promotion
      release gate can verify image signatures and report `release/ready`

### 4. First Push

```bash
git add .
git commit -m "feat: initial customization"
git push origin main
```

### 5. Enable Renovate (Required)

- [ ] Create a **Classic PAT** (Settings → Developer settings → Personal access tokens → Tokens (classic))
  - Scopes: `repo` (full control) + `workflow` (update workflows)
- [ ] Add the token as repository secret **`RENOVATE_TOKEN`** (Settings → Secrets and variables → Actions)
- [ ] Enable **Settings → General → Pull Requests → Allow auto-merge**
- [ ] Configure branch protection for `main`:
  - Settings → Branches → Add rule
  - Set **Branch name pattern** to `main`
  - Enable "Require a pull request before merging"
  - Enable "Require status checks to pass before merging"
  - Add `validate` as a required status check
  - Enable "Require branches to be up to date before merging"
- [ ] Configure branch protection for `stable`: require a pull request before
      merging so only promotion PRs land there
- [ ] Renovate will create a PR to pin your GitHub Actions to SHAs

Renovate targets `main`; approved changes reach `stable` through the promotion flow.

**Agent skills:** `finpilot-onboarding` (branch protection), `finpilot-ci` (Renovate config)

### 6. Add "What Makes this Raptor Different" to README

- [ ] Open `README.md`
- [ ] Paste the raptor section template (see README or use the `finpilot-onboarding` skill)
- [ ] Fill in placeholders with your planned customizations
- [ ] Update the `*Last updated: [date]*` timestamp

**Agent skills:** `finpilot-onboarding` (raptor section), `finpilot-maintain` (maintenance requirement)

### 7. Deploy

Test the candidate image from `main`:

```bash
sudo bootc switch --transport registry ghcr.io/YOUR_USERNAME/YOUR_REPO:stable-testing
sudo systemctl reboot
```

After merging the promotion to `stable`, deploy the production image:

```bash
sudo bootc switch --transport registry ghcr.io/YOUR_USERNAME/YOUR_REPO:stable
sudo systemctl reboot
```

## Optional: Production Features

### Enable Signing (Recommended)

This template uses keyless OIDC signing — no keys or secrets are required.

- [ ] Edit `.github/workflows/build-image.yml`
- [ ] Find the "OPTIONAL: Sign and attest" section
- [ ] Uncomment the `Sign and publish` step
- [ ] Commit and push (via PR to `main`)

**Agent skill:** `finpilot-templates` (signing setup)

### Enable Rechunking (Optional)

- [ ] Edit `.github/workflows/build-image.yml`
- [ ] Set `ENABLE_RECHUNKING: "true"`
- [ ] Keep the default `RECHUNK_MAX_LAYERS: "128"` unless you have measured a reason to change it
- [ ] Confirm a publish build completes before deploying the new image

The current OCI-native chunkah action does not use `/usr/libexec/bootc-base-imagectl`. Package cadence classification is a separate advanced setup and is not required for basic rechunking.

**Agent skill:** `finpilot-ci` (rechunking compatibility and workflow setup)

## Agent Handoff Reference

Which skill to load for each checklist block above:

| Checklist step                        | Skill                                       |
| ------------------------------------- | ------------------------------------------- |
| Rename (step 1)                       | `finpilot-templates`, `finpilot-onboarding` |
| Enable Actions (step 2)               | `finpilot-onboarding`                       |
| Branches + promotion (step 3)         | `finpilot-onboarding`, `finpilot-ci`        |
| Renovate + branch protection (step 5) | `finpilot-onboarding`, `finpilot-ci`        |
| Raptor section (step 6)               | `finpilot-onboarding`, `finpilot-maintain`  |
| Signing (optional)                    | `finpilot-templates`                        |
| Rechunking (optional)                 | `finpilot-ci`                               |

**Cross-link requirement**: Whenever you add or remove a package, app, or service **after** initial setup, update the README raptor section and its `*Last updated*` date. This is required by the `finpilot-maintain` skill.
