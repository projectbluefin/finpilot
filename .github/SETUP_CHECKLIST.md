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

### 3. First Push

```bash
git add .
git commit -m "feat: initial customization"
git push origin main
```

### 4. Enable Renovate (Required)

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
- [ ] Renovate will create a PR to pin your GitHub Actions to SHAs

**Agent skills:** `finpilot-onboarding` (branch protection), `finpilot-ci` (Renovate config)

### 5. Create Stable Branch

- [ ] Create the `stable` branch from `main`:

```bash
git checkout main
git checkout -b stable
git push origin stable
git checkout main
```

### 6. Install pull[bot] GitHub App (Required for Promotion)

The [pull](https://github.com/apps/pull) GitHub App automatically promotes tested changes from `main` → `stable`.

- [ ] Install the pull App: **Settings → Applications → Search "pull" → Install**
- [ ] Replace `OWNER` placeholder in `.github/pull.yml` with your GitHub username:
  ```bash
  sed -i "s/OWNER/your-github-username/g" .github/pull.yml
  ```
- [ ] Commit and push:
  ```bash
  git add .github/pull.yml
  git commit -m "chore: configure pull[bot] for OWNER"
  git push origin main
  ```

**Workflow:** `main` (PRs land → `:stable-testing` image) → pull[bot] auto-creates PR → `stable` (approved → `:stable` production image)

### 7. Add "What Makes this Raptor Different" to README

- [ ] Open `README.md`
- [ ] Paste the raptor section template (see README or use the `finpilot-onboarding` skill)
- [ ] Fill in placeholders with your planned customizations
- [ ] Update the `*Last updated: [date]*` timestamp

**Agent skills:** `finpilot-onboarding` (raptor section), `finpilot-maintain` (maintenance requirement)

### 8. Deploy

```bash
# Deploy testing image (from main branch)
sudo bootc switch --transport registry ghcr.io/YOUR_USERNAME/YOUR_REPO:stable-testing
sudo systemctl reboot

# Deploy production image (from stable branch, after pull[bot] promotion)
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

## Agent Handoff Reference

Which skill to load for each checklist block above:

| Checklist step                        | Skill                                           |
| ------------------------------------- | ----------------------------------------------- |
| Rename (step 1)                       | `finpilot-templates`, `finpilot-onboarding`     |
| Enable Actions (step 2)               | `finpilot-onboarding`                           |
| Renovate + branch protection (step 4) | `finpilot-onboarding`, `finpilot-ci`            |
| Stable branch (step 5)                | `finpilot-onboarding`                           |
| pull[bot] install (step 6)            | `finpilot-ci`                                   |
| Raptor section (step 7)               | `finpilot-onboarding`, `finpilot-maintain`      |
| Signing (optional)                    | `finpilot-templates`                            |

**Cross-link requirement**: Whenever you add or remove a package, app, or service **after** initial setup, update the README raptor section and its `*Last updated*` date. This is required by the `finpilot-maintain` skill.
