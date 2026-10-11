# Contributing

Thank you for helping improve iMage Pro.

## Before opening a change

- Explain the user-visible behavior and the macOS version you tested.
- Do not add images, fonts, models, code, or documentation whose redistribution
  terms are unclear.
- Do not commit personal projects, recovery files, screenshots containing private
  data, build products, or internal legal and patent reviews.
- Preserve the license and copyright notices for third-party material.

## Validation

Run the relevant tests, then run the release verification when changing bundled
resources or third-party notices:

    swift test --scratch-path /tmp/image-pro-swift-build
    zsh scripts/build.sh

Please describe any test limitation in the pull request. Do not include private
image files in issues or pull requests.
