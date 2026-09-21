---
name: overview
description: >-
  Architecture, repository layout, and file map for this template.
  Use when orienting to the repository, tracing how the image is assembled,
  or deciding which skill covers a task.
---

# Overview

This repository builds a bootc operating system image by assembling OCI layers
rather than by modifying an existing image. Bluefin, Aurora, and Bluefin LTS are
built the same way, so the desktop configuration here is the one they ship.

## How the image is assembled

The `Containerfile` is the source of truth, and it is deliberately verbose. It
defines three things:

1. **Context stage** (`ctx`) — combines the local `build/` and `custom/`
   directories with files pulled from two OCI images:

   - `ghcr.io/projectbluefin/common` — the shared desktop configuration,
     branding, and the Brew/Flatpak/ujust plumbing
   - `ghcr.io/ublue-os/brew` — the Homebrew integration

2. **Base image** — the `FROM` line. It defaults to Fedora Silverblue and is the
   only place the base is chosen. `just build` reads the image name and tag from
   it; the Fedora major is read from the base image itself during the build.

3. **Phases** — each build script runs in its own `RUN` block, in the order the
   Containerfile names them. [build/README.md](../../../build/README.md) lists
   them.

## Layout

| Path | Holds |
|---|---|
| `Containerfile` | Image assembly: identity, base image, and phases. |
| `Justfile` | Build, VM, release, and test recipes. |
| `build/` | Build-time scripts: the phases, helpers, and the `.example` catalogue. |
| `custom/brew/` | Brewfiles, installed at runtime. |
| `custom/flatpaks/` | Flatpak preinstall declarations, installed on first boot. |
| `custom/ujust/` | `ujust` recipes. |
| `custom/files/` | System files overlaid onto `/`. |
| `custom/config/` | Per-user config seeded into `/etc/skel/.config/`. |
| `iso/` | Installer ISO and disk-image configuration. |
| `tests/` | `contract/` (interfaces the image must satisfy) and `template/` (this repository's build wiring). |
| `.github/` | Workflows, Renovate config, issue templates. |

## Which skill

| I need to… | Load |
|---|---|
| Understand the repository, or find the right skill | `overview` |
| Fork it and reach a first green build | `onboarding` |
| Add or remove a package, app, or command | `customize` |
| Change the Containerfile, Justfile, or a build phase | `build` |
| Change a workflow, Renovate, or the release model | `ci` |
| Fix something broken, or check before a pull request | `troubleshooting` |

## Upstream

The template consumes Project Bluefin's shared infrastructure rather than
copying it:

- `projectbluefin/common` — the shared runtime layer and the lifecycle label
  workflow
- `projectbluefin/actions` — the reusable workflows for image build, promotion,
  sync, PR validation, and Renovate
- `ublue-os/brew` — the Homebrew integration

Changes stay in this repository. `ublue-os/*` is read-only.
