# finpilot

A template for building custom bootc operating system images based on the lessons from [Universal Blue](https://universal-blue.org/) and [Bluefin](https://projectbluefin.io). It is designed to be used manually, but is optimized to be bootstraped by GitHub Copilot. After set up you'll have your own custom Linux.

This template uses the **multi-stage build architecture** from @projectbluefin/distroless, combining resources from multiple OCI containers for modularity and maintainability. See the [Architecture](#architecture) section below for details.

**Unlike previous templates, you are not modifying Bluefin and making changes.**: You are assembling your own Bluefin in the same exact way that Bluefin, Aurora, and Bluefin LTS are built. This is way more flexible and better for everyone since the image-agnostic and desktop things we love about Bluefin lives in @projectbluefin/common.

Instead, you create your own OS repository based on this template, allowing full customization while leveraging Bluefin's robust build system and shared components.

> Be the one who moves, not the one who is moved.

## What Makes this Raptor Different?

Here are the changes from [Base Image Name]. This image is based on [Bluefin/Bazzite/Aurora/etc] and includes these customizations:

### Added Packages (Build-time)

- **System packages**: tmux, micro, mosh - [brief explanation of why]

### Added Applications (Runtime)

- **CLI Tools (Homebrew)**: neovim, helix - [brief explanation]
- **GUI Apps (Flatpak)**: Spotify, Thunderbird - [brief explanation]

### Removed/Disabled

- List anything removed from base image

### Configuration Changes

- Any systemd services enabled/disabled
- Desktop environment changes
- Other notable modifications

_Last updated: [date]_

> Replace the placeholders above with your actual customizations whenever you add or remove packages, apps, or configuration. This section is what tells users how your image differs from the base.

## Guided Copilot Mode

This template works best with **phased prompts** that let Copilot bootstrap your image in three stages.

### Phase 1 — Bootstrap

Use this prompt first to get your fork building:

```
Bootstrap a new custom OS from @projectbluefin/finpilot. Name it after this repository. Read `.agents/skills/finpilot-onboarding.md` first, then:
1. Rename `finpilot` in the 7 required files
2. Enable GitHub Actions and set RENOVATE_TOKEN (repo + workflow scopes)
3. Configure branch protection for `main` with `validate` as a required status check
4. Enable auto-merge
5. Trigger the first green build on `main`
6. Add the "What Makes this Raptor Different" section to README.md (with placeholders)
```

### Phase 2 — Customize

Once the first build is green, use this prompt to add packages:

```
Read `.agents/skills/finpilot-packages.md` and `.agents/skills/finpilot-custom.md`, then:
1. Add one system package to the image in `build/10-build.sh`
2. Add one CLI tool to `custom/brew/default.Brewfile`
3. Add one GUI app to `custom/flatpaks/default.preinstall`
4. Add shortcuts in `custom/ujust/custom-apps.just` to install them
5. Update the README "What Makes this Raptor Different" section with the new entries
6. Run `just build && just build-qcow2 && just run-vm-qcow2` to verify locally
7. Open a PR and merge once `validate` passes
```

### Phase 3 — Production

When you are ready for production, use this prompt to harden the setup:

```
Read `.agents/skills/finpilot-maintain.md` and `.agents/skills/finpilot-ci.md`, then:
1. Enable keyless image signing by uncommenting the step in `.github/workflows/build-image.yml`
2. Verify the cosign command works: cosign verify --certificate-identity-regexp="https://github.com/USER/REPO/.github/workflows/" --certificate-oidc-issuer="https://token.actions.githubusercontent.com" ghcr.io/USER/REPO:stable
3. Review the maintenance schedule in `finpilot-maintain.md`
```

## What's Included

### Build System

- Automated builds via GitHub Actions on every commit
- Self-hosted Renovate for automated dependency updates
- Automatic cleanup of old images (90+ days) to keep it tidy
- Pull request workflow - test changes before merging to main
  - PRs build and validate before merge
  - `main` branch builds `:stable` images
- Validates your files on pull requests so you never break a build:
  - Brewfile, Justfile, ShellCheck, Renovate config, and it'll even check to make sure the flatpak you add exists on FlatHub
- Production Grade Features
  - Container signing with keyless OIDC
  - See checklist below to enable these as they take some manual configuration

### Homebrew Integration

- Pre-configured Brewfiles for easy package installation and customization
- Includes curated collections: development tools, fonts, CLI utilities. Go nuts.
- Users install packages at runtime with `brew bundle`, aliased to premade `ujust commands`
- See [custom/brew/README.md](custom/brew/README.md) for details

### Flatpak Support

- Ship your favorite flatpaks
- Automatically installed on first boot after user setup
- See [custom/flatpaks/README.md](custom/flatpaks/README.md) for details

### ujust Commands

- User-friendly command shortcuts via `ujust`
- Pre-configured examples for app installation and system maintenance for you to customize
- See [custom/ujust/README.md](custom/ujust/README.md) for details

### Build Scripts

- Modular numbered scripts (10-, 20-, 30-) run in order
- Example scripts included for third-party repositories and desktop replacement
- Helper functions for safe COPR usage
- See [build/README.md](build/README.md) for details

## Quick Start

### 1. Create Your Repository

Click "Use this template" to create a new repository from this template.

### 2. Rename the Project

Important: Change `finpilot` to your repository name in these 7 files:

1. `Containerfile` (`# Name:` comment and `ARG IMAGE_NAME`): `# Name: your-repo-name`
2. `Justfile` (`export IMAGE_NAME := env("IMAGE_NAME", ...)`): `your-repo-name`
3. `README.md` (title): `# your-repo-name`
4. `artifacthub-repo.yml` (`repositoryID`): `repositoryID: your-repo-name`
5. `custom/ujust/README.md` (bootc switch example): `localhost/your-repo-name:stable`
6. `.github/workflows/clean.yml` (`packages`): `packages: your-repo-name`
7. `iso/iso.toml` (bootc switch URL): `ghcr.io/YOUR_USERNAME/your-repo-name:stable`

### 3. Enable GitHub Actions

- Go to the "Actions" tab in your repository
- Click "I understand my workflows, go ahead and enable them"

Your first build will start automatically!

Note: Image signing is disabled by default. Your images will build successfully without any signing keys. Once you're ready for production, see "Optional: Enable Image Signing" below.

### 4. Enable Renovate (Required)

Renovate automatically updates dependencies and GitHub Actions (including workflow files). This template uses a self-hosted Renovate runner via `projectbluefin/actions`.

**One-time setup:**

1. Go to GitHub → Settings → Developer settings → **Personal access tokens** → **Tokens (classic)**
2. Click **Generate new token (classic)**
3. Set a note like `renovate-finpilot`
4. Select scopes: **`repo`** (full control) and **`workflow`** (update workflows)
5. Click **Generate token** and copy the value
6. Go to your repository → Settings → Secrets and variables → Actions
7. Add a new secret: **`RENOVATE_TOKEN`** (paste the token value)
8. Enable **Settings → General → Pull Requests → Allow auto-merge** so Renovate can merge low-risk updates after checks pass
9. **Configure branch protection for `main`** (required for automerge to work):
   - Go to Settings → Branches → Add rule
   - Set **Branch name pattern** to `main`
   - Enable **"Require a pull request before merging"**
   - Enable **"Require status checks to pass before merging"**
   - Add `validate` as a required status check
   - Enable **"Require branches to be up to date before merging"** (recommended)

Renovate will run every 6 hours and on config changes. It pins GitHub Actions to SHAs and updates tracked image digests automatically.

### 5. Customize Your Image

Choose your base image in `Containerfile` (the `FROM` line):

```dockerfile
FROM quay.io/fedora-ostree-desktops/silverblue:44@sha256:...
```

Finpilot layers on top of Fedora Silverblue, not Bluefin. Bluefin's desktop
configuration is provided by `@projectbluefin/common` earlier in the build.

Add your packages in `build/10-build.sh`:

```bash
dnf5 install -y package-name
```

Customize your apps:

- Add Brewfiles in `custom/brew/` ([guide](custom/brew/README.md))
- Add Flatpaks in `custom/flatpaks/` ([guide](custom/flatpaks/README.md))
- Add ujust commands in `custom/ujust/` ([guide](custom/ujust/README.md))

### 6. Development Workflow

All changes should be made via pull requests:

1. Open a pull request on GitHub with the change you want.
2. The PR will automatically trigger:
   - Build validation
   - Brewfile, Flatpak, Justfile, and shellcheck validation
   - Test image build
3. Once checks pass, merge the PR
4. Merging triggers publishes a `:stable` image

### 7. Deploy Your Image

Switch to your image:

```bash
sudo bootc switch ghcr.io/your-username/your-repo-name:stable
sudo systemctl reboot
```

## Optional: Enable Image Signing

Image signing is disabled by default to let you start building immediately. However, signing is strongly recommended for production use.

### Why Sign Images?

- Verify image authenticity and integrity
- Prevent tampering and supply chain attacks
- Required for some enterprise/security-focused deployments
- Industry best practice for production images

### Setup Instructions

This template uses **keyless OIDC signing** via Cosign and GitHub Actions. No manual key generation, `cosign.key`, or `cosign.pub` files are required.

1. Edit `.github/workflows/build-image.yml`
2. Find the "OPTIONAL: Sign and attest" section
3. Uncomment the `Sign and publish` step (remove the `#` from the beginning of each line in that section)
4. Commit and push

Your next build will produce a signed image. The signature is created using GitHub's OIDC token via Fulcio.

Users can verify your images with:

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/your-username/your-repo-name/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/your-username/your-repo-name:stable
```

## Love Your Image? Let's Go to Production

Ready to take your custom OS to production? Enable these features for enhanced security, reliability, and performance:

### Production Checklist

- [ ] **Enable Image Signing** (Recommended)
  - Provides cryptographic verification of your images
  - Prevents tampering and ensures authenticity
  - Uses keyless OIDC signing via GitHub Actions — no keys or secrets required
  - See "Optional: Enable Image Signing" section above for setup instructions
  - Status: **Disabled by default** to allow immediate testing

- [ ] **Enable Image Rechunking** (Recommended)
  - Optimizes bootc image layers for better update performance
  - Reduces update sizes by 5-10x when combined with package cadence data
  - Improves download resumability with evenly sized layers
  - To enable:
    1. Edit `.github/workflows/build-image.yml`
    2. Find the "OPTIONAL: Rechunking" section
    3. Uncomment the `bootc-build/chunka` step
  - For optimal results, also add `bootc-build/apply-pkg-intervals` and a `pkg-cadence.yml` workflow
  - Status: **Not enabled by default** (optional optimization)

#### Adding Image Rechunking

After building your bootc image, add a rechunk step before pushing to the registry. The template ships with a commented `bootc-build/chunka` step in `.github/workflows/build-image.yml`:

```yaml
- name: Rechunk image
  if: github.event_name != 'pull_request'
  id: rechunk-image
  uses: projectbluefin/actions/bootc-build/chunka@6231015b336556d2ff0adc1d1e59514bf19dcb42 # v1
  with:
    source-image: localhost/${{ env.IMAGE_NAME }}:${{ env.DEFAULT_TAG }}
    max-layers: 128
```

This uses [chunkah](https://github.com/coreos/chunkah) to reorganize OCI layers without rpm-ostree. Renovate will keep the action updated once it is uncommented.

**Parameters:**

- `max-layers`: Maximum number of layers for the rechunked image (128 is a typical bootc default)
- `source-image`: Local image reference to rechunk

**For optimal OTA deltas**, also add `bootc-build/apply-pkg-intervals` before the rechunk step and create a `.github/workflows/pkg-cadence.yml` workflow that calls `projectbluefin/actions/.github/workflows/reusable-pkg-cadence.yml@v1`. This groups packages by update cadence (weekly, monthly, quarterly, yearly) so a typical update only downloads layers that actually changed. Without it, chunkah still works but uses default layer grouping.

**References:**

- [CoreOS rpm-ostree build-chunked-oci documentation](https://coreos.github.io/rpm-ostree/build-chunked-oci/)
- [bootc documentation](https://containers.github.io/bootc/)

### After Enabling Production Features

Your workflow will:

- Sign all images using keyless OIDC signing
- Provide cryptographic proof of authenticity via SLSA build provenance attestation

Users can verify your images with:

```bash
cosign verify \
  --certificate-identity-regexp="https://github.com/your-username/your-repo-name/.github/workflows/" \
  --certificate-oidc-issuer="https://token.actions.githubusercontent.com" \
  ghcr.io/your-username/your-repo-name:stable
```

## Detailed Guides

- [Homebrew/Brewfiles](custom/brew/README.md) - Runtime package management
- [Flatpak Preinstall](custom/flatpaks/README.md) - GUI application setup
- [ujust Commands](custom/ujust/README.md) - User convenience commands
- [Build Scripts](build/README.md) - Build-time customization

## Architecture

This template follows the **multi-stage build architecture** from @projectbluefin/distroless, as documented in the [Bluefin Contributing Guide](https://docs.projectbluefin.io/contributing/).

### Multi-Stage Build Pattern

**Stage 1: Context (ctx)** - Combines resources from multiple sources:

- Local build scripts (`/build`)
- Local custom files (`/custom`)
- **@projectbluefin/common** - Desktop configuration shared with Aurora (includes branding/artwork content)
- **@ublue-os/brew** - Homebrew integration

**Stage 2: Base Image** - Default options:

- `quay.io/fedora-ostree-desktops/silverblue:44` (Fedora-based GNOME desktop, default)
- `quay.io/centos-bootc/centos-bootc:stream10` (CentOS-based alternative)

### Benefits of This Architecture

- **Modularity**: Compose your image from reusable OCI containers
- **Maintainability**: Update shared components independently
- **Reproducibility**: Renovate automatically updates OCI tags to SHA digests
- **Consistency**: Share components across Bluefin, Aurora, and custom images

### OCI Container Resources

The template imports files from these OCI containers at build time:

```dockerfile
COPY --from=ghcr.io/projectbluefin/common:latest /system_files /oci/common
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /oci/brew
```

Your build scripts can access these files at:

- `/ctx/oci/common/` - Shared desktop configuration (branding/artwork content lives inside `common`)
- `/ctx/oci/brew/` - Homebrew integration files

**Note**: Renovate automatically updates `:latest` tags to SHA digests for reproducible builds.

## Local Testing

Test your changes before pushing:

```bash
just build              # Build container image
just build-qcow2        # Build VM disk image
just run-vm-qcow2       # Test in browser-based VM
```

## Community

- [Universal Blue Discord](https://discord.gg/WEu6BdFEtp)
- [bootc Discussion](https://github.com/bootc-dev/bootc/discussions)

## Learn More

- [Universal Blue Documentation](https://universal-blue.org/)
- [bootc Documentation](https://containers.github.io/bootc/)
- [Video Tutorial by TesterTech](https://www.youtube.com/watch?v=IxBl11Zmq5wE)

## Security

This template provides security features for production use:

- Optional image signing with keyless OIDC cosign for cryptographic verification
- Automated security updates via Renovate
- Build provenance tracking

These security features are disabled by default to allow immediate testing. When you're ready for production, see the "Love Your Image? Let's Go to Production" section above to enable them.

## Troubleshooting

### Flatpaks not preinstalled after bootc switch (fixes #49)

Flatpaks are installed on first boot via `flatpak-preinstall.service`, not during `bootc switch`. Ensure:

- Internet is available on first boot
- `flatpak-preinstall.service` completes (`systemctl status flatpak-preinstall.service`)
- Wait until the service finishes before checking for flatpaks

### flatpak-preinstall errors about adw-gtk3 runtimes (fixes #30)

The `adw-gtk3-dark` runtime is not available on Flathub. These warnings are cosmetic and do not prevent other flatpaks from installing. To suppress, remove `adw-gtk3-dark` from your flatpak list in `custom/flatpaks/`.

### Homebrew not available after bootc switch (fixes #44)

Homebrew is **pre-staged at build time** (tarball + systemd services). The `brew-setup.service` extracts it on **first boot**. If you don't see `brew`, verify `brew-setup.service` ran (`systemctl status brew-setup.service`) and that your Containerfile includes the Brew integration.
