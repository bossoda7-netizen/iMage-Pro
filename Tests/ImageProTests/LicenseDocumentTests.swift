import XCTest
@testable import ImagePro

final class LicenseDocumentTests: XCTestCase {
  func testPagesPreserveCompleteNoticeAndBoundLayoutSize() {
    let notice = "Copyright\n" + String(repeating: "许可 abc 👩🏽‍🎨\n", count: 3000)
    let documents = LicenseDocument.parse(notice)
    XCTAssertEqual(documents.count, 1)
    XCTAssertEqual(documents[0].pages.joined(), notice.trimmingCharacters(in: .whitespacesAndNewlines))
    XCTAssertTrue(documents[0].pages.allSatisfy { $0.count <= 6000 })
  }

  func testBundledNoticesIncludeMIGANAndHaveNoEmptyPages() {
    let documents = LicenseDocument.load()
    XCTAssertEqual(documents.count, 6)
    XCTAssertTrue(documents.contains { $0.title.contains("MI-GAN model weights") })
    XCTAssertTrue(documents.contains { $0.title.contains("ONNX Runtime") })
    XCTAssertTrue(documents.allSatisfy { !$0.pages.isEmpty && $0.pages.allSatisfy { !$0.isEmpty } })
  }
}
