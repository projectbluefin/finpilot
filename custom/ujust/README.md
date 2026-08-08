# ujust - User-facing Just Commands

This directory contains Just recipe files that will be installed into your custom image and made available to end users via the `ujust` command.

## What is ujust?

`ujust` is a command that allows users to run predefined tasks on their system. It's built on top of [just](https://github.com/casey/just), a command runner similar to `make` but designed for commands rather than builds.

## How It Works

1. **During Build**: All `.just` files in this directory are consolidated and copied to `/usr/share/ublue-os/just/60-custom.just` in the image
2. **Automatic Import**: The base `ublue-os-just` package imports `60-custom.just`; Bluefin recipes from `projectbluefin/common` remain available in the build context but are not installed by default
3. **After Installation**: Users run `ujust` to see available commands
4. **User Experience**: Simple command interface for system tasks

## File Structure

Create `.just` files in this directory with your custom commands:

```
custom/ujust/
├── README.md          # This file
├── custom-apps.just   # Application installation commands
└── custom-system.just # System configuration commands
```

**Example Files in this directory:**
- [`custom-apps.just`](custom-apps.just) - Application installation commands (Brewfiles, Flatpaks, JetBrains Toolbox)
- [`custom-system.just`](custom-system.just) - System configuration commands (benchmarks, dev groups, maintenance)

## Example Commands

### Basic Command
```just
# Run a system maintenance task
run-maintenance:
    echo "Running maintenance..."
    sudo systemctl restart some-service
```

### Interactive Command with gum
```just
# Configure system setting
configure-thing:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh
    echo "Configure thing?"
    OPTION=$(Choose "Enable" "Disable")
    if [[ "${OPTION,,}" =~ ^enable ]]; then
        echo "Enabling..."
        # your enable logic
    else
        echo "Disabling..."
        # your disable logic
    fi
```

### Command with Group
```just
# Groups organize commands in ujust help
[group('Apps')]
install-brewfile:
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile
```

## Best Practices

### Naming Conventions
- Use lowercase with hyphens: `install-something`
- Use verb prefixes for clarity:
  - `install-` - Install something
  - `configure-` - Configure something pre-installed
  - `setup-` - Install + configure
  - `toggle-` - Enable/disable a feature
  - `fix-` - Apply a fix or workaround

### Command Structure
```just
# Brief description of what the command does
[group('Category')]
command-name:
    #!/usr/bin/bash
    # Use bash shebang for multi-line scripts
    # Commands go here
```

### Error Handling
```just
install-something:
    #!/usr/bin/bash
    set -euo pipefail  # Exit on error, undefined vars, pipe failures
    # Your commands
```

### User Prompts
Use `gum` for interactive prompts. The template installs it at build time because the default ujust recipes depend on it:
```just
interactive-command:
    #!/usr/bin/bash
    source /usr/lib/ujust/ujust.sh  # Provides Choose() and other helpers
    OPTION=$(Choose "Option 1" "Option 2" "Cancel")
    echo "You chose: $OPTION"
```

## Common Use Cases

### 1. Installing Software via Brewfiles
```just
[group('Apps')]
install-dev-tools:
    brew bundle --file /usr/share/ublue-os/homebrew/development.Brewfile
```

**See examples in [`custom-apps.just`](custom-apps.just)** for Brewfile shortcuts.

### 2. System Configuration
```just
[group('System')]
configure-firewall:
    #!/usr/bin/bash
    sudo firewall-cmd --permanent --add-service=ssh
    sudo firewall-cmd --reload
```

**See examples in [`custom-system.just`](custom-system.just)** for system configuration.

### 3. Development Environment Setup
```just
[group('Development')]
setup-nodejs:
    #!/usr/bin/bash
    curl -fsSL https://fnm.vercel.app/install | bash
    source ~/.bashrc
    fnm install --lts
```

### 4. Maintenance Tasks
```just
[group('Maintenance')]
clean-containers:
    podman system prune -af
    podman volume prune -f
```

**See examples in [`custom-system.just`](custom-system.just)** for maintenance tasks.

## Important: Package Installation

**Do not install packages via dnf5/rpm in ujust commands.** Bootc images are immutable and package installation should happen at build time in [`build/10-build.sh`](../../build/10-build.sh).

For runtime package installation, use:
- **Brewfiles** - Create shortcuts to Brewfiles in [`custom/brew/`](../brew/)
- **Flatpak** - Install Flatpaks for GUI applications
- **Containers** - Use toolbox/distrobox for development environments

Example Brewfile shortcut (from [`custom-apps.just`](custom-apps.just)):
```just
[group('Apps')]
install-fonts:
    brew bundle --file /usr/share/ublue-os/homebrew/fonts.Brewfile
```

## Available Helpers

Universal Blue images include helpers in `/usr/lib/ujust/ujust.sh`:

- `Choose()` - Present multiple choice menu
- `Confirm()` - Yes/no prompt
- Color variables: `${bold}`, `${normal}`, etc.

## Testing Your Commands

Test locally before committing:

1. Build your image: `just build` (see [`Justfile`](../../Justfile))
2. If on a bootc system: `sudo bootc switch --target localhost/your-repo-name:stable`
3. Reboot and test: `ujust your-command`

Or test the just files directly:
```bash
just --justfile custom/ujust/custom-apps.just --list
just --justfile custom/ujust/custom-apps.just install-something
```

## Customization

**Start by editing the example files:**
- **[`custom-apps.just`](custom-apps.just)** - Add your application installation commands
- **[`custom-system.just`](custom-system.just)** - Add your system configuration commands

**Create new files** for different categories:
- `custom-gaming.just` - Gaming-related commands
- `custom-media.just` - Media editing workflows
- `custom-dev.just` - Development environment setups

All `.just` files in this directory are automatically included. See [`build/10-build.sh`](../../build/10-build.sh) for the consolidation logic.

## Groups for Organization

Use groups to categorize commands:

```just
[group('Apps')]
install-app:
    echo "Installing app..."

[group('System')]
configure-system:
    echo "Configuring system..."

[group('Development')]
setup-dev:
    echo "Setting up dev environment..."
```

## Examples from Bluefin

The included files provide starting examples:
- **[`custom-apps.just`](custom-apps.just)** - Application installation commands
- **[`custom-system.just`](custom-system.just)** - System configuration commands

These files show how to:
- Create shortcuts to Brewfiles in [`custom/brew/`](../brew/)
- Install Flatpaks interactively
- Configure system settings
- Run maintenance tasks

## Resources

- [Just Manual](https://just.systems/man/en/)
- [Universal Blue Just Documentation](https://universal-blue.org/guide/just/)
- [Bluefin ujust Commands](https://docs.projectbluefin.io/administration)
- [gum Documentation](https://github.com/charmbracelet/gum)

## Notes

- Commands run with user privileges by default
- Use `sudo` or `pkexec` when root access needed
- Consider providing both install and uninstall options
- Test on a clean system before distributing
- Document any prerequisites or dependencies
