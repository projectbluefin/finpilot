# Copilot Instructions for finpilot bootc Image Template

## Start here

Read the repo skill docs before changing behavior:

- `.agents/skills/finpilot-overview.md` — architecture, repo layout, task router
- `.agents/skills/finpilot-onboarding.md` — fork bootstrap: rename, Actions, token, first build
- `.agents/skills/finpilot-packages.md` — decision tree (dnf5 vs Brew vs Flatpak)
- `.agents/skills/finpilot-custom.md` — Brewfiles, Flatpaks, ujust rules
- `.agents/skills/finpilot-build.md` — Containerfile, Justfile, build scripts
- `.agents/skills/finpilot-ci.md` — GitHub Actions workflows, composite actions, Renovate
- `.agents/skills/finpilot-maintain.md` — ongoing: Renovate PRs, signing, local test loop
- `.agents/skills/finpilot-troubleshooting.md` — symptom → cause → fix
- `.agents/skills/finpilot-pr-checklist.md` — PR gates by change type
- `.agents/skills/finpilot-examples.md` — runnable examples and activation patterns

### Task Router

| I need to…                                     | Load                                      |
| ---------------------------------------------- | ----------------------------------------- |
| Bootstrap a new fork                           | `finpilot-onboarding.md`                  |
| Add/remove a package                           | `finpilot-packages.md`                    |
| Change Brewfiles, Flatpaks, or ujust           | `finpilot-custom.md`                      |
| Change Containerfile, Justfile, or build/\*.sh | `finpilot-build.md`                       |
| Fix CI or Renovate                             | `finpilot-ci.md` / `finpilot-maintain.md` |
| Open a PR                                      | `finpilot-pr-checklist.md`                |
| Debug a build or deploy failure                | `finpilot-troubleshooting.md`             |
| Follow a worked example                        | `finpilot-examples.md`                    |
| Initialize/ rename this template               | `finpilot-templates.md`                   |
| Orient to repo architecture                    | `finpilot-overview.md`                    |

## Branch Strategy

- `main` is the testing branch and publishes `:stable-testing`.
- `stable` is the production branch and publishes `:stable`.
- All feature and Renovate pull requests target `main`.
- pull[bot] opens promotion pull requests from `main` to `stable` using `.github/pull.yml`.
- Never make independent changes on `stable`; approve promotion only after testing the candidate image.

## CI Structure

```text
.github/
├── pull.yml                  # pull[bot] main -> stable promotion
└── workflows/
    ├── build-image.yml       # PR builds and branch-aware image publishing
    ├── pr-validation.yml     # Required validation for PRs to main
    ├── renovate.yml          # Dependency update automation
    └── validate-*.yml        # Targeted file validation
```

## Release Workflow

1. Open changes against `main`.
2. Merge only after required validation and image build checks pass.
3. Test `ghcr.io/OWNER/IMAGE:stable-testing`.
4. Review the pull[bot] promotion PR from `main` to `stable`.
5. Merge the promotion to publish `ghcr.io/OWNER/IMAGE:stable`.

| Branch | Mutable image tag | Audience |
| --- | --- | --- |
| `main` | `:stable-testing` | Testers and release candidates |
| `stable` | `:stable` | Production systems |

## CRITICAL: GitHub API Usage

**ALWAYS use GitHub API for external references:**

- When researching other repositories (e.g., projectbluefin/distroless, ublue-os/bluefin)
- When checking Containerfiles, build scripts, or configuration files
- Use the `github-mcp-server-get_file_contents` tool instead of curl/wget
- This ensures consistent, authenticated access and better error handling

## CRITICAL: Pre-Commit Checklist

**Execute before EVERY commit:**

1. **Conventional Commits** - ALL commits MUST follow conventional commit format (see below)
2. **Shellcheck** - `shellcheck *.sh` on all modified shell files
3. **YAML validation** - `python3 -c "import yaml; yaml.safe_load(open('file.yml'))"` on all modified YAML
4. **Justfile syntax** - `just --list` to verify
5. **Confirm with user** - Always confirm before committing and pushing

**Never commit files with syntax errors.**

### REQUIRED: Conventional Commit Format

**ALL commits MUST use conventional commits format**

```
<type>[optional scope]: <description>
```

## PR Comment Policy

**One comment per PR event, max.** Combine all findings into a single comment. Never post a follow-up comment for a new observation — edit the existing one instead.

**Never duplicate GitHub UI state.** Do not post approval counts, merge queue status, or CI pass/fail summaries — GitHub already surfaces these natively in the PR timeline.

**Test reports: minimal.** Report what ran, pass/fail, and blockers only. No diff summaries. No tables unless comparing ≥3 divergent approaches that require a human decision.

**@ mentions in context only.** Only ping someone if asking them to do something specific. Always inside the combined comment — never as a standalone comment.

**When in doubt, don't post.** If the only thing to report is "tests pass", post nothing.

## Critical Rules (Enforced)

1. **ALWAYS** use Conventional Commits format for ALL commits (see `.github/commit-convention.md`)
2. **NEVER** commit `cosign.key` to repository (`cosign.key` is `.gitignore`-d)
3. **ALWAYS** disable COPRs after use (`copr_install_isolated` in `build/copr-helpers.sh`)
4. **ALWAYS** use `dnf5` exclusively (never `dnf`, `yum`, `rpm-ostree`)
5. **ALWAYS** use `-y` flag for non-interactive installs
6. **NEVER** use `dnf5` in ujust files — only Brewfile/Flatpak shortcuts
7. **NEVER** push directly to `main` (only via PR with passing `validate` check)
8. **NEVER** push directly to `stable`; promote tested `main` commits through pull[bot]
9. **ALWAYS** target `main` and test `:stable-testing` before approving promotion
10. **ALWAYS** confirm with user before deviating from @ublue-os/bluefin patterns
11. **ALWAYS** run shellcheck/YAML validation before committing
12. **ALWAYS** follow numbered script convention: `10-*.sh`, `20-*.sh`, `30-*.sh`
13. **ALWAYS** validate that new Flatpak IDs exist on Flathub before adding
14. **NEVER** modify validation workflows without understanding impact on PR checks

## Analysis vs Implementation

**Answer first, implement when asked.** Provide analysis before making changes. Don't implement unless explicitly asked.

## Attribution Requirements

AI agents must disclose what tool and model they are using in the "Assisted-by" commit footer:

```text
Assisted-by: [Model Name] via [Tool Name]
```

---

**Last Updated**: 2026-08-04
**Template Version**: finpilot (Agent UX Overhaul)
**Maintainer**: Universal Blue Community
