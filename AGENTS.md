# Copilot Instructions for finpilot bootc Image Template

## CRITICAL: Pre-Commit Checklist

**Execute before EVERY commit:**
1. **Conventional Commits** - ALL commits MUST follow conventional commit format (see below)
2. **Shellcheck** - `shellcheck *.sh` on all modified shell files
3. **YAML validation** - `python3 -c "import yaml; yaml.safe_load(open('file.yml'))"` on all modified YAML
4. **Justfile syntax** - `just --list` to verify
5. **Confirm with user** - Always confirm before committing and pushing

**Never commit files with syntax errors.**

### REQUIRED: Conventional Commit Format

**ALL commits MUST use conventional commits format**

```
<type>[optional scope]: <description>
```

## CRITICAL: Template Initialization

**When this repository is used as a template, you MUST:**

### 1. Rename ALL instances of `finpilot`

**Source of truth**: `Containerfile` line 9: `# Name: finpilot`

**Files to update:**
- `Containerfile` (line 9)
- `Justfile` (line 1)
- `README.md` (line 1)
- `artifacthub-repo.yml` (line 5)
- `custom/ujust/README.md` (~line 175)
- `.github/workflows/ghcr-pruner.yml` (line 22)

### 2. Create "What's Different" section in README

**CRITICAL**: Add this section near the top of README.md (after the title/intro, before detailed docs):

```markdown
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

*Last updated: [date]*
```

**Maintenance requirement**: 
- **ALWAYS update this section when you modify packages or configuration**
- Keep descriptions brief and user-focused (explain "why", not just "what")
- Write for typical Linux users, not developers
- Update the "Last updated" date with each change

### 3. Verify copilot instructions are present

Confirm `.github/copilot-instructions.md` exists in the new repository. This file should be automatically copied when using this as a GitHub template.

### 4. Explain signing is optional

Signing is DISABLED by default. First builds succeed immediately. Enable later for production (see README).

**These 4 steps are REQUIRED for every new template instance.**

---

## Repository Structure

```
├── Containerfile          # Main build definition (multi-stage build with OCI imports)
├── Justfile              # Local build automation (image name, build commands)
├── build/                # Build-time scripts (10-build.sh, 20-chrome.sh, etc.)
│   ├── 10-build.sh      # Main build script (copy custom files, install packages)
│   ├── 20-*.sh.example  # Example third-party repos (rename to use)
│   ├── 30-*.sh.example  # Example desktop replacement (rename to use)
│   ├── copr-helpers.sh  # Helper functions for COPR repositories
│   └── README.md        # Build scripts documentation
├── custom/               # User customizations (NOT in container, installed at runtime/first boot)
│   ├── brew/            # Homebrew Brewfiles (CLI tools, dev tools)
│   │   ├── default.Brewfile      # General CLI tools
│   │   ├── development.Brewfile  # Dev environments
│   │   ├── fonts.Brewfile        # Font packages
│   │   └── README.md             # Homebrew documentation
│   ├── flatpaks/        # Flatpak preinstall (GUI apps, post-first-boot)
│   │   ├── default.preinstall    # Default GUI apps (INI format)
│   │   └── README.md             # Flatpak documentation
│   └── ujust/           # User commands (shortcuts to Brewfiles, system tasks)
│       ├── custom-apps.just      # App installation shortcuts
│       ├── custom-system.just    # System maintenance commands
│       └── README.md             # ujust documentation
├── iso/                  # Local testing only (no CI/CD)
│   ├── disk.toml        # VM/disk image config (QCOW2/RAW)
│   ├── iso.toml         # ISO installer config (bootc switch URL)
│   └── rclone/          # Upload configs (Cloudflare R2, AWS S3, etc.)
├── .github/              # GitHub configuration and CI/CD
│   ├── workflows/       # GitHub Actions workflows
│   │   ├── build.yml               # Builds :stable on main
│   │   ├── clean.yml               # Deletes images >90 days old
│   │   ├── renovate.yml            # Renovate bot updates (6h interval)
│   │   ├── validate-*.yml          # Pre-merge validation checks
│   │   └── ...
│   ├── copilot-instructions.md  # THIS FILE - Instructions for Copilot
│   ├── SETUP_CHECKLIST.md       # Quick setup checklist for users
│   ├── commit-convention.md     # Conventional commits guide
│   └── renovate.json5           # Renovate configuration
├── .pre-commit-config.yaml   # Pre-commit hooks (optional local use)
└── .gitignore                # Prevents committing secrets (cosign.key, etc.)
```

---

## Core Principles

