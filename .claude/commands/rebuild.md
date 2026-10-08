Build JZLLMContext, install the signed build to /Applications, restart the app, and open Finder at the build output.

Steps to execute in order:
1. Run `xcodegen generate` in the project root
2. Run `xcodebuild -scheme JZLLMContext -configuration Debug build` and report any errors
3. If build succeeded: kill any running JZLLMContext instance with `pkill -x JZLLMContext || true`
4. Install the signed build to /Applications (replaces the previous copy):
   ```
   rm -rf /Applications/JZLLMContext.app
   ditto ~/Library/Developer/Xcode/DerivedData/JZLLMContext-*/Build/Products/Debug/JZLLMContext.app /Applications/JZLLMContext.app
   ```
5. Verify the installed app is signed: `codesign -dv /Applications/JZLLMContext.app 2>&1 | grep TeamIdentifier` must show `TeamIdentifier=HA25F4PWCQ` (not `not set`). If it isn't, report it and do not launch.
6. Launch the installed app: `open /Applications/JZLLMContext.app`
7. Open Finder at the build output folder: `open ~/Library/Developer/Xcode/DerivedData/JZLLMContext-*/Build/Products/Debug`
8. Update readme.md if needed

If the build fails, show only the error lines and stop — do not kill, install or relaunch.
