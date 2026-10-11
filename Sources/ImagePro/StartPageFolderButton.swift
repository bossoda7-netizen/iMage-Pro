import SwiftUI

struct StartPageFolderButton: View {
  @ObservedObject private var localization = LocalizationState.shared
  let name: String
  let count: Int
  var selected = false
  var targeted = false
  let action: () -> Void
  @State private var hover = false

  var body: some View {
    Button(action:action) {
      VStack(spacing:6) {
        ProjectFolderArtwork()
          .frame(width:76,height:76)
          .padding(.horizontal,10).padding(.vertical,2)
          .background(Color.primary.opacity(targeted ? 0.13 : selected ? 0.09 : hover ? 0.045 : 0),
            in:RoundedRectangle(cornerRadius:10))
          .overlay {
            if targeted {
              RoundedRectangle(cornerRadius:10).strokeBorder(.primary.opacity(0.65),lineWidth:1.5)
                .allowsHitTesting(false)
            }
          }
        Text(name).font(.system(size:13,weight:selected ? .semibold : .regular))
          .foregroundStyle(.primary).lineLimit(2).multilineTextAlignment(.center)
          .padding(.horizontal,6).padding(.vertical,2)
          .background(Color.primary.opacity(selected || targeted ? 0.12 : 0),in:RoundedRectangle(cornerRadius:4))
        Text(L("{0} 项", count)).font(.system(size:11)).foregroundStyle(.secondary)
      }.padding(8).frame(maxWidth:.infinity,minHeight:140,alignment:.top)
        .contentShape(Rectangle())
    }.buttonStyle(.plain).onHover {hover = $0}
      .help(L("打开文件夹：{0}", name))
      .accessibilityLabel(L("打开文件夹：{0}", name))
      .accessibilityValue(L("{0} 项", count))
      .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

/// A quiet blue-gray project folder, distinct from Finder's saturated system icon.
private struct ProjectFolderArtwork: View {
  @ObservedObject private var localization = LocalizationState.shared
  @Environment(\.colorScheme) private var scheme
  var body: some View {
    Canvas {context,size in
      let sx = size.width/76,sy = size.height/76
      context.scaleBy(x:sx,y:sy)
      var back = Path()
      back.move(to:CGPoint(x:8,y:25))
      back.addLine(to:CGPoint(x:8,y:19))
      back.addQuadCurve(to:CGPoint(x:13,y:14),control:CGPoint(x:8,y:14))
      back.addLine(to:CGPoint(x:29,y:14))
      back.addQuadCurve(to:CGPoint(x:33,y:16),control:CGPoint(x:31,y:14))
      back.addLine(to:CGPoint(x:38,y:21))
      back.addLine(to:CGPoint(x:63,y:21))
      back.addQuadCurve(to:CGPoint(x:68,y:26),control:CGPoint(x:68,y:21))
      back.addLine(to:CGPoint(x:68,y:58))
      back.addQuadCurve(to:CGPoint(x:62,y:64),control:CGPoint(x:68,y:64))
      back.addLine(to:CGPoint(x:14,y:64))
      back.addQuadCurve(to:CGPoint(x:8,y:58),control:CGPoint(x:8,y:64))
      back.closeSubpath()
      let dark = scheme == .dark
      context.fill(back,with:.color(Color(red:dark ? 0.32 : 0.39,green:dark ? 0.42 : 0.50,blue:dark ? 0.48 : 0.57)))
      let sheet = Path(roundedRect:CGRect(x:15,y:25,width:45,height:30),cornerRadius:3)
      context.fill(sheet,with:.color(Color(red:0.80,green:0.85,blue:0.86)))
      let front = Path(roundedRect:CGRect(x:7,y:31,width:62,height:35),cornerRadius:6)
      context.fill(front,with:.linearGradient(Gradient(colors:[
        Color(red:dark ? 0.60 : 0.65,green:dark ? 0.72 : 0.76,blue:dark ? 0.76 : 0.80),
        Color(red:dark ? 0.40 : 0.46,green:dark ? 0.54 : 0.60,blue:dark ? 0.60 : 0.66)
      ]),startPoint:CGPoint(x:38,y:31),endPoint:CGPoint(x:38,y:66)))
      context.stroke(front,with:.color(.white.opacity(0.24)),lineWidth:0.7)
      // The stacked project mark relates the folder to the editor's layer language.
      let rearMark = Path(roundedRect:CGRect(x:32,y:40,width:17,height:13),cornerRadius:2)
      let frontMark = Path(roundedRect:CGRect(x:27,y:45,width:17,height:13),cornerRadius:2)
      context.stroke(rearMark,with:.color(.white.opacity(0.7)),lineWidth:1.2)
      context.fill(frontMark,with:.color(Color(red:0.40,green:0.54,blue:0.60)))
      context.stroke(frontMark,with:.color(.white.opacity(0.9)),lineWidth:1.2)
    }.accessibilityHidden(true)
  }
}
