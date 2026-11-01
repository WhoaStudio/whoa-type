# Protected-branch releases

Changes to `stable` require a pull request and the `build` check. Required
approvals are zero while the repository has one maintainer. Add an independent
reviewer before increasing the approval requirement.

## From GitHub Actions

1. Run **Release** on `stable`, supplying a numeric version without `v`.
2. If the version needs updating, the workflow opens a version PR and stops.
   Approve its workflow runs when GitHub prompts, wait for CI, and merge it.
3. Run **Release** again with the same version. It tags the merged version,
   builds and publishes the release, and opens a cask update PR.
4. Approve the cask PR's workflow runs when prompted, then merge after CI passes.

## From the command line

On a clean, up-to-date `stable`, run `scripts/release.sh <version>`. If it opens a
version PR, merge that PR, pull `stable`, and rerun the same command. Once the
version is merged, the script pushes only the release tag. The release workflow
opens the cask update PR.

The release jobs explicitly request `contents: write` and `pull-requests: write`.
The repository permits Actions to create PRs for these jobs; the default token
and the CI workflow remain read-only. No workflow approves or merges its own PRs.
