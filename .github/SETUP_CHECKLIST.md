# Repository Setup Checklist

## Initial Setup

### 1. Rename Template

- [ ] Update `finpilot` to your name in **7 files** (see `finpilot-templates`):
  1. `Containerfile` — `ARG IMAGE_NAME` and `ARG IMAGE_VENDOR`
  2. `Justfile` — `export IMAGE_NAME`
  3. `README.md` — title
  4. `artifacthub-repo.yml` — `repositoryID`
  5. `custom/ujust/README.md` — bootc switch example
  6. `.github/workflows/clean.yml` — `packages`
  7. `iso/iso.toml` — bootc switch URL

**Agent skill:** `finpilot-templates` (rename rules), `finpilot-onboarding` (fork bootstrap)

### 2. Enable GitHub Actions

- [ ] Settings → Actions → General → Enable workflows
- [ ] Set "Read and write permissions"

### 3. Configure Testing and Production Branches

Create `stable` as an exact copy of `main`, then return to `main`:

```bash
git switch main
git switch -c stable
git push --set-upstream origin stable
git switch main
```

- [ ] Replace `castrojo` in `.github/pull.yml` (`reviewers` and `conflictReviewers`) with your GitHub username
- [ ] Install the [pull GitHub App](https://github.com/apps/pull) for this repository
- [ ] Validate the configuration at `https://pull.git.ci/check/YOUR_USERNAME/YOUR_REPO`
- [ ] Never commit directly to `stable`; pull[bot] must keep it synchronized with `main`

The resulting delivery flow is:

```text
feature branch
      |
      v
PR -> main -> ghcr.io/OWNER/REPO:stable-testing
             |
             v
       pull[bot] promotion PR
             |
             v
          stable -> ghcr.io/OWNER/REPO:stable
```

### 4. First Change

Open a pull request targeting `main`. After it merges:

1. Verify the `:stable-testing` image.
2. Wait for pull[bot] to open the `main` -> `stable` promotion PR.
3. Approve and merge the promotion PR.
4. Verify the `:stable` image.

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
- [ ] Protect `stable` from direct pushes and require pull requests and successful checks

Renovate targets `main`; approved changes reach `stable` through the same promotion flow.

**Agent skill:** `finpilot-onboarding` (branch protection), `finpilot-ci` (Renovate config)

### 6. Add "What Makes this Raptor Different" to README

- [ ] Open `README.md`
- [ ] Paste the raptor section template (see README or `finpilot-onboarding`)
- [ ] Fill in placeholders with your planned customizations
- [ ] Update the `*Last updated: [date]*` timestamp

**Agent skill:** `finpilot-onboarding` (raptor section), `finpilot-maintain` (maintenance requirement)

### 7. Deploy

Test the candidate image from `main`:

```bash
sudo bootc switch --transport registry ghcr.io/YOUR_USERNAME/YOUR_REPO:stable-testing
sudo systemctl reboot
```

After approving promotion to `stable`, deploy the production image:

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
- [ ] Commit through a pull request to `main`

**Agent skill:** `finpilot-templates` (signing setup)

## Agent Handoff Reference

| Checklist step | Skill |
| --- | --- |
| Rename (step 1) | `finpilot-templates`, `finpilot-onboarding` |
| Enable Actions (step 2) | `finpilot-onboarding` |
| Branches and pull[bot] (step 3) | `finpilot-onboarding`, `finpilot-ci` |
| Renovate + branch protection (step 5) | `finpilot-onboarding`, `finpilot-ci` |
| Raptor section (step 6) | `finpilot-onboarding`, `finpilot-maintain` |
| Signing (optional) | `finpilot-templates` |

**Cross-link requirement**: Whenever you add or remove a package, app, or service **after** initial setup, update the README raptor section and its `*Last updated*` date. This is required per `finpilot-maintain`.
