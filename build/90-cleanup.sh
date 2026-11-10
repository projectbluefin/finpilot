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

# Revert the build-time dnf settings the Containerfile installs. Removing the
# keys, rather than overwriting one, leaves the base image's dnf.conf as it was,
# so packages installed on top of the image still pull in weak dependencies.
dnf5 config-manager unsetopt keepcache install_weak_deps
dnf5 versionlock clear

# Disable every third-party repository. copr_install_isolated already disables
# each COPR it uses; this is the backstop for anything else the build enabled.
disable_repo_file() {
	[[ -f "$1" ]] || return 0
	sed -i -E 's@^[[:space:]]*enabled[[:space:]]*=.*@enabled=0@I' "$1"
}

# One list feeds both the disable pass and the guard below, so a repository
# the script knows how to disable is always one the guard re-checks.
third_party_repo_files=(
	"${REPOS_DIR}"/_copr:*.repo
	"${REPOS_DIR}"/_copr_*.repo
	"${REPOS_DIR}"/rpmfusion-*.repo
)
for repo_name in fedora-multimedia tailscale fedora-cisco-openh264 fedora-coreos-pool; do
	third_party_repo_files+=("${REPOS_DIR}/${repo_name}.repo")
done

# A vendor repository the build added (for example vscode.repo from an
# addrepo, or nvidia-container-toolkit.repo from a curl) has no fixed name in
# this list, so classify by ownership too: base Fedora repo files are owned by
# fedora-repos*, while anything dnf5, config-manager or a script writes is
# owned by nothing and is therefore third-party.
#
# rpm is always present in a bootc Fedora image, but guard the pass so a
# missing rpm can never make every base file look unowned and disable the base
# repositories. De-duplicate below, since the ownership pass can name a file
# the fixed list already covers.
if command -v rpm >/dev/null 2>&1; then
	for repo_file in "${REPOS_DIR}"/*.repo; do
		[[ -f "${repo_file}" ]] || continue
		rpm -qf "${repo_file}" >/dev/null 2>&1 && continue
		third_party_repo_files+=("${repo_file}")
	done
fi

# The fixed globs and the ownership pass can name the same file twice, so
# de-duplicate before both loops see the list.
declare -A third_party_seen=()
third_party_unique=()
for repo_file in "${third_party_repo_files[@]}"; do
	[[ -n "${third_party_seen["${repo_file}"]:-}" ]] && continue
	third_party_seen["${repo_file}"]=1
	third_party_unique+=("${repo_file}")
done
third_party_repo_files=("${third_party_unique[@]}")

for repo_file in "${third_party_repo_files[@]}"; do
	disable_repo_file "${repo_file}"
done

# Fail loudly rather than shipping a third-party repository that is still live.
# Ask dnf which repositories are actually enabled, rather than pattern-matching
# the .repo files: a repository that ships with no enabled= key is enabled by
# dnf's default and slips past both the rewrite above and a grep of the file.
# The allowlist is an exact set of Fedora's own repository ids; anything else
# dnf reports as live, including Fedora-like names such as fedora-multimedia,
# leaked through the disable pass and fails the build.
if ! repo_list="$(dnf5 -q repo list --enabled)"; then
	echo "::error::could not query enabled repositories with dnf5" >&2
	exit 1
fi
live="$(printf '%s\n' "${repo_list}" | awk '
	BEGIN { split("fedora updates fedora-updates fedora-cisco-openh264", ok, " "); for (i in ok) allowed[ok[i]] = 1 }
	NF == 0 { next }
	$1 == "repo" && $2 == "id" { next }
	$1 == "Id" || $1 == "Id:" { next }
	!($1 in allowed) { print $1 }
')"
if [ -n "${live}" ]; then
	echo "::error::third-party repository still enabled: ${live}" >&2
	exit 1
fi

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
