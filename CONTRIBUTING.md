# CONTRIBUTING

Thanks for helping out!

Check the [Contributing Guide](https://docs.projectbluefin.io/contributing) for contribution information.

This repository is for building the images, you are probably looking for [@projectbluefin/common](https://github.com/projectbluefin/common) to change something in Bluefin. Make sure you check [the architecture diagram](https://docs.projectbluefin.io/contributing#understanding-bluefins-architecture).

## Agent-Driven Development Workflow

This repository uses a two-branch testing/stable workflow with automatic promotion via [pull[bot]](https://github.com/apps/pull).

### The Workflow

1. **Create a feature branch** from `main` and open a PR targeting `main`
2. **PR triggers CI**: build validation, Brewfile/Flatpak/Justfile/shellcheck checks
3. **Merge the PR** once all checks pass
4. **Testing image builds**: `main` push triggers `:stable-testing` image
5. **pull[bot] promotes**: Auto-creates a PR from `main` → `stable`
6. **Review the promotion PR**: Verify changes look good
7. **Approve and merge**: Triggers `:stable` production image build

### For AI Agents

- **Always target `main`** for feature branches and PRs
- **Use conventional commits** for all commits (see `.github/commit-convention.md`)
- **Never push directly to `stable`** — use pull[bot] for promotion
- **Run pre-commit checks** before committing (shellcheck, YAML validation, Justfile syntax)

### For Humans

- **Review PRs** targeting `main` for correctness
- **Test images** using `:stable-testing` tag before approving promotion
- **Review and approve** pull[bot] promotion PRs to `stable`
- **Replace `OWNER`** in `.github/pull.yml` with your GitHub username after installing the pull App
