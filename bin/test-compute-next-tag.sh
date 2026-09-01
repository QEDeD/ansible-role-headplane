#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Slavi Pantaleev
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Exercises bin/compute-next-tag.sh against throwaway git repositories.
#
# Usage: bin/test-compute-next-tag.sh
#
# Every scenario creates a repository in a temporary directory, gives it role
# files and a release history, and then replays a series of merges through the
# real script, tagging as it goes just like the autotag workflow does. This
# repository is never touched and no network access is needed.

set -euo pipefail

script_under_test="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/compute-next-tag.sh"
workflow_under_test="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)/.github/workflows/autotag.yml"

failures=0
workdir=''

expect_workflow_contract() {
	local description="$1" pattern="$2"

	if grep -Eq "$pattern" "$workflow_under_test"; then
		printf '  ok   | workflow %s\n' "$description"
	else
		printf '  FAIL | workflow does not %s\n' "$description"
		failures=$((failures + 1))
	fi
}

expect_workflow_contract 'evaluates current main' '^[[:space:]]+ref:[[:space:]]+main([[:space:]]|$)'
expect_workflow_contract 'fetches complete history and tags' '^[[:space:]]+fetch-depth:[[:space:]]+0([[:space:]]|$)'
expect_workflow_contract 'retains all queued runs' '^[[:space:]]+queue:[[:space:]]+max([[:space:]]|$)'
expect_workflow_contract 'does not cancel a running release' '^[[:space:]]+cancel-in-progress:[[:space:]]+false([[:space:]]|$)'
expect_workflow_contract 'has tag-write permission' '^[[:space:]]+contents:[[:space:]]+write([[:space:]]|$)'
expect_workflow_contract 'rejects fork release jobs' '!github[.]event[.]repository[.]fork'
expect_workflow_contract 'limits release jobs to main' "github[.]ref == 'refs/heads/main'"
expect_workflow_contract 'pushes only the computed tag ref' 'git push origin "refs/tags/[$]TAG"'

cleanup() {
	cd /
	if [ -n "$workdir" ]; then
		rm -rf "$workdir"
		workdir=''
	fi
}

trap cleanup EXIT

# The fixture reproduces the shape of the real defaults/main.yml around the
# version: the Renovate annotation that decides which literal gets bumped, the
# leaf literal itself (which carries no leading `v`, while the tags do), and
# the Jinja-derived image variables that sit next to it. A refactor that made
# the script read one of those derived variables instead of the leaf would
# produce a tag containing `{{` here, and every scenario would fail.
write_defaults() {
	cat > defaults/main.yml <<EOF
headplane_identifier: headplane

# renovate: datasource=docker depName=ghcr.io/tale/headplane versioning=semver
headplane_version: $1
headplane_arch: amd64

headplane_container_image: "{{ headplane_container_image_registry_prefix }}tale/headplane:{{ headplane_container_image_tag }}"
headplane_container_image_tag: "{{ headplane_version }}"
headplane_container_image_registry_prefix: "{{ headplane_container_image_registry_prefix_upstream }}"
EOF
}

# Starts a scenario with a repository at Headplane 0.6.2 which has already seen
# two releases of it (v0.6.2-0 and v0.6.2-1).
scenario() {
	echo "$1"

	cleanup
	workdir="$(mktemp -d)"

	mkdir -p "$workdir/bin" "$workdir/defaults" "$workdir/tasks" "$workdir/templates"
	cp "$script_under_test" "$workdir/bin/"
	cd "$workdir"

	git init -q -b main .
	git config user.email 'test@example.com'
	git config user.name 'Test'
	git config commit.gpgsign false

	write_defaults 0.6.2
	printf 'placeholder\n' > tasks/main.yml
	printf 'placeholder\n' > templates/env.j2
	printf 'placeholder\n' > README.md

	git add -A
	git commit -qm 'Initial commit'

	local release_number
	for release_number in 0 1; do
		git tag "v0.6.2-$release_number"
	done
}

