# Build Scripts

This directory contains build scripts used during image creation. The default Containerfile explicitly runs the required scripts; extra scripts must be explicitly added to the Containerfile.

## How It Works

Scripts are named with a number prefix (e.g., `10-build.sh`, `20-onepassword.sh`) and run in ascending order during the container build process.

## Included Scripts

- **`10-build.sh`** - Main build script for base system modifications, package installation, and service configuration

## Example Scripts

- **`20-onepassword.sh.example`** - Example showing how to install software from third-party RPM repositories (Google Chrome, 1Password)
- **`30-cosmic-desktop.sh.example`** - Example showing how to replace the GNOME desktop with COSMIC desktop
- **`40-nvidia.sh.example`** - Example showing how to add NVIDIA drivers and CDI container support

To use an example script:
1. Rename it to remove the `.example` extension (for example, `mv build/20-onepassword.sh.example build/20-onepassword.sh`).
2. Add the standard `RUN` block below after the `10-build.sh` block in `Containerfile`, replacing `NN-example.sh` with the renamed script.
3. Run `just build`.

```dockerfile
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=secret,id=GITHUB_TOKEN \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/NN-example.sh
```

## Creating Your Own Scripts

Create numbered scripts for different purposes:

```bash
# 10-build.sh - Base system (already exists)
# 20-drivers.sh - Hardware drivers
# 30-development.sh - Development tools
# 40-gaming.sh - Gaming software
# 50-cleanup.sh - Final cleanup tasks
```

### Script Template

```bash
#!/usr/bin/env bash
set -oue pipefail

echo "Running custom setup..."
# Your commands here
```

### Best Practices

- **Use descriptive names**: `40-nvidia.sh` is better than `40-stuff.sh`
- **One purpose per script**: Easier to debug and maintain
- **Clean up after yourself**: Remove temporary files and disable temporary repos
- **Test incrementally**: Add one script at a time and test builds
- **Comment your code**: Future you will thank present you

### Disabling Scripts

To disable an activated script, remove its corresponding `RUN` block from `Containerfile` and rename it back to `.example` (or remove it).

## Execution Order

The template runs scripts explicitly, rather than automatically discovering files by prefix. Place extra script blocks after `10-build.sh` and before `clean-stage.sh`. Use numbered names to communicate the intended order.

## Notes

- Scripts run as root during build
- Build context is available at `/ctx`
- Use dnf5 for package management (not dnf or yum)
- Always use `-y` flag for non-interactive installs
