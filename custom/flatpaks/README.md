# Flatpak Preinstall Integration

This directory contains Flatpak preinstall configuration files that will be copied into your custom image at `/usr/share/flatpak/preinstall.d/`.

## What is Flatpak Preinstall?

Flatpak preinstall is a feature that allows system administrators to define Flatpak applications that should be installed on first boot. These files are read by the Flatpak system integration and automatically install the specified applications.

## How It Works

1. **During Build**: Files in this directory are copied to `/usr/share/flatpak/preinstall.d/` in the image
2. **On First Boot**: After user setup completes, the system reads these files and installs the specified Flatpaks
3. **User Experience**: Applications appear automatically after first login

## Important: Installation Timing

**Flatpaks are NOT included in the ISO or container image.** They are downloaded and installed after:
- User completes initial system setup
- Network connection is established
- First boot process runs `flatpak preinstall`

This means:
- The ISO remains small and bootable offline
- Users need an internet connection after installation
- First boot may take longer while Flatpaks download and install
- This is NOT an offline ISO with pre-embedded applications

## File Format

Each file uses the INI format with `[Flatpak Preinstall NAME]` sections:

```ini
[Flatpak Preinstall org.mozilla.firefox]
Branch=stable

[Flatpak Preinstall org.gnome.Calculator]
Branch=stable
```

**Keys:**
- `Install` - (boolean) Whether to install (default: true)
- `Branch` - (string) Branch name (default: "master", commonly "stable")
- `IsRuntime` - (boolean) Whether this is a runtime (default: false for apps)
- `CollectionID` - (string) Collection ID of the remote, if any

See: https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall

## Usage

### Adding Flatpaks to Your Image

1. Edit [`default.preinstall`](default.preinstall) or create new `.preinstall` files in this directory
2. Add Flatpak references in INI format with `[Flatpak Preinstall NAME]` sections
3. Build your image - the files will be copied to `/usr/share/flatpak/preinstall.d/`
4. After user setup completes, Flatpaks will be automatically installed

**Example Files in this directory:**
- [`default.preinstall`](default.preinstall) - Core applications from Bluefin

### Finding Flatpak IDs

To find the ID of a Flatpak:
```bash
flatpak search app-name
```

Or browse Flathub: https://flathub.org/

## Customization

Edit the existing file or create new ones:
- **[`default.preinstall`](default.preinstall)** - Modify the default application list
- **Create new files:**
  - `development.preinstall` - Development tools
  - `gaming.preinstall` - Gaming applications
  - `media.preinstall` - Media editing tools

Each new `.preinstall` file will be automatically copied during the build process. See [`build/10-build.sh`](../../build/10-build.sh) for how files are copied.

## Important Notes

- Files must use the `.preinstall` extension
- Comments can be added with `#`
- Empty lines are ignored
- **Flatpaks are downloaded from Flathub on first boot** - not embedded in the image
- **Internet connection required** after installation for Flatpaks to install
- Installation happens automatically after user setup completes
- Users can still uninstall these applications if desired
- First boot will take longer while Flatpaks are being installed

## Resources

- [Flatpak Documentation](https://docs.flatpak.org/)
- [Flatpak Preinstall Reference](https://docs.flatpak.org/en/latest/flatpak-command-reference.html#flatpak-preinstall)
- [Flathub](https://flathub.org/)
