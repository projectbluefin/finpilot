#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Example: Tailscale from the vendor RPM repository
###############################################################################
# Teaches the third-party repository pattern: add the vendor's repository,
# install from it, then take the repository back out. The image ships no live
# third-party source and no repository file left enabled to rot.
#
# Tailscale is the worked example because it is the common ask. The pattern is
# the same for any vendor that publishes a .repo file: swap the URL and the
# package name.
#
# To use this script:
# 1. Rename it to remove the .example extension: 30-tailscale.sh
# 2. Add the explicit RUN block from build/README.md for
#    /ctx/build/30-tailscale.sh after the 20-packages-and-services.sh block and
#    before the 90-cleanup.sh block in the Containerfile.
#
# Fedora also packages tailscale, but lags upstream by several releases. The
# vendor repository is used to track current upstream builds.
###############################################################################

echo "::group:: Install Tailscale"

# Let dnf5 fetch the vendor's own .repo file instead of hand-writing one, so
# baseurl and gpgkey stay the vendor's responsibility and cannot drift.
dnf5 config-manager addrepo --overwrite \
	--from-repofile=https://pkgs.tailscale.com/stable/fedora/tailscale.repo
dnf5 install -y tailscale

# Remove the repository file. A third-party repository is a build-time source
# only; 90-cleanup.sh also disables tailscale.repo as a backstop.
rm -f /etc/yum.repos.d/tailscale.repo

echo "::endgroup::"

echo "::group:: Enable the Tailscale daemon"

# tailscaled runs the tailnet. Joining one is a first-boot action for the person
# at the machine, so the image only enables the unit: it never runs
# `tailscale up` and never embeds an auth key.
systemctl enable tailscaled.service

echo "::endgroup::"
