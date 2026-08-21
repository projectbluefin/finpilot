---
name: finpilot-onboarding
description: >-
  Fork bootstrap playbook: rename (locations: `finpilot-templates`),
  enable Actions, RENOVATE_TOKEN, first green build, README "What Makes
  this Raptor Different" section, and branch protection. Use when creating
  a new fork from this template.
---

# finpilot Onboarding

## When to Use

- Creating a new fork from the finpilot template
- Bootstrapping a new bootc-based custom image repository
- Setting up GitHub Actions, Renovate, and branch protection for the first time
- Onboarding a new contributor who needs to understand the fork-to-first-build pipeline

## When NOT to Use

- The repository is already initialized and has had a successful build
- You are adding packages or changing build logic — use `finpilot-packages` or `finpilot-build`
- You are updating CI workflows — use `finpilot-ci`

## Core Process

1. **Fork the template**: Use "Use this template" on GitHub to create a new repository
2. **Rename all 7 locations** (table: `finpilot-templates`)
3. **Enable GitHub Actions** in the new repository
4. **Add `RENOVATE_TOKEN` secret** (Classic PAT with `repo` + `workflow` scopes)
5. **Configure branch protection and auto-merge**
6. **Trigger first build**
7. **Add the "What Makes this Raptor Different" section to README** (template below)
8. **Verify signing** on the first signed build (`finpilot-templates`)

Keep day-one changes minimal and iterate in phases:

1. **Phase 1 — Bootstrap**: rename, enable Actions, add `RENOVATE_TOKEN`,
   trigger the first green build (this skill)
2. **Phase 2 — Customize**: add one or two packages, run `just build` locally
   (`finpilot-packages`, `finpilot-build`)
3. **Phase 3 — Runtime**: add Flatpak/Brew customizations, test in a VM with
   `just run-vm-qcow2` (`finpilot-custom`)
4. **Phase 4 — Production**: verify signing, full branch protection
   (`finpilot-templates`, `finpilot-maintain`)

Resist changing everything at once — each phase validates the previous.

Each step's completion criterion is the matching item in the Verification checklist below.

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

## Set Up Promotion (Stable Branch)

Create `stable` as an exact copy of `main` (git commands in `SETUP_CHECKLIST.md`
step 3). The `promote-main-to-stable.yml` workflow then automates releases:

1. Pushes to `main` publish `:stable-testing`; a squash PR to `stable` opens
   automatically whenever the trees differ
2. The PR requests review from `<owner>/maintainers` — org forks need that
   team; personal-account forks should replace the caller workflow with a
   local one that skips reviewer requests
3. `stable`'s required approvals set the automation level: `0` = fully
   automatic, `1` = review, then auto-merge
4. Keyless signing (enabled by default) feeds the release gate — signed
   `:testing` images report `release/ready`; unsigned images report
   `release/blocked`

Full requirements live in `SETUP_CHECKLIST.md` → step 3; promotion mechanics
in `finpilot-ci`.

## First Green Build

After the rename and secret setup, trigger a build:

- **Option A**: Push any commit to `main` (e.g., edit `README.md` with the raptor section)
- **Option B**: Go to **Actions → build-image → Run workflow → main**

Monitor the workflow. A successful first build:

- Passes `bootc container lint --fatal-warnings`
- Publishes `:stable-testing` and `:testing` tags to GHCR (`stable` branch builds publish `:stable`)
- Appears under **Packages** in your repository

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

**Maintenance requirement**: update this section on every package or
configuration change — see the update rules in `finpilot-maintain`.

## Signing

No setup required — first builds publish signed images. Verification details:
`finpilot-templates`.

## Common Rationalizations

| Rationalization                                                | Reality                                                                                                    |
| -------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| "I'll rename the obvious places and fix the rest later."       | Missing `.github/workflows/clean.yml` or `iso/iso.toml` causes silent failures months later. Do all 7 now. |
| "I don't need branch protection for a personal fork."          | Without it, Renovate auto-merge won't work, and digest PRs sit unmerged.                                   |
| "I'll add the raptor section to README after I have packages." | Add the section immediately with placeholders. Update it iteratively.                                      |
| "Signing is too much work for a first build."                  | Nothing to configure — builds sign images automatically.                                                   |
| "I'll use my fine-grained PAT for Renovate."                   | Renovate requires a **Classic PAT** with `repo` + `workflow` scopes. Fine-grained PATs do not work.        |

## Red Flags

- Fork repo still has `finpilot` in any of the 7 locations
- `RENOVATE_TOKEN` not set but Renovate workflow is enabled (fails silently or errors on first run)
- `cosign.pub` or `cosign.key` added to the repo
- Auto-merge not enabled, causing Renovate digest PRs to sit unmerged
- Branch protection missing `validate` as a required check
- README missing the "What Makes this Raptor Different" section entirely

## Verification

- [ ] All 7 rename locations updated with the new image name?
- [ ] GitHub Actions enabled in the fork?
- [ ] `RENOVATE_TOKEN` secret added (Classic PAT, `repo` + `workflow`)?
- [ ] Auto-merge enabled in repository settings?
- [ ] Branch protection for `main` configured with `validate` as required check?
- [ ] First green build succeeded and image published to GHCR?
- [ ] README contains the "What Makes this Raptor Different" section?
- [ ] Signing verified on the first signed build?
