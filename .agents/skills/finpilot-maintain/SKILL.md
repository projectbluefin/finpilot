---
name: finpilot-maintain
description: >-
  Maintenance of an active finpilot fork: Renovate digest PRs, README raptor
  section updates, signing enablement, local test loops, and maintenance
  schedules. Use when maintaining a fork after onboarding.
---

# finpilot Maintenance

## When to Use

- Reviewing and merging Renovate PRs for OCI digest bumps
- Updating the README "What Makes this Raptor Different" section after changes
- Deciding whether to enable image signing for production
- Running local test builds before pushing changes
- Planning a maintenance schedule for your fork

## When NOT to Use

- First-time fork setup — use `finpilot-onboarding`
- Adding new packages for the first time — use `finpilot-packages`
- Debugging a specific build failure — use `finpilot-troubleshooting`

## Core Process

1. **Review incoming Renovate PRs** — merge if CI passes
2. **Update README raptor section** whenever packages or configuration change
3. **Run local test loop** before opening PRs
4. **Open PRs to `main`** — never push directly
5. **Enable signing** when ready for production

## Handle Renovate Digest PRs

Renovate automatically opens PRs for:

- OCI image digest bumps in `Containerfile`
- GitHub Actions SHA updates in workflows
- Pinned tool version updates (with `# renovate: datasource=...` comments)

### Review Checklist

- [ ] CI passes (`pr-validation.yml` and any `validate-*.yml`)
- [ ] The digest change is isolated to the expected file
- [ ] No unexpected version jumps (e.g., Fedora major version changed when it shouldn't)
- [ ] Security advisories checked (Renovate usually flags CVEs in PR body)

### Merge Strategy

Digest-only PRs are safe to automerge (configured in `renovate.json`). If auto-merge is enabled and CI passes, they merge automatically.

For PRs with non-digest changes (e.g., major version bumps), review manually before merging.

## Update README Raptor Section

The "What Makes this Raptor Different?" section in `README.md` must be updated on **every package or configuration change**. The full section template is in `finpilot-onboarding`.

### When to Update

| Change                                      | Section to Update                          |
| ------------------------------------------- | ------------------------------------------ |
| Added system package in `build/10-build.sh` | "Added Packages (Build-time)"              |
| Added Brewfile package                      | "Added Applications (Runtime) → CLI Tools" |
| Added Flatpak                               | "Added Applications (Runtime) → GUI Apps"  |
| Removed/disabled package or service         | "Removed/Disabled"                         |
| Enabled/disabled systemd service            | "Configuration Changes"                    |
| Desktop environment change                  | "Configuration Changes"                    |

### Format

```markdown
_Last updated: [date]_
```

Always update the date. Keep descriptions brief and user-focused, written for
typical Linux users, not developers.

## Enable Signing When Ready for Production

Signing is **disabled by default** to allow first builds to succeed. Enable when
your fork is stable: uncomment the `Sign and publish` step in
`.github/workflows/build-image.yml` — full setup and verification:
`finpilot-templates`.

## Local Test Loop

Use the local test loop for rapid iteration before opening a PR.

### Commands

```bash
# 1. Build container image
just build

# 2. Build QCOW2 disk image
just build-qcow2

# 3. Run in VM
just run-vm-qcow2
```

### Combined (Common Workflow)

```bash
just build && just build-qcow2 && just run-vm-qcow2
```

### Alternative: ISO Testing

```bash
just build
just build-iso
just run-vm-iso
```

### When to Run

| Scenario                   | Test                                                             |
| -------------------------- | ---------------------------------------------------------------- |
| Added system package       | `just build` + `bootc container lint`                            |
| Changed ujust command      | `just --list`                                                    |
| Changed Brewfile           | `brew bundle check --file custom/brew/default.Brewfile`          |
| Changed Flatpak preinstall | Verify app ID on Flathub                                         |
| Major base image change    | Full loop: `just build && just build-qcow2 && just run-vm-qcow2` |

## PR vs Direct Push Policy

### Always Open a PR to `main`

Direct pushes to `main` bypass validation and create untraceable changes. PRs
trigger `pr-validation.yml` and the `validate-*.yml` checks; branch protection
should require PRs with the `validate` status check (setup: `finpilot-onboarding`).

### PR Best Practices

Use Conventional Commits and the change-type checklists — see
`finpilot-pr-checklist`.

## Keeping OCI Digests Current via Renovate

Renovate handles digest updates automatically. It needs a valid `RENOVATE_TOKEN`
(setup: `finpilot-onboarding`), the Renovate workflow enabled, and auto-merge for
digest-only PRs. If Renovate stops creating PRs, run the Renovate section of
`finpilot-troubleshooting`.

## Maintenance Schedule Recommendations

### Weekly

- Review and merge Renovate PRs
- Check that `validate` checks are passing on `main`

### Monthly

- Run local test loop (`just build && just build-qcow2 && just run-vm-qcow2`)
- Review and update README raptor section if any drift
- Check for security advisories on base image (via Renovate PRs or GitHub Security tab)

### Quarterly

- Review and clean up old branches
- Verify `RENOVATE_TOKEN` still valid
- Consider enabling signing if not already enabled
- Review `build/*.sh` scripts for obsolete packages or patterns

### Annually

- Review and bump Fedora major version (if desired)
- Update `FEDORA_MAJOR_VERSION` ARG in `Containerfile`
- Test full build and deployment cycle
- Review and update documentation (`README.md`, `AGENTS.md`, skills)

## Common Rationalizations

| Rationalization                                                             | Reality                                                                                             |
| --------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| "I'll merge this Renovate PR without reading it — it's just a digest bump." | Always verify the file affected. A misconfigured Renovate rule could affect the wrong image.        |
| "I'll update the README later when I have more changes."                    | Update incrementally. "Later" often means never, and users rely on README for current state.        |
| "Local builds are optional since CI builds everything."                     | Local builds catch issues faster and don't burn CI minutes. The `just build` loop is essential.     |
| "I'll push to main to save time."                                           | PRs are cheap. Direct pushes bypass validation and create untraceable changes.                      |
| "Signing is too hard — I'll skip it."                                       | Keyless OIDC signing is one uncomment step. The hard part is already done in the workflow template. |

## Red Flags

- Renovate PRs sitting unmerged for weeks
- README raptor section missing or severely outdated
- No local builds run before PRs are opened
- Direct pushes to `main` bypassing branch protection
- Signing still disabled after months of production use
- `RENOVATE_TOKEN` expired (Renovate workflow fails)

## Verification

- [ ] Are all Renovate PRs merged or under active review?
- [ ] Is the README raptor section updated for the latest changes?
- [ ] Was `just build` run locally before the last PR?
- [ ] Are all pushes to `main` via PR with passing `validate` check?
- [ ] Is image signing enabled (or on the roadmap for production)?
- [ ] Is `RENOVATE_TOKEN` valid and the Renovate workflow running?
