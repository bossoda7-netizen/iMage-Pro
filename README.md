# iMage Pro

原生 macOS 图像编辑器，当前公开预览版为 **0.9.2**。项目使用 SwiftUI、AppKit、Core Image、Metal 和本机图像识别能力，智能修复模型在本机运行。

## 功能

- 多图层编辑、文件夹、蒙版、剪切蒙版和非破坏效果器
- 选区、画笔、文字、路径、裁剪、渐变、变换和标尺工具
- 智能修复、涂抹、液化推移、仿制图章等修饰工具
- 四种界面语言：简体中文、English、한국어、日本語
- `.imgp` 项目保存、PSD/PSB 导入和 PNG、JPEG、TIFF、WebP 等格式导出
- 本机 ONNX Runtime 与 MI-GAN 模型，不要求 Python 或 Node.js

## 使用

从 [GitHub Releases](https://github.com/bossoda7-netizen/iMage-Pro/releases) 下载 Apple Silicon 预览版，解压后将 `iMage Pro.app` 放入“应用程序”。当前版本采用临时签名，尚未通过 Apple 公证；如系统拦截，可在“系统设置 → 隐私与安全性”中查看是否提供“仍要打开”。

双击应用启动。创建或打开项目后，使用底栏选择工具；图层、效果器和调节器分别从底栏和顶栏打开。使用顶栏“…”访问打开、保存、吸附、网格和使用指南。

常用快捷键：V 移动、B 画笔、E 橡皮、M 选区、L 套索、T 文字、U 形状、C 裁剪、P 钢笔、⌘T 自由变换、⌘S 保存项目、⇧⌘E 导出。完整快捷键在应用的使用指南和设置 → 快捷键中提供。

智能修复位于修饰分类。选择可编辑的图像图层后，涂过需要修复的区域，松开鼠标后由本机模型处理。建议分次处理小区域；结果可用 ⌘Z 撤销。

## 构建与测试

要求 Xcode 26、Swift 6、Apple Silicon 和 macOS 14 或更高版本。

    git clone https://github.com/bossoda7-netizen/iMage-Pro.git
    cd iMage-Pro
    zsh scripts/build.sh
    swift test --scratch-path /tmp/image-pro-swift-build

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

此二维码由项目创作者提供，用于自愿赞助，保留其权利，不包含在代码许可证中。
