import AppKit
import SwiftUI

private struct AppAccentKey: EnvironmentKey {
  static let defaultValue: Color = .accentColor
}
extension EnvironmentValues {
  var appAccent: Color {
    get { self[AppAccentKey.self] }
    set { self[AppAccentKey.self] = newValue }
  }
}

struct GlassSurface: ViewModifier {
  var radius: Double = 22
  var attached = false
  @Environment(\.accessibilityReduceTransparency) var reduceTransparency
  @Environment(\.colorSchemeContrast) var contrast
  func body(content: Content) -> some View {
    Group {
      if reduceTransparency {
        content.background(
          Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: radius))
      } else if #available(macOS 26.0, *) {
        content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: radius))
      } else {
        content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius))
      }
    }
    .overlay(alignment: .bottom) {
      if attached {
        Rectangle().fill(Color.primary.opacity(contrast == .increased ? 0.4 : 0.09))
          .frame(height: 0.7)
      } else {
        RoundedRectangle(cornerRadius: radius).strokeBorder(
          Color.primary.opacity(contrast == .increased ? 0.4 : 0.09), lineWidth: 0.7)
      }
    }
    .shadow(color: .black.opacity(attached ? 0 : 0.1), radius: attached ? 0 : 15,
            y: attached ? 0 : 6)
  }
}
extension View {
  func glassSurface(_ radius: Double = 22, attached: Bool = false) -> some View {
    modifier(GlassSurface(radius: radius, attached: attached))
  }
}

struct IconButton: View {
  @ObservedObject private var localization = LocalizationState.shared
  var symbol: String
  var label: String
  var selected = false
  var size: Double = 32
  var action: () -> Void
  @State private var hover = false
  @Environment(\.appAccent) private var appAccent
  var body: some View {
    Button(action: action) {
      Image(systemName: symbol).font(.system(size: 15, weight: .medium))
        .frame(width: size, height: size)
        .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.8))
        .background(
          selected ? appAccent : Color.primary.opacity(hover ? 0.08 : 0),
          in: RoundedRectangle(cornerRadius: 10))
    }.buttonStyle(.plain).help(L(label)).accessibilityLabel(L(label)).onHover { hover = $0 }
  }
}
struct TextAction: View {
  @ObservedObject private var localization = LocalizationState.shared
  var title: String
  var symbol: String? = nil
  var selected = false
  var action: () -> Void
  @State private var hover = false
  @Environment(\.appAccent) private var appAccent
  var body: some View {
    Button(action: action) {
      HStack(spacing: 8) {
        if let symbol { Image(systemName: symbol).font(.system(size: 16, weight: .medium)) }
        Text(L(title)).font(.system(size: 13, weight: .medium))
      }
      .padding(.horizontal, 13).frame(height: 36)
      .foregroundStyle(selected ? appAccent : Color.primary)
      .background(Color.primary.opacity(hover || selected ? 0.07 : 0), in: Capsule())
    }.buttonStyle(.plain).onHover { hover = $0 }
  }
}
struct PanelHeader: View {
  @ObservedObject private var localization = LocalizationState.shared
  var title: String
  var subtitle: String? = nil
  var close: () -> Void
  var body: some View {
    HStack(alignment: .center) {
      VStack(alignment: .leading, spacing: 3) {
        Text(L(title)).font(.system(size: 16, weight: .semibold))
        if let subtitle {
          Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
        }
      }
      Spacer()
      IconButton(symbol: "xmark", label: "关闭\(title)", size: 28, action: close)
    }
  }
}
struct ParameterSlider: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var title: String
  var value: Double
  var range: ClosedRange<Double>
  var unit = ""
  var digits = 0
  var percentage = false
  var defaultValue: Double? = nil
  var set: (Double) -> Void
  @State private var numericDragOrigin: Double?
  @FocusState private var numericFocused: Bool
  var body: some View {
    VStack(spacing: 8) {
      HStack {
        Text(L(title)).foregroundStyle(.secondary)
        Spacer()
        ScrubNumberField(value: Binding(
          get: { percentage ? value * 100 : value },
          set: { input in set(percentage ? input / 100 : input) }
        ), range: percentage ? (range.lowerBound * 100)...(range.upperBound * 100) : range, digits: digits,
        beginEditing: { store.beginTransaction("调整\(title)") },
        endEditing: { store.endTransaction() })
        .frame(minWidth: 50, maxWidth: 76, minHeight: 20)
        Text(L(unit)).foregroundStyle(.tertiary).font(.system(size: 10))
      }.font(.system(size: 11, weight: .medium))
      ResettableSlider(value: Binding(get: { value }, set: set), range: range,
        reset: {
          store.beginTransaction("重置" + title)
          set(defaultValue ?? ParameterDefaults.value(title, range: range))
          store.endTransaction()
        }, begin: { store.beginTransaction("调整" + title) }, end: { store.endTransaction() })
        .frame(height: 20).accessibilityLabel(L(title)).help(L("双击滑块恢复默认值"))
    }
  }
}

