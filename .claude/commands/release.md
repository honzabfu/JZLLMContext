Build JZLLMContext in Release configuration and publish a new GitHub Release.

If $ARGUMENTS is provided, use it as the version number (e.g. `0.5`). Otherwise read MARKETING_VERSION from project.yml.

Steps to execute in order:

1. **Determine version:**
   - If $ARGUMENTS is non-empty, use it as VERSION.
   - Otherwise run `grep 'MARKETING_VERSION' project.yml | head -1 | grep -oE '[0-9]+\.[0-9]+'` to extract VERSION.
   - If $ARGUMENTS was provided, update project.yml: replace the existing `MARKETING_VERSION: "..."` value with the new version. Also reset `CURRENT_PROJECT_VERSION` to 1 if bumping major/minor.

2. **Check for uncommitted changes:**
   - Run `git status --porcelain`.
   - If there are uncommitted changes (besides project.yml which may have just been edited), warn the user and stop.

3. **Generate Xcode project:**
   - Run `xcodegen generate` in the project root.

4. **Build Release:**
   - Run:
     ```
     xcodebuild \
       -scheme JZLLMContext \
       -configuration Release \
       -derivedDataPath /tmp/JZLLMContext-release \
       CODE_SIGN_IDENTITY="" \
       CODE_SIGNING_REQUIRED=NO \
       CODE_SIGNING_ALLOWED=NO \
       build
     ```
   - If build fails, show only error lines (lines containing `: error:`) and stop.

5. **Zip app bundle:**
   - Run:
     ```
     cd /tmp/JZLLMContext-release/Build/Products/Release
     zip -r --symlinks JZLLMContext.zip JZLLMContext.app
     ```

6. **Commit version bump (only if project.yml was modified):**
   - Run `git diff --name-only` — if project.yml appears, stage and commit it:
     ```
     git add project.yml
     git commit -m "Bump version to {VERSION}"
     ```

7. **Create and push git tag:**
   - Run `git tag v{VERSION}`.
   - Run `git push origin main --tags`.

8. **Publish GitHub Release:**
   - Run:
     ```
     gh release create v{VERSION} \
       /tmp/JZLLMContext-release/Build/Products/Release/JZLLMContext.zip \
       --title "v{VERSION}" \
       --notes "Sestavení verze {VERSION}. Binárka není podepsána — před spuštěním spusť: xattr -cr JZLLMContext.app"
     ```

9. **Restart local app:**
   - Kill any running instance: `pkill -x JZLLMContext || true`
   - Launch the newly built app: `open /tmp/JZLLMContext-release/Build/Products/Release/JZLLMContext.app`

10. **Report result:**
    - Print the release URL returned by `gh release create`.
    - Open Finder at `/tmp/JZLLMContext-release/Build/Products/Release`.
