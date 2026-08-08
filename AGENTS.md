# Copilot Instructions for finpilot bootc Image Template

## Start here

Task-specific instructions are Agent Skills under
`.agents/skills/<skill-name>/SKILL.md`. Agents discover them automatically from
their descriptions. Use the matching skill before changing behavior; for an
unfamiliar multi-phase task, start with `finpilot-overview`, continue with the
domain skill, and finish with `finpilot-pr-checklist`. Not sure which skill
fits? Load `finpilot-router` — it owns the routing table. The skill index with
links lives in `.agents/skills/README.md`.

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
8. **ALWAYS** confirm with user before deviating from @ublue-os/bluefin patterns
9. **ALWAYS** run shellcheck/YAML validation before committing
10. **ALWAYS** follow numbered script convention: `10-*.sh`, `20-*.sh`, `30-*.sh`
11. **ALWAYS** validate that new Flatpak IDs exist on Flathub before adding
12. **NEVER** modify validation workflows without understanding impact on PR checks

## Analysis vs Implementation

**Answer first, implement when asked.** Provide analysis before making changes. Don't implement unless explicitly asked.

## Attribution Requirements

AI agents must disclose what tool and model they are using in the "Assisted-by" commit footer:

```text
Assisted-by: [Model Name] via [Tool Name]
```

---

## Factory workflow and ownership

Use the shared lifecycle and labels in
[`projectbluefin/common/docs/skills/label-workflow.md`](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md).
Humans triage and approve; agents work only on assigned or
`3-clanker-queue` issues. Clankers is authenticated Hive transport only, not
merge authority. Keep template-specific ownership local and never write to
`ublue-os/*`.

## Self-Improvement

Every session: ship the work and update the relevant skill file in
`.agents/skills/`. Same PR, not a follow-up.

Banned:
- No changelog files. Delete `IMPROVEMENTS.md`, `CHANGELOG.md`, and
  `SESSION.md` if found.
- No session notes committed to the repository.
- No "append here" documentation. Route durable learning to `.agents/skills/`.

Before marking work done:
- [ ] Discovered a workaround, pattern, or convention?
- [ ] Updated or created the relevant skill file?
- [ ] Included that learning in this PR?

**Last Updated**: 2026-08-05
**Template Version**: finpilot (Agent UX Overhaul)
**Maintainer**: Universal Blue Community
