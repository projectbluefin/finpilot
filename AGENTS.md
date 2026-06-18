# finpilot bootc Image Template — Agent Instructions

## CRITICAL: GitHub API Usage

**ALWAYS use GitHub API for external references** (e.g., projectbluefin/distroless, ublue-os/bluefin). Use `github-mcp-server-get_file_contents` instead of curl/wget.

## CRITICAL: Pre-Commit Checklist

Before EVERY commit:
1. **Conventional Commits** — `feat:`, `fix:`, `chore:`, etc.
2. **Shellcheck** — `shellcheck *.sh` on all modified shell files
3. **YAML validation** — `python3 -c "import yaml; yaml.safe_load(open('file.yml'))"` on all modified YAML
4. **Justfile syntax** — `just --list` to verify
5. **Confirm with user** — always confirm before committing and pushing

Never commit files with syntax errors.

## Architecture

Multi-stage OCI build pattern (Bluefin architecture from @projectbluefin/distroless):
- **Context stage (ctx)** — combines local build scripts (`/build`), custom files (`/custom`), and OCI resources from @projectbluefin/common, @projectbluefin/branding, @ublue-os/artwork, @ublue-os/brew
- **OCI resources** copied to distinct subdirectories (`/oci/*`) to avoid file conflicts
- Renovate auto-updates `:latest` tags to SHA digests for reproducibility

### Build-time vs Runtime
- **Build-time** (`build/`): Baked into container. `dnf5 install`. System packages, services, configs.
- **Runtime** (`custom/`): User-installs post-deployment. Brewfiles, Flatpaks, ujust commands.

## Bluefin Convention Compliance

- Use `dnf5` exclusively (never `dnf`, `yum`, `rpm-ostree`)
- Always `-y` flag for non-interactive
- COPRs: enable → install → **DISABLE** (critical — prevents repo persistence)
- Use `copr_install_isolated` function pattern
- Numbered build scripts: `10-build.sh`, `20-chrome.sh`, etc.
- Follow @bootc-dev container best practices

## Branch Strategy
- **main** = Production releases ONLY. Never push directly. Builds `:stable` images.
- All validation happens on PRs. Merging to main triggers stable builds.

## Where to Add Packages

| Package type | Location | Format |
|---|---|---|
| System packages (dnf5) | `build/10-build.sh` | `dnf5 install -y <pkg>` |
| Homebrew CLI tools | `custom/brew/default.Brewfile` or `custom/brew/development.Brewfile` | `brew "pkg"` |
| Homebrew fonts | `custom/brew/fonts.Brewfile` | `brew "font-name"` |
| Flatpak GUI apps | `custom/flatpaks/default.preinstall` | INI format |
| ujust commands | `custom/ujust/` | Justfile syntax |

## Don'ts

- **Don't modify** `.github/renovate.json5`, `.github/workflows/validate-*.yml`, `.gitignore`, `build/copr-helpers.sh`, `LICENSE`, `cosign.pub`
- **Don't modify** `.github/workflows/build.yml`, `.github/workflows/clean.yml`, or `Justfile` without extreme caution — users rely on these
- **Don't use** `dnf`, `yum`, or `rpm-ostree` — `dnf5` exclusively
- **Don't leave COPR repos enabled** after install — always disable
- **Never push directly to main**
