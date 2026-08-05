---
name: finpilot-packages
description: >-
  Decision tree for where to add packages in finpilot. Maps requests to the
  correct file and install method: build-time dnf5, runtime Brewfile, or
  runtime Flatpak. Use when deciding how to add a new package or tool.
---

# finpilot Package Decision Tree

## When to Use

- A user or agent asks "how do I add package X?"
- You need to decide whether a package belongs in build-time or runtime
- Reviewing a PR that adds packages and verifying they are in the right place
- Creating new build scripts or Brewfiles/Flatpak preinstall files

## When NOT to Use

- You already know the target file and install method — go edit it directly
- You are debugging why a package fails to install — use `finpilot-troubleshooting`

## Core Process

1. **Identify the package type** (system utility, CLI tool, GUI app, service)
2. **Use the decision table below** to map it to the correct path
3. **Apply the installation pattern** for that path
4. **Consider scope**: doc tasks (no CI impact) vs CI tasks (trigger validation/build)

## Decision Table

| Request                        | Action                                        | Location                             |
| ------------------------------ | --------------------------------------------- | ------------------------------------ |
| Add a system package (dnf5)    | `dnf5 install -y pkg`                         | `build/10-build.sh`                  |
| Add a COPR package             | `copr_install_isolated "owner/repo" pkg`      | `build/10-build.sh` (or `20-*.sh`)   |
| Add a third-party repo package | Enable repo → `dnf5 install -y` → remove repo | `build/20-*.sh` (see examples)       |
| Add a CLI tool (runtime)       | `brew "pkg"`                                  | `custom/brew/default.Brewfile`       |
| Add a dev environment tool     | `brew "pkg"`                                  | `custom/brew/development.Brewfile`   |
| Add a font                     | `brew "font-xyz"`                             | `custom/brew/fonts.Brewfile`         |
| Add a GUI app                  | `[Flatpak Preinstall org.app.id]`             | `custom/flatpaks/default.preinstall` |
| Add a user command             | Create shortcut (NO dnf5)                     | `custom/ujust/*.just`                |
| Enable a systemd service       | `systemctl enable service.name`               | `build/10-build.sh`                  |
| Replace desktop environment    | Remove old → install new → set default        | `build/30-*.sh` (see examples)       |
| Switch base image              | Update `FROM` line                            | `Containerfile`                      |
| Add OCI containers             | Uncomment/add `COPY --from=`                  | `Containerfile` ctx stage            |
| Add NVIDIA GPU support         | Rename `40-nvidia.sh.example`, then add its RUN block after `10-build.sh` | `build/40-nvidia.sh` |

## Build-Time: `build/10-build.sh`

System packages are installed at build-time and baked into the container image.

**Example:**

```bash
# In build/10-build.sh
dnf5 install -y vim git htop neovim tmux
systemctl enable podman.socket
```

**When to use:**

- System utilities and services
- Dependencies required for other build-time operations
- Packages needed immediately on first boot
- Services that need `systemctl enable`

**Rules:**

- Always use `dnf5` (never `dnf`, `yum`, or `rpm-ostree`)
- Always use `-y` flag for non-interactive installs
- For COPR repositories, use `copr_install_isolated` pattern and disable after use
- Group related `dnf5 install` commands together for efficient layer caching

## COPR: `copr_install_isolated`

Community repositories must be isolated to prevent repo persistence.

**Example:**

```bash
source /ctx/build/copr-helpers.sh
copr_install_isolated "ublue-os/staging" package-name
```

**What `copr_install_isolated` does:**

1. Enables the COPR repo
2. Installs the specified package(s)
3. Disables the COPR repo

**Never leave a COPR enabled after install.**

## Third-Party Repos: `build/20-*.sh`

For Google Chrome, 1Password, VS Code, etc. Follow the example scripts.

**Pattern:**

1. Add GPG key (if required)
2. Create repo file in `/etc/yum.repos.d/`
3. `dnf5 install -y` the package(s)
4. **CRITICAL**: Remove the repo file at end of script

See `build/20-onepassword.sh.example` for a complete working example.

## Runtime Brew: `custom/brew/*.Brewfile`

Homebrew is for CLI tools and development environments, installed by users
after first boot. File locations, syntax, and validation:
`finpilot-custom`.

## Runtime Flatpak: `custom/flatpaks/*.preinstall`

Flatpaks are for GUI apps, installed post-first-boot (not in the ISO or
container). INI syntax, `Branch=stable`, Flathub ID lookup, and validation:
`finpilot-custom`.

## Scope Rules

### Doc Tasks (No CI Impact)

README edits, comments, `.gitignore`, and `custom/ujust/README.md` trigger no CI.

### CI Tasks (Trigger Validation/Build)

Which `validate-*.yml` workflow fires for your file type — see the Workflow Map
in `finpilot-ci`.

## Common Rationalizations

| Rationalization                                                           | Reality                                                                                                                         |
| ------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| "I'll put this CLI tool in `build/10-build.sh` so it's always available." | Build-time packages bloat the image and slow updates. Runtime Brew is preferred for CLI tools that users can install on demand. |
| "I'll add a GUI app via dnf5 so it works offline."                        | Flatpaks are the standard for GUI apps. They update independently and avoid base image bloat.                                   |
| "COPR packages are safe to leave enabled."                                | Enabled COPRs persist and can cause conflicts on updates. Always use `copr_install_isolated`.                                   |
| "I'll just add the package to the example script and rename it later."    | Active `.sh` scripts run on every build. Only `.example` files are inactive. Rename carefully.                                  |

## Red Flags

- Using `dnf` or `yum` instead of `dnf5`
- Leaving a COPR enabled after install
- Not removing a third-party repo file after package install
- Adding GUI apps via `dnf5` instead of Flatpak
- Adding CLI tools to `build/10-build.sh` without considering runtime Brew first
- Modifying `build/*.example` files without renaming to `.sh`

## Verification

- [ ] Does the package type match the chosen installation method?
- [ ] For build-time: does it use `dnf5 install -y`?
- [ ] For COPR: is `copr_install_isolated` used?
- [ ] For third-party repo: is the repo file removed at end of script?
- [ ] For Flatpak: is the app ID verified on Flathub?
- [ ] For Brewfile: does `brew bundle check --file` pass locally?
- [ ] Does the changed path trigger the correct `validate-*.yml` workflow?
