Use @projectbluefin/finpilot as a template, name the OS the repository name. Ensure the entire operating system is bootstrapped. Ensure all github actions are enabled and running. Ensure the README has the GitHub setup instructions for keyless image signing and the other steps required to finish the task.

**Phase 1 — Bootstrap (Do this first):**

1. Rename `finpilot` to the repository name in exactly 7 files (see README section "2. Rename the Project")
2. Enable GitHub Actions and set `RENOVATE_TOKEN` (Classic PAT with `repo` + `workflow`)
3. Create `stable` from `main`, replace `OWNER` in `.github/pull.yml`, and install the pull GitHub App
4. Protect `main` and `stable`, with `validate` required on `main`
5. Enable auto-merge in repository settings
6. Trigger the first `:stable-testing` build on `main`, then approve promotion to `stable`

**Phase 2 — Customize:**

1. Read `.agents/skills/finpilot-packages.md` and add your first system package + first Flatpak/Brew entry
2. Update the README "What Makes this Raptor Different" section
3. Test locally with `just build && just build-qcow2 && just run-vm-qcow2`
4. Open a PR to `main`, merge once `validate` passes, test `:stable-testing`, and approve promotion

**Phase 3 — Production:**

1. Enable keyless signing by uncommenting the step in `.github/workflows/build-image.yml`
2. Verify with: `cosign verify --certificate-identity-regexp="https://github.com/USER/REPO/.github/workflows/" --certificate-oidc-issuer="https://token.actions.githubusercontent.com" ghcr.io/USER/REPO:stable`
3. Review `.agents/skills/finpilot-maintain.md` for ongoing maintenance schedule
