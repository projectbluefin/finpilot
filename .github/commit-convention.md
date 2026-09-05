# Conventional Commits for bootc Image Template

This repository follows [Conventional Commits v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/) specification.

## Commit Message Format

```
<type>(<scope>): <subject>

[optional body]

[optional footer(s)]
```

## Types

Use these commit types for changes to this bootc image template:

- **build**: Changes to the image build process (Containerfile, build.sh)
- **ci**: Changes to GitHub Actions workflows
- **config**: Changes to disk image configurations (TOML files)
- **feat**: New features or packages added to the image
- **fix**: Bug fixes or corrections
- **docs**: Documentation changes only
- **chore**: Maintenance tasks (dependencies, metadata)
- **refactor**: Code restructuring without changing behavior

## Scopes

Use these scopes to indicate what part of the image is affected:

- **base**: Base image changes (FROM line in Containerfile)
- **packages**: Package installation/removal
- **services**: Systemd service configuration
- **disk**: Disk image configuration (ISO, QCOW2, RAW)
- **workflow**: GitHub Actions workflows
- **metadata**: Image metadata and branding
- **signing**: Cosign key and signing configuration

## Examples

### Adding Packages

```
feat(packages): add development tools and editors

- Install neovim, git, and htop
- Add Development Tools group
```

### Changing Base Image

```
build(base): switch from Bazzite to Bluefin

Changing to Bluefin for better developer tooling support
```

### Configuring Services

```
feat(services): enable SSH and container services

- Enable sshd.service for remote access
- Enable podman.socket for rootless containers
```

### ISO Configuration

```
config(disk): update ISO to use custom registry

Update bootc switch URL to point to ghcr.io/username/repo
```

### Workflow Changes

```
ci(workflow): cache DNF metadata between image builds

Restore and save the DNF cache in build-image.yml, keyed on Containerfile
```

### Metadata Updates

```
chore(metadata): update image description and keywords

Update ArtifactHub metadata with project-specific information
```

### Documentation

```
docs: add installation instructions for new features
```

### Bug Fixes

```
fix(packages): disable COPR after package installation

Ensure COPR repositories don't persist in final image
```

## Breaking Changes

If a change is breaking (e.g., removing packages, changing base image significantly), add `!` after the type/scope:

```
build(base)!: migrate from Fedora 40 to Fedora 41

BREAKING CHANGE: This upgrade requires a clean reinstall for existing users.
```

## Tips

- Keep subject line under 50 characters
- Use imperative mood ("add" not "added" or "adds")
- Don't end subject line with a period
- Separate subject from body with a blank line
- Use body to explain _what_ and _why_, not _how_
- Be short and concise, avoid long commit messages, keep it simple
- Reference issues/PRs in footer when applicable
