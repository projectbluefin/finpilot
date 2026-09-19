# vim: set ft=make :
####################
### custom-apps.just
####################
## Homebrew shortcuts.
##
## Every Brewfile in custom/brew/ is copied to /usr/share/ublue-os/homebrew/ at
## build time. Add a recipe here for each one, so users install it with `ujust`
## instead of remembering the path.
##
## See custom/brew/README.md.

# Install default applications via Homebrew
[group('Apps')]
install-default-apps:
    #!/usr/bin/env bash
    echo "Installing default applications via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile

# Install development tools via Homebrew
[group('Apps')]
install-dev-tools:
    #!/usr/bin/env bash
    echo "Installing development tools via Homebrew..."
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile
