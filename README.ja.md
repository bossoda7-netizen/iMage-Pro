# iMage Pro

<p>
  <a href="README.md"><img src="assets/readme/language-zh.svg" alt="简体中文" height="30" /></a>
  <a href="README.en.md"><img src="assets/readme/language-en.svg" alt="English" height="30" /></a>
  <a href="README.ko.md"><img src="assets/readme/language-ko.svg" alt="한국어" height="30" /></a>
  <a href="README.ja.md"><img src="assets/readme/language-ja.svg" alt="日本語" height="30" /></a>
</p>

macOS向けのネイティブ画像編集アプリです。現在の公開プレビュー版は **0.9.2** です。SwiftUI、AppKit、Core Image、Metal、デバイス上の画像認識機能を使用し、インテリジェント修復のモデルもローカルで実行します。

[公式サイト · ひらめきを広げるキャンバス](https://bossoda7-netizen.github.io/iMage-Pro-website/index-ja.html) · [プレビュー版をダウンロード](https://github.com/bossoda7-netizen/iMage-Pro/releases/tag/v0.9.2)

![iMage Proのインターフェイス](assets/readme/image-pro-overview.png)

## 機能

- 45種類のツール、36種類のエフェクト、直感的な操作
- 複数レイヤーの編集、非破壊エフェクト、プロスコープ、並べ替え可能なインスペクタ、定規モード、スマートツールバー
- 4つの表示言語：中国語（簡体字）、英語、韓国語、日本語
- `.imgp` プロジェクトの保存、PSD/PSBの読み込み、PNG、JPEG、TIFF、WebPなどの形式への書き出し

## 使い方

[GitHub Releases](https://github.com/bossoda7-netizen/iMage-Pro/releases)からApple Silicon向けプレビュー版をダウンロードし、展開して `iMage Pro.app` を「アプリケーション」に移動してください。現在のバージョンは一時的な署名（アドホック署名）を使用しており、Appleの公証はまだ受けていません。macOSが起動をブロックした場合は、「システム設定 → プライバシーとセキュリティ」に「このまま開く」が表示されるか確認してください。

## ビルドとテスト

Xcode 26、Swift 6、Apple Silicon、およびmacOS 14以降が必要です。

```sh
git clone https://github.com/bossoda7-netizen/iMage-Pro.git
cd iMage-Pro
zsh scripts/build.sh
swift test --scratch-path /tmp/image-pro-swift-build
```

一般公開する前に、開発者証明書で再署名し、公証を完了する必要があります。ビルドスクリプトは、同梱のモデル、ランタイム、ライセンス、プライバシーマニフェストを検証します。

## プライバシー、サードパーティ製コンポーネント、アイコン

現在のバージョンは、標準で画像とプロジェクトをローカルで処理します。アカウントは不要で、広告トラッカーや解析サービスを含まず、画像を自動的にアップロードすることもありません。詳しくは[プライバシーポリシー](PRIVACY.md)をご覧ください。インテリジェント修復、ランタイム、フォントのライセンスは[サードパーティに関する告知](THIRD_PARTY_NOTICES.md)に記載しています。アプリの「このアプリについて → サードパーティライセンス」でも全文を確認できます。

アプリアイコンおよび `Design/Icon.icon` の元のアートワークは、iMage Pro projectのオリジナル作品です。すべての権利を留保し、ソースコードのApache-2.0ライセンスには含まれません。

## ライセンス

本プロジェクトのソースコードには[Apache License 2.0](LICENSE)が適用されます。サードパーティ製コンポーネント、モデルの重み、フォント、テストサンプルには、それぞれのライセンスが引き続き適用されます。プロジェクトのライセンスがこれらの条件を上書きしたり、置き換えたりすることはありません。使用前に[免責事項](DISCLAIMER.md)をお読みください。

貢献方法は[CONTRIBUTING.md](CONTRIBUTING.md)、セキュリティに関する問題は[SECURITY.md](SECURITY.md)をご覧ください。

## 創作を応援する

iMage Proは無料のオープンソースアプリです。支援は完全に任意であり、機能の解放や利用条件に影響することはありません。

<a href="https://ko-fi.com/T0N028J9BE" target="_blank" rel="noopener noreferrer"><img height="36" style="border:0px;height:36px;" src="https://storage.ko-fi.com/cdn/kofi3.png?v=6" alt="Buy Me a Coffee at ko-fi.com" /></a>

AlipayのQRコードを読み取って支援することもできます。

<img src="assets/alipay-qr.jpg" width="240" alt="Alipay支援用QRコード" />