/// A native text field with continuous value scrubbing. A single click
/// selects the complete number, a horizontal drag changes it, and a second
/// click enters normal text editing. Keeping the mouse sequence in AppKit
/// avoids SwiftUI TextField stealing the drag and leaving the value unchanged.
struct ScrubNumberField: NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  @Binding var value: Double
  var range: ClosedRange<Double>
  var digits: Int
  var beginEditing: () -> Void = {}
  var endEditing: () -> Void = {}

  func makeCoordinator() -> Coordinator { Coordinator(self) }
  func makeNSView(context: Context) -> ScrubTextField {
    let field = ScrubTextField()
    field.coordinator = context.coordinator
    field.isEditable = true
    field.isSelectable = true
    field.isBordered = false
    field.focusRingType = .none
    field.drawsBackground = false
    field.alignment = .right
    field.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
    field.target = context.coordinator
    field.action = #selector(Coordinator.commit(_:))
    field.formatter = context.coordinator.formatter
    field.delegate = context.coordinator
    updateNSView(field, context: context)
    return field
  }

  func updateNSView(_ field: ScrubTextField, context: Context) {
    context.coordinator.parent = self
    field.coordinator = context.coordinator
    context.coordinator.field = field
    context.coordinator.formatter.minimum = range.lowerBound as NSNumber
    context.coordinator.formatter.maximum = range.upperBound as NSNumber
    if field.currentEditor() == nil {
      field.stringValue = context.coordinator.format(value)
    }
  }
  static func dismantleNSView(_ field:ScrubTextField,coordinator:Coordinator) {field.finishScrubbing()}

  final class Coordinator: NSObject, NSTextFieldDelegate {
    var parent: ScrubNumberField
    weak var field: ScrubTextField?
    var startValue: Double = 0
    var dragging = false
    let formatter: NumberFormatter
    init(_ parent: ScrubNumberField) {
      self.parent = parent
      formatter = NumberFormatter()
      formatter.minimumFractionDigits = 0
      formatter.maximumFractionDigits = max(0, parent.digits)
      formatter.minimum = parent.range.lowerBound as NSNumber
      formatter.maximum = parent.range.upperBound as NSNumber
    }
    func controlTextDidBeginEditing(_ notification: Notification) { parent.beginEditing() }
    func controlTextDidEndEditing(_ notification: Notification) {
      if let field = notification.object as? NSTextField { commit(field) }; parent.endEditing()
    }
    func format(_ value: Double) -> String {
      formatter.string(from: NSNumber(value: value)) ?? String(format: "%.*f", parent.digits, value)
    }
    func start(at value: Double) { startValue = value; dragging = true; parent.beginEditing() }
    func update(translation: CGFloat) {
      let span = parent.range.upperBound - parent.range.lowerBound
      let step = span < 10 ? 0.01 : span < 100 ? 0.1 : 1
      let next = min(parent.range.upperBound, max(parent.range.lowerBound, startValue + Double(translation) * step))
      parent.value = next
      field?.stringValue = format(next)
    }
    func finish() { if dragging { dragging = false; parent.endEditing() } }
    @objc func commit(_ sender: NSTextField) {
      let parsed = formatter.number(from: sender.stringValue)?.doubleValue ?? parent.value
      parent.value = min(parent.range.upperBound, max(parent.range.lowerBound, parsed))
      sender.stringValue = format(parent.value)
    }
  }
}

