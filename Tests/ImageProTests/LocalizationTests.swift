import XCTest
import AppKit
@testable import ImagePro

final class LocalizationTests: XCTestCase {
  private func translated(_ source: String, _ language: AppLanguage, _ arguments: String...) -> String {
    AppLocalization.string(source, language: language, arguments: arguments)
  }

  func testAllLanguagesHaveCompleteCatalogsAndMatchingPlaceholders() throws {
    let chinese = try XCTUnwrap(AppLocalization.tables[.simplifiedChinese])
    XCTAssertGreaterThan(chinese.count, 1200)
    let regex = try NSRegularExpression(pattern: "\\{[0-9]+\\}")
    func placeholders(_ value: String) -> [String] {
      regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map {
        String(value[Range($0.range, in: value)!])
      }.sorted()
    }
    for language in AppLanguage.allCases {
      let table = try XCTUnwrap(AppLocalization.tables[language])
      XCTAssertEqual(Set(table.keys), Set(chinese.keys), language.rawValue)
      for (key, value) in table {
        XCTAssertFalse(value.isEmpty, "\(language.rawValue): \(key)")
        XCTAssertEqual(placeholders(key), placeholders(value), "\(language.rawValue): \(key)")
        if [.english, .korean].contains(language), !["简体中文", "日本語"].contains(key) {
          XCTAssertNil(value.range(of: "[\\p{Han}]", options: .regularExpression), "Untranslated \(language.rawValue): \(key)")
        }
      }
    }
  }

  func testEditingTerminologyAndContextAreDistinct() {
    for (language, mask, clipping, selection, path) in [
      (AppLanguage.english, "Mask", "Clipping Mask", "Selection", "Path"),
      (.korean, "마스크", "클리핑 마스크", "선택 영역", "패스"),
      (.japanese, "マスク", "クリッピングマスク", "選択範囲", "パス")
    ] {
      XCTAssertEqual(translated("蒙版", language), mask)
      XCTAssertEqual(translated("剪切蒙版", language), clipping)
      XCTAssertEqual(translated("选区", language), selection)
      XCTAssertEqual(translated("路径", language), path)
      XCTAssertNotEqual(translated("扩展", language), translated("style.spread", language))
      XCTAssertNotEqual(translated("appearance.dark", language), translated("深色", language))
    }
    XCTAssertEqual(translated("blend.luminosity", .english), "Luminosity")
    XCTAssertEqual(translated("明度", .english), "Lightness")
    XCTAssertEqual(translated("亮度", .english), "Brightness")
    XCTAssertEqual(translated("阴影", .english), "Shadow")
    XCTAssertEqual(translated("tone.shadows", .english), "Shadows")
    XCTAssertEqual(translated("brush.chisel", .english), "Chisel")
    XCTAssertEqual(translated("斜切", .english), "Skew")
    XCTAssertEqual(translated("transform.scale", .english), "Scale")
    XCTAssertEqual(translated("缩放", .english), "Zoom")
    XCTAssertEqual(translated("selection.expand", .english), "Expand")
    XCTAssertEqual(translated("vignette.shading", .english), "Shading")
    XCTAssertEqual(translated("调整style.spread", .english), "Adjust Spread")
  }

  func testInterpolationPreservesUserTextAndLiteralPlaceholders() {
    let userName = "颜色 {1} 🖼️ 프로젝트 / 作品"
    for language in AppLanguage.allCases {
      let message = translated("保存“{0}”的更改？", language, userName)
      XCTAssertTrue(message.contains(userName))
      let multi = translated("打开{0}，{1}", language, userName, "{0} detail")
      XCTAssertTrue(multi.contains(userName))
      XCTAssertTrue(multi.contains("{0} detail"))
      XCTAssertEqual(translated("third-party 🔧 message", language), "third-party 🔧 message")
    }
    XCTAssertEqual(translated("调整style.spread", .simplifiedChinese), "调整扩展")
    XCTAssertEqual(translated("调整画布", .english), "Adjust Canvas")
    XCTAssertEqual(translated("晨光 2", .english), "Morning Light 2")
  }

  func testLanguagePreferencePersistsAndRejectsUnsupportedValues() throws {
    let suite = "com.imagepro.tests.localization.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    XCTAssertEqual(AppLanguage.saved(in: defaults), .simplifiedChinese)
    for language in AppLanguage.allCases {
      language.save(in: defaults)
      XCTAssertEqual(AppLanguage.saved(in: defaults), language)
    }
    defaults.set("unsupported", forKey: AppLanguage.preferenceKey)
    XCTAssertEqual(AppLanguage.saved(in: defaults), .simplifiedChinese)
  }

