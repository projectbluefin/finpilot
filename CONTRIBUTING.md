# CONTRIBUTING

Thanks for helping out!

Check the [Contributing Guide](https://docs.projectbluefin.io/contributing) for contribution information.

This repository is for building the images, you are probably looking for [@projectbluefin/common](https://github.com/projectbluefin/common) to change something in Bluefin. Make sure you check [the architecture diagram](https://docs.projectbluefin.io/contributing#understanding-bluefins-architecture).

## Agent-Driven Development Workflow

This repository uses a **two-branch delivery model**: `main` is the testing
branch and `stable` is the production branch. pull[bot] promotes tested
commits from `main` to `stable` (see `.github/pull.yml`).

The 8-step workflow:

1. Create a focused feature branch from `main`.
2. Use [Conventional Commits](.github/commit-convention.md) for every commit.
3. Open a pull request targeting `main`, never `stable`.
4. Merge after all required validation and build checks pass.
5. Verify the new `:stable-testing` image published from `main`.
6. Wait for pull[bot] to open a promotion pull request from `main` to `stable`.
7. Review and approve the promotion only after the candidate has been tested.
8. Merge the promotion to publish the production `:stable` image.

**For AI agents:** Always target `main`, use Conventional Commits, follow the
validation instructions in `AGENTS.md` (shellcheck/YAML checks before
committing), and never push directly to `stable`. Production promotion is left
to a human reviewer.

**For humans:** Review feature pull requests, test `:stable-testing` on a real
machine before approving, and merge pull[bot] promotion pull requests only
when the candidate is ready for production.