final class ScrubTextField: NSTextField {
  weak var coordinator: ScrubNumberField.Coordinator?
  private var downPoint: NSPoint = .zero
  private var downValue: Double = 0
  private var didScrub = false
  private var numberSelected = false
  private var selectedOnDown = false
  private var scrubMotion = ScrubMotion()
  private var capturedPointer = false
  private var deactivateObserver:NSObjectProtocol?
  private var closeObserver:NSObjectProtocol?
  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if let deactivateObserver {NotificationCenter.default.removeObserver(deactivateObserver)}
    if let closeObserver {NotificationCenter.default.removeObserver(closeObserver)}
    deactivateObserver = nil;closeObserver = nil
    guard let window else {finishScrubbing();return}
    deactivateObserver = NotificationCenter.default.addObserver(forName:NSApplication.didResignActiveNotification,object:nil,queue:.main) {[weak self] _ in self?.finishScrubbing()}
    closeObserver = NotificationCenter.default.addObserver(forName:NSWindow.willCloseNotification,object:window,queue:.main) {[weak self] _ in self?.finishScrubbing()}
  }
  deinit {
    if let deactivateObserver {NotificationCenter.default.removeObserver(deactivateObserver)}
    if let closeObserver {NotificationCenter.default.removeObserver(closeObserver)}
    if capturedPointer {CGAssociateMouseAndMouseCursorPosition(1);NSCursor.unhide()}
  }
  func finishScrubbing() {
    if capturedPointer {CGAssociateMouseAndMouseCursorPosition(1);NSCursor.unhide();capturedPointer = false}
    coordinator?.finish();didScrub = false
  }
  override var acceptsFirstResponder:Bool {true}
  // NSTextField's default implementation immediately creates its field editor,
  // which then steals the next drag. Keep selection in this control until the
  // user explicitly enters editing with a second click or a key.
  override func becomeFirstResponder()->Bool {true}
  override func resignFirstResponder()->Bool {numberSelected = false;needsDisplay = true;return super.resignFirstResponder()}
  override func draw(_ dirtyRect:NSRect) {
    if numberSelected, currentEditor() == nil {NSColor.selectedTextBackgroundColor.withAlphaComponent(0.25).setFill();NSBezierPath(roundedRect:bounds.insetBy(dx:1,dy:1),xRadius:3,yRadius:3).fill()}
    super.draw(dirtyRect)
  }
  override func keyDown(with event:NSEvent) {
    if didScrub,event.keyCode == 53 {
      coordinator?.parent.value = downValue;stringValue = coordinator?.format(downValue) ?? stringValue
      finishScrubbing();window?.makeFirstResponder(nil);return
    }
    if numberSelected {numberSelected = false;selectText(nil);currentEditor()?.keyDown(with:event)} else {super.keyDown(with:event)}
  }
  override var mouseDownCanMoveWindow: Bool { false }
  override func mouseDown(with event: NSEvent) {
    finishScrubbing()
    downPoint = event.locationInWindow
    downValue = coordinator?.parent.value ?? doubleValue
    didScrub = false;selectedOnDown = numberSelected
  }
  override func mouseDragged(with event: NSEvent) {
    let dx = event.locationInWindow.x - downPoint.x
    if !didScrub, abs(dx) < 3 { return }
    if !didScrub {
      didScrub = true;coordinator?.start(at:downValue);scrubMotion.translation = dx
      // Relative mouse deltas keep changing even at a display edge. The
      // pointer stays at the number and is restored on every exit path.
      if window?.isVisible == true,NSApp.isActive,CGAssociateMouseAndMouseCursorPosition(0) == .success {
        capturedPointer = true;NSCursor.hide();window?.makeFirstResponder(self)
      }
    } else if capturedPointer {scrubMotion.append(delta:CGFloat(event.deltaX))}
    else {scrubMotion.translation = dx}
    coordinator?.update(translation:scrubMotion.translation)
  }
  override func mouseUp(with event: NSEvent) {
    if didScrub {
      finishScrubbing()
      window?.makeFirstResponder(nil)
    } else if event.clickCount == 1 {
      if selectedOnDown {
        numberSelected = false;selectText(nil)
        if let editor = currentEditor() as? NSTextView {editor.setSelectedRange(NSRange(location:editor.string.utf16.count,length:0))}
      }
      else {window?.makeFirstResponder(self);numberSelected = true;needsDisplay = true}
    } else if event.clickCount >= 2 {
      numberSelected = false;selectText(nil)
    }
  }
}

/// Native page/panel scrolling: indicators appear while the user scrolls and
/// disappear when idle, matching macOS instead of introducing a custom blue
/// track or thumb. The axis is explicit so horizontal content gets the same
/// treatment as vertical pages.
struct PageScrollStyle: ViewModifier {
  var axes: Axis.Set
  var hidden = false

  func body(content: Content) -> some View {
    content
      .scrollIndicators(hidden ? .hidden : .automatic, axes: axes)
      .scrollBounceBehavior(.basedOnSize, axes: axes)
      .background(ScrollViewConfigurator(axes: axes, hidden: hidden).frame(width: 0, height: 0))
  }
}

private struct ScrollViewConfigurator: NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  let axes: Axis.Set
  let hidden: Bool
  func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
  func updateNSView(_ view: NSView, context: Context) {
    DispatchQueue.main.async {
      // Configure every native scroll view, preserving the axes SwiftUI owns.
      // A background can be a sibling of its scroll view; looking only through
      // ancestors misses it, while picking the first descendant can change the
      // unrelated tab strip's axes.
      func configure(_ root:NSView) {
        if let scroll = root as? NSScrollView {
          if scroll.scrollerStyle != .overlay {scroll.scrollerStyle = .overlay};scroll.autohidesScrollers = true
          scroll.verticalScroller?.controlSize = .small;scroll.horizontalScroller?.controlSize = .small
        }
        for child in root.subviews {configure(child)}
      }
      if let host = view.window?.contentView {configure(host)}

    }
  }
}