  func testEveryToolEffectAndPresetHasTranslations() {
    let sources = ToolCategory.allCases.map(\.rawValue)
      + ToolCategory.allCases.flatMap { $0.branches.map(\.title) }
      + EffectKind.allCases.flatMap { [$0.title, $0.subtitle] }
      + BrushTip.all.map(\.name) + ShapePreset.all.map(\.name)
      + CanvasPreset.all.map(\.name) + ShortcutCatalog.guide.flatMap { [$0.0, $0.1] }
      + UserGuide.sections.flatMap { [$0.title] + $0.paragraphs }
    for source in sources where source.unicodeScalars.contains(where: { (0x4E00...0x9FFF).contains($0.value) }) {
      for language in [AppLanguage.english, .korean, .japanese] {
        XCTAssertNotNil(AppLocalization.tables[language]?[source], "\(language.rawValue): \(source)")
      }
    }
  }

  @MainActor func testNewDefaultNamesFollowLanguageAndClearingTextDoesNotRestoreChinese() {
    let previous = AppLocalization.language
    defer { AppLocalization.language = previous }
    for language in AppLanguage.allCases {
      AppLocalization.language = language
      let store = EditorStore(loadRecovery: false)
      store.newProject(width: 80, height: 80)
      XCTAssertEqual(store.document.name, L("未命名"))
      XCTAssertEqual(store.document.layers.first?.name, L("画布"))
      store.addLayer(.text)
      XCTAssertEqual(AppLocalization.string(store.active.undo.last!.name, language: .english), "Create Text")
      store.updateSelected("编辑文字") { $0.text = "内容 日本語 한국어" }
      XCTAssertEqual(store.selected?.name, "内容 日本語 한국어")
      store.updateSelected("编辑文字") { $0.text = "" }
      XCTAssertEqual(store.selected?.name, L("文字"))
    }
  }

  @MainActor func testStandardMenusSwitchWithoutChangingActions() {
    let previous = AppLocalization.language
    defer { AppLocalization.language = previous }
    let menu = NSMenu()
    let file = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
    file.submenu = NSMenu(title: "文件")
    menu.addItem(file)
    let app = NSMenuItem(title: "iMage Pro", action: nil, keyEquivalent: "")
    app.submenu = NSMenu(title: "iMage Pro")
    let quit = NSMenuItem(title: "退出 iMage Pro", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    quit.attributedTitle = NSAttributedString(string: "退出 iMage Pro")
    app.submenu?.addItem(quit)
    menu.addItem(app)
    for language in AppLanguage.allCases {
      AppLocalization.language = language
      NativeMenuLocalization.shared.localize(menu)
      XCTAssertEqual(file.title, L("menu.file"))
      XCTAssertEqual(file.submenu?.title, L("menu.file"))
      XCTAssertEqual(quit.title, L("menu.quit"))
      XCTAssertEqual(quit.action, #selector(NSApplication.terminate(_:)))
      XCTAssertEqual(quit.keyEquivalent, "q")
      XCTAssertTrue(quit.attributedTitle == nil || quit.attributedTitle?.string.isEmpty == true)
      XCTAssertEqual(app.title, "iMage Pro")
    }
  }

  @MainActor func testLiveSwitchLeavesDocumentSelectionAndHistoryUntouched() throws {
    let previousLanguage = AppLocalization.language
    let previousPreference = UserDefaults.standard.object(forKey: AppLanguage.preferenceKey)
    defer {
      AppLocalization.language = previousLanguage
      if let previousPreference { UserDefaults.standard.set(previousPreference, forKey: AppLanguage.preferenceKey) }
      else { UserDefaults.standard.removeObject(forKey: AppLanguage.preferenceKey) }
    }
    let store = EditorStore(loadRecovery: false)
    store.newProject(name: "颜色", width: 80, height: 80)
    store.addLayer(.text)
    store.updateSelected("编辑文字") { $0.text = "日本語 한국어 English 中文"; $0.name = "蒙版" }
    let document = store.document
    let history = store.active.undo.map(\.name)
    let selected = store.selectedIDs
    let session = store.active.id
    store.sheet = "settings"
    for language in AppLanguage.allCases {
      store.language = language
      XCTAssertEqual(AppLocalization.language, language)
      XCTAssertEqual(AppLanguage.saved(), language)
      XCTAssertEqual(store.document, document)
      XCTAssertEqual(store.active.undo.map(\.name), history)
      XCTAssertEqual(store.selectedIDs, selected)
      XCTAssertEqual(store.active.id, session)
      XCTAssertEqual(store.sheet, "settings")
      let reopened = try JSONDecoder().decode(ImageDocument.self, from: JSONEncoder().encode(store.document))
      XCTAssertEqual(reopened.name, "颜色")
      XCTAssertEqual(reopened.layers, document.layers)
    }
    // The on-disk enum identities remain compatible with existing projects.
    XCTAssertEqual(BlendMode.multiply.rawValue, "正片叠底")
    XCTAssertEqual(EffectKind.grain.rawValue, "胶片颗粒")
    XCTAssertEqual(ToolCategory.path.rawValue, "路径")
  }
}
