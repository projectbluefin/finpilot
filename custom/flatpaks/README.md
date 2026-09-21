# Flatpak preinstall

Declarations here are copied into the image at `/usr/share/flatpak/preinstall.d/`
and read on first boot by `flatpak-preinstall.service`, which installs each app
from Flathub. Nothing is embedded in the image or the ISO.

## Files

- `default.preinstall` — the apps installed on first boot

## Format

An INI file, one section per app:

```ini
[Flatpak Preinstall org.mozilla.Thunderbird]
Branch=stable
```

Keys: `Branch` (default `master`; use `stable`), `Install` (default true),
`IsRuntime` (default false), and `CollectionID` (only for a remote that needs
one).

Two gotchas:

- The parser is GKeyFile. Comments must start with `#`; a `;` line is a syntax
  error, and flatpak discards the entire file when one line is malformed.
- `just validate-flatpaks` checks every section for a `Branch=` key and confirms
  the app exists on Flathub. CI runs it too.

## Adding one

Append a section to `default.preinstall`, or add another `.preinstall` file. Find
the ID with `flatpak search`, or on [Flathub](https://flathub.org/).

## First boot

The Flathub remote comes from `/etc/flatpak/remotes.d/flathub.flatpakrepo`, which
the build fetches, so there is nothing to add by hand.

`flatpak-preinstall.service` needs the network. When it cannot reach Flathub it
logs a warning, installs nothing, and **still exits successfully**, so it does
not retry that boot. If the first boot happened before Wi-Fi was configured,
reboot once you are online and it will install.
