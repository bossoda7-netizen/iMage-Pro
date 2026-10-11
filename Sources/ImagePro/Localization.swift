import Foundation
import SwiftUI

/// UI language is independent of document contents and serialized tool IDs.
enum AppLanguage: String, CaseIterable, Identifiable {
  case simplifiedChinese = "zh-Hans", english = "en", korean = "ko", japanese = "ja"
  static let preferenceKey = "appLanguage"
  var id: String { rawValue }
  var nativeName: String {
    switch self {
    case .simplifiedChinese: return "简体中文"
    case .english: return "English"
    case .korean: return "한국어"
    case .japanese: return "日本語"
    }
  }
  static func saved(in defaults: UserDefaults = .standard) -> Self {
    defaults.string(forKey: preferenceKey).flatMap(Self.init(rawValue:)) ?? .simplifiedChinese
  }
  func save(in defaults: UserDefaults = .standard) { defaults.set(rawValue, forKey: Self.preferenceKey) }
}

/// Only pass app-owned UI strings here. User text, file names and folder names
/// are rendered verbatim. All language tables have the same source keys.
final class LocalizationState: ObservableObject {
  static let shared = LocalizationState()
}

enum AppLocalization {
  static var language = AppLanguage.saved() {
    didSet { LocalizationState.shared.objectWillChange.send() }
  }
  static let tables: [AppLanguage: [String: String]] = {
    Dictionary(uniqueKeysWithValues: AppLanguage.allCases.map { language in
      guard let path = Bundle.module.path(forResource: "Localizable", ofType: "strings", inDirectory: nil, forLocalization: language.rawValue),
            let data = FileManager.default.contents(atPath: path),
            let table = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: String] else {
        assertionFailure("Missing localization: \(language.rawValue)")
        return (language, [:])
      }
      return (language, table)
    })
  }()
  // Legacy undo history contains already-interpolated Chinese messages. Match
  // those templates only after exact lookup, never by replacing individual words.
  private static let templates: [(String, NSRegularExpression, String)] = {
    (tables[.simplifiedChinese] ?? [:]).keys.filter { $0.contains("{0}") }.sorted { $0.count > $1.count }.compactMap { key in
      let parts = key.components(separatedBy: try! NSRegularExpression(pattern: "\\{[0-9]+\\}"))
      let pattern = "^" + parts.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "([\\s\\S]*?)") + "$"
      guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
      return (key, regex, parts.first ?? "")
    }
  }()
  static func string(_ source: String, language: AppLanguage, arguments: [String] = []) -> String {
    let table = tables[language] ?? [:]
    if let translated = table[source] { return interpolate(translated, arguments: arguments) }
    guard arguments.isEmpty else { return interpolate(source, arguments: arguments) }
    // The literal Chinese segments make these patterns specific. Prefix filtering
    // avoids regex work on slider labels and unrecognized third-party messages.
    for (key, regex, prefix) in templates where prefix.isEmpty || source.hasPrefix(prefix) {
      guard let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)), let translated = table[key] else { continue }
      var captures = (1..<match.numberOfRanges).map { index in
        Range(match.range(at: index), in: source).map { String(source[$0]) } ?? ""
      }
      if ["调整{0}", "重置{0}", "关闭{0}", "{0} · 更多设置", "{0}色轮", "新建{0}", "添加{0}"].contains(key) {
        captures = captures.map { table[$0] ?? $0 }
      }
      return interpolate(translated, arguments: captures)
    }
    return source
  }
  private static let placeholderRegex = try! NSRegularExpression(pattern: "\\{([0-9]+)\\}")
  private static func interpolate(_ template: String, arguments: [String]) -> String {
    // One pass ensures a user's literal “{1}” is never treated as a placeholder.
    guard !arguments.isEmpty else { return template }
    let regex = placeholderRegex
    var result = template
    for match in regex.matches(in: template, range: NSRange(template.startIndex..., in: template)).reversed() {
      guard let indexRange = Range(match.range(at: 1), in: template), let index = Int(template[indexRange]), arguments.indices.contains(index), let range = Range(match.range, in: result) else { continue }
      result.replaceSubrange(range, with: arguments[index])
    }
    return result
  }
}

private extension String {
  func components(separatedBy regex: NSRegularExpression) -> [String] {
    var parts: [String] = [], start = startIndex
    for match in regex.matches(in: self, range: NSRange(startIndex..., in: self)) {
      guard let range = Range(match.range, in: self) else { continue }
      parts.append(String(self[start..<range.lowerBound])); start = range.upperBound
    }
    parts.append(String(self[start...])); return parts
  }
}

func L(_ source: String, _ arguments: Any...) -> String {
  AppLocalization.string(source, language: AppLocalization.language, arguments: arguments.map { String(describing: $0) })
}
