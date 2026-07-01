---
name: finpilot-troubleshooting
description: >-
  Consolidated symptom-cause-fix table for finpilot. Covers local build failures,
  CI failures, runtime issues, Renovate problems, COPR persistence, and ujust
  command not found. Use when something is broken and you need a quick diagnosis.
metadata:
  context7-sources: []
---

# finpilot Troubleshooting

## When to Use

- A local build fails and you need to diagnose the cause
- CI is failing on a PR and the error is unclear
- A runtime issue appears after deployment (missing packages, failed services)
- Renovate is not creating PRs or is failing
- A COPR repo seems to persist across builds
- A `ujust` command is not found or not working

## When NOT to Use

- You are still setting up the fork for the first time — see `finpilot-onboarding.md`
- You are deciding where to add a package — see `finpilot-packages.md`
- You need to plan ongoing maintenance — see `finpilot-maintain.md`

## Core Process

1. **Identify the symptom** from the tables below
2. **Check the likely cause**
3. **Apply the solution**
4. **Verify the fix**

## Local Build Failures

| Symptom                                | Cause                                                                        | Solution                                                                                    |
| -------------------------------------- | ---------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Build fails: "permission denied"       | Signing misconfigured or signing step uncommented without proper permissions | Verify signing step is commented out OR `id-token: write` permission is granted in workflow |
| Build fails: "package not found"       | Typo in package name, or package unavailable in configured repos             | Check spelling, verify on RPMfusion, add COPR if needed                                     |
| Build fails: "base image not found"    | Invalid `FROM` line or digest mismatch                                       | Check Containerfile syntax, verify base image tag and digest                                |
| Build fails: "shellcheck error"        | Script syntax error in `build/*.sh`                                          | Run `shellcheck build/*.sh` locally, fix errors                                             |
| `bootc container lint` fails           | Missing cleanup, leftover artifacts, or invalid image structure              | Run `build/clean-stage.sh` manually, check for stray files in `/opt` or `/var`              |
| Podman/Docker not found                | Container runtime not installed                                              | Install `podman` or `docker`, ensure daemon is running                                      |
| Base image pull fails                  | Network issue or invalid digest                                              | Verify network, check digest is correct, try `podman pull <base-image>` manually            |
| Multi-stage build fails at `ctx` stage | Missing `COPY --from=` or invalid OCI image reference                        | Verify OCI image names and digests in `Containerfile` ctx stage                             |
| `just build` fails immediately         | `just` not installed or `Justfile` syntax error                              | Run `just --list`, check `Justfile` for syntax errors                                       |

## CI Failures

| Symptom                                    | Cause                                              | Solution                                                                  |
| ------------------------------------------ | -------------------------------------------------- | ------------------------------------------------------------------------- |
| PR validation fails: shellcheck            | Syntax error in modified `.sh` file                | Run `shellcheck build/*.sh` locally, fix errors                           |
| PR validation fails: hadolint              | Dockerfile lint rule violation                     | Check `.hadolint.yaml` for allowed suppressions, fix or document new ones |
| PR validation fails: Brewfile              | Invalid Brewfile syntax                            | Check Ruby syntax, ensure packages exist (`brew search`)                  |
| PR validation fails: Flatpak               | Invalid app ID                                     | Verify app ID exists on https://flathub.org/                              |
| PR validation fails: justfile              | Invalid just syntax                                | Run `just --list` locally to test, fix syntax                             |
| CI build fails: workflow permissions       | Missing `id-token: write` or `packages: write`     | Verify `.github/workflows/build-image.yml` has correct permissions        |
| CI build fails: token health               | `RENOVATE_TOKEN` or `GITHUB_TOKEN` invalid/expired | Check token expiry, verify scopes, regenerate if needed                   |
| CI build fails: signing misconfig          | Signing step uncommented but OIDC not configured   | Comment out signing step OR verify OIDC trust in repo settings            |
| CI build fails: composite action not found | Wrong commit SHA or repo name in `uses:`           | Verify `projectbluefin/actions` SHA, check network access                 |
| CI build succeeds but image not published  | Wrong `IMAGE_NAME` or `IMAGE_VENDOR`               | Check `Containerfile` ARGs, verify `clean.yml` package name matches       |

## Runtime Issues

