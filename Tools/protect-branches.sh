#!/usr/bin/env bash
# Run manually only after owner approval. Requires gh authentication and admin access.
# The stable branch must exist. Confirm the build check runs on PR heads
# before enabling required checks.
# This script intentionally does not modify workflows.
# NOTE: the Release workflow pushes the cask commit directly to stable, which these
# rules block. Before applying them, add a ruleset bypass for github-actions[bot]
# or change the workflow to open a cask pull request instead.
set -euo pipefail
repo="${1:-WhoaStudio/whoa-type}"
branch=stable
gh api --method PUT "repos/$repo/branches/$branch/protection" --input - <<'JSON'
{
  "required_status_checks": {"strict": true, "contexts": ["build"]},
  "enforce_admins": true,
  "required_pull_request_reviews": {
    "dismiss_stale_reviews": true,
    "required_approving_review_count": 1
  },
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
