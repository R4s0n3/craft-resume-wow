# Craft Resume repository instructions

## Release checklist

Before creating or pushing a release tag:

1. Update `## Version` in `CraftResume/CraftResume.toc` to the new release
   version.
2. Use a matching Git tag with a `v` prefix. For example, TOC version `0.6.0`
   must use tag `v0.6.0`.
3. Run `make test` and require all model, event, UI, and Lua syntax checks to
   pass.
4. Run `make package` and verify the generated ZIP contains
   `CraftResume/CraftResume.toc` with no files outside the top-level
   `CraftResume/` directory.
5. Commit the version change before creating the tag. Never move an existing
   published release tag to another commit; create a new version instead.

The `.github/workflows/release.yml` workflow enforces that the tag and TOC
versions match. A version tag publishes the ZIP as a GitHub release and uploads
it to CurseForge, using the `CURSEFORGE_PROJECT_ID` repository variable and
`CF_API_TOKEN` repository secret.

Do not put API tokens, SavedVariables, account data, or local WoW paths in the
repository or release archive.
