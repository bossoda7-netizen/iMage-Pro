import SwiftUI
import AppKit

/// Separate glass controls keep the compact rail open to the canvas between items.
struct InspectorSwitcherButton: View {
  @ObservedObject private var localization = LocalizationState.shared
  let title: String
  let symbol: String
  var selected = false
  var dim = false
  let action: () -> Void

  var body: some View {
    Button(action:action) {
      VStack(spacing:5) {
        Image(systemName:symbol)
          .font(.system(size:17,weight:selected ? .semibold : .medium))
          .foregroundStyle(.primary)
          .frame(width:39,height:39)
          .modifier(InspectorSwitcherSurface(shape:Circle(),selected:selected,selectionRing:true))
        Text(L(title))
          .font(.system(size:11,weight:selected ? .semibold : .medium))
          .lineLimit(2).multilineTextAlignment(.center).foregroundStyle(.primary)
          .padding(.horizontal,6).padding(.vertical,4)
          .modifier(InspectorSwitcherSurface(shape:RoundedRectangle(cornerRadius:5),selected:selected))
          .overlay(alignment:.bottom) {
            // A clear monochrome mark identifies selection without relying on tint.
            Capsule().fill(.primary).frame(width:22,height:3)
              .offset(y:4).opacity(selected ? 1 : 0).allowsHitTesting(false)
          }
      }.frame(maxWidth:.infinity).opacity(dim && !selected ? 0.55 : 1)
    }
    .buttonStyle(InspectorSwitcherPressStyle())
    .help(L(title)).accessibilityLabel(L(title))
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

private struct InspectorSwitcherSurface<S: InsettableShape>: ViewModifier {
  let shape: S
  let selected: Bool
  var selectionRing = false
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.colorSchemeContrast) private var contrast

  func body(content:Content) -> some View {
    Group {
      if reduceTransparency {
        content.background(Color(nsColor:.windowBackgroundColor),in:shape)
          .overlay(shape.fill(Color.primary.opacity(selected ? 0.18 : 0)).allowsHitTesting(false))
      } else if #available(macOS 26.0, *) {
        // Use the same regular system glass as the inspector, without an opaque backing.
        content.glassEffect(selected ? .regular.tint(Color.primary.opacity(0.22)).interactive() : .regular.interactive(),in:shape)
      } else {
        content.background(.regularMaterial,in:shape)
          .overlay(shape.fill(Color.primary.opacity(selected ? 0.18 : 0)).allowsHitTesting(false))
      }
    }.overlay {
      if selected && selectionRing {
        shape.strokeBorder(Color.primary.opacity(contrast == .increased ? 1 : 0.8),lineWidth:1.5)
          .padding(2).allowsHitTesting(false)
      } else if contrast == .increased {
        shape.strokeBorder(Color.primary.opacity(selected ? 0.75 : 0.45),lineWidth:selected ? 1.5 : 1)
          .allowsHitTesting(false)
      }
    }
  }
}

private struct InspectorSwitcherPressStyle: ButtonStyle {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  func makeBody(configuration:Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.96 : 1)
      .animation(reduceMotion ? nil : .easeOut(duration:0.12),value:configuration.isPressed)
  }
}
