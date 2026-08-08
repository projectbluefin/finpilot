Use @projectbluefin/finpilot as a template, name the OS the repository name. Ensure the entire operating system is bootstrapped. Ensure all github actions are enabled and running. Ensure the README has the GitHub setup instructions for keyless image signing and the other steps required to finish the task.

**Phase 1 — Bootstrap (Do this first):**

1. Rename `finpilot` to the repository name in exactly 7 files (see README section "2. Rename the Project")
2. Enable GitHub Actions and set `RENOVATE_TOKEN` (Classic PAT with `repo` + `workflow`)
3. Configure branch protection on `main` with `validate` as required status check
4. Enable auto-merge in repository settings
5. Trigger first green build (push to `main` or run workflow manually)

**Phase 2 — Customize:**

1. Use the `finpilot-packages` skill and add your first system package + first Flatpak/Brew entry
2. Update the README "What Makes this Raptor Different" section
3. Test locally with `just build && just build-qcow2 && just run-vm-qcow2`
4. Open a PR and merge once `validate` passes

**Phase 3 — Production:**

1. Enable keyless signing by uncommenting the step in `.github/workflows/build-image.yml`
2. Verify with: `cosign verify --certificate-identity-regexp="https://github.com/USER/REPO/.github/workflows/" --certificate-oidc-issuer="https://token.actions.githubusercontent.com" ghcr.io/USER/REPO:stable`
3. Use the `finpilot-maintain` skill for the ongoing maintenance schedule

For issue and PR workflow, use the shared [label workflow](https://github.com/projectbluefin/common/blob/main/docs/skills/label-workflow.md).
Humans triage and approve; agents work only on assigned or `3-clanker-queue`
issues. Clankers only transports Hive assignments, and `ublue-os/*` is read-only.