| Symptom                                 | Cause                                                       | Solution                                                                                                                        |
| --------------------------------------- | ----------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| Flatpaks not installed                  | Expected behavior — they install post-first-boot            | Ensure internet connection on first boot, or run `ujust install-default-apps`                                                   |
| Brew missing or not found               | Homebrew not extracted yet or service failed | Run `systemctl status brew-setup.service`. Homebrew is extracted on first boot via systemd service, not user-installed. Check `/var/home/linuxbrew/.linuxbrew/bin/brew` |
| `bootc switch` fails                    | Wrong image URL or missing registry credentials             | Verify bootc switch URL matches your repo (see `iso/iso.toml`), check registry access                                           |
| `bootc switch` fails: "image not found" | Image not yet published to GHCR                             | Trigger a build on `main`, verify image appears under Packages                                                                  |
| Service not starting                    | Service not enabled or missing dependency                   | Check `systemctl status service.name`, verify `systemctl enable` in `build/10-build.sh`                                         |
| Missing package after boot              | Installed in wrong layer or runtime vs build-time confusion | Check if it's in `build/10-build.sh` (build-time) or `custom/brew/` (runtime)                                                   |
| `/opt` is not writable                  | `/opt` is symlinked to `/var/opt` by default                | In `Containerfile`, replace `RUN rm -rf /opt && ln -s /var/opt /opt` with `RUN rm /opt && mkdir /opt` if immutability is needed |

## Renovate Issues

| Symptom                       | Cause                                              | Solution                                                                   |
| ----------------------------- | -------------------------------------------------- | -------------------------------------------------------------------------- |
| Renovate not creating PRs     | `RENOVATE_TOKEN` missing, expired, or wrong scopes | Verify token is Classic PAT with `repo` + `workflow`, regenerate if needed |
| Renovate PRs fail CI          | Renovate branch is out of date with `main`         | Rebase Renovate branch, or close and let Renovate recreate                 |
| Renovate updates wrong files  | Misconfigured `renovate.json`                      | Run `renovate-config-validator .github/renovate.json`, fix regex patterns  |
| Renovate creates too many PRs | Broad match in `renovate.json`                     | Scope `matchPackageNames` or `matchPaths` more narrowly                    |
| Renovate workflow times out   | Large number of repositories or heavy load         | Check Renovate logs, increase timeout, or run manually                     |

## COPR Persistence Issues

| Symptom                                 | Cause                                                         | Solution                                                                                      |
| --------------------------------------- | ------------------------------------------------------------- | --------------------------------------------------------------------------------------------- |
| COPR packages missing after boot        | COPR not disabled correctly, repo persists but packages don't | Use `copr_install_isolated` from `build/copr-helpers.sh` — it enables, installs, and disables |
| COPR conflicts on update                | Multiple COPRs enabled simultaneously                         | Ensure all COPRs are disabled after install, use isolated installs only                       |
| `dnf5 copr list` shows unexpected repos | Old COPR not cleaned up                                       | Remove repo files from `/etc/yum.repos.d/` if not managed by `copr_install_isolated`          |

## ujust Command Not Found

| Symptom                                | Cause                                                           | Solution                                                                             |
| -------------------------------------- | --------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| `ujust` not found                      | `ujust` not in PATH, or shell not reloaded                      | Open a new terminal, or source shell profile (`source ~/.bashrc`)                    |
| `ujust --list` missing custom commands | `.just` files not copied during build                           | Verify `custom/ujust/*.just` files exist and are copied in `build/10-build.sh`       |
| `ujust my-command` fails               | Script error in `.just` file                                    | Run `just --list` to check syntax, or run the script block manually for error output |
| `ujust install-default-apps` fails     | Brew not installed or Brewfile path wrong                       | Verify brew is installed, check `BREWFILE` path in the just command                  |
| ujust on ISO vs installed system       | ujust commands may differ between live ISO and installed system | Ensure commands are designed for the target environment (ISO vs installed)           |

## Common Rationalizations

| Rationalization                                                   | Reality                                                                                                                                              |
| ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------- |
| "The build failed in CI but works locally — it must be a CI bug." | CI is the source of truth. Local environments often have cached layers or different podman versions. Start with `just build` on a clean environment. |
| "Renovate is broken — it hasn't made a PR in days."               | Renovate runs on a schedule (default 6h). Check the workflow run logs before assuming failure.                                                       |
| "I don't need to run shellcheck locally — CI will catch it."      | Running `shellcheck` locally is faster and keeps CI queues free. It's a 5-second check.                                                              |
| "The COPR was disabled, so it can't be the problem."              | Repo files can persist in `/etc/yum.repos.d/` even if `copr` metadata is gone. Check the directory directly.                                         |

## Red Flags

- Skipping local `just build` before opening a PR
- Ignoring CI failures because "it worked on my machine"
- Manually updating digests in `Containerfile` instead of using Renovate
- Leaving COPRs enabled after install
- Not verifying app IDs on Flathub before adding to `.preinstall`
- Pushing fixes directly to `main` instead of opening a PR

## Verification

- [ ] Did you identify the correct category (local, CI, runtime, Renovate, COPR, ujust)?
- [ ] Did you check the symptom-cause table for your specific error?
- [ ] Did you apply the recommended solution?
- [ ] Did you verify the fix by running the relevant test (build, just --list, etc.)?
- [ ] If the issue persists, did you check the workflow logs or run with verbose output (`--log-level=debug`)?
