#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Slavi Pantaleev
#
# SPDX-License-Identifier: AGPL-3.0-or-later

# Prints the tag that the currently checked out commit should be released as,
# or nothing at all if it does not warrant a release.
#
# Usage: bin/compute-next-tag.sh
#
# Tags look like `v<Headplane version>-<release>`:
#
# - if defaults/main.yml points at a Headplane version that has never been
#   released, the release counter restarts at 0 (`v0.7.0-0`)
# - otherwise the counter is incremented (`v0.7.0-1`), but only if something
#   that actually affects the role has changed since the last release
#
# Determining the version from defaults/main.yml, rather than from the commit
# message of the pull request that got merged, makes the result independent of
# the order in which pull requests get merged, and lets any change to the role
# (bugfix, feature, dependency bump) release itself without a human tagging.

set -euo pipefail

repository_path="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd -- "$repository_path"

defaults_path='defaults/main.yml'

# Paths that shape the behavior of the role for its consumers. A commit
# touching only other paths (a README fix, CI configuration, Molecule tests)
# does not change what a playbook run does, and releasing it would only create
# churn in the repositories that consume this role.
role_defining_paths=(
	'action_plugins'
	'become_plugins'
	'cache_plugins'
	'callback_plugins'
	'cliconf_plugins'
	'connection_plugins'
	'defaults'
	'files'
	'filter_plugins'
	'handlers'
	'httpapi_plugins'
	'inventory_plugins'
	'library'
	'lookup_plugins'
	'meta'
	'modules'
	'module_utils'
	'netconf_plugins'
	'plugins'
	'shell_plugins'
	'strategy_plugins'
	'tasks'
	'templates'
	'test_plugins'
	'vars'
)

# Known repository-only directories that do not change the installed role.
# Failing on an unclassified directory makes future role structure changes an
# explicit release-policy decision instead of silently omitting them.
non_role_top_level_paths=(
	'.github'
	'LICENSES'
	'bin'
	'docs'
	'molecule'
	'tests'
)

is_known_top_level_path() {
	local candidate="$1" known_path

	for known_path in "${role_defining_paths[@]}" "${non_role_top_level_paths[@]}"; do
		if [ "$candidate" = "$known_path" ]; then
			return 0
		fi
	done

	return 1
}

while IFS= read -r top_level_path; do
	if ! is_known_top_level_path "$top_level_path"; then
		echo >&2 "Unclassified top-level directory: $top_level_path"
		echo >&2 'Classify it as role-defining or repository-only before releasing'
		exit 1
	fi
done < <(git ls-tree -d --name-only HEAD)

version="$(sed -nE 's|^headplane_version:[[:space:]]*"?([^"[:space:]]+)"?.*$|\1|p' "$defaults_path" | head -n1)"

if [ -z "$version" ]; then
	echo >&2 "Could not determine the Headplane version from $defaults_path"
	exit 1
fi

# The version value carries no leading `v` (e.g. `0.7.0`) while the tags do
# (`v0.7.0-0`). Stripping one that is not there is harmless, and keeps this
# working if the value ever starts carrying one.
tag_prefix="v${version#v}-"

# Release tags are immutable history. Deleting one makes its revision number
# ambiguous and is intentionally not repaired by this workflow.
#
# Of all releases of this version, the highest release number. Sorted
# numerically, so that -10 is recognized as newer than -9.
last_release="$(git tag --list "${tag_prefix}*" | sed -e "s|^${tag_prefix}||" | grep -E '^[0-9]+$' | sort -n | tail -n1 || true)"

if [ -z "$last_release" ]; then
	echo >&2 "Version $version has never been released"
	echo "${tag_prefix}0"
	exit 0
fi

previous_tag="${tag_prefix}${last_release}"

# The workflow evaluates current main, not its triggering commit. This ancestry
# check is an additional guard against an unexpected stale checkout or moved
# tag; divergent history must be investigated instead of tagged automatically.
if git merge-base --is-ancestor "$previous_tag" HEAD; then
	:
elif git merge-base --is-ancestor HEAD "$previous_tag"; then
	echo >&2 "Current commit is already included in later release $previous_tag"
	exit 0
else
	echo >&2 "$previous_tag and the current commit have diverged"
	exit 1
fi

if git diff --quiet "$previous_tag" HEAD -- "${role_defining_paths[@]}"; then
	echo >&2 "Nothing affecting the role has changed since $previous_tag"
	exit 0
fi

echo >&2 "The role has changed since $previous_tag"
echo "${tag_prefix}$((last_release + 1))"
