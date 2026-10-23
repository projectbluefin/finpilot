#!/usr/bin/env bats
# Contract: the tags build-image.yml publishes are the tags the release path
# reads.
#
# build-image.yml decides its tags in two inline bash steps. "Determine image
# tag" turns a build on main into the testing stream, and "Finalize branch
# tags" rewrites the generate-tags output into the names that get pushed. Two
# other workflows depend on the result without being able to see it:
# execute-release.yml and promote-main-to-stable.yml both resolve the
# candidate digest from the bare :testing tag, and users on the testing branch
# follow :stable-testing. If the rewrite stopped emitting :testing, every
# release would keep promoting the last candidate that still carried it; if it
# let a stable-daily* or bare :stable tag through, a main build would overwrite
# what stable users run without passing the release gate. Neither failure
# shows up in the build's own log, which still reports a successful push.
#
# The two steps are lifted out of the workflow and run for real, so a change to
# either one is tested as written. The generate-tags output they consume is
# fed in as fixtures in the shape the pinned projectbluefin/actions
# bootc-build/generate-tags action emits for each stream.
#
# Run with: bats tests/contract/build-image-tags_test.bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
WORKFLOW="${REPO_ROOT}/.github/workflows/build-image.yml"
EXECUTE_RELEASE="${REPO_ROOT}/.github/workflows/execute-release.yml"
PROMOTE="${REPO_ROOT}/.github/workflows/promote-main-to-stable.yml"

VERSION="44.20261022"
VERSION_DATE="20261022"

# Lift a step's `run: |` block out of the workflow and dedent it. The marker
# names the step's `name:` line so a comment that mentions the step cannot
# start the extraction early. The block ends at the first line indented no
# deeper than the `run:` key.
extract_run_block() {
	awk -v marker="$1" '
		index($0, marker) { found = 1 }
		found && !grab && $0 ~ /run: \|/ { match($0, /^ */); indent = RLENGTH; grab = 1; next }
		grab {
			if ($0 ~ /^[[:space:]]*$/) { print ""; next }
			match($0, /^ */)
			if (RLENGTH <= indent) exit
			print substr($0, indent + 3)
		}
	' "${WORKFLOW}"
}

# Read a top-level `env:` value of build-image.yml, so the tests use the
# defaults the workflow uses instead of a copy that can drift.
workflow_env() {
	sed -n "s/^  $1: \"\([^\"]*\)\".*/\1/p" "${WORKFLOW}"
}

# The tags generate-tags emits for a non-PR build of a stream, as computed by
# bootc-build/generate_tags.sh: the stream, the stream with the full version,
# and the stream with the date part of the version. A stable stream uses the
# stable-daily prefix and also gets the bare version.
generated_tags_for() {
	case "$1" in
	testing) echo "testing testing-${VERSION} testing-${VERSION_DATE}" ;;
	stable) echo "stable-daily ${VERSION} stable-daily-${VERSION} stable-daily-${VERSION_DATE}" ;;
	*) return 1 ;;
	esac
}

# Both steps run under `shell: bash`, which GitHub invokes as
# `bash --noprofile --norc -eo pipefail`; the helpers below do the same.

# Run "Determine image tag" for a ref and load what it wrote to GITHUB_ENV.
determine_tag() {
	local env_file="${BATS_TEST_TMPDIR}/github_env"
	: >"${env_file}"
	REF_NAME="$1" \
		DEFAULT_TAG="${WF_DEFAULT_TAG}" \
		PRODUCTION_BRANCH="${WF_PRODUCTION_BRANCH}" \
		GITHUB_ENV="${env_file}" \
		bash --noprofile --norc -eo pipefail "${DETERMINE_SCRIPT}" >/dev/null

	# GitHub applies GITHUB_ENV to the next steps; start from the workflow
	# default and let the file override it the same way.
	DEFAULT_TAG="${WF_DEFAULT_TAG}"
	TAG_STREAM=""
	local line
	while IFS= read -r line; do
		case "${line}" in
		DEFAULT_TAG=*) DEFAULT_TAG="${line#DEFAULT_TAG=}" ;;
		TAG_STREAM=*) TAG_STREAM="${line#TAG_STREAM=}" ;;
		*) echo "unexpected GITHUB_ENV line: ${line}" >&2 && return 1 ;;
		esac
	done <"${env_file}"
}

# Run "Finalize branch tags" and expose its outputs as TAGS and OUT_DEFAULT_TAG.
finalize_tags() {
	local out_file="${BATS_TEST_TMPDIR}/github_output"
	: >"${out_file}"
	GENERATED_TAGS="$1" \
		TAG_STREAM="$2" \
		DEFAULT_TAG="$3" \
		GITHUB_OUTPUT="${out_file}" \
		bash --noprofile --norc -eo pipefail "${FINALIZE_SCRIPT}"
	TAGS="$(sed -n 's/^tags=//p' "${out_file}")"
	OUT_DEFAULT_TAG="$(sed -n 's/^default-tag=//p' "${out_file}")"
}

# The tag a JSON `source_tag`/`target_tag` field or a YAML `target_tag:` key
# names in one of the release workflows.
release_tag_in() {
	grep -oE "\"source_tag\":\"[^\"]+\"|target_tag: [A-Za-z0-9._-]+" "$1" |
		sed -E 's/.*[:"] ?"?([A-Za-z0-9._-]+)"?$/\1/' | head -n1
}

has_tag() {
	local want="$1" tag
	for tag in ${TAGS}; do
		[[ "${tag}" == "${want}" ]] && return 0
	done
	return 1
}

