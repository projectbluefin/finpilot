#!/usr/bin/env bash

set -euo pipefail

###############################################################################
# Final cleanup
###############################################################################
# The last mutation before image metadata, init, and `bootc container lint`.
# It finalises package and Flatpak sources, then prunes build artifacts.
#
# CLEAN_ROOT is a test seam: it prefixes every filesystem path and defaults to
# "/" in the image build.
###############################################################################

CLEAN_ROOT="${CLEAN_ROOT:-/}"
REPOS_DIR="${CLEAN_ROOT}/etc/yum.repos.d"

echo "::group:: Finalise package repositories"

# Revert the build-time dnf settings the Containerfile installs.
dnf5 config-manager setopt keepcache=0
dnf5 versionlock clear

# Disable every third-party repository. copr_install_isolated already disables
# each COPR it uses; this is the backstop for anything else the build enabled.
disable_repo_file() {
	[[ -f "$1" ]] || return 0
	sed -i 's@enabled=1@enabled=0@g' "$1"
}

for repo_file in "${REPOS_DIR}"/_copr:*.repo "${REPOS_DIR}"/_copr_*.repo "${REPOS_DIR}"/rpmfusion-*.repo; do
	disable_repo_file "${repo_file}"
done
for repo_name in fedora-multimedia tailscale fedora-cisco-openh264 fedora-coreos-pool; do
	disable_repo_file "${REPOS_DIR}/${repo_name}.repo"
done

# Fail loudly rather than shipping a third-party repository that is still live.
for repo_file in "${REPOS_DIR}"/_copr:*.repo "${REPOS_DIR}"/_copr_*.repo "${REPOS_DIR}"/rpmfusion-*.repo; do
	[[ -f "${repo_file}" ]] || continue
	if grep -qE '^enabled=1' "${repo_file}"; then
		echo "::error::third-party repository still enabled: $(basename "${repo_file}")" >&2
		exit 1
	fi
done

echo "::endgroup::"

echo "::group:: Finalise Flatpak sources"

# The Fedora Flatpak remote must never be added on first boot.
systemctl disable flatpak-add-fedora-repos.service
systemctl mask flatpak-add-fedora-repos.service
rm -f "${CLEAN_ROOT}/usr/lib/systemd/system/flatpak-add-fedora-repos.service"

echo "::endgroup::"

echo "::group:: Finalise automatic updates"

# uupd owns the update policy; stop the desktop base's own updater racing it.
# Guarded so a base without the unit (for example a non-Silverblue base) still
# builds instead of failing on a missing unit.
systemctl disable rpm-ostreed-automatic.timer 2>/dev/null || true

echo "::endgroup::"

echo "::group:: Prune build artifacts"

rm -rf "${CLEAN_ROOT}/.gitkeep"
# Use -mindepth/-maxdepth instead of shell globs so these are no-ops when the
# directories are empty (e.g. /var/cache/{libdnf5,rpm-ostree} only exist as
# transient buildah cache mounts and are not present in this layer).
find "${CLEAN_ROOT}/var" -mindepth 1 -maxdepth 1 -type d \! -name cache -exec rm -fr {} \;
find "${CLEAN_ROOT}/var/cache" -mindepth 1 -maxdepth 1 -type d \! -name libdnf5 \! -name rpm-ostree -exec rm -fr {} \;

# Clear tmpfs-backed runtime directories without deleting the directories
# themselves. Buildah may have bind mounts in these paths during RUN, so
# replacing the mountpoint can fail with EBUSY.
for runtime_dir in tmp boot; do
	mkdir -p "${CLEAN_ROOT:?}/${runtime_dir}"
	find "${CLEAN_ROOT:?}/${runtime_dir}" -mindepth 1 -maxdepth 1 -print0 |
		while IFS= read -r -d '' entry; do
			if mountpoint -q "${entry}" 2>/dev/null; then
				continue
			fi
			rm -rf "${entry}"
		done
done

# /run can contain nested bind mounts created by the build container. Walk it
# depth-first so we can remove image-owned files like /run/dnf while leaving
# mounted files and any directories that still contain them alone.
mkdir -p "${CLEAN_ROOT:?}/run"
find "${CLEAN_ROOT:?}/run" -mindepth 1 -depth -print0 |
	while IFS= read -r -d '' entry; do
		if mountpoint -q "${entry}" 2>/dev/null; then
			continue
		fi
		if [[ -d "${entry}" ]]; then
			rmdir "${entry}" 2>/dev/null || true
			continue
		fi
		rm -f "${entry}"
	done

echo "::endgroup::"
