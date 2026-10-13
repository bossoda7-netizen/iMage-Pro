# iMage Pro

<p>
  <a href="README.md"><img src="assets/readme/language-zh.svg" alt="简体中文" height="30" /></a>
  <a href="README.en.md"><img src="assets/readme/language-en.svg" alt="English" height="30" /></a>
  <a href="README.ko.md"><img src="assets/readme/language-ko.svg" alt="한국어" height="30" /></a>
  <a href="README.ja.md"><img src="assets/readme/language-ja.svg" alt="日本語" height="30" /></a>
</p>

原生 macOS 图像编辑器，当前公开预览版为 **0.9.2**。项目使用 SwiftUI、AppKit、Core Image、Metal 和本机图像识别能力，智能修复模型在本机运行。

[官网 · 探索灵感画布](https://bossoda7-netizen.github.io/iMage-Pro-website/) · [下载预览版](https://github.com/bossoda7-netizen/iMage-Pro/releases/tag/v0.9.2)

![iMage Pro 主界面](assets/readme/image-pro-overview.png)

## 功能

- 45款工具 36款效果器 直观使用体验
- 多图层编辑、非破坏效果器、专业图谱、可排序调节器、标尺模式、智能工具栏
- 四种界面语言：简体中文、英语、韩语、日语
- `.imgp` 项目保存、PSD/PSB 导入和 PNG、JPEG、TIFF、WebP 等格式导出

## 使用

从 [GitHub Releases](https://github.com/bossoda7-netizen/iMage-Pro/releases) 下载 Apple Silicon 预览版，解压后将 `iMage Pro.app` 放入“应用程序”。当前版本采用临时签名，尚未通过 Apple 公证；如系统拦截，可在“系统设置 → 隐私与安全性”中查看是否提供“仍然要打开”。

## 构建与测试

要求 Xcode 26、Swift 6、Apple Silicon 和 macOS 14 或更高版本。

```sh
git clone https://github.com/bossoda7-netizen/iMage-Pro.git
cd iMage-Pro
zsh scripts/build.sh
swift test --scratch-path /tmp/image-pro-swift-build
```

公开分发前需要使用开发者证书重新签名并完成公证。构建脚本会验证随包模型、运行时、许可证和隐私清单。

## 隐私、第三方组件与图标

当前版本默认在本机处理图片和项目，不要求账号，不包含广告追踪或分析服务，也不会自动上传图片。详见 [隐私政策](PRIVACY.md)。智能修复、运行时和字体的许可证见 [第三方声明](THIRD_PARTY_NOTICES.md)，应用内也可从“关于 → 第三方许可”查看完整文本。

应用图标及 `Design/Icon.icon` 中的源图稿由 iMage Pro project 原创，保留全部权利，不包含在源代码的 Apache-2.0 授权中。

## 许可证

本项目代码采用 [Apache License 2.0](LICENSE)。第三方组件、模型权重、字体和测试样本继续受其各自许可证约束；项目许可证不会覆盖或替换这些条款。使用前请阅读 [免责声明](DISCLAIMER.md)。

贡献方式见 [CONTRIBUTING.md](CONTRIBUTING.md)，安全问题见 [SECURITY.md](SECURITY.md)。

## 支持创作

iMage Pro 免费、开源。赞助完全自愿，不解锁功能，也不影响任何人的使用。

<a href="https://ko-fi.com/T0N028J9BE" target="_blank" rel="noopener noreferrer"><img height="36" style="border:0px;height:36px;" src="https://storage.ko-fi.com/cdn/kofi3.png?v=6" alt="Buy Me a Coffee at ko-fi.com" /></a>

也可以使用支付宝扫码支持：

<img src="assets/alipay-qr.jpg" width="240" alt="支付宝赞助二维码" />
