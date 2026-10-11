import AppKit
import SwiftUI

/// The sheet's native window must also be transparent: a clear SwiftUI
/// presentation background alone does not remove the AppKit window's backing.
struct ManagementWindowMaterial: View {
  @ObservedObject private var localization = LocalizationState.shared
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  var body: some View {
    if reduceTransparency {
      Color(nsColor: .windowBackgroundColor)
    } else {
      NativeSheetMaterial().allowsHitTesting(false).accessibilityHidden(true)
    }
  }
}

private struct NativeSheetMaterial: NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  func makeNSView(context: Context) -> ManagementBackdropView {
    let view = ManagementBackdropView()
    // This is the entire auxiliary window's background, rather than the
    // comparatively opaque fill used by a standard sheet's content.
    view.material = .underWindowBackground
    view.blendingMode = .behindWindow
    view.state = .active
    return view
  }
  func updateNSView(_ view: ManagementBackdropView, context: Context) {
    view.configureWindow()
  }
  static func dismantleNSView(_ view: ManagementBackdropView, coordinator: ()) {
    view.restoreWindow()
  }
}

final class ManagementBackdropView: NSVisualEffectView {
  private weak var materialWindow: NSWindow?
  private var originalBackground: NSColor?
  private var originalOpaque = true

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    configureWindow()
    // SwiftUI configures the sheet's backing during the presentation
    // transaction. Reapply after that transaction, without changing its frame.
    DispatchQueue.main.async { [weak self] in self?.configureWindow() }
  }

  func configureWindow() {
    guard let window else { return }
    if materialWindow !== window {
      restoreWindow()
      materialWindow = window
      originalBackground = window.backgroundColor
      originalOpaque = window.isOpaque
    }
    window.isOpaque = false
    window.backgroundColor = .clear
  }

  func restoreWindow() {
    if let materialWindow {
      materialWindow.isOpaque = originalOpaque
      if let originalBackground { materialWindow.backgroundColor = originalBackground }
    }
    materialWindow = nil
    originalBackground = nil
  }
}

struct ExportArtworkPreview: View {
  @ObservedObject private var localization = LocalizationState.shared
  var image: CGImage?
  var aspectRatio: CGFloat
  var transparent: Bool
  var body: some View {
    ZStack {
      if transparent {
        Canvas { context, size in
          context.fill(Path(CGRect(origin: .zero, size: size)),
            with: .color(Color(nsColor: .textBackgroundColor)))
          let cell: CGFloat = 10
          for row in 0..<Int(ceil(size.height / cell)) {
            for column in 0..<Int(ceil(size.width / cell)) where (row + column).isMultiple(of: 2) {
              context.fill(Path(CGRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell,
                width: cell, height: cell)), with: .color(.primary.opacity(0.13)))
            }
          }
        }
      } else {
        Color.white
      }
      if let image {
        Image(decorative: image, scale: 1).resizable().scaledToFit()
      }
    }.aspectRatio(aspectRatio, contentMode: .fit)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5))
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .accessibilityLabel(L("作品合成预览"))
  }
}

struct ExportOptionRow: View {
  @ObservedObject private var localization = LocalizationState.shared
  var title: String
  var value: String
  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 16) {
      Text(L(title)).foregroundStyle(.secondary)
      Spacer(minLength: 8)
      Text(L(value)).foregroundStyle(.primary).monospacedDigit().multilineTextAlignment(.trailing)
    }.frame(maxWidth: .infinity)
  }
}
