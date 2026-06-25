# Convenience targets. The iOS Xcode project is generated from ios/project.yml
# by XcodeGen and is NOT committed (see .gitignore / E15). Run `make project`
# after cloning, or whenever you add/rename/remove an iOS source file.

.PHONY: project ios-open

## Generate ios/VisualWinelistIOS.xcodeproj from ios/project.yml (XcodeGen).
project:
	@command -v xcodegen >/dev/null 2>&1 || { \
		echo "XcodeGen not found — installing via Homebrew…"; \
		brew install xcodegen; \
	}
	cd ios && xcodegen generate

## Generate the project, then open it in Xcode.
ios-open: project
	open ios/VisualWinelistIOS.xcodeproj