extension View {
  func pageScrollStyle(_ axes: Axis.Set = .vertical, hidden: Bool = false) -> some View {
    modifier(PageScrollStyle(axes: axes, hidden: hidden))
  }
}

struct NumericField: View {
  @ObservedObject private var localization = LocalizationState.shared
  var store: EditorStore? = nil
  var title: String
  var value: Double
  var suffix = "px"
  var range: ClosedRange<Double> = -100000...100000
  var set: (Double) -> Void
  var body: some View {
    HStack(spacing: 5) {
      Text(L(title)).foregroundStyle(.secondary).frame(minWidth: 12)
      ScrubNumberField(value: Binding(get: { value }, set: { if $0.isFinite {set($0)} }),
        range: range, digits: 1, beginEditing: {store?.beginTransaction("调整" + title)},
        endEditing: {store?.endTransaction()})
        .frame(minWidth: 28, maxWidth: .infinity, minHeight: 22).accessibilityLabel(L(title))
      Text(L(suffix)).foregroundStyle(.tertiary).font(.system(size: 10))
    }.font(.system(size: 12)).padding(9)
      .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
      .help(L("左右拖动数值调整；单击全选，双击编辑"))
  }
}

struct ResettableSlider: NSViewRepresentable {
  @ObservedObject private var localization = LocalizationState.shared
  @Environment(\.appAccent) private var accent
  @Binding var value: Double
  var range: ClosedRange<Double>
  var reset: () -> Void
  var begin: () -> Void
  var end: () -> Void
  func makeNSView(context: Context) -> ResettableNSSlider {
    let slider = ResettableNSSlider()
    slider.controlSize = .small; slider.target = slider; slider.action = #selector(ResettableNSSlider.changed)
    return slider
  }
  func updateNSView(_ slider: ResettableNSSlider, context: Context) {
    slider.trackFillColor = NSColor(accent)
    slider.minValue = range.lowerBound; slider.maxValue = range.upperBound; slider.doubleValue = value
    slider.setValue = {value = $0}
    slider.reset = {[weak slider] in reset();slider?.doubleValue = value}
    slider.begin = begin; slider.end = end
  }
}
final class ResettableNSSlider: NSSlider {
  var setValue: ((Double) -> Void)?
  var reset: (() -> Void)?
  var begin: (() -> Void)?
  var end: (() -> Void)?
  override var mouseDownCanMoveWindow: Bool {false}
  @objc func changed() {setValue?(doubleValue)}
  override func mouseDown(with event: NSEvent) {
    if event.clickCount >= 2 {reset?(); return}
    begin?(); super.mouseDown(with: event); end?()
  }
}
struct SectionCaption: View {
  @ObservedObject private var localization = LocalizationState.shared
  var title: String
  var body: some View {
    Text(L(title)).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).frame(
      maxWidth: .infinity, alignment: .leading)
  }
}
struct ColorWell: View {
  @ObservedObject private var localization = LocalizationState.shared
  @ObservedObject var store: EditorStore
  var layer = false
  @State private var showing = false
  var value: RGBA { layer ? store.selected?.color ?? store.foreground : store.foreground }
  var body: some View {
    Button { showing.toggle() } label: {
      RoundedRectangle(cornerRadius: 8).fill(value.color).frame(width: 28, height: 28)
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.16)))
    }.buttonStyle(.plain).help(L("颜色")).accessibilityLabel(L("颜色"))
      .popover(isPresented: $showing) {
        ModernColorPalette(color: Binding(get: { value }, set: { rgba in
          if layer { store.updateSelected("调整颜色") { $0.color = rgba } }
          else { store.foreground = rgba }
        }),editingChanged:{active in
          if layer { if active { store.beginTransaction("调整颜色") } else { store.endTransaction() } }
        }).padding(20).frame(width: 300)
      }
  }
}

enum ParameterDefaults {
  static func value(_ title: String, range: ClosedRange<Double>) -> Double {
    let defaults: [String: Double] = ["大小":48, "硬度":0.8, "不透明度":1, "流量":1,
      "对比度":1, "饱和度":1, "线宽":4, "圆角":24, "半径":10, "强度":0.5,
      "行距":1.2, "圆度":1, "间距":0.15, "边数":6, "密度":1]
    let v = defaults[title] ?? (range.contains(0) ? 0 : range.lowerBound)
    return min(range.upperBound, max(range.lowerBound, v))
  }
}
