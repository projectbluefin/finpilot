#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Runtime overlays
###############################################################################
# This phase owns every runtime integration the image applies on top of its
# base: the selected Common and Brew filesystem overlays, the template's custom
# declaration seams, and the systemd enablement that makes those declarations
# live.
#
# It installs nothing. RPM and COPR installation belongs to
# 20-packages-and-services.sh.
#
# Order is the contract. Every step writes over the one above it, so a later
# step deliberately wins:
#
#   1. common/shared     reusable runtime infrastructure
#   2. ublue-os/brew     the Homebrew mechanism and its shell integration
#   3. custom/files      the override seam: mirrors / and may replace anything
#   4. custom/config     per-user defaults, seeded into /etc/skel/.config
#
# The declaration seams write into directories the overlays above created:
# custom/brew/*.Brewfile, custom/ujust/ (any depth), and
# custom/flatpaks/*.preinstall.
# A custom file sharing a name with an inherited one overrides it. That follows
# the same precedence rule; it is not a collision to guard against.
#
# common/bluefin/ is imported into the build context but never overlaid:
# shared/ is reusable runtime infrastructure, while bluefin/ is product
# opinion, and nvidia/ is a paired hardware feature that must ship with a real
# driver installation.
###############################################################################

shopt -s nullglob

echo "::group:: Overlay shared Common runtime files"

# Shared runtime substrate: the ujust entry point and wrapper, first-boot setup
# hooks, container trust policy, and the Flatpak/Brew declarations these
# services consume.
#
# /etc/containers/policy.json arrives here, and the template deliberately takes
# it unmodified. Its sigstore scopes cover ghcr.io/ublue-os and
# quay.io/toolbx-images; this image's own namespace matches the `""` catch-all
# (insecureAcceptAnything), which is why 00-image-info.sh writes an unverified
# update transport. Merging a scope for this namespace — with jq, never by
# forking the file through custom/files, which would freeze every inherited
# scope — is only worth doing once the image is signed with a key the policy
# can name; a keyless GitHub Actions identity is unmatchable here.
rsync -rvK /ctx/oci/common/shared/ /

echo "::endgroup::"

echo "::group:: Overlay Brew integration files"

# Brew supplies the Homebrew mechanism (archive, systemd units, shell
# integration). The template supplies the package declarations below.
rsync -rvK /ctx/oci/brew/ /

echo "::endgroup::"

echo "::group:: Overlay template system files"

# custom/files mirrors the image root, so a fork can ship systemd units,
# presets, and other system payloads by path. The leading slash anchors the
# exclusion to the copy root, so the seam's own README never lands in the image
# while a nested file named README.md still ships.
rsync -rvKl --exclude=/README.md /ctx/custom/files/ /

echo "::endgroup::"

echo "::group:: Copy template custom declarations"

# custom/config seeds each new user's ~/.config. Updating users who already
# exist is a deliberate, idempotent ujust command, never an automatic login
# hook. The leading slash anchors the exclusion to the copy root, so only the
# seam's own README is skipped and a nested file named README.md still ships.
if [[ -d /ctx/custom/config ]]; then
	mkdir -p /etc/skel/.config
	rsync -a --exclude=/README.md /ctx/custom/config/ /etc/skel/.config/
fi

# Brewfiles consumed by first-user Homebrew setup.
mkdir -p /usr/share/ublue-os/homebrew/
cp /ctx/custom/brew/*.Brewfile /usr/share/ublue-os/homebrew/

# Merge custom ujust recipes into the file the shared ujust entry point imports.
# Walk the tree so a fork can organise recipes into subdirectories, and sort the
# inputs so the merged result is deterministic and idempotent.
mkdir -p /usr/share/ublue-os/just/
: >/usr/share/ublue-os/just/60-custom.just
if [[ -d /ctx/custom/ujust ]]; then
	mapfile -t recipes < <(find /ctx/custom/ujust -type f -iname '*.just' | LC_ALL=C sort)
	for recipe in "${recipes[@]}"; do
		cat "${recipe}" >>/usr/share/ublue-os/just/60-custom.just
		printf '\n' >>/usr/share/ublue-os/just/60-custom.just
	done
fi

# Flatpak preinstall declarations, consumed at first boot.
mkdir -p /usr/share/flatpak/preinstall.d/
cp /ctx/custom/flatpaks/*.preinstall /usr/share/flatpak/preinstall.d/

echo "::endgroup::"

echo "::group:: Add the Flathub remote descriptor"

# flatpak imports remotes from /etc/flatpak/remotes.d into the default system
# installation the first time it is used, then records them in the repository's
# applied-remotes list: the remote is imported once, and is the user's to remove
# afterwards. Shipping the descriptor is therefore all that is needed. There is
# deliberately no unit and no build-time `flatpak remote-add`, which would only
# write to /var and be pruned by 90-cleanup.sh. Fetched rather than committed so
# Flathub's signing key stays current.
install -d -m0755 /etc/flatpak/remotes.d
curl --fail --retry 3 --silent --show-error \
	--output /etc/flatpak/remotes.d/flathub.flatpakrepo \
	https://dl.flathub.org/repo/flathub.flatpakrepo

echo "::endgroup::"

echo "::group:: Enable runtime services"

# Units the overlays above provide. Enabling them here is what makes the Brew
# and Flatpak declarations take effect, and it matches how Bluefin's cleanup
# phase wires the same shared services.
systemctl enable brew-setup.service
systemctl enable brew-update.timer
systemctl enable brew-upgrade.timer
systemctl --global enable brew-preinstall.service
systemctl enable flatpak-preinstall.service
systemctl enable flatpak-appstream-refresh.service

# First-boot setup framework.
systemctl enable ublue-system-setup.service
systemctl --global enable ublue-user-setup.service

# Rootless container management for the reference image.
systemctl enable podman.socket

echo "::endgroup::"

shopt -u nullglob

echo "Overlay phase complete!"
