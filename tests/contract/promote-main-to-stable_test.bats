#!/usr/bin/env bats
# Unit tests for .github/workflows/promote-main-to-stable.yml.
#
# The workflow is a thin caller around two reusables, but it also carries three
# jobs of its own inline bash, and none of it had ever been executed by a test.
# The one that rewrites history is `repair-promotion-branch`: it force-pushes a
# commit over the promotion branch the reusable just built. Its failure mode is
# silent in the direction that matters — if the repair stops rebuilding, the
# branch keeps the stale paths a rename left behind, its tree no longer matches
# main's, and the tree guard in execute-release.yml refuses the promotion only
# *after* a human has merged the PR. By then `stable` has moved and no release
# was produced.
#
# So the repair script is extracted from the workflow and run for real, against
# throwaway git repositories under BATS_TEST_TMPDIR, with the same branch shapes
# the reusable produces. Nothing here touches a network remote: `origin` is a
# local bare repository, so the force-push is exercised rather than mocked.
#
# The remaining jobs (`locate-promotion-pr`, `unblock-promotion-checks`) talk to
# the GitHub API and are covered statically, for the two invariants that are not
# visible in a run's logs: every job has to agree on one promotion branch name,
# and the run approver has to stay inside its trust boundary.
#
# Run with: bats tests/contract/promote-main-to-stable_test.bats

REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
WORKFLOW="${REPO_ROOT}/.github/workflows/promote-main-to-stable.yml"
PROMOTION_BRANCH="auto/promote-main-to-stable"

# Lift a step's `run: |` block out of the workflow and dedent it, so the tests
# execute the script the workflow executes instead of a copy that can drift.
# The block ends at the first line indented no deeper than the `run:` key.
extract_run_block() {
	awk -v marker="$1" '
		$0 ~ marker { found = 1 }
		found && !grab && $0 ~ /run: \|/ { match($0, /^ */); indent = RLENGTH; grab = 1; next }
		grab {
			if ($0 ~ /^[[:space:]]*$/) { print ""; next }
			match($0, /^ */)
			if (RLENGTH <= indent) exit
			print substr($0, indent + 3)
		}
	' "${WORKFLOW}"
}

git_q() {
	git -C "${1}" "${@:2}"
}

# A remote carrying main and stable, plus a clone configured the way
# actions/checkout leaves one: a full wildcard fetch refspec, so every branch
# the script names resolves as origin/<branch>.
setup() {
	REPAIR_SCRIPT="${BATS_TEST_TMPDIR}/repair.sh"
	extract_run_block "Rebuild the branch when its tree has drifted" >"${REPAIR_SCRIPT}"

	# Guard the extraction itself: an empty or truncated script would let every
	# assertion below pass against nothing.
	[ -s "${REPAIR_SCRIPT}" ]
	grep -q 'git commit-tree' "${REPAIR_SCRIPT}"

	REMOTE="${BATS_TEST_TMPDIR}/remote.git"
	SEED="${BATS_TEST_TMPDIR}/seed"
	CLONE="${BATS_TEST_TMPDIR}/clone"

	git init -q --bare "${REMOTE}"
	git init -q -b main "${SEED}"
	git_q "${SEED}" config user.email promote@example.invalid
	git_q "${SEED}" config user.name promote

	mkdir -p "${SEED}/build"
	echo original >"${SEED}/build/moved.sh"
	git_q "${SEED}" add -A
	git_q "${SEED}" commit -q -m "feat: seed the image"
	git_q "${SEED}" remote add origin "${REMOTE}"
	git_q "${SEED}" push -q origin main

	# stable starts level with main, as it is right after a promotion.
	git_q "${SEED}" branch stable
	git_q "${SEED}" push -q origin stable
}

clone_repo() {
	git clone -q "${REMOTE}" "${CLONE}"
	git_q "${CLONE}" config user.email promote@example.invalid
	git_q "${CLONE}" config user.name promote
}

