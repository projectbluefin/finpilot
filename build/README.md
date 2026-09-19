# Build scripts

Scripts that run during image assembly. The Containerfile names each one in its
own `RUN` block, so the order is whatever the Containerfile says — there is no
prefix auto-discovery. The numbers communicate intent.

## Phases

| Script | Does |
|---|---|
| `00-image-info.sh` | Writes the image identity into `os-release` and `image-info.json`: the base image name, the Fedora major derived from the base's `os-release`, the version string, and the tag. |
| `10-overlay.sh` | Overlays `projectbluefin/common`'s shared layer and the Brew integration, copies this template's declarations (Brewfiles, ujust recipes, Flatpak preinstalls, `/etc/skel` seeds), and enables the units that consume them. Installs no packages. |
| `20-packages-and-services.sh` | Installs the default RPM and COPR packages and enables their services. Packages live here, not in the overlay phase, so an overlay edit cannot invalidate the package layer. |
| `90-cleanup.sh` | Finalises package and Flatpak sources, prunes build artifacts, and prepares for `bootc container lint`. |

Helpers, not phases: `copr-helpers.sh` (sourced), `validate-brewfiles.sh`, and
`validate-flatpaks.sh` (called by the Justfile and CI).

## Examples

Inactive until you activate them:

- `30-tailscale.sh.example` — a third-party RPM repository done safely
- `40-gnome-extensions.sh.example` — GNOME Shell extensions with a dconf override
- `50-nvidia.sh.example` — NVIDIA drivers and CDI container support
- `60-desktop-swap.sh.example` — replacing the GNOME desktop

To activate one, rename it off `.example` and add a `RUN` block to the
Containerfile after the package phase and before the cleanup phase. Copy the
shape below and substitute your script's path:

```dockerfile
RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    --mount=type=cache,dst=/var/cache/libdnf5 \
    --mount=type=cache,dst=/var/cache/rpm-ostree \
    --mount=type=tmpfs,dst=/boot \
    --mount=type=tmpfs,dst=/tmp \
    /ctx/build/NN-example.sh
```

Deactivating is the reverse: delete the block, rename the file back.

## Writing one

```bash
#!/usr/bin/env bash
set -euo pipefail

dnf5 install -y package-name
```

- Scripts run as root, with the build context at `/ctx`.
- Use `dnf5`, never `dnf` or `yum`, and always `-y`.
- Disable any repository you enable. `copr_install_isolated` does it for COPRs.
- Keep one purpose per script, and name it for that purpose.
