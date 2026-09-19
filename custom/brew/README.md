# Homebrew

Brewfiles declared here are copied into the image at
`/usr/share/ublue-os/homebrew/`. Users install them after boot; nothing is
installed at build time.

## Files

- `default.Brewfile` — the essential CLI tools
- `development.Brewfile` — the development stack

The image also ships `/usr/share/ublue-os/homebrew/fonts.Brewfile`, a curated
font set from Common's shared layer, so this directory does not need its own.

## Adding one

Write a `.Brewfile` here, then add a `ujust` recipe for it in
`custom/ujust/custom-apps.just` so users install it by name instead of
remembering the path. That directory's README has the recipe shape.

## Format

A Brewfile is a Ruby DSL with three kinds of entry:

```ruby
tap "homebrew/cask"           # add a third-party repository
brew "bat"                    # a formula: a CLI tool
brew "eza"
cask "font-jetbrains-mono"    # a cask: a macOS-style package
```

- `tap` comes before anything that needs it.
- `brew` installs formulae.
- `cask` installs macOS-style packages. On Linux only some are available —
  mostly fonts and those that ship a Linux binary.

A repository Brewfile is never evaluated — that would be code execution from a
pull request. `just validate-brewfiles` checks one literally instead, and the
pre-commit hook calls the same script.

## Using them

```bash
brew bundle --file /usr/share/ublue-os/homebrew/default.Brewfile
```

or, on an image built from this template:

```bash
ujust install-default-apps
ujust install-dev-tools
```

Homebrew itself is pre-staged at build time and unpacked on first boot by
`brew-setup.service`.
