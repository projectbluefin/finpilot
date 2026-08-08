# CONTRIBUTING

Thanks for helping out!

Check the [Contributing Guide](https://docs.projectbluefin.io/contributing) for contribution information.

This repository is for building the images, you are probably looking for [@projectbluefin/common](https://github.com/projectbluefin/common) to change something in Bluefin. Make sure you check [the architecture diagram](https://docs.projectbluefin.io/contributing#understanding-bluefins-architecture).

## Agent-Driven Development Workflow

Finpilot uses a two-branch testing & production pipeline managed by pull[bot]:

### Workflow Steps
1. **Branch**: Create a feature branch off `main`.
2. **PR**: Open a PR targeting `main` with conventional commit titles.
3. **Validate**: CI runs validation checks on the PR (`validate` workflow).
4. **Testing Build**: Merging into `main` builds and publishes a `:stable-testing` container image.
5. **pull[bot] Promotion**: [pull[bot]](https://github.com/apps/pull) automatically creates a promotion PR from `main` → `stable`.
6. **Local Testing**: Test the `:stable-testing` image locally (`sudo bootc switch ...:stable-testing`).
7. **Approve Promotion**: Review and merge pull[bot]'s PR into `stable`.
8. **Production Build**: Merging into `stable` builds and publishes the production `:stable` container image.

### Guidelines
- **For AI Agents**: Always target `main` for PRs. Always use conventional commit messages. Never push directly to `main` or `stable`.
- **For Maintainers**: Review feature PRs to `main`, test `:stable-testing` builds, and merge pull[bot] promotion PRs when ready for production release.
