Build JZLLMContext, restart the app, and open Finder at the build output.

Steps to execute in order:
1. Run `xcodegen generate` in the project root
2. Run `xcodebuild -scheme JZLLMContext -configuration Debug build` and report any errors
3. If build succeeded: kill any running JZLLMContext instance with `pkill -x JZLLMContext`
4. Launch the new build: `open ~/Library/Developer/Xcode/DerivedData/JZLLMContext-*/Build/Products/Debug/JZLLMContext.app`
5. Open Finder at the build output folder: `open /Users/jan/Library/Developer/Xcode/DerivedData/JZLLMContext-ashuidigwvrybugixttzlkbflcis/Build/Products/Debug`
6. Update readme.md if needed

If the build fails, show only the error lines and stop — do not kill or relaunch.
