# CONTRIBUTING

Thanks for helping out!

Check the [Contributing Guide](https://docs.projectbluefin.io/contributing) for general contribution information.

This repository builds custom images. Changes to shared Bluefin behavior usually belong in [@projectbluefin/common](https://github.com/projectbluefin/common); see the [architecture diagram](https://docs.projectbluefin.io/contributing#understanding-bluefins-architecture) before opening a pull request.

## Agent-Driven Development Workflow

1. Create a focused feature branch from `main`.
2. Use Conventional Commits for every commit.
3. Open a pull request targeting `main`, never `stable`.
4. Merge after all required validation and build checks pass.
5. Verify the new `:stable-testing` image from `main`.
6. Wait for pull[bot] to open a promotion pull request to `stable`.
7. Review and approve the promotion after testing.
8. Merge the promotion to publish the production `:stable` image.

AI agents must always target `main`, follow repository validation instructions, and leave production promotion to a human reviewer. Human maintainers should review feature pull requests, test `:stable-testing`, and approve pull[bot] promotion pull requests only when the candidate is ready for production.
