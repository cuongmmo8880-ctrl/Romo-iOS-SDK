# Lily Rebuild — Stage 1

This directory is a bootstrap rebuild of the extracted Lily iOS application.

## Current goal

Build and launch the iOS app using the recovered `Shared.framework`, then continue recovering the original Lily UI and runtime wiring from the framework.

The project deliberately does **not** integrate Romo yet.

## Framework requirement

`Frameworks/Shared.framework/Shared` is the recovered arm64 iOS framework binary from the installed Lily app. It must be present in the repository before GitHub Actions can produce the IPA.

The binary is about 97.6 MiB, so it should be committed with Git LFS or uploaded directly through GitHub's web UI if the repository accepts the file size.

## Build

GitHub Actions workflow:

`/.github/workflows/build-lily.yml`

The workflow builds an unsigned iPhoneOS IPA with Xcode on a macOS runner. It does not require an Apple signing certificate.
