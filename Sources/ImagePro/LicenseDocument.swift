import Foundation

struct LicenseDocument: Identifiable, Sendable {
  let id: Int
  let title: String
  let pages: [String]

  /// Bound each layout operation, while preserving every character of a notice.
  static func parse(_ text: String, pageLength: Int = 6000) -> [LicenseDocument] {
    text.components(separatedBy: "\n========================================================================\n")
      .enumerated().compactMap { index, section in
        let content = section.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return nil }
        var pages: [String] = []
        var start = content.startIndex
        while start < content.endIndex {
          let end = content.index(start, offsetBy: max(1, pageLength), limitedBy: content.endIndex) ?? content.endIndex
          pages.append(String(content[start..<end]))
          start = end
        }
        return LicenseDocument(id: index, title: String(content.prefix(while: { $0 != "\n" })), pages: pages)
      }
  }

  static func load() -> [LicenseDocument] {
    guard let url = Bundle.module.url(forResource: "ThirdPartyLicenses", withExtension: "txt", subdirectory: "Legal"),
      let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
    return parse(text)
  }
}