# The script operates on the current working directory, so it must only ever be
# started from inside the throwaway clone. Started anywhere else it would fetch
# from, and force-push to, whatever `origin` that directory has.
run_repair() {
	run env -i PATH="${PATH}" HOME="${BATS_TEST_TMPDIR}" \
		PROMOTION_BRANCH="${PROMOTION_BRANCH}" \
		bash -c 'cd "$1" && bash "$2"' _ "${CLONE}" "${REPAIR_SCRIPT}"
}

# Advance main the way a merged pull request does.
commit_on_main() {
	git_q "${SEED}" checkout -q main
	"${@}"
	git_q "${SEED}" add -A
	git_q "${SEED}" commit -q -m "feat: advance main"
	git_q "${SEED}" push -q origin main
}

# Reproduce what reusable-promote-squash leaves behind: stable's history with
# main's tree overlaid on top. Overlaying cannot remove a path main deleted, so
# a renamed file survives on its old path — the drift this job exists to repair.
push_overlay_promotion_branch() {
	git_q "${SEED}" checkout -q -B "${PROMOTION_BRANCH}" stable
	git_q "${SEED}" checkout -q main -- .
	git_q "${SEED}" add -A
	git_q "${SEED}" commit -q -m "chore: promote main to stable"
	git_q "${SEED}" push -q --force origin "${PROMOTION_BRANCH}"
	git_q "${SEED}" checkout -q main
}

origin_tree() {
	git_q "${CLONE}" rev-parse "origin/${1}^{tree}"
}

@test "repair: rebuilds the branch when a rename left the old path behind" {
	commit_on_main git -C "${SEED}" mv build/moved.sh build/renamed.sh
	push_overlay_promotion_branch
	clone_repo

	# Precondition: the branch the reusable built really does carry both paths,
	# so a passing result below cannot come from an already-correct branch.
	run git_q "${CLONE}" ls-tree -r --name-only "origin/${PROMOTION_BRANCH}"
	[[ "$output" == *"build/moved.sh"* ]]
	[[ "$output" == *"build/renamed.sh"* ]]

	run_repair
	[ "$status" -eq 0 ]
	[[ "$output" == *"Rebuilt ${PROMOTION_BRANCH} from main's tree."* ]]

	git_q "${CLONE}" fetch -q origin
	run git_q "${CLONE}" ls-tree -r --name-only "origin/${PROMOTION_BRANCH}"
	[[ "$output" != *"build/moved.sh"* ]]
	[[ "$output" == *"build/renamed.sh"* ]]
}

@test "repair: the rebuilt branch promotes main's exact tree onto stable" {
	commit_on_main git -C "${SEED}" mv build/moved.sh build/renamed.sh
	push_overlay_promotion_branch
	clone_repo

	run_repair
	[ "$status" -eq 0 ]
	[[ "$output" == *"Rebuilt"* ]]
	git_q "${CLONE}" fetch -q origin

	# The tree guard in execute-release.yml compares exactly these two.
	[ "$(origin_tree "${PROMOTION_BRANCH}")" = "$(origin_tree main)" ]

	# One parent, and it is stable: the promotion has to be a squash onto the
	# production branch, not a merge that drags main's history across.
	run git_q "${CLONE}" rev-list --parents -n1 "origin/${PROMOTION_BRANCH}"
	[ "$(echo "$output" | wc -w)" -eq 2 ]
	[ "$(git_q "${CLONE}" rev-parse "origin/${PROMOTION_BRANCH}^1")" = \
		"$(git_q "${CLONE}" rev-parse origin/stable)" ]
}

@test "repair: the rebuilt commit's subject is one execute-release accepts" {
	# The repair force-pushes a single commit, so GitHub's squash merge takes
	# its subject (COMMIT_OR_PR_TITLE). A subject that stops matching the
	# release pattern promotes nothing and reports success, which is the
	# failure execute-release_test.bats guards from the other side.
	commit_on_main git -C "${SEED}" mv build/moved.sh build/renamed.sh
	push_overlay_promotion_branch
	clone_repo

	run_repair
	[ "$status" -eq 0 ]
	[[ "$output" == *"Rebuilt"* ]]
	git_q "${CLONE}" fetch -q origin

	local subject pattern line
	subject="$(git_q "${CLONE}" log -1 --format=%s "origin/${PROMOTION_BRANCH}")"
	line="$(grep -F '=~ ' "${REPO_ROOT}/.github/workflows/execute-release.yml")"
	pattern="${line#*=~ }"
	pattern="${pattern% ]]; then}"
	[ -n "${pattern}" ]

	[[ "${subject}" =~ ${pattern} ]]
	[[ "${subject} (#22)" =~ ${pattern} ]]
}

