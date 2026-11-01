#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
fail() { echo "Release aborted: $*" >&2; exit 1; }
[[ $# == 1 ]] || fail 'Usage: scripts/release.sh <version>'
version=$1
python3 scripts/version.py "$version"
tag="v$version"
[[ $(git branch --show-current) == stable ]] || fail 'Switch to stable before releasing.'
[[ -z $(git status --porcelain) ]] || fail 'Working tree is dirty; commit or stash all changes first.'
git rev-parse --verify HEAD >/dev/null 2>&1 || fail 'Create the initial commit first.'
git fetch origin stable --tags
[[ $(git rev-parse HEAD) == "$(git rev-parse refs/remotes/origin/stable)" ]] ||
  fail 'stable must exactly match origin/stable; pull or push your changes first.'
if git show-ref --verify --quiet "refs/tags/$tag"; then
  fail "Tag $tag already exists."
fi
[[ -z $(git ls-remote --tags origin "refs/tags/$tag") ]] || fail "Remote tag $tag already exists."
command -v gh >/dev/null || fail 'Install gh and authenticate before releasing.'
branch="release/$tag"
existing=$(gh pr list --base stable --head "$branch" --json url --jq '.[0].url // empty')
if [[ -n "$existing" ]]; then
  echo "Merge $existing after CI passes, then rerun scripts/release.sh $version."
  exit 0
fi
python3 scripts/version.py "$version" --bump
if ! git diff --quiet -- whoa-type.xcodeproj/project.pbxproj; then
  git switch -c "$branch"
  git add whoa-type.xcodeproj/project.pbxproj
  git commit -m "chore(release): prepare $tag"
  git push origin "HEAD:refs/heads/$branch"
  gh pr create --base stable --head "$branch" --title "chore(release): prepare $tag" \
    --body 'Prepare the release version. Merge after CI passes, then rerun scripts/release.sh with the same version on the updated stable branch.'
  git switch stable
  echo "Merge the version PR, pull stable, then rerun scripts/release.sh $version."
  exit 0
fi
git tag -a "$tag" -m "Release $tag"
git push origin "refs/tags/$tag"
repo_url=$(git remote get-url origin)
repo_url=${repo_url%.git}
repo_url=${repo_url/git@github.com:/https:\/\/github.com/}
echo "Release pushed: $tag"
echo "Actions: $repo_url/actions/workflows/release-build.yml"
if [[ ${RELEASE_WATCH:-1} == 1 ]] && command -v gh >/dev/null; then
  sha=$(git rev-parse HEAD)
  for ((attempt=0; attempt<12; attempt++)); do
    run_id=$(gh run list --workflow release-build.yml --event push --commit "$sha" \
      --json databaseId --jq '.[0].databaseId // empty') || break
    if [[ -n $run_id ]]; then
      gh run view "$run_id" --json url --jq .url
      gh run watch "$run_id" --exit-status
      exit $?
    fi
    sleep 5
  done
  echo 'Run not visible yet; use the Actions link above.'
fi
