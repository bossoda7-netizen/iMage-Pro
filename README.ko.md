# iMage Pro

<p>
  <a href="README.md"><img src="assets/readme/language-zh.svg" alt="简体中文" height="30" /></a>
  <a href="README.en.md"><img src="assets/readme/language-en.svg" alt="English" height="30" /></a>
  <a href="README.ko.md"><img src="assets/readme/language-ko.svg" alt="한국어" height="30" /></a>
  <a href="README.ja.md"><img src="assets/readme/language-ja.svg" alt="日本語" height="30" /></a>
</p>

macOS용 네이티브 이미지 편집기입니다. 현재 공개 프리뷰 버전은 **0.9.2**입니다. SwiftUI, AppKit, Core Image, Metal 및 기기 내 이미지 인식 기능을 사용하며, 지능형 복원 모델도 로컬에서 실행됩니다.

[공식 웹사이트 · 영감을 펼칠 캔버스](https://bossoda7-netizen.github.io/iMage-Pro-website/index-ko.html) · [프리뷰 다운로드](https://github.com/bossoda7-netizen/iMage-Pro/releases/tag/v0.9.2)

![iMage Pro 인터페이스](assets/readme/image-pro-overview.png)

## 기능

- 도구 45종, 효과 36종, 직관적인 사용 경험
- 다중 레이어 편집, 비파괴 효과, 전문 스코프, 순서를 바꿀 수 있는 속성 패널, 눈금자 모드, 스마트 도구 모음
- 네 가지 인터페이스 언어: 중국어 간체, 영어, 한국어, 일본어
- `.imgp` 프로젝트 저장, PSD/PSB 가져오기, PNG, JPEG, TIFF, WebP 등 다양한 형식으로 내보내기

## 사용 방법

[GitHub Releases](https://github.com/bossoda7-netizen/iMage-Pro/releases)에서 Apple Silicon용 프리뷰를 다운로드하고 압축을 푼 뒤, `iMage Pro.app`을 응용 프로그램 폴더로 옮기세요. 현재 버전은 임시 서명(ad-hoc)을 사용하며 아직 Apple의 공증을 받지 않았습니다. macOS가 실행을 차단하면 시스템 설정 → 개인정보 보호 및 보안에서 ‘확인 없이 열기’ 옵션이 표시되는지 확인하세요.

## 빌드 및 테스트

Xcode 26, Swift 6, Apple Silicon 및 macOS 14 이상이 필요합니다.

```sh
git clone https://github.com/bossoda7-netizen/iMage-Pro.git
cd iMage-Pro
zsh scripts/build.sh
swift test --scratch-path /tmp/image-pro-swift-build
```

공개 배포 전에는 개발자 인증서로 다시 서명하고 공증을 완료해야 합니다. 빌드 스크립트는 앱에 포함된 모델, 런타임, 라이선스 및 개인정보 보호 매니페스트를 검증합니다.

## 개인정보 보호, 타사 구성 요소 및 아이콘

현재 버전은 기본적으로 이미지와 프로젝트를 로컬에서 처리합니다. 계정이 필요 없고 광고 추적기나 분석 서비스를 포함하지 않으며, 이미지를 자동으로 업로드하지 않습니다. 자세한 내용은 [개인정보 처리방침](PRIVACY.md)을 참고하세요. 지능형 복원, 런타임 및 글꼴의 라이선스는 [타사 고지](THIRD_PARTY_NOTICES.md)에 정리되어 있으며, 앱의 정보 → 타사 라이선스에서도 전문을 확인할 수 있습니다.

앱 아이콘과 `Design/Icon.icon`의 원본 아트워크는 iMage Pro project가 직접 제작했습니다. 모든 권리를 보유하며, 소스 코드의 Apache-2.0 라이선스에 포함되지 않습니다.

## 라이선스

프로젝트의 소스 코드는 [Apache License 2.0](LICENSE)을 따릅니다. 타사 구성 요소, 모델 가중치, 글꼴 및 테스트 샘플에는 각각의 라이선스가 계속 적용되며, 프로젝트 라이선스는 해당 조건을 대체하거나 무효화하지 않습니다. 사용 전 [면책 조항](DISCLAIMER.md)을 읽어 주세요.

기여 방법은 [CONTRIBUTING.md](CONTRIBUTING.md), 보안 문제는 [SECURITY.md](SECURITY.md)를 참고하세요.

## 창작 후원

iMage Pro는 무료 오픈 소스입니다. 후원은 전적으로 자발적이며, 기능을 잠금 해제하거나 다른 사용자의 이용에 영향을 주지 않습니다.

<a href="https://ko-fi.com/T0N028J9BE" target="_blank" rel="noopener noreferrer"><img height="36" style="border:0px;height:36px;" src="https://storage.ko-fi.com/cdn/kofi3.png?v=6" alt="Buy Me a Coffee at ko-fi.com" /></a>

Alipay QR 코드를 스캔하여 후원할 수도 있습니다.

<img src="assets/alipay-qr.jpg" width="240" alt="Alipay 후원 QR 코드" />