# Applies a change, commits it, and tags whatever the script says it should be.
# Prints the tag, or nothing when the script decided against a release.
merge() {
	local change="$1" tag

	eval "$change"
	git add -A
	git commit -qm 'Merge'

	tag="$(bin/compute-next-tag.sh 2>/dev/null)"

	if [ -n "$tag" ]; then
		git tag "$tag"
	fi

	printf '%s' "$tag"
}

expect() {
	local description="$1" expected="$2" actual="$3"

	if [ "$actual" = "$expected" ]; then
		printf '  ok   | %s -> %s\n' "$description" "${actual:-no release}"
	else
		printf '  FAIL | %s -> expected %s, got %s\n' "$description" "${expected:-no release}" "${actual:-no release}"
		failures=$((failures + 1))
	fi
}

expect_failure() {
	local description="$1"

	if bin/compute-next-tag.sh >/dev/null 2>&1; then
		printf '  FAIL | %s -> expected failure, got success\n' "$description"
		failures=$((failures + 1))
	else
		printf '  ok   | %s -> failed safely\n' "$description"
	fi
}

bump_version='write_defaults 0.6.3'
revert_version='write_defaults 0.6.2'
edit_task="printf 'a task\n' >> tasks/main.yml"
edit_template="printf 'a line\n' >> templates/env.j2"
edit_readme="printf 'documentation\n' >> README.md"
edit_script="printf '# a comment\n' >> bin/compute-next-tag.sh"

write_runtime_file() {
	local path="$1"

	mkdir -p "$(dirname -- "$path")"
	printf 'runtime content\n' >> "$path"
}

# The two merge orders below apply the same updates and must each end up with
# every update released exactly once, whichever order they arrive in.

scenario 'A version bump merged before other role changes'
expect 'version bump' v0.6.3-0 "$(merge "$bump_version")"
expect 'task edit'    v0.6.3-1 "$(merge "$edit_task")"
expect 'template'     v0.6.3-2 "$(merge "$edit_template")"

scenario 'A version bump merged after other role changes'
expect 'task edit'    v0.6.2-2 "$(merge "$edit_task")"
expect 'version bump' v0.6.3-0 "$(merge "$bump_version")"

scenario 'Commits that do not affect the role'
expect 'README'   ''       "$(merge "$edit_readme")"
expect 'a script' ''       "$(merge "$edit_script")"
expect 'a task'   v0.6.2-2 "$(merge "$edit_task")"

scenario 'Release numbers past 9'
for release_number in 2 3 4 5 6 7 8 9 10; do
	git tag "v0.6.2-$release_number"
done
expect 'a task' v0.6.2-11 "$(merge "$edit_task")"

scenario 'Reverting to an already released version'
merge "$bump_version" > /dev/null
# The role is now identical to what v0.6.2-1 already published, so there is
# nothing new to release.
expect 'a revert' '' "$(merge "$revert_version")"

scenario 'Reverting to an already released version, with a change'
merge "$bump_version" > /dev/null
expect 'a revert' v0.6.2-2 "$(merge "$revert_version && $edit_task")"

# Tags of an unrelated version must not be mistaken for releases of the one in
# defaults/main.yml, and neither must a tag whose release part is not a number.
scenario 'Tags that do not belong to the version being released'
git tag 'v0.6.20-7'
git tag 'v0.6.2-rc1'
expect 'a task' v0.6.2-2 "$(merge "$edit_task")"

scenario 'Standard role runtime directories trigger releases'
runtime_paths=(
	'files/payload.txt'
	'filter_plugins/example.py'
	'handlers/main.yml'
	'library/example.py'
	'lookup_plugins/example.py'
	'meta/runtime.yml'
	'module_utils/example.py'
	'modules/example.py'
	'plugins/filter/example.py'
	'vars/main.yml'
)
release_number=2
for runtime_path in "${runtime_paths[@]}"; do
	expect "$runtime_path" "v0.6.2-$release_number" "$(merge "write_runtime_file '$runtime_path'")"
	release_number=$((release_number + 1))
done

