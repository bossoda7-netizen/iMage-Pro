# iMage Pro

<p>
  <a href="README.md"><img src="assets/readme/language-zh.svg" alt="简体中文" height="30" /></a>
  <a href="README.en.md"><img src="assets/readme/language-en.svg" alt="English" height="30" /></a>
  <a href="README.ko.md"><img src="assets/readme/language-ko.svg" alt="한국어" height="30" /></a>
  <a href="README.ja.md"><img src="assets/readme/language-ja.svg" alt="日本語" height="30" /></a>
</p>

A native macOS image editor. The current public preview is **0.9.2**. Built with SwiftUI, AppKit, Core Image, Metal, and on-device image recognition, with an intelligent repair model that runs locally.

[Website · Explore your canvas for inspiration](https://bossoda7-netizen.github.io/iMage-Pro-website/index-en.html) · [Download the preview](https://github.com/bossoda7-netizen/iMage-Pro/releases/tag/v0.9.2)

![iMage Pro interface](assets/readme/image-pro-overview.png)

## Features

- 45 tools, 36 effects, and an intuitive editing experience
- Multilayer editing, nondestructive effects, Pro Scopes, reorderable inspectors, Ruler Mode, and a smart toolbar
- Four interface languages: Simplified Chinese, English, Korean, and Japanese
- Save `.imgp` projects, import PSD/PSB, and export PNG, JPEG, TIFF, WebP, and other formats

## Getting started

Download the Apple Silicon preview from [GitHub Releases](https://github.com/bossoda7-netizen/iMage-Pro/releases), unzip it, and move `iMage Pro.app` to Applications. This version uses ad-hoc signing and has not yet been notarized by Apple. If macOS blocks it, check System Settings → Privacy & Security for the “Open Anyway” option.

## Building and testing

Requires Xcode 26, Swift 6, Apple Silicon, and macOS 14 or later.

```sh
git clone https://github.com/bossoda7-netizen/iMage-Pro.git
cd iMage-Pro
zsh scripts/build.sh
swift test --scratch-path /tmp/image-pro-swift-build
```

Before public distribution, sign the app with a developer certificate and complete notarization. The build script verifies the bundled model, runtime, licenses, and privacy manifest.

## Privacy, third-party components, and icons

The current version processes images and projects locally by default. It requires no account, contains no advertising trackers or analytics services, and does not automatically upload images. See the [Privacy Policy](PRIVACY.md). Licenses for intelligent repair, the runtime, and fonts are listed in the [Third-Party Notices](THIRD_PARTY_NOTICES.md). The full license texts are also available in the app under About → Third-Party Licenses.

The application icon and source artwork in `Design/Icon.icon` are original works by iMage Pro project. All rights are reserved, and this artwork is excluded from the source code’s Apache-2.0 license.

## License

The project’s source code is licensed under the [Apache License 2.0](LICENSE). Third-party components, model weights, fonts, and test fixtures remain subject to their respective licenses; the project license does not override or replace those terms. Please read the [Disclaimer](DISCLAIMER.md) before use.

See [CONTRIBUTING.md](CONTRIBUTING.md) for contributions and [SECURITY.md](SECURITY.md) for security issues.

## Support creativity

iMage Pro is free and open source. Donations are entirely voluntary, do not unlock features, and do not affect anyone’s access to the app.

<a href="https://ko-fi.com/T0N028J9BE" target="_blank" rel="noopener noreferrer"><img height="36" style="border:0px;height:36px;" src="https://storage.ko-fi.com/cdn/kofi3.png?v=6" alt="Buy Me a Coffee at ko-fi.com" /></a>

You can also support the project by scanning the Alipay QR code:

<img src="assets/alipay-qr.jpg" width="240" alt="Alipay donation QR code" />