### Multi-Stage Build Architecture
This template follows the **Bluefin architecture pattern** from @projectbluefin/distroless:

**Architecture Layers:**
1. **Context Stage (ctx)** - Combines resources from multiple sources:
   - Local build scripts (`/build`)
   - Local custom files (`/custom`)
   - **@projectbluefin/common** - Desktop configuration shared with Aurora (`/oci/common`)
   - **@projectbluefin/branding** - Branding assets (`/oci/branding`)
   - **@ublue-os/artwork** - Artwork shared with Aurora and Bazzite (`/oci/artwork`)
   - **@ublue-os/brew** - Homebrew integration (`/oci/brew`)

2. **Base Image Options:**
   - `ghcr.io/ublue-os/silverblue-main:42` (Fedora-based, default)
   - `quay.io/centos-bootc/centos-bootc:stream10` (CentOS-based)

**OCI Container Resources:**
- Resources from OCI containers are copied to **distinct subdirectories** (`/oci/*`) to avoid file conflicts
- Renovate automatically updates `:latest` tags to **SHA digests** for reproducibility
- All OCI resources are mounted at build-time via the `ctx` stage

**Reference:** See [Bluefin Contributing Guide](https://docs.projectbluefin.io/contributing/) for architecture diagram

### Build-time vs Runtime
- **Build-time** (`build/`): Baked into container. Use `dnf5 install`. Services, configs, system packages.
- **Runtime** (`custom/`): User installs after deployment. Use Brewfiles, Flatpaks. CLI tools, GUI apps, dev environments.

### Bluefin Convention Compliance
**ALWAYS follow @ublue-os/bluefin patterns. Confirm before deviating.**
- Use `dnf5` exclusively (never `dnf`, `yum`, `rpm-ostree`)
- Always `-y` flag for non-interactive
- COPRs: enable → install → **DISABLE** (critical, prevents repo persistence)
- Use `copr_install_isolated` function pattern
- Numbered scripts: `10-build.sh`, `20-chrome.sh`, `30-cosmic.sh`
- Check @bootc-dev for container best practices

### Branch Strategy
- **main** = Production releases ONLY. Never push directly. Builds `:stable` images.
- **Conventional Commits** = REQUIRED. `feat:`, `fix:`, `chore:`, etc.
- **Workflows** = All validation happens on PRs. Merging to main triggers stable builds.

### Validation Workflows
The repository includes automated validation on pull requests:
- **validate-shellcheck.yml** - Runs shellcheck on all `build/*.sh` scripts
- **validate-brewfiles.yml** - Validates Homebrew Brewfile syntax
- **validate-flatpaks.yml** - Checks Flatpak app IDs exist on Flathub
- **validate-justfiles.yml** - Validates just file syntax
- **validate-renovate.yml** - Validates Renovate configuration

**When adding files**: These validations run automatically on PRs. Fix any errors before merge.

---

## Where to Add Packages

This section provides clear guidance on where to add different types of packages.

### System Packages (dnf5 - Build-time)

**Location**: `build/10-build.sh`

System packages are installed at build-time and baked into the container image. Use `dnf5` exclusively.

**Example**:
```bash
# In build/10-build.sh
dnf5 install -y vim git htop neovim tmux
```

**When to use**: 
- System utilities and services
- Dependencies required for other build-time operations
- Packages that need to be available immediately on first boot
- Services that need to be enabled with `systemctl enable`

**Important**: 
- Always use `dnf5` (never `dnf`, `yum`, or `rpm-ostree`)
- Always add `-y` flag for non-interactive installs
- For COPR repositories, use `copr_install_isolated` pattern and disable after use
- For third-party repos, see example scripts: `build/20-onepassword.sh.example`

**Script Naming Convention**:
- `10-build.sh` - Main build script (always runs first)
- `20-*.sh` - Additional scripts (run in numerical order)
- `30-*.sh` - Desktop environment changes
- `.example` suffix - Rename to `.sh` to activate

### Homebrew Packages (Brew - Runtime)

**Location**: `custom/brew/*.Brewfile`

Homebrew packages are installed by users after deployment. Best for CLI tools and development environments.

**Files**:
- `custom/brew/default.Brewfile` - General purpose CLI tools
- `custom/brew/development.Brewfile` - Development tools and environments
- `custom/brew/fonts.Brewfile` - Font packages
- Create custom `*.Brewfile` as needed

**Example**:
```ruby
# In custom/brew/default.Brewfile
brew "bat"        # cat with syntax highlighting
brew "eza"        # Modern replacement for ls
brew "ripgrep"    # Faster grep
brew "fd"         # Simple alternative to find
```

**When to use**:
- CLI tools and utilities
- Development tools (node, python, go, etc.)
- User-specific tools that don't need to be in the base image
- Tools that update frequently

**Important**:
- Brewfiles use Ruby syntax
- Users install via `ujust` commands (e.g., `ujust install-default-apps`)
- Not installed in ISO/container - users install after deployment

### Flatpak Applications (GUI Apps - Runtime)

**Location**: `custom/flatpaks/*.preinstall`

Flatpak applications are GUI apps installed after first boot. Use INI format.

**Files**:
- `custom/flatpaks/default.preinstall` - Default GUI applications
- Create custom `*.preinstall` files as needed

**Example**:
```ini
# In custom/flatpaks/default.preinstall
[Flatpak Preinstall org.mozilla.firefox]
Branch=stable

[Flatpak Preinstall com.visualstudio.code]
Branch=stable

[Flatpak Preinstall org.gnome.Calculator]
Branch=stable
```

**When to use**:
- GUI applications
- Desktop apps (browsers, editors, media players)
- Apps that users expect to have immediately available
- Apps from Flathub (https://flathub.org/)

**Important**:
- Installed post-first-boot (not in ISO/container)
- Requires internet connection
- Find app IDs at https://flathub.org/
- Use INI format with `[Flatpak Preinstall APP_ID]` sections
- Always specify `Branch=stable` (or another branch)

---

## Quick Reference: Common User Requests

| Request | Action | Location |
|---------|--------|----------|
| Add package (build-time) | `dnf5 install -y pkg` | `build/10-build.sh` |
| Add package (runtime) | `brew "pkg"` | `custom/brew/default.Brewfile` |
| Add GUI app | `[Flatpak Preinstall org.app.id]` | `custom/flatpaks/default.preinstall` |
| Add user command | Create shortcut (NO dnf5) | `custom/ujust/*.just` |
| Add third-party repo | Use example scripts | `build/20-*.sh.example` (rename) |
| Replace desktop | Use example script | `build/30-cosmic-desktop.sh.example` |
| Switch base image | Update FROM line | `Containerfile` line 24 |
| Test locally | `just build && just build-qcow2 && just run-vm-qcow2` | Terminal |
| Deploy (production) | `sudo bootc switch ghcr.io/user/repo:stable` | Terminal |
| Enable service | `systemctl enable service.name` | `build/10-build.sh` |
| Add COPR | enable → install → **DISABLE** | `build/10-build.sh` |
| Validate changes | Automatic on PR | `.github/workflows/validate-*.yml` |

---

## Detailed Workflows

### 1. Multi-Stage Build Architecture

**File**: `Containerfile`

This template uses a **multi-stage build** following the @projectbluefin/distroless pattern.

**Stage 1: Context (ctx) - Line 39**
Combines resources from multiple OCI containers:
```dockerfile
FROM scratch AS ctx

COPY build /build
COPY custom /custom
# Import from OCI containers - Renovate updates :latest to SHA-256 digests
COPY --from=ghcr.io/ublue-os/base-main:latest /system_files /oci/base
COPY --from=ghcr.io/projectbluefin/common:latest /system_files /oci/common
COPY --from=ghcr.io/projectbluefin/branding:latest /system_files /oci/branding
COPY --from=ghcr.io/ublue-os/artwork:latest /system_files /oci/artwork
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /oci/brew
```

**Stage 2: Base Image - Line 52**
```dockerfile
FROM ghcr.io/ublue-os/silverblue-main:latest  # Default (Fedora-based)
# OR
FROM quay.io/centos-bootc/centos-bootc:stream10  # CentOS-based
```

**Common alternative base images**:
```dockerfile
FROM ghcr.io/ublue-os/bluefin:stable      # Dev, GNOME, `:stable` or `:gts`
FROM ghcr.io/ublue-os/bazzite:stable      # Gaming, Steam Deck
FROM ghcr.io/ublue-os/aurora:stable       # KDE Plasma
FROM quay.io/fedora/fedora-bootc:42       # Upstream Fedora
```

**Tags**: `:stable` (recommended), `:latest` (bleeding edge), `-nvidia` variants available

**Renovate**: Base image SHA and OCI container tags are auto-updated by Renovate bot every 6 hours (see `.github/renovate.json5`)

**OCI Container Resources:**
- **@ublue-os/base-main** - Base system configuration
- **@projectbluefin/common** - Desktop configuration shared with Aurora
- **@projectbluefin/branding** - Branding assets
- **@ublue-os/artwork** - Artwork shared with Aurora and Bazzite
- **@ublue-os/brew** - Homebrew integration

**File Locations in Build Scripts:**
- Local build scripts: `/ctx/build/`
- Local custom files: `/ctx/custom/`
- Base files: `/ctx/oci/base/`
- Common files: `/ctx/oci/common/`
- Branding files: `/ctx/oci/branding/`
- Artwork files: `/ctx/oci/artwork/`
- Brew files: `/ctx/oci/brew/`

### 2. Build Scripts (`build/`)

**Pattern**: Numbered files (`10-build.sh`, `20-chrome.sh`, `30-cosmic.sh`) run in order.

**Example - `build/10-build.sh`**:
```bash
#!/usr/bin/env bash
set -euo pipefail

# Install packages
dnf5 install -y vim git htop neovim

# Enable services
systemctl enable podman.socket

# Download binaries
curl -L https://example.com/tool -o /usr/local/bin/tool
chmod +x /usr/local/bin/tool
```

**Example - COPR pattern** (see `build/20-onepassword.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

source /ctx/copr-install-functions.sh

# Chrome
dnf config-manager addrepo --from-repofile=https://dl.google.com/linux/linux_signing_key.pub
dnf5 install -y google-chrome-stable

# 1Password via COPR (isolated)
copr_install_isolated username/repo package-name
```

**Example - Desktop swap** (see `build/30-cosmic.sh`):
```bash
#!/usr/bin/env bash
set -euo pipefail

# Remove GNOME, install COSMIC
dnf5 group remove -y "GNOME Desktop Environment"
dnf5 copr enable -y ryanabx/cosmic-epoch
dnf5 install -y cosmic-desktop
dnf5 copr disable -y ryanabx/cosmic-epoch
systemctl set-default graphical.target
```

**CRITICAL**: Use `copr_install_isolated` function. Always disable COPRs.

**Example scripts**: See `build/20-onepassword.sh.example` and `build/30-cosmic-desktop.sh.example` for complete working examples.

### 3. Homebrew (`custom/brew/`)

**Files**: `*.Brewfile` (Ruby syntax)

**Example - `custom/brew/default.Brewfile`**:
```ruby
# CLI tools
brew "bat"        # Better cat
brew "eza"        # Better ls
brew "ripgrep"    # Better grep
brew "fd"         # Better find

# Dev tools
tap "homebrew/cask"
brew "node"
brew "python"
```

**Users install via**: `ujust install-default-apps` (create shortcut in `custom/ujust/`)

### 4. ujust Commands (`custom/ujust/`)

**Files**: `*.just` (all auto-consolidated)

**Example - `custom/ujust/apps.just`**:
```just
[group('Apps')]
install-default-apps:
    #!/usr/bin/env bash
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile

[group('Apps')]
install-dev-tools:
    #!/usr/bin/env bash
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile
```

**RULES**:
- **NEVER** use `dnf5` in ujust - only Brewfile/Flatpak shortcuts
- Use `[group('Category')]` for organization
- All `.just` files merged during build

### 5. Flatpaks (`custom/flatpaks/`)

**Files**: `*.preinstall` (INI format, installed after first boot)

**Example - `custom/flatpaks/default.preinstall`**:
```ini
[Flatpak Preinstall org.mozilla.firefox]
Branch=stable

[Flatpak Preinstall org.gnome.Calculator]
Branch=stable

[Flatpak Preinstall com.visualstudio.code]
Branch=stable
```

**Important**: Not in ISO/container. Installed post-first-boot. Requires internet. Find IDs at https://flathub.org/

### 6. ISO/Disk Images (`iso/`)

**For local testing only. No CI/CD.**

**Files**:
- `iso/disk.toml` - VM images (QCOW2/RAW): `just build-qcow2`
- `iso/iso.toml` - Installer ISO: `just build-iso`

**CRITICAL** - Update bootc switch URL in `iso/iso.toml`:
```toml
[customizations.installer.kickstart]
contents = """
%post
bootc switch --mutate-in-place --transport registry ghcr.io/USERNAME/REPO:stable
%end
"""
```

**Upload**: Use `iso/rclone/` configs (Cloudflare R2, AWS S3, Backblaze B2, SFTP)

### 7. Release Workflow

**Branches**:
- `main` - Production only. Builds `:stable` images. Never push directly.

**Workflows**:
- `build.yml` - Builds `:stable` on main
- `renovate.yml` - Monitors base image updates (every 6 hours)
- `clean.yml` - Deletes images >90 days (weekly)
- `validate-*.yml` - Pre-merge validation (shellcheck, Brewfile, Flatpak, etc.)

**Image Tags**:
- `:stable` - Latest stable release from main branch
- `:stable.YYYYMMDD` - Datestamped stable release
- `:YYYYMMDD` - Date only
- `:pr-123` - Pull request builds (for testing)
- `:sha-abc123` - Git commit SHA (short)

**Renovate Bot**: 
- Automatically updates base image SHAs in `Containerfile`
- Runs every 6 hours (configured in `.github/renovate.json5`)
- Creates PRs for updates - review and merge to keep images current

### 8. Understanding the Multi-Stage Build Architecture

This template implements a **multi-stage build pattern** following @projectbluefin/distroless.

**Why Multi-Stage?**
- **Modularity**: Combine resources from multiple OCI containers
- **Reusability**: Share common components across different images
- **Maintainability**: Update shared components independently
- **Reproducibility**: Renovate updates OCI container tags to SHA digests

**Stage Breakdown:**

**Stage 1: Context (ctx)**
```dockerfile
FROM scratch AS ctx
COPY build /build                    # Local build scripts
COPY custom /custom                  # Local customizations
COPY --from=ghcr.io/projectbluefin/common:latest /system_files /oci/common
COPY --from=ghcr.io/projectbluefin/branding:latest /system_files /oci/branding
COPY --from=ghcr.io/ublue-os/artwork:latest /system_files /oci/artwork
COPY --from=ghcr.io/ublue-os/brew:latest /system_files /oci/brew
```

This stage combines:
- **Local resources** (build scripts, custom files)
- **OCI container resources** from upstream projects
- Resources are copied to **distinct subdirectories** to avoid conflicts

**Stage 2: Final Image**
```dockerfile
FROM ghcr.io/ublue-os/silverblue-main:42

RUN --mount=type=bind,from=ctx,source=/,target=/ctx \
    /ctx/build/10-build.sh
```

The final stage:
- Starts from base image
- Mounts the `ctx` stage at `/ctx`
- Runs build scripts with access to all resources

**Accessing OCI Resources in Build Scripts:**

Build scripts can access files from OCI containers:
```bash
#!/usr/bin/env bash
# Example: Copy branding files
cp -r /ctx/oci/branding/* /usr/share/branding/

# Example: Copy common desktop config
cp /ctx/oci/common/config.yaml /etc/myapp/

# Example: Use brew files
cp /ctx/oci/brew/*.sh /usr/local/bin/
```

**Renovate Integration:**
- Renovate monitors OCI container tags (`:latest`)
- Automatically updates to SHA digests for reproducibility
- Example: `:latest` → `@sha256:abc123...`
- Ensures builds are reproducible and verifiable

**Reference:** See [Bluefin Contributing Guide](https://docs.projectbluefin.io/contributing/) for architecture diagram

### 9. Image Signing (Optional, Recommended for Production)

**Default**: DISABLED (commented out in workflows) to allow first builds.
```bash
# Generate keys
COSIGN_PASSWORD="" cosign generate-key-pair
# Creates: cosign.key (SECRET), cosign.pub (COMMIT)

# Add to GitHub
# Settings → Secrets and Variables → Actions → New secret
# Name: SIGNING_SECRET
# Value: <paste entire contents of cosign.key>

# Uncomment signing sections in:
# - .github/workflows/build.yml
# - .github/workflows/build-testing.yml
```

**NEVER commit `cosign.key`**. Already in `.gitignore`.

---

## Critical Rules (Enforced)

1. **ALWAYS** use Conventional Commits format for ALL commits (required for Release Please)
   - Format: `<type>[scope]: <description>`
   - Valid types: `feat:`, `fix:`, `docs:`, `chore:`, `build:`, `ci:`, `refactor:`, `test:`
   - Breaking changes: Add `!` or `BREAKING CHANGE:` in footer
   - See `.github/commit-convention.md` for examples
2. **NEVER** commit `cosign.key` to repository
3. **ALWAYS** disable COPRs after use (`copr_install_isolated` function)
4. **ALWAYS** use `dnf5` exclusively (never `dnf`, `yum`, `rpm-ostree`)
5. **ALWAYS** use `-y` flag for non-interactive installs
6. **NEVER** use `dnf5` in ujust files - only Brewfile/Flatpak shortcuts
7. **ALWAYS** work on testing branch for development
8. **ALWAYS** let Release Please handle testing→main merges
9. **NEVER** push directly to main (only via Release Please)
10. **ALWAYS** confirm with user before deviating from @ublue-os/bluefin patterns
11. **ALWAYS** run shellcheck/YAML validation before committing
12. **ALWAYS** update bootc switch URL in `iso/iso.toml` to match user's repo
13. **ALWAYS** follow numbered script convention: `10-*.sh`, `20-*.sh`, `30-*.sh`
14. **ALWAYS** check example scripts before creating new patterns (`.example` files in `build/`)
15. **ALWAYS** validate that new Flatpak IDs exist on Flathub before adding
16. **NEVER** modify validation workflows without understanding impact on PR checks
---

## Troubleshooting

| Symptom | Cause | Solution |
|---------|-------|----------|
| Build fails: "permission denied" | Signing misconfigured | Verify signing commented out OR `SIGNING_SECRET` set |
| Build fails: "package not found" | Typo or unavailable | Check spelling, verify on RPMfusion, add COPR if needed |
| Build fails: "base image not found" | Invalid FROM line | Check syntax in `Containerfile` line 24 |
| Build fails: "shellcheck error" | Script syntax error | Run `shellcheck build/*.sh` locally, fix errors |
| PR validation fails: Brewfile | Invalid Brewfile syntax | Check Ruby syntax, ensure packages exist |
| PR validation fails: Flatpak | Invalid app ID | Verify app ID exists on https://flathub.org/ |
| PR validation fails: justfile | Invalid just syntax | Run `just --list` locally to test |
| Changes not in production | Wrong workflow | Push to main (via PR) to trigger stable builds |
| ISO missing customizations | Wrong bootc URL | Update `iso/iso.toml` bootc switch URL to match repo |
| COPR packages missing after boot | COPR not disabled | COPRs persist if not disabled - use `copr_install_isolated` |
| ujust commands not working | Wrong install location | Files must be in `custom/ujust/` and copied to `/usr/share/ublue-os/just/` |
| Flatpaks not installed | Expected behavior | Flatpaks install post-first-boot, not in ISO/container |
| Local build fails | Wrong environment | Must run on bootc-based system or have podman installed |
| Renovate not creating PRs | Configuration issue | Check `.github/renovate.json5` syntax |
| Third-party repo not working | Repo file persists | Remove repo file at end of script (see examples) |

---

## Common Patterns & Examples

### Pattern 1: Adding Third-Party RPM Repositories

**Use case**: Installing Google Chrome, 1Password, VS Code, etc.

**Example**: See `build/20-onepassword.sh.example`

**Steps**:
1. Add GPG key (if required)
2. Create repo file in `/etc/yum.repos.d/`
3. Install packages with `dnf5 install -y`
4. **CRITICAL**: Remove repo file at end

```bash
# Add repo
cat > /etc/yum.repos.d/google-chrome.repo << 'EOF'
[google-chrome]
name=google-chrome
baseurl=https://dl.google.com/linux/chrome/rpm/stable/x86_64
enabled=1
gpgcheck=1
gpgkey=https://dl.google.com/linux/linux_signing_key.pub
EOF

# Install
dnf5 install -y google-chrome-stable

# Clean up (required!)
rm -f /etc/yum.repos.d/google-chrome.repo
```

### Pattern 2: Using COPR Repositories

**Use case**: Installing packages from Fedora COPR (community repos)

**Example**: See `build/copr-helpers.sh` and `build/30-cosmic-desktop.sh.example`

**Always use `copr_install_isolated` function**:
```bash
source /ctx/build/copr-helpers.sh

# Install from COPR (isolated - auto-disables after install)
copr_install_isolated "ublue-os/staging" package-name

# Install multiple packages
copr_install_isolated "ryanabx/cosmic-epoch" \
    cosmic-session \
    cosmic-greeter \
    cosmic-comp
```

### Pattern 3: Replacing Desktop Environment

**Use case**: Swap GNOME for KDE, COSMIC, etc.

**Example**: See `build/30-cosmic-desktop.sh.example`

**Steps**:
1. Remove old desktop: `dnf5 remove -y gnome-shell ...`
2. Install new desktop: `copr_install_isolated ...`
3. Configure display manager: `systemctl enable ...`
4. Set default session

### Pattern 4: Enabling System Services

**Location**: `build/10-build.sh`

```bash
# Enable service
systemctl enable podman.socket

# Mask unwanted service
systemctl mask unwanted-service

# Set default target
systemctl set-default graphical.target
```

### Pattern 5: Creating Custom ujust Commands

**Location**: `custom/ujust/*.just`

**Example structure**:
```just
# vim: set ft=make :

# Install development tools
[group('Apps')]
install-dev-tools:
    #!/usr/bin/env bash
    echo "Installing development tools..."
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile

# Custom system command
[group('System')]
my-custom-command:
    #!/usr/bin/env bash
    echo "Running custom command..."
    # Your logic here (NO dnf5!)
```

### Pattern 6: Local Testing Workflow

**Complete local testing cycle**:
```bash
# 1. Build container image
just build

# 2. Build QCOW2 disk image
just build-qcow2

# 3. Run in VM
just run-vm-qcow2

# Or combine all steps
just build && just build-qcow2 && just run-vm-qcow2
```

**Alternative**: Build ISO for installation testing
```bash
just build
just build-iso
just run-vm-iso
```

### Pattern 7: Pre-commit Validation (Optional)

**Setup pre-commit hooks locally**:
```bash
# Install pre-commit
pip install pre-commit

# Install hooks
pre-commit install

# Run manually
pre-commit run --all-files
```

**Note**: Pre-commit config exists (`.pre-commit-config.yaml`) but is optional. CI validation runs automatically on PRs.

---

## Advanced Topics

### /opt Immutability
Some packages (Chrome, Docker Desktop) write to `/opt`. On Fedora, it's symlinked to `/var/opt` (mutable). To make immutable:

Uncomment `Containerfile` line 20:
```dockerfile
RUN rm /opt && mkdir /opt
```

### Multi-Architecture
- Local `just` commands support your platform
- Most UBlue images support amd64/arm64
- Add `-arm64` suffix if needed: `bluefin-arm64:stable`
- Cross-platform builds require additional setup

### Custom Build Functions
See `build/copr-install-functions.sh` for reusable patterns:
- `copr_install_isolated` - Enable COPR, install packages, disable COPR
- Follow @ublue-os/bluefin conventions exactly

### Rechunker (Optional)
Rechunker optimizes container layer distribution for better resumability.

**Default**: Disabled (faster initial builds)

**To enable**:
1. Edit `.github/workflows/build.yml`
2. Uncomment "Run Rechunker" step (~line 124)
3. Uncomment "Load in podman and tag" step (~line 151)
4. Comment out "Tag for registry" step (~line 159)

**Recommendation**: Enable for production after initial testing succeeds.

**Documentation**: https://github.com/hhd-dev/rechunk

---

## Understanding the Build Process

### Container Build Flow

1. **Base Image** - Pulls base image specified in `Containerfile` FROM line
2. **Context Stage** - Mounts `build/` and `custom/` directories
3. **Build Scripts** - Runs scripts in `build/` directory in numerical order:
   - `10-build.sh` - Always runs first (copies custom files, installs packages)
   - `20-*.sh` - Additional scripts (if present and not .example)
   - `30-*.sh` - More scripts (if present and not .example)
4. **Container Lint** - Validates final image with `bootc container lint`
5. **Push to Registry** - Uploads to GitHub Container Registry (ghcr.io)

### What Gets Included in the Image

**Build-time (baked into image)**:
- System packages from `dnf5 install`
- Enabled systemd services
- Custom files copied from `/ctx/custom/` to standard locations:
  - Brewfiles → `/usr/share/ublue-os/homebrew/`
  - ujust files → `/usr/share/ublue-os/just/60-custom.just`
  - Flatpak preinstall → `/etc/flatpak/preinstall.d/`

**Runtime (installed after deployment)**:
- Homebrew packages (user runs `ujust install-*`)
- Flatpak applications (installed on first boot, requires internet)

### Local vs CI Builds

**Local builds** (with `just build`):
- Uses your local podman
- Faster for testing
- No signing, no rechunking
- No automatic push to registry

**CI builds** (GitHub Actions):
- Uses GitHub runners
- Automatic on push/PR
- Includes validation steps
- Can include signing and rechunking
- Automatic push to ghcr.io

### Image Layers and Caching

**Efficient layering**:
- Each `RUN` command creates a new layer
- Layers are cached between builds
- Changes near end of Containerfile = faster rebuilds
- Use `--mount=type=cache` for package managers

**Best practices**:
- Group related `dnf5 install` commands together
- Don't install and remove in same layer
- Clean up in same RUN command as install

---

## Image Tags Reference

**Main branch** (production releases):
- `stable` - Latest stable release (recommended)
- `stable.20250129` - Datestamped stable release
- `20250129` - Date only
- `v1.0.0` - Version from Release Please

**PR builds**:
- `pr-123` - Pull request number
- `sha-abc123` - Git commit SHA (short)

---

## File Modification Priority

When user requests customization, check in this order:

1. **`build/10-build.sh`** (50%) - Build-time packages, services, system configs
2. **`custom/brew/`** (20%) - Runtime CLI tools, dev environments
3. **`custom/ujust/`** (15%) - User convenience commands
4. **`custom/flatpaks/`** (5%) - GUI applications
5. **`Containerfile`** (5%) - Base image, /opt config, advanced builds
6. **`Justfile`** (2%) - Image name, build parameters
7. **`iso/*.toml`** (2%) - ISO/disk customization for testing
8. **`.github/workflows/`** (1%) - Metadata, triggers, workflow config

### Files to AVOID Modifying

**Do NOT modify unless specifically requested or necessary**:
- `.github/renovate.json5` - Renovate configuration (auto-updates)
- `.github/workflows/validate-*.yml` - Validation workflows
- `.gitignore` - Prevents committing secrets
- `build/copr-helpers.sh` - Helper functions (stable patterns)
- `LICENSE` - Repository license
- `cosign.pub` - Public signing key (regenerate if changing keys)

**Modify with extreme caution**:
- `.github/workflows/build.yml` - Core build workflow
- `.github/workflows/clean.yml` - Image cleanup
- `Justfile` - Local build automation (users rely on these commands)

---

## Debugging Tips

### Local Debugging

**Build failures**:
```bash
# Build with verbose output
podman build --log-level=debug .

# Check build script syntax
shellcheck build/*.sh

# Test specific script in container
podman run --rm -it ghcr.io/ublue-os/bluefin:stable bash
# Then run your script commands manually
```

**Brewfile issues**:
```bash
# Validate Brewfile syntax
brew bundle check --file custom/brew/default.Brewfile

# List what would be installed
brew bundle list --file custom/brew/default.Brewfile
```

**Just file issues**:
```bash
# Check syntax
just --list

# Check specific file
just --unstable --fmt --check -f custom/ujust/custom-apps.just

# Run specific command with debug
just --verbose install-default-apps
```

### CI Debugging

**Check workflow logs**:
1. Go to Actions tab in GitHub
2. Click on failed workflow run
3. Expand failed step
4. Look for error messages

**Common CI failures**:
- Shellcheck errors: Fix script syntax
- Brewfile validation: Check package names exist
- Flatpak validation: Verify app IDs on Flathub
- Image pull failures: Check base image SHA/tag

**Test PR before merge**:
```bash
# PR builds are tagged as :pr-NUMBER
podman pull ghcr.io/YOUR_USERNAME/YOUR_REPO:pr-123
podman run --rm -it ghcr.io/YOUR_USERNAME/YOUR_REPO:pr-123 bash
```

### Runtime Debugging

**After deployment**:
```bash
# Check system info
bootc status

# Check running services
systemctl list-units --failed

# Check logs
journalctl -b -p err

# Check ujust commands available
ujust --list

# Check Brewfiles location
ls -la /usr/share/ublue-os/homebrew/

# Check Flatpak preinstall
ls -la /etc/flatpak/preinstall.d/
```

**Flatpak debugging**:
```bash
# Check Flatpak remotes
flatpak remotes

# Check installed Flatpaks
flatpak list

# Install Flatpak manually
flatpak install -y flathub org.mozilla.firefox
```

**Homebrew debugging**:
```bash
# Check Homebrew status
brew doctor

# Check Brewfile
cat /usr/share/ublue-os/homebrew/default.Brewfile

# Install manually
brew install package-name
```

---

## Resources & Documentation

- **Bluefin patterns**: https://github.com/ublue-os/bluefin
- **bootc documentation**: https://github.com/containers/bootc
- **Conventional Commits**: https://www.conventionalcommits.org/
- **RPMfusion packages**: https://mirrors.rpmfusion.org/
- **Flatpak IDs**: https://flathub.org/
- **Homebrew**: https://brew.sh/
- **Universal Blue**: https://universal-blue.org/
- **Renovate**: https://docs.renovatebot.com/
- **GitHub Actions**: https://docs.github.com/en/actions
- **Podman**: https://podman.io/
- **Justfile**: https://just.systems/

---

## Other Rules that are Important to the Maintainers

- Ensure that [conventional commits](https://www.conventionalcommits.org/en/v1.0.0/#specification) are used and enforced for every commit and pull request title.
- Always be surgical with the least amount of code, the project strives to be easy to maintain.

## Attribution Requirements

AI agents must disclose what tool and model they are using in the "Assisted-by" commit footer:

```text
Assisted-by: [Model Name] via [Tool Name]
```

Example:

```text
Assisted-by: Claude 3.5 Sonnet via GitHub Copilot
```

---

**Last Updated**: 2025-11-14  
**Template Version**: finpilot (Enhanced with comprehensive Copilot instructions)  
**Maintainer**: Universal Blue Community