@test "repair: leaves a branch that already matches main alone" {
	# A correct branch must not be force-pushed: the push would reset the
	# promotion PR's approvals and its unblocked check runs for no change.
	commit_on_main bash -c "echo changed >'${SEED}/build/moved.sh'"
	git_q "${SEED}" push -q --force "origin" "main:refs/heads/${PROMOTION_BRANCH}"
	clone_repo

	local before
	before="$(git_q "${CLONE}" rev-parse "origin/${PROMOTION_BRANCH}")"

	run_repair
	[ "$status" -eq 0 ]
	[[ "$output" == *"already matches main"* ]]

	git_q "${CLONE}" fetch -q origin
	[ "$(git_q "${CLONE}" rev-parse "origin/${PROMOTION_BRANCH}")" = "${before}" ]
}

@test "repair: exits cleanly when there is no promotion branch" {
	# main and stable already match, so the reusable built no branch. That is
	# the ordinary daily no-op and must not fail the run.
	clone_repo

	run_repair
	[ "$status" -eq 0 ]
	[[ "$output" == *"No ${PROMOTION_BRANCH} to repair"* ]]

	run git_q "${CLONE}" ls-remote --exit-code --heads origin "${PROMOTION_BRANCH}"
	[ "$status" -ne 0 ]
}

@test "promote: every job names the same promotion branch" {
	# repair, locate and unblock each hardcode the branch the reusable derives
	# from source_branch/target_branch. Three copies of one name drift silently:
	# the repair would rebuild a branch nobody looks for, and the approver would
	# approve runs on a branch nobody promotes.
	local source_branch target_branch
	source_branch="$(sed -n 's/^ *source_branch: *//p' "${WORKFLOW}")"
	target_branch="$(sed -n 's/^ *target_branch: *//p' "${WORKFLOW}")"
	[ -n "${source_branch}" ]
	[ -n "${target_branch}" ]

	run grep -c "PROMOTION_BRANCH: auto/promote-${source_branch}-to-${target_branch}$" "${WORKFLOW}"
	[ "$status" -eq 0 ]
	[ "$output" -eq 3 ]

	# And the PR is looked up against the branch the promotion targets.
	run grep -F -- "--base ${target_branch}" "${WORKFLOW}"
	[ "$status" -eq 0 ]
}

@test "promote: the PR lookup is scoped to an open promotion PR" {
	# Without --state open the lookup can return a merged promotion PR, and the
	# gate would then verify and label last week's release.
	run grep -A8 -F 'gh pr list' "${WORKFLOW}"
	[ "$status" -eq 0 ]
	[[ "$output" == *"--state open"* ]]
	[[ "$output" == *'--head "${PROMOTION_BRANCH}"'* ]]

	# Both consumers must tolerate the no-op run, where there is no PR at all.
	run grep -c "needs.locate-promotion-pr.outputs.pr_number != ''" "${WORKFLOW}"
	[ "$status" -eq 0 ]
	[ "$output" -eq 2 ]
}

@test "promote: the run approver stays inside its trust boundary" {
	# This job holds actions: write and approves held workflow runs. Approving
	# on branch alone would approve a run from any actor who can push that
	# branch name; approving on actor alone would approve that bot's runs on any
	# branch. Both filters have to be present, on the same selection.
	local filter
	filter="$(grep -F 'runs_filter=' "${WORKFLOW}")"
	[ -n "${filter}" ]
	[[ "${filter}" == *'.head_branch == \"${PROMOTION_BRANCH}\"'* ]]
	[[ "${filter}" == *'.actor.login == \"github-actions[bot]\"'* ]]

	# Only runs GitHub is actually holding may be approved.
	run grep -F 'actions/runs?status=action_required' "${WORKFLOW}"
	[ "$status" -eq 0 ]
}