scenario 'An unclassified top-level directory fails visibly'
mkdir -p unclassified
printf 'runtime status unknown\n' > unclassified/example.txt
git add -A
git commit -qm 'Unclassified directory'
expect_failure 'unclassified top-level directory'

scenario 'An unclassified top-level file fails visibly'
printf 'runtime status unknown\n' > unclassified.txt
git add -A
git commit -qm 'Unclassified file'
expect_failure 'unclassified top-level file'

scenario 'A stale queued run after a later commit has been released'
expect 'first task' v0.6.2-2 "$(merge "$edit_task")"
older_commit="$(git rev-parse HEAD)"
expect 'later template' v0.6.2-3 "$(merge "$edit_template")"
git checkout -q "$older_commit"
expect 'stale task run' '' "$(bin/compute-next-tag.sh 2>/dev/null)"

scenario 'A stale event cannot tag a change reverted by current main'
eval "$edit_task"
git add -A
git commit -qm 'Task change'
superseded_commit="$(git rev-parse HEAD)"
git show 'v0.6.2-1:tasks/main.yml' > tasks/main.yml
git add -A
git commit -qm 'Revert task change'
expect 'current main after the revert' '' "$(bin/compute-next-tag.sh 2>/dev/null)"
# Simulate the older event starting after the revert. The workflow explicitly
# checks out main, so it evaluates the current branch tip rather than this SHA.
git checkout -q "$superseded_commit"
git checkout -q main
expect 'superseded queued event' '' "$(bin/compute-next-tag.sh 2>/dev/null)"

scenario 'A push after checkout is reconciled by the next retained run'
remote_path="$workdir/.git/release-remote.git"
git init -q --bare "$remote_path"
git remote add origin "$remote_path"
git push -q origin main
git push -q origin 'refs/tags/v0.6.2-0' 'refs/tags/v0.6.2-1'
eval "$edit_task"
git add -A
git commit -qm 'Task change'
checked_out_commit="$(git rev-parse HEAD)"
checked_out_tag="$(bin/compute-next-tag.sh 2>/dev/null)"
git show 'v0.6.2-1:tasks/main.yml' > tasks/main.yml
git add -A
git commit -qm 'Revert task change'
git push -q origin main
# The already-running job may still release the accepted commit it evaluated.
# The next retained job then compares current main with that release and cuts a
# follow-up tag for the revert, leaving the highest tag on current main.
git tag "$checked_out_tag" "$checked_out_commit"
git push -q origin "refs/tags/$checked_out_tag"
expect 'current main after mid-run push' v0.6.2-3 "$(bin/compute-next-tag.sh 2>/dev/null)"
git tag v0.6.2-3
git push -q origin 'refs/tags/v0.6.2-3'
expect 'highest tag reaches current main' "$(git rev-parse HEAD)" "$(git --git-dir="$remote_path" rev-parse 'refs/tags/v0.6.2-3^{}')"

scenario 'Quoted versions and malformed declarations'
write_defaults "'0.6.2'"
git add -A
git commit -qm 'Single-quoted version'
expect 'single-quoted version' v0.6.2-2 "$(bin/compute-next-tag.sh 2>/dev/null)"
printf 'headplane_version: 0.6.2\n' >> defaults/main.yml
git add -A
git commit -qm 'Duplicate version declaration'
expect_failure 'duplicate version declarations'

scenario 'Malformed numeric release tags fail visibly'
git tag 'v0.6.2-08'
expect_failure 'leading-zero release number'

scenario 'Release counters have a supported upper bound'
git tag 'v0.6.2-999999'
expect_failure 'exhausted release counter'

scenario 'A release tag on a divergent history'
git branch divergent
expect 'main task' v0.6.2-2 "$(merge "$edit_task")"
git checkout -q divergent
eval "$edit_template"
git add -A
git commit -qm 'Divergent merge'
expect_failure 'divergent tag and commit'

if [ "$failures" -gt 0 ]; then
	echo >&2 "$failures scenario(s) behaved unexpectedly"
	exit 1
fi

echo 'All scenarios behaved as expected'
