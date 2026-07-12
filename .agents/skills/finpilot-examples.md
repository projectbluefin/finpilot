---
name: finpilot-examples
description: >-
  Index of runnable example scripts and the activation pattern. Covers
  existing .example files and how to activate them.
  Use when adding new build scripts or explaining the activation pattern to
  contributors.
metadata:
  context7-sources: []
---

# finpilot Example Scripts

## When to Use

- You need to add a third-party repository or desktop swap
- You want to understand the `.example` → `.sh` activation pattern
- You are creating a new build script and want a starting point
- You need to document a new pattern for contributors

## When NOT to Use

- You are modifying existing active `.sh` scripts directly — edit them, don't activate an example
- You are adding a simple package — use `build/10-build.sh` directly, no example needed

## Core Process

1. **Find the relevant example** in `build/` directory
2. **Copy and rename** from `.example` to `.sh`
3. **Customize** for your specific use case
4. **Validate** with `shellcheck` and `just build`
5. **Commit** (via PR to `main`)

## The Activation Pattern

All example scripts in `build/` follow the pattern:

1. **Inactive**: Named `NN-descriptive-name.sh.example`
2. **Active**: Rename to `NN-descriptive-name.sh`
3. **Execution**: Build scripts run in numerical order (`00-`, `10-`, `20-`, `30-`)

**Important:** Only `.sh` files are executed during the build. `.example` files are ignored.

## Existing Example Scripts

### `build/20-nvidia.sh.example`

**What it does:**

- Pulls pre-built NVIDIA akmods from `ghcr.io/ublue-os/akmods-nvidia-open`
- Installs NVIDIA driver (open kernel modules, CUDA, libnvidia-container)
- Configures CDI (Container Device Interface) GPU passthrough for Podman
- Writes bootc kernel args: nouveau blacklist + `nvidia-drm.modeset=1`
- Enables Mutter `kms-modifiers` for Wayland support on NVIDIA

**How to activate:**

```bash
cp build/20-nvidia.sh.example build/20-nvidia.sh
just build
```

All NVIDIA logic is self-contained in the script. When activated (renamed to `.sh`), it provisions NVIDIA support directly into the base image — no separate image variant needed. Deactivate by removing or renaming back to `.example`.

**Expected validation:**

- `pr-validation.yml` → shellcheck
- `build-image.yml` → full build test
- **Must test on actual NVIDIA hardware** — Wayland/modeset issues are not caught in CI

---

### `build/20-onepassword.sh.example`

**What it does:**

- Adds the 1Password repository
- Installs `1password` and `1password-cli`
- Removes the repo file after install (isolated install pattern)

**How to activate:**

```bash
cp build/20-onepassword.sh.example build/20-onepassword.sh
# Edit build/20-onepassword.sh to customize if needed
```

**Expected validation:**

- `pr-validation.yml` → shellcheck
- `build-image.yml` → full build test

---

### `build/30-cosmic-desktop.sh.example`

**What it does:**

- Removes the GNOME desktop environment
- Installs the COSMIC desktop environment from COPR
- Sets the default graphical target

**How to activate:**

```bash
cp build/30-cosmic-desktop.sh.example build/30-cosmic-desktop.sh
# Edit build/30-cosmic-desktop.sh to customize if needed
```

**Expected validation:**

- `pr-validation.yml` → shellcheck
- `build-image.yml` → full build test (significant change, test thoroughly)

---

## Creating New Example Scripts

When adding a new pattern that others might reuse, create an `.example` file:

1. **Name it** with the correct prefix: `20-` for third-party repos, `30-` for desktop swaps
2. **Include comments** explaining what it does and how to customize
3. **Follow conventions**: `set -euo pipefail`, `dnf5`, `copr_install_isolated` for COPRs
4. **Add to this skill** (or `AGENTS.md`) so agents know it exists

### Template for New Examples

```bash
#!/usr/bin/env bash
set -euo pipefail

# Description: [What this script does]
# Activate by: cp build/NN-name.sh.example build/NN-name.sh
# Customize: [What to change]

# Example: Add a third-party repository
# dnf config-manager addrepo --from-repofile=https://example.com/repo.repo
# dnf5 install -y package-name
# rm -f /etc/yum.repos.d/example.repo  # Clean up repo file
```

## Validation by Example Type

| Example                      | Shellcheck | Build Test | Additional Validation                   |
| ---------------------------- | ---------- | ---------- | --------------------------------------- |
| Third-party repo (`20-*.sh`) | Yes        | Yes        | Verify repo URL accessible              |
| Desktop swap (`30-*.sh`)     | Yes        | Yes        | Test in VM (`just run-vm-qcow2`)        |
| COPR install (`20-*.sh`)     | Yes        | Yes        | Verify COPR exists and packages install |
| NVIDIA GPU (`20-*.sh`)       | Yes        | Yes        | Test on NVIDIA hardware; verify `nvidia-smi` after boot |

## Link to Package Decision Tree

For deciding whether to use an example script or add directly to `build/10-build.sh`, see `finpilot-packages.md`.

**Quick guide:**

- Simple system packages → `build/10-build.sh`
- Third-party repo or complex install → `build/20-*.sh` (activate an example or create new)
- Desktop environment swap → `build/30-*.sh` (activate an example or create new)

## Common Rationalizations

| Rationalization                                              | Reality                                                                                                  |
| ------------------------------------------------------------ | -------------------------------------------------------------------------------------------------------- |
| "I'll just add my script directly — no need for an example." | If the pattern is reusable, an example helps future contributors. If it's one-off, add to `10-build.sh`. |
| "I'll leave it as `.example` and never rename it."           | `.example` files are ignored in the build. They must be renamed to `.sh` to have any effect.             |
| "I modified the `.example` file — that should be enough."    | The build only runs `.sh` files. Modify the `.example`, then rename to `.sh`.                            |

## Red Flags

- `.example` file modified but not renamed to `.sh`
- New `.sh` file without `set -euo pipefail`
- Script using `dnf` or `yum` instead of `dnf5`
- COPR repo not disabled after install
- Third-party repo file not removed after install
- Missing shellcheck validation before committing

## Verification

- [ ] Did you rename the `.example` file to `.sh`?
- [ ] Did you run `shellcheck` on the new `.sh` file?
- [ ] Did the build succeed with `just build`?
- [ ] For desktop swaps: did you test in a VM (`just run-vm-qcow2`)?
- [ ] For desktop swaps: did you verify the new session works at the login screen?
- [ ] Did you document the new pattern in `AGENTS.md` or this skill?
