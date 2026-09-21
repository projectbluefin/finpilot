#!/usr/bin/env bats
# Unit tests for .github/workflows/execute-release.yml and the signature identity
# the release workflows share.
#
# Nothing else catches this. The workflow accepts a release only when the
# pushed commit subject matches its pattern, and a subject that stopped
# matching used to report success while promoting nothing, leaving no :stable
# image and no release behind. The pattern is read out of the workflow rather
# than duplicated here, so the two cannot drift apart unnoticed. The signature
# identity is read the same way, because an over-broad one accepts a signature
# from any repository in the org.
#
# Run with: bats tests/template/execute-release_test.bats

SCRIPT_DIR="$(cd "$(dirname "${BATS_TEST_FILENAME}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/../.."
WORKFLOW="${SCRIPT_DIR}/../../.github/workflows/execute-release.yml"

setup() {
	local line
	line=$(grep -F '=~ ' "${WORKFLOW}")

	# Strip the shell wrapper, leaving the pattern itself.
	PATTERN="${line#*=~ }"
	PATTERN="${PATTERN% ]]; then}"

	# If the workflow line is reformatted, fail here rather than letting an
	# empty pattern match every subject below.
	[ -n "${PATTERN}" ]
	[[ "${PATTERN}" == ^* ]]
}

@test "execute-release: accepts the subject a squash promotion produces" {
	# squash_merge_commit_title is COMMIT_OR_PR_TITLE and the promotion branch
	# carries a single commit, so this is the subject GitHub writes.
	[[ "chore: promote main to stable" =~ ${PATTERN} ]]
	[[ "chore: promote main to stable (#22)" =~ ${PATTERN} ]]
}

@test "execute-release: accepts the rendered promotion PR title" {
	# Insurance: this becomes the subject if the branch ever carries more than
	# one commit, or if the repository setting changes to PR_TITLE.
	[[ "ci(promote): finpilot main → stable 2026-09-17" =~ ${PATTERN} ]]
	[[ "ci(promote): finpilot main → stable 2026-09-17 (#22)" =~ ${PATTERN} ]]
}

@test "execute-release: rejects the subjects a promotion never produces" {
	# A merge commit is not a promotion. That shape must not pass, and must
	# fail loudly, because nothing was promoted.
	! [[ "Merge pull request #16 from octocat/auto/promote-main-to-stable" =~ ${PATTERN} ]]
	! [[ "ci: publish stable release notes" =~ ${PATTERN} ]]
	! [[ "fix(release): hand-edit something on stable" =~ ${PATTERN} ]]
}

@test "execute-release: fails the run on a non-promotion push to stable" {
	run grep -A3 -F 'Refuse a non-promotion push to stable' "${WORKFLOW}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"steps.check.outputs.is-promotion != 'true'"* ]]
}

@test "release workflows: the signature identity is scoped to this repository" {
	# A signature's identity is the signing workflow's URL. Matching the owner and
	# then any repository (`[^/]+`) accepts a signature minted by any repo in the
	# org, so the identity must name this repository. github.repository keeps that
	# true in a fork without hardcoding the owner.
	run grep -rlF 'https://github\.com/${{ github.repository }}/\.github/workflows/' \
		"${REPO_ROOT}/.github/workflows/"
	[ "$status" -eq 0 ]
	[[ "$output" == *"execute-release.yml"* ]]
	[[ "$output" == *"promote-main-to-stable.yml"* ]]

	# The org-wide form is the regression this guards.
	! grep -rqF 'github.repository_owner }}/[^/]+/\.github' "${REPO_ROOT}/.github/workflows/"
}
