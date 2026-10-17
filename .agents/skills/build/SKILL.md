---
name: build
description: >-
  The Containerfile, Justfile, build phases, image pinning, and the example
  scripts. Use when changing how the image is assembled or activating an
  example.
---

# Build

## The Containerfile

It is the source of truth for image assembly, and it is written to be read. Its
structure, in order:

1. **Identity** — `ARG IMAGE_NAME`, `IMAGE_VENDOR`, `UBLUE_IMAGE_TAG`, and the
   `# Name:` comment. The name actually published is the repository name; these
   are the local fallback and the image metadata.
2. **Context stage** — `COPY build /build`, `COPY custom /custom`, then the two
   OCI images into `/oci/common` and `/oci/brew`.
3. **Base** — the `FROM` line. The only place the base is chosen; the Fedora
   major, the image name, and the digest all follow from it.
4. **Phases** — one `RUN` block per script, in the order they are named.
   [build/README.md](../../../build/README.md) lists them.
5. **Metadata** — the `LABEL` block, fed by ARGs declared late so a new version
   or commit only invalidates the label layer.

Order matters for cache: volatile values go after the expensive layers.

## The Justfile

```bash
just build            # build the image
just build-qcow2      # build a QCOW2 disk image
just build-iso        # build an installer ISO
just run-vm-qcow2     # boot the image in a VM
just test-unit        # run the suite
just lint             # shellcheck every tracked script
just check            # verify Justfile syntax
```

`just --list` has the rest. `IMAGE_NAME` defaults to the value in the Justfile
and is overridable by the `IMAGE_NAME` environment variable; CI sets that from
the repository name.

## Pinning

Every OCI reference is pinned by digest and updated by Renovate: the base image,
`projectbluefin/common`, `ublue-os/brew`, `bootc-image-builder`, and the GitHub
Actions. Do not hand-edit a digest; let Renovate propose it.

Exception: the base image's Fedora major (the final `FROM
quay.io/fedora-ostree-desktops/silverblue:N` in `Containerfile`) is *not*
updated by Renovate. The `packageRules` entry in `.github/renovate.json` that
matches `matchDepNames: ["quay.io/fedora-ostree-desktops/*"]` with
`matchUpdateTypes: ["major"]` sets `enabled: false`, so *no* major update is
proposed for that namespace — including an already-released one such as
44 -> 45. That is deliberate: the namespace also tags unreleased branches, and
every major rebase is a manual step tied to a known-good validation. Bump the
tag in `Containerfile` by hand when the next major is released and validated.

The base image's `FROM` line is the only place the base is chosen, so the Fedora
major cannot desync the way a hand-maintained `FEDORA_MAJOR_VERSION` ARG could.
Two readers derive it from that base: `just build` parses the tag for the version
string, and `00-image-info.sh` reads the base's `os-release` for the image
metadata.

`BASE_IMAGE_NAME` has no default in the Containerfile on purpose: a stale default
like `silverblue` would silently mislabel a CentOS or Hummingbird fork. `just
build` fills it from the `FROM` line and `00-image-info.sh` hard-fails on an empty
value, so build through `just`; a bare `podman build .` is unsupported.

## Examples

`build/*.sh.example` are inactive until you activate them: rename the file off
`.example` and add a `RUN` block after the package phase.
[build/README.md](../../../build/README.md) has the block to copy.

`50-nvidia.sh.example` pulls `ghcr.io/ublue-os/akmods-nvidia-open` through a
`skopeo` policy that accepts only images signed by `build/akmods-cosign.pub`, a
copy of [ublue-os/akmods `cosign.pub`](https://github.com/ublue-os/akmods/blob/main/cosign.pub).
If upstream rotates that key, update the copy; do not weaken the policy to
`insecureAcceptAnything` to get a build through.
