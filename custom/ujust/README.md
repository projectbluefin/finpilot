# ujust

Recipes here become the image's `ujust` commands. Every `.just` file in this
directory tree is concatenated into `/usr/share/ublue-os/just/60-custom.just` at
build time, and the base `ublue-os-just` package imports that file. The search is
recursive, so recipes can be grouped into subdirectories by topic.

## Files

- `custom-apps.just` — Homebrew shortcuts
- `custom-system.just` — system configuration

## Writing a recipe

```just
# Install the default applications via Homebrew
[group('Apps')]
install-default-apps:
    #!/usr/bin/env bash
    set -euo pipefail
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile
```

- `[group('…')]` puts the recipe in a section of `ujust --list`.
- Use a bash shebang for anything past one line, and `set -euo pipefail`.
- Name with a verb prefix: `install-`, `configure-`, `setup-`, `toggle-`, `fix-`.
- `gum` is installed at build time; use it for prompts, or the `Choose()` and
  `Confirm()` helpers from `/usr/lib/ujust/ujust.sh`.

## The rules

- **No package installation.** The image is immutable, so `dnf5` and `rpm` do
  not belong in a recipe. Install software at build time, or point at a
  Brewfile, a Flatpak, or a container.
- Recipes run as the invoking user. Escalate with `sudo` or `pkexec` only where
  the step needs it.
- Nothing here runs automatically. An image update never rewrites a user's
  configuration or changes their groups — these recipes are the explicit way to
  do both.

## Testing

```bash
just --justfile custom/ujust/custom-apps.just --list
just --justfile custom/ujust/custom-apps.just install-default-apps
```

Or build and boot one: `just build && just run-vm-qcow2`, then run `ujust` in the
VM.