setup() {
	DETERMINE_SCRIPT="${BATS_TEST_TMPDIR}/determine.sh"
	FINALIZE_SCRIPT="${BATS_TEST_TMPDIR}/finalize.sh"
	extract_run_block "name: Determine image tag" >"${DETERMINE_SCRIPT}"
	extract_run_block "name: Finalize branch tags" >"${FINALIZE_SCRIPT}"

	# Guard the extraction: an empty or truncated script would let every
	# assertion below pass against nothing.
	grep -q 'TAG_STREAM=testing' "${DETERMINE_SCRIPT}"
	grep -q 'add_tag "${DEFAULT_TAG}"' "${FINALIZE_SCRIPT}"

	WF_DEFAULT_TAG="$(workflow_env DEFAULT_TAG)"
	WF_PRODUCTION_BRANCH="$(workflow_env PRODUCTION_BRANCH)"
	[ -n "${WF_DEFAULT_TAG}" ]
	[ -n "${WF_PRODUCTION_BRANCH}" ]
}

@test "build-image-tags: a main build is a testing build tagged stable-testing" {
	determine_tag main

	[ "${TAG_STREAM}" = "testing" ]
	[ "${DEFAULT_TAG}" = "${WF_DEFAULT_TAG}-testing" ]
	[ "${DEFAULT_TAG}" = "stable-testing" ]
}

@test "build-image-tags: any ref other than the production branch is a testing build" {
	local ref
	for ref in main feature/x "${WF_PRODUCTION_BRANCH}-hotfix"; do
		determine_tag "${ref}"
		[ "${TAG_STREAM}" = "testing" ]
		[ "${DEFAULT_TAG}" = "${WF_DEFAULT_TAG}-testing" ]
	done
}

@test "build-image-tags: the production branch keeps the stable stream and default tag" {
	determine_tag "${WF_PRODUCTION_BRANCH}"

	[ "${TAG_STREAM}" = "${WF_DEFAULT_TAG}" ]
	[ "${DEFAULT_TAG}" = "${WF_DEFAULT_TAG}" ]
}

@test "build-image-tags: a testing build publishes exactly the testing set" {
	finalize_tags "$(generated_tags_for testing)" testing stable-testing

	[ "${TAGS}" = "testing stable-testing stable-testing-${VERSION} stable-testing-${VERSION_DATE}" ]
	[ "${OUT_DEFAULT_TAG}" = "stable-testing" ]
}

@test "build-image-tags: a main build publishes the tag the release gate resolves" {
	local release_source promote_target
	release_source="$(release_tag_in "${EXECUTE_RELEASE}")"
	promote_target="$(release_tag_in "${PROMOTE}")"
	[ "${release_source}" = "testing" ]
	[ "${promote_target}" = "testing" ]

	determine_tag main
	finalize_tags "$(generated_tags_for "${TAG_STREAM}")" "${TAG_STREAM}" "${DEFAULT_TAG}"

	has_tag "${release_source}"
	has_tag "${promote_target}"
	has_tag "${DEFAULT_TAG}"
}

@test "build-image-tags: a main build never publishes a stable or stable-daily tag" {
	determine_tag main
	finalize_tags "$(generated_tags_for "${TAG_STREAM}")" "${TAG_STREAM}" "${DEFAULT_TAG}"

	local tag
	for tag in ${TAGS}; do
		[[ "${tag}" != "stable" ]]
		[[ "${tag}" != stable-daily* ]]
		[[ "${tag}" != "${VERSION}" ]]
		[[ "${tag}" == "testing" || "${tag}" == stable-testing* ]]
	done
}

@test "build-image-tags: a testing build renames every stream tag, not only the bare one" {
	finalize_tags "$(generated_tags_for testing)" testing stable-testing

	local tag
	for tag in ${TAGS}; do
		[[ "${tag}" != testing-* ]]
	done
	has_tag "stable-testing-${VERSION}"
	has_tag "stable-testing-${VERSION_DATE}"
}

@test "build-image-tags: the default tag is published once even when generated again" {
	finalize_tags "testing testing-${VERSION} testing testing-${VERSION}" testing stable-testing

	[ "${TAGS}" = "testing stable-testing stable-testing-${VERSION}" ]
	[ "$(tr ' ' '\n' <<<"${TAGS}" | sort | uniq -d)" = "" ]
}

@test "build-image-tags: the default tag is published even when generate-tags omits it" {
	finalize_tags "testing-${VERSION}" testing stable-testing

	[ "${TAGS}" = "stable-testing-${VERSION} stable-testing" ]
	[ "${OUT_DEFAULT_TAG}" = "stable-testing" ]
}

@test "build-image-tags: a production build passes the generated tags through and adds :stable" {
	determine_tag "${WF_PRODUCTION_BRANCH}"
	finalize_tags "$(generated_tags_for stable)" "${TAG_STREAM}" "${DEFAULT_TAG}"

	[ "${TAGS}" = "stable-daily ${VERSION} stable-daily-${VERSION} stable-daily-${VERSION_DATE} stable" ]
	[ "${OUT_DEFAULT_TAG}" = "stable" ]
	run has_tag testing
	[ "$status" -ne 0 ]
}

@test "build-image-tags: the build only runs from main, so the production path is never published" {
	# The production branch receives the gated candidate digest from
	# execute-release.yml and must never rebuild. Pin the two guards that keep
	# the production tag set above unreachable from a run of this workflow.
	run awk '/^on:/{on=1} on && /^[a-z]/ && !/^on:/{exit} on' "${WORKFLOW}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"branches:"*"- main"* ]]
	[[ "$output" != *"- ${WF_PRODUCTION_BRANCH}"* ]]

	grep -qF "if: github.event_name != 'workflow_dispatch' || github.ref_name == github.event.repository.default_branch" "${WORKFLOW}"
}
