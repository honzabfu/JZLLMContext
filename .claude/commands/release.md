Build JZLLMContext in Release configuration and publish a new GitHub Release.

If $ARGUMENTS is provided, use it as the version number (e.g. `0.6`). Otherwise auto-increment from project.yml.

Steps to execute in order:

1. **Determine version and update project.yml:**
   - If $ARGUMENTS is non-empty, use it as VERSION.
   - Otherwise auto-increment: read current MARKETING_VERSION, then compute new VERSION:
     - Split on the last `.` → prefix (e.g. `0`) and last (e.g. `5` or `51`)
     - If last is a single digit (e.g. `5`): new last = last + "1" → `51`
     - If last is multiple digits (e.g. `51`): new last = last + 1 → `52`
     - VERSION = prefix + "." + new last (e.g. `0.51`)
   - Update project.yml: replace `MARKETING_VERSION: "..."` with VERSION, reset `CURRENT_PROJECT_VERSION` to 1.
   - project.yml is always modified in this step.

2. **Check for uncommitted changes:**
   - Run `git status --porcelain`.
   - If there are uncommitted changes besides project.yml, warn the user and stop.

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

6. **Update RELEASE_NOTES.md and commit:**
   - In `RELEASE_NOTES.md`, replace the `## Unreleased` heading with `## v{VERSION} – {TODAY}` (where TODAY is the current date in YYYY-MM-DD format), then prepend a new `## Unreleased\n` block at the top of the file (right after the `# Release Notes` heading).
   - Stage and commit both files:
     ```
     git add project.yml RELEASE_NOTES.md
     git commit -m "Bump version to {VERSION}"
     ```

7. **Create and push git tag:**
   - Run `git tag v{VERSION}`.
   - Run `git push origin main --tags`.

8. **Publish GitHub Release:**
   - Extract the release notes for this version from `RELEASE_NOTES.md`: read the lines between `## v{VERSION}` and the next `## ` heading (exclusive). Store them as WHAT_IS_NEW.
   - Write release notes to a temp file, then publish:
     ```
     # Build the notes file
     cat > /tmp/jzllmcontext-release-notes.md << 'NOTES'
     > ⚠ **Unsigned app** — see [Download / Installation](https://github.com/honzabfu/JZLLMContext#download) · [Stažení / Instalace](https://github.com/honzabfu/JZLLMContext#stažení)
     NOTES

     # Append What's new section if WHAT_IS_NEW is non-empty
     if [ -n "{WHAT_IS_NEW}" ]; then
       printf '\n## What'\''s new in v{VERSION}\n\n%s\n' "{WHAT_IS_NEW}" >> /tmp/jzllmcontext-release-notes.md
     fi

     gh release create v{VERSION} \
       /tmp/JZLLMContext-release/Build/Products/Release/JZLLMContext.zip \
       --title "v{VERSION}" \
       --notes-file /tmp/jzllmcontext-release-notes.md
     ```

9. **Restart local app (signed local build):**
   - The distributed release build from step 4 is intentionally unsigned (ad-hoc) — never run it locally: its code identity differs from the signed build that stored the API keys, so Keychain would re-prompt for the login password.
   - Build the signed local app (Apple Development identity from `DEVELOPMENT_TEAM` in `project.yml`):
     ```
     xcodebuild -scheme JZLLMContext -configuration Debug build
     ```
     If the build fails, show only error lines and skip the relaunch (the release is already published).
   - Kill any running instance: `pkill -x JZLLMContext || true`
   - Launch the signed build: `open ~/Library/Developer/Xcode/DerivedData/JZLLMContext-*/Build/Products/Debug/JZLLMContext.app`
   - Verify it is signed: `codesign -dv <app path> 2>&1 | grep TeamIdentifier` must show `TeamIdentifier=HA25F4PWCQ`, not `not set`.

10. **Report result:**
    - Print the release URL returned by `gh release create`.
    - Open Finder at `/tmp/JZLLMContext-release/Build/Products/Release`.
