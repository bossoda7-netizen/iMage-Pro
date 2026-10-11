import AppKit

/// AppKit's standard menu headings do not follow SwiftUI's locale environment.
/// Translate their titles without replacing their actions or enabled states.
@MainActor
final class NativeMenuLocalization {
  static let shared = NativeMenuLocalization()
  private var observers: [NSObjectProtocol] = []
  private var refreshing = false
  private var scheduled = false
  private let headingKeys = ["menu.file", "menu.edit", "menu.view", "menu.window", "menu.help", "menu.services"]
  private let actionKeys: [String: String] = [
    "hide:": "menu.hide", "hideOtherApplications:": "menu.hideOthers",
    "unhideAllApplications:": "menu.showAll", "terminate:": "menu.quit",
    "performClose:": "menu.close", "performMiniaturize:": "menu.minimize",
    "performZoom:": "menu.zoom", "arrangeInFront:": "menu.front",
    "orderFrontCharacterPalette:": "menu.emoji"
  ]
  func install() {
    guard observers.isEmpty else { refresh(); return }
    for notification in [NSMenu.didBeginTrackingNotification, NSMenu.didChangeItemNotification, NSMenu.didAddItemNotification] {
      observers.append(NotificationCenter.default.addObserver(forName: notification, object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { Self.shared.scheduleRefresh() }
      })
    }
    scheduleRefresh()
  }
  private func scheduleRefresh() {
    guard !refreshing, !scheduled else { return }
    scheduled = true
    DispatchQueue.main.async { self.scheduled = false; self.refresh() }
  }
  func refresh() {
    guard let app = NSApp, let menu = app.mainMenu else { return }
    localize(menu)
  }
  func localize(_ menu: NSMenu) {
    guard !refreshing else { return }
    refreshing = true
    defer { refreshing = false }
    func setTitle(_ item: NSMenuItem, _ title: String) {
      if item.title != title { item.title = title }
      if let attributedTitle = item.attributedTitle, !attributedTitle.string.isEmpty { item.attributedTitle = nil }
    }
    func visit(_ menu: NSMenu, level: Int) {
      for item in menu.items {
        if let action = item.action, let key = actionKeys[NSStringFromSelector(action)] {
          setTitle(item, L(key))
        } else {
          let keys = level == 0 ? headingKeys : ["menu.services", "menu.fullscreen", "menu.exitFullscreen", "menu.toolbar", "menu.hideToolbar", "menu.customizeToolbar", "menu.showSidebar", "menu.hideSidebar", "menu.tabBar", "menu.hideTabBar", "menu.allTabs"]
          if let key = keys.first(where: { key in
            AppLanguage.allCases.contains { [item.title, item.attributedTitle?.string ?? "", item.submenu?.title ?? ""].contains(AppLocalization.tables[$0]?[key] ?? "<missing>") }
          }) {
            setTitle(item, L(key))
          }
        }
        if let submenu = item.submenu {
          submenu.title = item.title
          visit(submenu, level: level + 1)
        }
      }
    }
    visit(menu, level: 0)
  }
}
