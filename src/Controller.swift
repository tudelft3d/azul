// azul
// Copyright © 2016-2026 Ken Arroyo Ohori
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

import Cocoa
import Metal
import MetalKit
import ObjectiveC

struct ViewParameters: Codable {
  var eye: [Float]
  var centre: [Float]
  var fieldOfView: Float
  var modelTranslationToCentreOfRotationMatrix: [Float]
  var modelRotationMatrix: [Float]
  var modelShiftBackMatrix: [Float]
  var modelMatrix: [Float]
  var viewMatrix: [Float]
  var projectionMatrix: [Float]
  var viewEdges: Bool
  var viewBoundingBox: Bool
  var showAppearances: Bool?
  var appearanceTheme: String?
}

class SearchFieldDelegate: NSObject, NSSearchFieldDelegate {
  var controller: Controller?
  func controlTextDidChange(_ obj: Notification) {
    let searchField = obj.object as! NSSearchField
    searchField.stringValue.withCString { pointer in
      controller!.dataManager.setSearchString(pointer)
    }
    controller!.objectsSourceList!.reloadData()
  }
}

class OutlineView: NSOutlineView {
  var controller: Controller?
  
  override func keyDown(with event: NSEvent) {
    switch event.charactersIgnoringModifiers![(event.charactersIgnoringModifiers?.startIndex)!] {
    case " ":
      controller?.dataManager.toggleVisibility(forSelection: controller?.objectsSourceList)
    default:
      super.keyDown(with: event)
    }
  }
  
  @IBAction func copy(_ sender: Any) {
    controller?.copySelectedObjectIds()
  }
}

extension NSToolbarItem.Identifier {
  static let lodSelector = NSToolbarItem.Identifier("azul.lodSelector")
  static let search = NSToolbarItem.Identifier("azul.search")
  static let toggleEdges = NSToolbarItem.Identifier("azul.toggleEdges")
  static let appearanceThemeSelector = NSToolbarItem.Identifier("azul.appearanceThemeSelector")
}

@main
@objc class Controller: NSObject, NSApplicationDelegate, NSToolbarDelegate, NSMenuItemValidation {

  @IBOutlet weak var window: NSWindow!
  var splitView: NSSplitView?
  var leftSplitView: NSSplitView?
  @objc var searchField: NSSearchField?
  @objc var lodSegmentedControl: NSSegmentedControl?
  @objc var lodToolbarItem: NSToolbarItem?
  @objc var toggleEdgesToolbarItem: NSToolbarItem?
  @objc var appearanceThemePopUpButton: NSPopUpButton?
  @objc var appearanceThemeToolbarItem: NSToolbarItem?
  var objectsScrollView: NSScrollView?
  var objectsClipView: NSClipView?
  @objc var objectsSourceList: OutlineView?
  var objectsSourceListColumn: NSTableColumn?
  var attributesScrollView: NSScrollView?
  var attributesClipView: NSClipView?
  @objc var attributesTableView: NSTableView?
  var attributeNamesColumn: NSTableColumn?
  var attributeValuesColumn: NSTableColumn?
  var totalProgress: Double = 0.0
  var statusBarView: NSVisualEffectView?
  var progressIndicator: NSProgressIndicator?
  var statusTextField: NSTextField?
  
  @objc var metalView: MetalView?
  var openFiles = Set<URL>()
  var retainedSecurityScopedURLs = [String: URL]()
  var openRecentMenuItem: NSMenuItem?
  
  @IBOutlet weak var toggleViewEdgesMenuItem: NSMenuItem!
  @IBOutlet weak var toggleViewBoundingBoxMenuItem: NSMenuItem!
  @IBOutlet weak var goHomeMenuItem: NSMenuItem!
  @IBOutlet weak var toggleSideBarMenuItem: NSMenuItem!
  @IBOutlet weak var openFileMenuItem: NSMenuItem!
  @IBOutlet weak var newFileMenuItem: NSMenuItem!
  @IBOutlet weak var copyObjectIdMenuItem: NSMenuItem!
  @IBOutlet weak var findMenuItem: NSMenuItem!
  @IBOutlet weak var loadViewParametersMenuItem: NSMenuItem!
  @IBOutlet weak var saveViewParametersMenuItem: NSMenuItem!
  @IBOutlet weak var toggleFullScreenMenuItem: NSMenuItem!
  var lodMenuItem: NSMenuItem?
  var currentLodFilter: String = "__highest__"
  var currentAppearanceTheme: String = ""
  
  let dataManager = DataManagerWrapperWrapper()!
  let performanceHelper = PerformanceHelperWrapperWrapper()!
  let mainSplitViewController = NSSplitViewController()
  var emptyStateView: NSView?
  let searchFieldDelegate = SearchFieldDelegate()
  var pendingURLs = [URL]()
  var isLoading = false {
    didSet {
      newFileMenuItem?.isEnabled = !isLoading
      openFileMenuItem?.isEnabled = !isLoading
    }
  }
  var preferencesWindow: NSWindow?
  var colourTypeWells: [NSColorWell] = []
  var colourTypeNames: [String] = []

  func applicationDidFinishLaunching(_ aNotification: Notification) {
    Swift.print("Controller.applicationDidFinishLaunching(Notification)")
    
    leftSplitView = NSSplitView(frame: NSRect(x: 0, y: 0, width: 200, height: 600))
    leftSplitView!.dividerStyle = .thin
    
    objectsScrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 474))
    objectsScrollView!.translatesAutoresizingMaskIntoConstraints = false
    objectsScrollView!.hasVerticalScroller = true
    objectsScrollView!.hasHorizontalScroller = false
    objectsScrollView!.horizontalScrollElasticity = .none
    objectsScrollView!.wantsLayer = true
    objectsScrollView!.identifier = NSUserInterfaceItemIdentifier.init(rawValue: "ObjectsScrollView")
    leftSplitView!.addSubview(objectsScrollView!)
    
    objectsClipView = NSClipView(frame: .zero)
    objectsScrollView!.contentView = objectsClipView!
    
    objectsSourceList = OutlineView(frame: objectsScrollView!.bounds)
    objectsSourceList!.controller = self
    objectsSourceList!.style = .sourceList
    objectsSourceList!.floatsGroupRows = false
    objectsSourceList!.indentationPerLevel = 16
    objectsSourceList!.indentationMarkerFollowsCell = false
    objectsSourceList!.wantsLayer = true
    objectsSourceList!.headerView = nil
    objectsSourceList!.allowsMultipleSelection = true
    objectsSourceList!.autoresizingMask = .width
    objectsSourceList!.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
    objectsClipView!.documentView = objectsSourceList!
    
    objectsSourceListColumn = NSTableColumn(identifier: .init("Objects"))
    objectsSourceListColumn!.isEditable = false
    objectsSourceListColumn!.headerCell.stringValue = "Object"
    objectsSourceListColumn!.resizingMask = .autoresizingMask
    objectsSourceList!.addTableColumn(objectsSourceListColumn!)
    objectsSourceList!.outlineTableColumn = objectsSourceListColumn
    
    attributesScrollView = NSScrollView(frame: NSRect(x: 0, y: 0, width: 200, height: 126))
    attributesScrollView!.translatesAutoresizingMaskIntoConstraints = false
    attributesScrollView!.hasVerticalScroller = true
    attributesScrollView!.hasHorizontalScroller = false
    attributesScrollView!.horizontalScrollElasticity = .none
    attributesScrollView!.wantsLayer = true
    attributesScrollView!.identifier = NSUserInterfaceItemIdentifier.init(rawValue: "AttributesScrollView")
    leftSplitView!.addSubview(attributesScrollView!)
    
    attributesClipView = NSClipView(frame: .zero)
    attributesScrollView!.contentView = attributesClipView!
    
    attributesTableView = NSTableView(frame: attributesScrollView!.bounds)
    attributesTableView!.usesAlternatingRowBackgroundColors = true
    attributesTableView!.autoresizingMask = .width
    attributesTableView!.columnAutoresizingStyle = .sequentialColumnAutoresizingStyle
    attributesClipView!.documentView = attributesTableView!
    
    attributeNamesColumn = NSTableColumn(identifier: .init("A"))
    attributeNamesColumn!.title = "Attribute"
    attributeNamesColumn!.resizingMask = .autoresizingMask
    attributeValuesColumn = NSTableColumn(identifier: .init("V"))
    attributeValuesColumn!.title = "Value"
    attributeValuesColumn!.resizingMask = .autoresizingMask
    attributesTableView!.addTableColumn(attributeNamesColumn!)
    attributesTableView!.addTableColumn(attributeValuesColumn!)
    
    // Only constrain the unmanaged axis (horizontal). NSSplitView handles vertical internally.
    NSLayoutConstraint.activate([
      objectsScrollView!.leadingAnchor.constraint(equalTo: leftSplitView!.leadingAnchor),
      objectsScrollView!.trailingAnchor.constraint(equalTo: leftSplitView!.trailingAnchor),
      
      attributesScrollView!.leadingAnchor.constraint(equalTo: leftSplitView!.leadingAnchor),
      attributesScrollView!.trailingAnchor.constraint(equalTo: leftSplitView!.trailingAnchor),
    ])
    
    DispatchQueue.main.async {
      self.leftSplitView?.setPosition(474, ofDividerAt: 0)
    }
    
    let defaultDevice = MTLCreateSystemDefaultDevice()
    metalView = MetalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), device: defaultDevice)
    metalView!.controller = self
    metalView!.dataManager = dataManager
    
    let statusBar = NSVisualEffectView()
    statusBar.material = .hudWindow
    statusBar.blendingMode = .withinWindow
    statusBar.state = .followsWindowActiveState
    statusBar.wantsLayer = true
    statusBar.layer?.cornerRadius = 8
    statusBar.layer?.masksToBounds = true
    statusBar.translatesAutoresizingMaskIntoConstraints = false
    statusBar.isHidden = true
    metalView!.addSubview(statusBar)
    statusBarView = statusBar
    
    NSLayoutConstraint.activate([
      statusBar.leadingAnchor.constraint(equalTo: metalView!.leadingAnchor, constant: 8),
      statusBar.trailingAnchor.constraint(equalTo: metalView!.trailingAnchor, constant: -8),
      statusBar.bottomAnchor.constraint(equalTo: metalView!.bottomAnchor, constant: -8),
      statusBar.heightAnchor.constraint(equalToConstant: 36),
    ])
    
    progressIndicator = NSProgressIndicator()
    progressIndicator!.isIndeterminate = false
    progressIndicator!.translatesAutoresizingMaskIntoConstraints = false
    statusBar.addSubview(progressIndicator!)
    
    statusTextField = NSTextField()
    statusTextField!.stringValue = "Ready"
    statusTextField!.isBordered = false
    statusTextField!.isEditable = false
    statusTextField!.drawsBackground = false
    statusTextField!.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    statusTextField!.textColor = .secondaryLabelColor
    statusTextField!.translatesAutoresizingMaskIntoConstraints = false
    statusBar.addSubview(statusTextField!)
    
    NSLayoutConstraint.activate([
      progressIndicator!.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 8),
      progressIndicator!.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
      progressIndicator!.heightAnchor.constraint(equalToConstant: 12),
      
      statusTextField!.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -8),
      statusTextField!.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
      statusTextField!.widthAnchor.constraint(equalToConstant: 180),
      statusTextField!.heightAnchor.constraint(equalToConstant: 14),
      
      progressIndicator!.trailingAnchor.constraint(equalTo: statusTextField!.leadingAnchor, constant: -8),
    ])
    
    setupEmptyStateView()
    
    dataManager.controller = self
    
    // NSSplitViewController for the main horizontal split
    let sidebarVC = NSViewController()
    let sidebarEffectView = NSVisualEffectView()
    sidebarEffectView.material = .sidebar
    sidebarEffectView.blendingMode = .behindWindow
    sidebarEffectView.state = .followsWindowActiveState
    sidebarEffectView.addSubview(leftSplitView!)
    leftSplitView!.frame = sidebarEffectView.bounds
    leftSplitView!.autoresizingMask = [.width, .height]
    sidebarVC.view = sidebarEffectView
    
    let contentVC = NSViewController()
    contentVC.view = metalView!
    
    let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarVC)
    sidebarItem.minimumThickness = 200
    mainSplitViewController.addSplitViewItem(sidebarItem)
    mainSplitViewController.addSplitViewItem(NSSplitViewItem(viewController: contentVC))
    
    splitView = mainSplitViewController.splitView
    splitView!.autoresizingMask = [.width, .height]
    
    window.contentView!.addSubview(mainSplitViewController.view)
    mainSplitViewController.view.frame = window.contentView!.bounds
    mainSplitViewController.view.autoresizingMask = [.width, .height]
    window.makeFirstResponder(metalView)
    toggleViewEdgesMenuItem.state = .on
    window.minSize = NSSize(width: 400, height: 300)
    
    // Unified toolbar with integrated title
    window.styleMask.insert(.unifiedTitleAndToolbar)
    window.toolbarStyle = .unified
    
    let toolbar = NSToolbar(identifier: "azul.toolbar")
    toolbar.delegate = self
    toolbar.allowsUserCustomization = true
    toolbar.displayMode = .iconOnly
    toolbar.autosavesConfiguration = false
    window.toolbar = toolbar
    
    objectsSourceList!.dataSource = dataManager
    objectsSourceList!.delegate = dataManager
    objectsSourceList!.doubleAction = #selector(sourceListDoubleClick)
    attributesTableView!.dataSource = dataManager
    attributesTableView!.delegate = dataManager
    
    loadPreferences()
    if !pendingURLs.isEmpty {
      let urls = pendingURLs
      pendingURLs.removeAll()
      loadData(from: urls)
    }
    setupViewMenu()
    setupFileMenu()
  }
  
  func setupFileMenu() {
    let fileMenu = NSApp.mainMenu!.item(withTitle: "File")!.submenu!
    var fileItems = fileMenu.items
    // Persistent "Open Recent", backed by security-scoped bookmarks (the
    // standard system menu is cleared at launch and loses sandbox access
    // across launches).
    let recentMenuItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
    recentMenuItem.submenu = NSMenu(title: "Open Recent")
    if let index = fileItems.firstIndex(where: { $0.title == "Open Recent" }) {
      fileItems[index] = recentMenuItem
    } else {
      fileItems.insert(recentMenuItem, at: fileItems.firstIndex(where: { $0.keyEquivalent == "w" })!)
    }
    self.openRecentMenuItem = recentMenuItem
    let exportItem = NSMenuItem(title: "Export Image…", action: #selector(exportImage(_:)), keyEquivalent: "e")
    exportItem.target = self
    fileItems.append(NSMenuItem.separator())
    fileItems.append(exportItem)
    fileMenu.items = fileItems
    reloadRecentFilesMenu()
  }

  // MARK: Recent files

  private func recentFiles() -> [(path: String, bookmark: Data?)] {
    guard let array = UserDefaults.standard.array(forKey: "azulRecentFiles") as? [[String: Any]] else { return [] }
    return array.compactMap { dict in
      guard let path = dict["path"] as? String else { return nil }
      return (path, dict["bookmark"] as? Data)
    }
  }

  private func saveRecentFiles(_ files: [(path: String, bookmark: Data?)]) {
    let array: [[String: Any]] = files.map { entry in
      var dict: [String: Any] = ["path": entry.path]
      if let bookmark = entry.bookmark { dict["bookmark"] = bookmark }
      return dict
    }
    UserDefaults.standard.set(array, forKey: "azulRecentFiles")
  }

  // The number of recent documents a user wants: the "Recent documents,
  // applications, and servers" setting is not exposed to apps, so honour the
  // legacy global-domain limit when present, and Apple's historical default
  // (10) otherwise.
  private var recentFilesLimit: Int {
    if let value = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["NSRecentDocumentsLimit"] as? Int {
      return max(0, value)
    }
    return 10
  }

  func addRecentFile(_ url: URL) {
    var files = recentFiles()
    files.removeAll { $0.path == url.path }
    let bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    files.insert((url.path, bookmark), at: 0)
    if files.count > recentFilesLimit { files = Array(files.prefix(recentFilesLimit)) }
    saveRecentFiles(files)
    DispatchQueue.main.async { self.reloadRecentFilesMenu() }
  }

  private func resolvedRecentFileURL(for entry: (path: String, bookmark: Data?)) -> URL? {
    if let bookmark = entry.bookmark {
      var stale = false
      if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) {
        // Sandboxed apps cannot even check file existence without an active scope.
        let accesses = url.startAccessingSecurityScopedResource()
        let exists = FileManager.default.fileExists(atPath: url.path)
        if accesses { url.stopAccessingSecurityScopedResource() }
        if exists {
          if stale { refreshRecentFileBookmark(for: url) }
          return url
        }
      }
    }
    let url = URL(fileURLWithPath: entry.path)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  private func refreshRecentFileBookmark(for url: URL) {
    var files = recentFiles()
    guard let index = files.firstIndex(where: { $0.path == url.path }) else { return }
    files[index].bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    saveRecentFiles(files)
  }

  func reloadRecentFilesMenu() {
    guard let submenu = openRecentMenuItem?.submenu else { return }
    submenu.removeAllItems()
    var files = recentFiles()
    if files.count > recentFilesLimit {
      files = Array(files.prefix(recentFilesLimit))
      saveRecentFiles(files)
    }
    for entry in files {
      guard let url = resolvedRecentFileURL(for: entry) else { continue }
      let item = NSMenuItem(title: url.lastPathComponent, action: #selector(openRecentDocument(_:)), keyEquivalent: "")
      item.target = self
      item.representedObject = url
      item.image = NSWorkspace.shared.icon(forFile: url.path)
      submenu.addItem(item)
    }
    if submenu.items.isEmpty {
      let placeholder = NSMenuItem(title: "No Recent Files", action: nil, keyEquivalent: "")
      placeholder.isEnabled = false
      submenu.addItem(placeholder)
      return
    }
    submenu.addItem(NSMenuItem.separator())
    let clearItem = NSMenuItem(title: "Clear Menu", action: #selector(clearRecentFiles(_:)), keyEquivalent: "")
    clearItem.target = self
    submenu.addItem(clearItem)
  }

  @objc func openRecentDocument(_ sender: NSMenuItem) {
    guard !isLoading, let url = sender.representedObject as? URL else { return }
    loadData(from: [url])
  }

  @objc func clearRecentFiles(_ sender: NSMenuItem) {
    UserDefaults.standard.removeObject(forKey: "azulRecentFiles")
    reloadRecentFilesMenu()
  }

  func setupEmptyStateView() {
    let emptyView = NSView()
    emptyView.translatesAutoresizingMaskIntoConstraints = false
    emptyView.wantsLayer = true
    metalView!.addSubview(emptyView)
    emptyView.topAnchor.constraint(equalTo: metalView!.topAnchor).isActive = true
    emptyView.leadingAnchor.constraint(equalTo: metalView!.leadingAnchor).isActive = true
    emptyView.trailingAnchor.constraint(equalTo: metalView!.trailingAnchor).isActive = true
    emptyView.bottomAnchor.constraint(equalTo: metalView!.bottomAnchor).isActive = true

    let icon = NSImageView()
    icon.translatesAutoresizingMaskIntoConstraints = false
    icon.image = NSImage(named: "AzulIcon")
    icon.contentTintColor = .tertiaryLabelColor
    emptyView.addSubview(icon)

    let titleLabel = NSTextField(labelWithString: "Azul")
    titleLabel.translatesAutoresizingMaskIntoConstraints = false
    titleLabel.font = NSFont.systemFont(ofSize: 34, weight: .bold)
    titleLabel.textColor = .labelColor
    titleLabel.alignment = .center
    emptyView.addSubview(titleLabel)

    let subtitleLabel = NSTextField(labelWithString: "3D City Viewer")
    subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
    subtitleLabel.font = NSFont.systemFont(ofSize: 17)
    subtitleLabel.textColor = .secondaryLabelColor
    subtitleLabel.alignment = .center
    emptyView.addSubview(subtitleLabel)

    let descriptionLabel = NSTextField(wrappingLabelWithString: "Open a CityJSON, CityGML, OBJ, OFF or POLY file to view your model.")
    descriptionLabel.translatesAutoresizingMaskIntoConstraints = false
    descriptionLabel.font = NSFont.systemFont(ofSize: 15)
    descriptionLabel.textColor = .secondaryLabelColor
    descriptionLabel.alignment = .center
    emptyView.addSubview(descriptionLabel)

    let openButton = NSButton(title: "  Open File", image: NSImage(systemSymbolName: "doc", accessibilityDescription: nil)!, target: self, action: #selector(openFile(_:)))
    openButton.translatesAutoresizingMaskIntoConstraints = false
    openButton.bezelStyle = .rounded
    openButton.controlSize = .large
    openButton.hasDestructiveAction = false
    emptyView.addSubview(openButton)

    let hintLabel = NSTextField(labelWithString: "— or use File → Open or ⌘O —")
    hintLabel.translatesAutoresizingMaskIntoConstraints = false
    hintLabel.font = NSFont.systemFont(ofSize: 13)
    hintLabel.textColor = .tertiaryLabelColor
    hintLabel.alignment = .center
    emptyView.addSubview(hintLabel)

    let stack = NSStackView(views: [icon, titleLabel, subtitleLabel, descriptionLabel, openButton, hintLabel])
    stack.translatesAutoresizingMaskIntoConstraints = false
    stack.orientation = .vertical
    stack.alignment = .centerX
    stack.spacing = 12
    emptyView.addSubview(stack)

    NSLayoutConstraint.activate([
      icon.widthAnchor.constraint(equalToConstant: 86),
      icon.heightAnchor.constraint(equalToConstant: 86),
      stack.centerXAnchor.constraint(equalTo: emptyView.centerXAnchor),
      stack.centerYAnchor.constraint(equalTo: emptyView.centerYAnchor, constant: -30),
      stack.leadingAnchor.constraint(greaterThanOrEqualTo: emptyView.leadingAnchor, constant: 40),
      stack.trailingAnchor.constraint(lessThanOrEqualTo: emptyView.trailingAnchor, constant: -40),
    ])
    emptyStateView = emptyView
  }

  func hideEmptyStateView() {
    guard let emptyView = emptyStateView, !emptyView.isHidden else { return }
    NSAnimationContext.runAnimationGroup { context in
      context.duration = 0.3
      emptyView.animator().alphaValue = 0
    } completionHandler: {
      emptyView.isHidden = true
    }
  }

  private var exportHandlerAssociationKey: UInt8 = 0

  private class ExportSizeHandler {
    let closure: (Int) -> Void
    init(_ closure: @escaping (Int) -> Void) { self.closure = closure }
    @objc func popupChanged(_ sender: NSPopUpButton) { closure(sender.indexOfSelectedItem) }
  }

  @IBAction func exportImage(_ sender: NSMenuItem) {
    let savePanel = NSSavePanel()
    savePanel.allowedContentTypes = [UTType.png]
    savePanel.canCreateDirectories = true

    let drawableSize = metalView!.drawableSize
    let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 64))

    let sizeLabel = NSTextField(labelWithString: "Resolution:")
    sizeLabel.frame = NSRect(x: 0, y: 38, width: 72, height: 20)
    accessoryView.addSubview(sizeLabel)

    let sizes: [(label: String, multiplier: Float)] = [
      ("1x", 1),
      ("2x", 2),
      ("4x", 4),
    ]
    let sizePopup = NSPopUpButton(frame: NSRect(x: 76, y: 34, width: 140, height: 24))
    for s in sizes { sizePopup.addItem(withTitle: s.label) }
    sizePopup.selectItem(at: 1)
    accessoryView.addSubview(sizePopup)

    let dimensionLabel = NSTextField(labelWithString: String(format: "Output: %d × %d", Int(drawableSize.width * 2), Int(drawableSize.height * 2)))
    dimensionLabel.frame = NSRect(x: 0, y: 14, width: 280, height: 18)
    dimensionLabel.font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize)
    dimensionLabel.textColor = .secondaryLabelColor
    accessoryView.addSubview(dimensionLabel)

    let transparentCheckbox = NSButton(checkboxWithTitle: "Transparent background", target: nil, action: nil)
    transparentCheckbox.frame = NSRect(x: 0, y: 0, width: 200, height: 20)
    accessoryView.addSubview(transparentCheckbox)

    savePanel.accessoryView = accessoryView

    let handler = ExportSizeHandler { [weak dimensionLabel] index in
      guard let label = dimensionLabel else { return }
      let mult = index < sizes.count ? sizes[index].multiplier : 1
      label.stringValue = String(format: "Output: %d × %d", Int(drawableSize.width * CGFloat(mult) + 0.5), Int(drawableSize.height * CGFloat(mult) + 0.5))
    }
    sizePopup.target = handler
    sizePopup.action = #selector(ExportSizeHandler.popupChanged(_:))
    objc_setAssociatedObject(sizePopup, &exportHandlerAssociationKey, handler, .OBJC_ASSOCIATION_RETAIN)

    savePanel.beginSheetModal(for: window) { [weak sizePopup, weak transparentCheckbox] result in
      guard result == .OK, let url = savePanel.url,
            let popup = sizePopup, let checkbox = transparentCheckbox else { return }
      let transparent = checkbox.state == .on
      let index = popup.indexOfSelectedItem
      let mult = CGFloat(index < sizes.count ? sizes[index].multiplier : 1)
      let w = Int(drawableSize.width * mult + 0.5)
      let h = Int(drawableSize.height * mult + 0.5)
      guard let image = self.metalView!.exportImage(width: w, height: h, transparentBackground: transparent),
            let data = image.tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: data),
            let pngData = bitmap.representation(using: .png, properties: [:]) else { return }
      try? pngData.write(to: url)
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }
  
  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    if menuItem.action == #selector(new(_:)) || menuItem.action == #selector(openFile(_:)) {
      return !isLoading
    }
    if menuItem.action == #selector(exportImage(_:)) {
      return !(metalView?.triangleBuffers.isEmpty ?? true)
    }
    if menuItem.action == #selector(openRecentDocument(_:)) {
      return !isLoading
    }
    return true
  }
  
  func setupViewMenu() {
    guard let mainMenu = NSApp.mainMenu else { return }
    for item in mainMenu.items {
      guard item.title == "View", let viewMenu = item.submenu else { continue }
      let lodMenuItem = NSMenuItem(title: "Level of Detail", action: nil, keyEquivalent: "")
      let lodSubmenu = NSMenu(title: "Level of Detail")
      let placeholder = NSMenuItem(title: "None", action: nil, keyEquivalent: "")
      placeholder.isEnabled = false
      lodSubmenu.addItem(placeholder)
      lodMenuItem.submenu = lodSubmenu
      viewMenu.insertItem(lodMenuItem, at: 2)
      self.lodMenuItem = lodMenuItem
      break
    }
  }

  func updateAppearanceThemeOptions() {
    guard let popUpButton = appearanceThemePopUpButton else { return }
    var themes = Set(dataManager.availableAppearanceThemes() ?? [])
    if themes.contains("Materials") && themes.contains("Textures") {
      themes.remove("visual")
    }
    let sortedThemes = themes.sorted()

    popUpButton.removeAllItems()
    popUpButton.addItem(withTitle: "By Type")
    popUpButton.lastItem?.image = NSImage(systemSymbolName: "paintpalette.fill", accessibilityDescription: "By Type")?.withSymbolConfiguration(NSImage.SymbolConfiguration.preferringMulticolor())
    for theme in sortedThemes {
      popUpButton.addItem(withTitle: theme)
      if theme == "Materials" {
        popUpButton.lastItem?.image = NSImage(systemSymbolName: "paintbrush.fill", accessibilityDescription: "Materials")
      } else if theme == "Textures" {
        popUpButton.lastItem?.image = NSImage(systemSymbolName: "photo.fill", accessibilityDescription: "Textures")
      } else {
        popUpButton.lastItem?.image = NSImage(systemSymbolName: "paintpalette", accessibilityDescription: theme)
      }
    }

    appearanceThemeToolbarItem?.isEnabled = true
    let appearancesOn = metalView?.showTextures ?? false
    if !appearancesOn || sortedThemes.isEmpty {
      if sortedThemes.isEmpty { metalView?.showTextures = false }
      popUpButton.selectItem(withTitle: "By Type")
    } else if let item = popUpButton.item(withTitle: currentAppearanceTheme) {
      popUpButton.select(item)
    } else {
      popUpButton.selectItem(at: 1)
    }
  }

  func refreshAppearanceRendering() {
    guard let metalView = metalView else { return }
    let appearancesEnabled = metalView.showTextures
    dataManager.setUseAppearances(appearancesEnabled)
    currentAppearanceTheme.withCString { pointer in
      dataManager.setAppearanceTheme(pointer)
    }
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16*1024*1024)
    reloadTriangleBuffers()
    updateVisibleStateBuffer()
    updateSelectionStateBuffer()
    if appearancesEnabled {
      metalView.clearFailedTexturePaths()
      metalView.primeTexturesForCurrentBuffers()
      let sourceURL = window.representedURL ?? openFiles.first
      if let sourceURL { requestTextureDirectoryAccessIfNeeded(for: sourceURL) }
    } else {
      metalView.clearFailedTexturePaths()
    }
    objectsSourceList?.reloadData()
    metalView.needsDisplay = true
  }
  
  // MARK: - NSToolbarDelegate
  
  func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    return [.toggleEdges, .appearanceThemeSelector, .lodSelector, .flexibleSpace, .search]
  }

  func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
    return [.toggleEdges, .appearanceThemeSelector, .lodSelector, .search]
  }
  
  func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
    switch itemIdentifier {
    case .toggleEdges:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      let edgesOn = metalView?.viewEdges ?? true
      item.image = NSImage(systemSymbolName: edgesOn ? "square.dashed" : "square", accessibilityDescription: "Toggle edges")
      item.label = "Edges"
      item.target = self
      item.action = #selector(toggleViewEdges(_:))
      item.isBordered = true
      toggleEdgesToolbarItem = item
      return item

    case .appearanceThemeSelector:
      let item = NSToolbarItem(itemIdentifier: itemIdentifier)
      let popUpButton = NSPopUpButton(frame: NSRect(x: 0, y: 0, width: 170, height: 28), pullsDown: false)
      popUpButton.target = self
      popUpButton.action = #selector(appearanceThemeChanged(_:))
      popUpButton.toolTip = "Type-based colours when \"By Type\" is selected; otherwise uses material/texture themes from the file"
      item.view = popUpButton
      item.label = "Colour Mode"
      appearanceThemePopUpButton = popUpButton
      appearanceThemeToolbarItem = item
      updateAppearanceThemeOptions()
      return item

    case .lodSelector:
      let lodItem = NSToolbarItem(itemIdentifier: itemIdentifier)
      let seg = NSSegmentedControl()
      seg.segmentCount = 1
      seg.setLabel("0", forSegment: 0)
      seg.selectedSegment = 0
      seg.target = self
      seg.action = #selector(lodSegmentChanged)
      lodItem.view = seg
      lodItem.label = "LoD"
      lodSegmentedControl = seg
      lodToolbarItem = lodItem
      return lodItem
      
    case .search:
      let searchItem = NSSearchToolbarItem(itemIdentifier: itemIdentifier)
      searchItem.searchField.delegate = searchFieldDelegate
      searchFieldDelegate.controller = self
      searchField = searchItem.searchField
      return searchItem
      
    default:
      return nil
    }
  }
  
  @IBAction func new(_ sender: NSMenuItem) {
    guard !isLoading else { return }
    Swift.print("Controller.new(NSMenuItem)")
    dataManager.clear()
    regenerateBoundingBoxBuffer()
    metalView!.clearTextureCaches()
    metalView!.new()
    objectsSourceList!.reloadData()
    attributesTableView!.reloadData()
    releaseAllRetainedSecurityScopes()
    openFiles = Set<URL>()
    self.window.representedURL = nil
    self.window.title = "azul"
    self.statusBarView?.isHidden = true
    currentAppearanceTheme = ""
    metalView?.showTextures = false
    dataManager.setUseAppearances(false)
    dataManager.setAppearanceTheme("")
    updateAppearanceThemeOptions()
    self.updateLodSegments()
  }
  
  @IBAction func openFile(_ sender: NSMenuItem) {
    Swift.print("Controller.openFile(NSMenuItem)")
    
    let allTypes = [
      UTType(filenameExtension: "gml"),
      UTType(filenameExtension: "xml"),
      UTType(filenameExtension: "json"),
      UTType(filenameExtension: "jsonl"),
      UTType(filenameExtension: "obj"),
      UTType(filenameExtension: "off"),
      UTType(filenameExtension: "poly"),
      UTType(filenameExtension: "fcb"),
      UTType(filenameExtension: "city.json"),
      UTType(filenameExtension: "cityjson")
    ].compactMap { $0 }
    let cityJSONOnly = [UTType(filenameExtension: "city.json"), UTType(filenameExtension: "cityjson")].compactMap { $0 }
    
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = true
    openPanel.canChooseDirectories = false
    openPanel.canChooseFiles = true
    openPanel.allowedContentTypes = allTypes
    
    let formatLabel = NSTextField(labelWithString: "Format:")
    let formatPopup = NSPopUpButton()
    formatPopup.addItems(withTitles: ["All Supported", "CityJSON Only"])
    formatPopup.target = self
    formatPopup.action = #selector(formatFilterChanged(_:))
    formatPopup.identifier = NSUserInterfaceItemIdentifier("openPanelFormatFilter")
    
    let accessoryView = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
    formatLabel.frame = NSRect(x: 0, y: 2, width: 50, height: 20)
    formatPopup.frame = NSRect(x: 54, y: 0, width: 186, height: 24)
    accessoryView.addSubview(formatLabel)
    accessoryView.addSubview(formatPopup)
    openPanel.accessoryView = accessoryView
    
    // Store which types to use per filter choice
    objc_setAssociatedObject(openPanel, &OpenPanelTypesKey.all, allTypes, .OBJC_ASSOCIATION_RETAIN)
    objc_setAssociatedObject(openPanel, &OpenPanelTypesKey.cityJSON, cityJSONOnly, .OBJC_ASSOCIATION_RETAIN)
    
    openPanel.beginSheetModal(for: window) { (result: NSApplication.ModalResponse) in
      if result == .OK {
        self.loadData(from: openPanel.urls)
      }
    }
  }
  
  @objc private func formatFilterChanged(_ sender: NSPopUpButton) {
    guard let openPanel = sender.window as? NSOpenPanel else { return }
    if sender.indexOfSelectedItem == 0 {
      if let types = objc_getAssociatedObject(openPanel, &OpenPanelTypesKey.all) as? [UTType] {
        openPanel.allowedContentTypes = types
      }
    } else {
      if let types = objc_getAssociatedObject(openPanel, &OpenPanelTypesKey.cityJSON) as? [UTType] {
        openPanel.allowedContentTypes = types
      }
    }
  }
  
  private struct OpenPanelTypesKey {
    static var all: UInt8 = 0
    static var cityJSON: UInt8 = 0
  }
  
  func application(_ sender: NSApplication, openFile filename: String) -> Bool {
    Swift.print("Controller.application(NSApplication, openFile: String)")
    Swift.print("Open \(filename)")
    let url = URL(fileURLWithPath: filename)
    loadData(from: [url])
    return true
  }
  
  func application(_ sender: NSApplication, openFiles filenames: [String]) {
    Swift.print("Controller.application(NSApplication, openFiles: String)")
    Swift.print("Open \(filenames)")
    var urls = [URL]()
    for filename in filenames {
      urls.append(URL(fileURLWithPath: filename))
    }
    loadData(from: urls)
  }
  
  @IBAction func toggleViewEdges(_ sender: Any) {
    metalView!.viewEdges.toggle()
    if let menuItem = sender as? NSMenuItem {
      menuItem.state = metalView!.viewEdges ? .on : .off
    }
    toggleEdgesToolbarItem?.image = NSImage(systemSymbolName: metalView!.viewEdges ? "square.dashed" : "square", accessibilityDescription: "Toggle edges")
    metalView!.needsDisplay = true
  }

  @objc func appearanceThemeChanged(_ sender: NSPopUpButton) {
    guard let selectedTheme = sender.selectedItem?.title else { return }

    if selectedTheme == "By Type" {
      metalView?.showTextures = false
      currentAppearanceTheme = ""
      dataManager.setUseAppearances(false)
      currentAppearanceTheme.withCString { pointer in
        dataManager.setAppearanceTheme(pointer)
      }
    } else {
      metalView?.showTextures = true
      currentAppearanceTheme = selectedTheme
      dataManager.setUseAppearances(true)
      currentAppearanceTheme.withCString { pointer in
        dataManager.setAppearanceTheme(pointer)
      }
    }
    refreshAppearanceRendering()
  }

  @IBAction func toggleViewBoundingBox(_ sender: Any) {
    metalView!.viewBoundingBox.toggle()
    if let menuItem = sender as? NSMenuItem {
      menuItem.state = metalView!.viewBoundingBox ? .on : .off
    }
    metalView!.needsDisplay = true
  }
  
  @IBAction func goHome(_ sender: NSMenuItem) {
    metalView!.goHome()
  }
  
  @IBAction func toggleSideBar(_ sender: NSMenuItem) {
    NSAnimationContext.runAnimationGroup { context in
      context.allowsImplicitAnimation = true
      mainSplitViewController.toggleSidebar(sender)
    } completionHandler: {
      sender.title = self.mainSplitViewController.splitViewItems[0].isCollapsed ? "Show Sidebar" : "Hide Sidebar"
    }
  }
  
  @IBAction func focusOnSearchBar(_ sender: NSMenuItem) {
    guard let searchField = searchField else { return }
    window.makeFirstResponder(searchField)
  }
  
  func loadData(from urls: [URL]) {
    guard metalView != nil else {
      pendingURLs.append(contentsOf: urls)
      Swift.print("Deferred loading until after setup: \(urls)")
      return
    }
    guard !isLoading else {
      Swift.print("Already loading, ignoring: \(urls)")
      return
    }
    let hasModelFiles = urls.contains { $0.pathExtension != "azulview" }
    if hasModelFiles {
      metalView?.showTextures = false
      currentAppearanceTheme = ""
      dataManager.setAppearanceTheme("")
      dataManager.setUseAppearances(false)
    }
    metalView?.clearTextureCaches()
    isLoading = true
    self.performanceHelper.startTimer()
    
    let progressPerFile = 100.0/Double(urls.count)
    totalProgress = 0.0
    progressIndicator?.doubleValue = totalProgress
    statusBarView?.alphaValue = 0
    statusBarView?.isHidden = false
    NSAnimationContext.runAnimationGroup { _ in
      statusBarView?.animator().alphaValue = 1
    }
    DispatchQueue.global().async(qos: .userInitiated) {
      for url in urls {
        
        if url.pathExtension == "azulview" {
          Swift.print("View url: \(url)")
          DispatchQueue.main.async {
            self.loadViewParameters(url: url)
            self.totalProgress += progressPerFile
            self.progressIndicator?.doubleValue = self.totalProgress
            if urls.last == url {
              self.statusBarView?.isHidden = true
            }
          }
          continue
        }
        
        if self.openFiles.contains(url) {
          Swift.print("\(url) already open")
          DispatchQueue.main.async {
            self.totalProgress += progressPerFile
            self.progressIndicator?.doubleValue = self.totalProgress
            if urls.last == url {
              self.statusBarView?.isHidden = true
            }
          }
          continue
        }

        self.retainSecurityScopes(for: url)
        
        Swift.print("Loading " + url.path + "...")
        DispatchQueue.main.async {
          self.statusBarView?.isHidden = false
          self.statusTextField?.stringValue = "Loading " + url.path + "..."
        }
        url.path.utf8CString.withUnsafeBufferPointer { pointer in
          self.dataManager.parse(pointer.baseAddress)
        }
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*20.071734/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusBarView?.isHidden = false
        }
        
        Swift.print("Clearing helpers...")
        self.dataManager.clearHelpers()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*0.51605/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusBarView?.isHidden = false
        }
        
        Swift.print("Transforming geographic CRS (if needed)...")
        self.dataManager.transformGeographicCoordinates()

        Swift.print("Updating bounds...")
        self.dataManager.updateBoundsWithLastFile()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*0.158675/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusBarView?.isHidden = false
        }
        
        Swift.print("Triangulating...")
        self.dataManager.triangulateLastFile()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*45.400172/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusBarView?.isHidden = false
        }
        
        Swift.print("Generating edges...")
        self.dataManager.generateEdgesForLastFile()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*1.150533/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusBarView?.isHidden = false
        }
        
        Swift.print("Clearing polygons...")
        self.dataManager.clearPolygonsOfLastFile()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*0.359982/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusBarView?.isHidden = false
        }
        
        Swift.print("Making triangle buffers...")
        self.dataManager.regenerateTriangleBuffers(withMaximumSize: 16*1024*1024)
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*3.535023/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusBarView?.isHidden = false
        }
        
        Swift.print("Making edge buffers...")
        self.dataManager.regenerateEdgeBuffers(withMaximumSize: 16*1024*1024)
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*2.085606/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusBarView?.isHidden = false
        }
        
        Swift.print("Loading triangle buffers...")
        self.reloadTriangleBuffers()
        if self.metalView?.showTextures == true {
          self.metalView?.primeTexturesForCurrentBuffers()
        }
        self.updateVisibleStateBuffer()
        self.updateSelectionStateBuffer()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*1.31523/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusBarView?.isHidden = false
        }
        
        Swift.print("Loading edge buffers...")
        self.reloadEdgeBuffers()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*0.572072/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusBarView?.isHidden = false
        }
        
        Swift.print("Regenerating bounding box buffer...")
        self.regenerateBoundingBoxBuffer()
        self.performanceHelper.printTimeSpent()
        self.performanceHelper.printMemoryUsage()
        DispatchQueue.main.async {
          self.totalProgress += progressPerFile*0.000162/75.165239
          self.progressIndicator?.doubleValue = self.totalProgress
          self.statusBarView?.isHidden = false
        }
        
        self.openFiles.insert(url)
        NSDocumentController.shared.noteNewRecentDocumentURL(url)
        self.addRecentFile(url)
        
        DispatchQueue.main.async {
          self.metalView!.needsDisplay = true
          self.objectsSourceList!.reloadData()
          for row in 0..<self.objectsSourceList!.numberOfRows {
            if let item = self.objectsSourceList!.item(atRow: row), self.objectsSourceList!.parent(forItem: item) == nil {
              self.objectsSourceList!.expandItem(item)
            }
          }
          switch self.openFiles.count {
          case 0:
            self.window.representedURL = nil
            self.window.title = "azul"
          case 1:
            self.window.representedURL = self.openFiles.first!
            self.window.title = self.openFiles.first!.lastPathComponent
          default:
            self.window.representedURL = nil
            self.window.title = "azul (\(self.openFiles.count) open files)"
          }
          if urls.last == url {
            Swift.print("status message: \(self.dataManager.statusMessage()!)")
            self.statusTextField?.stringValue = self.dataManager.statusMessage()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
              NSAnimationContext.runAnimationGroup { _ in
                self.statusBarView?.animator().alphaValue = 0
              } completionHandler: {
                self.statusBarView?.isHidden = true
                self.statusBarView?.alphaValue = 1
              }
            }
            self.updateLodSegments()
            self.updateAppearanceThemeOptions()
            self.hideEmptyStateView()
          }
        }
      }
      DispatchQueue.main.async {
        self.isLoading = false
      }
    }
  }
  
  func regenerateBoundingBoxBuffer() {
    
    // Get bounds
    let firstMinCoordinate = dataManager.minCoordinates()
    let minCoordinatesBuffer = UnsafeBufferPointer(start: firstMinCoordinate, count: 3)
    let minCoordinatesArray = ContiguousArray(minCoordinatesBuffer)
    let minCoordinates = [Double](minCoordinatesArray)
    let firstMidCoordinate = dataManager.midCoordinates()
    let midCoordinatesBuffer = UnsafeBufferPointer(start: firstMidCoordinate, count: 3)
    let midCoordinatesArray = ContiguousArray(midCoordinatesBuffer)
    let midCoordinates = [Double](midCoordinatesArray)
    let firstMaxCoordinate = dataManager.maxCoordinates()
    let maxCoordinatesBuffer = UnsafeBufferPointer(start: firstMaxCoordinate, count: 3)
    let maxCoordinatesArray = ContiguousArray(maxCoordinatesBuffer)
    let maxCoordinates = [Double](maxCoordinatesArray)
    let maxRange = dataManager.maxRange()
    let minCoords = minCoordinates.map(Float.init)
    let midCoords = midCoordinates.map(Float.init)
    let maxCoords = maxCoordinates.map(Float.init)
    let range = Float(maxRange)
    
    // Create bounding box vertices
    let boundingBoxVertices: [Vertex] = [Vertex(position: SIMD3<Float>((minCoords[0]-midCoords[0])/range,
                                                                        (minCoords[1]-midCoords[1])/range,
                                                                        (minCoords[2]-midCoords[2])/range)),  // 000 -> 001
                                         Vertex(position: SIMD3<Float>((minCoords[0]-midCoords[0])/range,
                                                                        (minCoords[1]-midCoords[1])/range,
                                                                        (maxCoords[2]-midCoords[2])/range)),
                                         Vertex(position: SIMD3<Float>((minCoords[0]-midCoords[0])/range,
                                                                        (minCoords[1]-midCoords[1])/range,
                                                                        (minCoords[2]-midCoords[2])/range)),  // 000 -> 010
                                         Vertex(position: SIMD3<Float>((minCoords[0]-midCoords[0])/range,
                                                                        (maxCoords[1]-midCoords[1])/range,
                                                                        (minCoords[2]-midCoords[2])/range)),
                                         Vertex(position: SIMD3<Float>((minCoords[0]-midCoords[0])/range,
                                                                        (minCoords[1]-midCoords[1])/range,
                                                                        (minCoords[2]-midCoords[2])/range)),  // 000 -> 100
                                         Vertex(position: SIMD3<Float>((maxCoords[0]-midCoords[0])/range,
                                                                        (minCoords[1]-midCoords[1])/range,
                                                                        (minCoords[2]-midCoords[2])/range)),
                                         Vertex(position: SIMD3<Float>((minCoords[0]-midCoords[0])/range,
                                                                        (minCoords[1]-midCoords[1])/range,
                                                                        (maxCoords[2]-midCoords[2])/range)),  // 001 -> 011
                                         Vertex(position: SIMD3<Float>((minCoords[0]-midCoords[0])/range,
                                                                        (maxCoords[1]-midCoords[1])/range,
                                                                        (maxCoords[2]-midCoords[2])/range)),
                                         Vertex(position: SIMD3<Float>((minCoords[0]-midCoords[0])/range,
                                                                        (minCoords[1]-midCoords[1])/range,
                                                                        (maxCoords[2]-midCoords[2])/range)),  // 001 -> 101
                                         Vertex(position: SIMD3<Float>((maxCoords[0]-midCoords[0])/range,
                                                                        (minCoords[1]-midCoords[1])/range,
                                                                        (maxCoords[2]-midCoords[2])/range)),
                                         Vertex(position: SIMD3<Float>((minCoords[0]-midCoords[0])/range,
                                                                        (maxCoords[1]-midCoords[1])/range,
                                                                        (minCoords[2]-midCoords[2])/range)),  // 010 -> 011
                                         Vertex(position: SIMD3<Float>((minCoords[0]-midCoords[0])/range,
                                                                        (maxCoords[1]-midCoords[1])/range,
                                                                        (maxCoords[2]-midCoords[2])/range)),
                                         Vertex(position: SIMD3<Float>((minCoords[0]-midCoords[0])/range,
                                                                        (maxCoords[1]-midCoords[1])/range,
                                                                        (minCoords[2]-midCoords[2])/range)),  // 010 -> 110
                                         Vertex(position: SIMD3<Float>((maxCoords[0]-midCoords[0])/range,
                                                                        (maxCoords[1]-midCoords[1])/range,
                                                                        (minCoords[2]-midCoords[2])/range)),
                                         Vertex(position: SIMD3<Float>((minCoords[0]-midCoords[0])/range,
                                                                        (maxCoords[1]-midCoords[1])/range,
                                                                        (maxCoords[2]-midCoords[2])/range)),  // 011 -> 111
                                         Vertex(position: SIMD3<Float>((maxCoords[0]-midCoords[0])/range,
                                                                        (maxCoords[1]-midCoords[1])/range,
                                                                        (maxCoords[2]-midCoords[2])/range)),
                                         Vertex(position: SIMD3<Float>((maxCoords[0]-midCoords[0])/range,
                                                                        (minCoords[1]-midCoords[1])/range,
                                                                        (minCoords[2]-midCoords[2])/range)),  // 100 -> 101
                                         Vertex(position: SIMD3<Float>((maxCoords[0]-midCoords[0])/range,
                                                                        (minCoords[1]-midCoords[1])/range,
                                                                        (maxCoords[2]-midCoords[2])/range)),
                                         Vertex(position: SIMD3<Float>((maxCoords[0]-midCoords[0])/range,
                                                                        (minCoords[1]-midCoords[1])/range,
                                                                        (minCoords[2]-midCoords[2])/range)),  // 100 -> 110
                                         Vertex(position: SIMD3<Float>((maxCoords[0]-midCoords[0])/range,
                                                                        (maxCoords[1]-midCoords[1])/range,
                                                                        (minCoords[2]-midCoords[2])/range)),
                                         Vertex(position: SIMD3<Float>((maxCoords[0]-midCoords[0])/range,
                                                                        (minCoords[1]-midCoords[1])/range,
                                                                        (maxCoords[2]-midCoords[2])/range)),  // 101 -> 111
                                         Vertex(position: SIMD3<Float>((maxCoords[0]-midCoords[0])/range,
                                                                        (maxCoords[1]-midCoords[1])/range,
                                                                        (maxCoords[2]-midCoords[2])/range)),
                                         Vertex(position: SIMD3<Float>((maxCoords[0]-midCoords[0])/range,
                                                                        (maxCoords[1]-midCoords[1])/range,
                                                                        (minCoords[2]-midCoords[2])/range)),  // 110 -> 111
                                         Vertex(position: SIMD3<Float>((maxCoords[0]-midCoords[0])/range,
                                                                        (maxCoords[1]-midCoords[1])/range,
                                                                        (maxCoords[2]-midCoords[2])/range))]
    metalView!.boundingBoxBuffer = metalView!.device!.makeBuffer(bytes: boundingBoxVertices, length: MemoryLayout<Vertex>.size*boundingBoxVertices.count, options: [])
  }
  
  @objc func reloadTriangleBuffers() {
    self.metalView!.triangleBuffers.removeAll()
    self.dataManager.initialiseTriangleBufferIterator()
    while !self.dataManager.triangleBufferIteratorEnded() {
      var bufferTypeLength: Int = 0
      let firstCharacterOfBufferType = UnsafeRawPointer(self.dataManager.currentTriangleBufferType(withLength: &bufferTypeLength))
      var bufferType = ""
      if let firstCharacterOfBufferType = firstCharacterOfBufferType, bufferTypeLength > 0 {
        let bufferTypeData = Data(bytes: firstCharacterOfBufferType, count: bufferTypeLength*MemoryLayout<Int8>.size)
        bufferType = String(data: bufferTypeData, encoding: .utf8) ?? ""
      }
      
      let firstBufferColourComponent = self.dataManager.currentTriangleBufferColour()
      let bufferColourBuffer = UnsafeBufferPointer(start: firstBufferColourComponent, count: 4)
      let bufferColourArray = ContiguousArray(bufferColourBuffer)
      let bufferColour = SIMD4<Float>(bufferColourArray[0], bufferColourArray[1], bufferColourArray[2], bufferColourArray[3])

      var texturePathLength: Int = 0
      let firstTexturePathCharacter = UnsafeRawPointer(self.dataManager.currentTriangleBufferTextureURI(withLength: &texturePathLength))
      var texturePath = ""
      if let firstTexturePathCharacter = firstTexturePathCharacter, texturePathLength > 0 {
        let texturePathData = Data(bytes: firstTexturePathCharacter, count: texturePathLength*MemoryLayout<Int8>.size)
        texturePath = String(data: texturePathData, encoding: .utf8) ?? ""
      }
      
      var vertexBufferSize: Int = 0
      let vertexBuffer = self.dataManager.currentTriangleBuffer(withSize: &vertexBufferSize)
      
      var indexBufferSize: Int = 0
      let indexBuffer = self.dataManager.currentTriangleBufferIndices(withSize: &indexBufferSize)
      
      if vertexBuffer != nil && indexBuffer != nil && indexBufferSize > 0 {
        let vertexMTLBuffer = self.metalView!.device!.makeBuffer(bytes: vertexBuffer!, length: vertexBufferSize, options: [])!
        let indexMTLBuffer = self.metalView!.device!.makeBuffer(bytes: indexBuffer!, length: indexBufferSize, options: [])!
        self.metalView!.triangleBuffers.append(BufferWithColour(buffer: vertexMTLBuffer,
                                                                indexBuffer: indexMTLBuffer,
                                                                indexCount: indexBufferSize / MemoryLayout<UInt32>.size,
                                                                type: bufferType,
                                                                colour: bufferColour,
                                                                texturePath: texturePath))
      }
      self.dataManager.advanceTriangleBufferIterator()
    }
  }
  
  @objc func reloadEdgeBuffers() {
    self.metalView!.edgeBuffers.removeAll()
    self.dataManager.initialiseEdgeBufferIterator()
    while !self.dataManager.edgeBufferIteratorEnded() {
      let firstBufferColourComponent = self.dataManager.currentEdgeBufferColour()
      let bufferColourBuffer = UnsafeBufferPointer(start: firstBufferColourComponent, count: 4)
      let bufferColourArray = ContiguousArray(bufferColourBuffer)
      let bufferColour = SIMD4<Float>(bufferColourArray[0], bufferColourArray[1], bufferColourArray[2], bufferColourArray[3])
      
      var bufferSize: Int = 0
      let buffer = self.dataManager.currentEdgeBuffer(withSize: &bufferSize)
      if buffer != nil {
        let vertexMTLBuffer = self.metalView!.device!.makeBuffer(bytes: buffer!, length: bufferSize, options: [])!
        self.metalView!.edgeBuffers.append(BufferWithColour(buffer: vertexMTLBuffer,
                                                            indexBuffer: vertexMTLBuffer,
                                                            indexCount: 0,
                                                            type: "",
                                                            colour: bufferColour))
      }
      self.dataManager.advanceEdgeBufferIterator()
    }
  }

  @objc func updateSelectionStateBuffer() {
    let count = Int(dataManager.selectionStateCount())
    guard count > 0 else { return }
    guard let ptr = dataManager.selectionStateData() else { return }
    let data = Data(bytes: UnsafeRawPointer(ptr), count: count * MemoryLayout<Float>.size)
    metalView!.updateSelectionStateBuffer(data)
  }
  
  @objc func updateVisibleStateBuffer() {
    let count = Int(dataManager.visibleStateCount())
    guard count > 0 else { return }
    guard let ptr = dataManager.visibleStateData() else { return }
    let data = Data(bytes: UnsafeRawPointer(ptr), count: count * MemoryLayout<Float>.size)
    metalView!.updateVisibleStateBuffer(data)
  }

  func applicationWillTerminate(_ aNotification: Notification) {
    Swift.print("Controller.applicationWillTerminate(Notification)")
    releaseAllRetainedSecurityScopes()
  }

  @discardableResult
  func retainSecurityScopeIfAvailable(for fileURL: URL) -> Bool {
    guard fileURL.isFileURL else { return false }
    let standardizedURL = fileURL.standardizedFileURL
    let path = standardizedURL.path
    if retainedSecurityScopedURLs[path] != nil { return true }
    guard standardizedURL.startAccessingSecurityScopedResource() else { return false }
    retainedSecurityScopedURLs[path] = standardizedURL
    return true
  }

  func retainSecurityScopes(for fileURL: URL) {
    guard fileURL.isFileURL else { return }
    var seenPaths = Set<String>()
    let candidates = [fileURL.standardizedFileURL, fileURL.deletingLastPathComponent().standardizedFileURL]
    for candidate in candidates {
      let path = candidate.path
      if seenPaths.contains(path) { continue }
      seenPaths.insert(path)
      _ = retainSecurityScopeIfAvailable(for: candidate)
    }
  }

  func hasRetainedSecurityScope(for fileURL: URL) -> Bool {
    retainedSecurityScopedURLs[fileURL.standardizedFileURL.path] != nil
  }

  func releaseAllRetainedSecurityScopes() {
    for scopedURL in retainedSecurityScopedURLs.values {
      scopedURL.stopAccessingSecurityScopedResource()
    }
    retainedSecurityScopedURLs.removeAll()
  }

  func promptForTextureDirectoryAccess(requestedDirectory: URL, sourceURL: URL) -> URL? {
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = true
    openPanel.canChooseFiles = false
    openPanel.directoryURL = requestedDirectory
    openPanel.prompt = "Allow"
    openPanel.message = "azul needs access to texture files for \(sourceURL.lastPathComponent). Select the texture directory."
    guard openPanel.runModal() == .OK else { return nil }
    return openPanel.url
  }

  func requestTextureDirectoryAccessIfNeeded(for sourceURL: URL) {
    guard let metalView = metalView else { return }
    var deniedDirectories = Set(metalView.consumePermissionDeniedTextureDirectories())
    if deniedDirectories.isEmpty {
      deniedDirectories.formUnion(metalView.failedTextureDirectories())
    }
    guard !deniedDirectories.isEmpty else { return }

    var grantedNewAccess = false
    for deniedDirectory in deniedDirectories.sorted() {
      let deniedDirectoryURL = URL(fileURLWithPath: deniedDirectory)
      if hasRetainedSecurityScope(for: deniedDirectoryURL) { continue }
      Swift.print("Texture directory access missing (\(sourceURL.lastPathComponent)): \(deniedDirectory)")
      guard let selectedDirectoryURL = promptForTextureDirectoryAccess(requestedDirectory: deniedDirectoryURL, sourceURL: sourceURL) else {
        Swift.print("Texture directory access not granted for: \(deniedDirectory)")
        continue
      }
      if retainSecurityScopeIfAvailable(for: selectedDirectoryURL) {
        Swift.print("Texture directory access granted: \(selectedDirectoryURL.path)")
        grantedNewAccess = true
      } else {
        Swift.print("Texture directory access still unavailable: \(selectedDirectoryURL.path)")
      }
    }

    if grantedNewAccess {
      metalView.clearFailedTexturePaths()
      metalView.primeTexturesForCurrentBuffers()
      metalView.needsDisplay = true
    }
  }
  
  @IBAction func showHelp(_ sender: Any) {
    if let url = URL(string: "https://github.com/tudelft3d/azul") {
      NSWorkspace.shared.open(url)
    }
  }

  @objc func sourceListDoubleClick(_ sender: Any?) {
    dataManager.sourceListDoubleClick()
    
    // Put model matrix in arrays and render
    metalView!.constants.modelMatrix = metalView!.modelMatrix
    metalView!.constants.modelViewProjectionMatrix = matrix_multiply(metalView!.projectionMatrix, matrix_multiply(metalView!.viewMatrix, metalView!.modelMatrix))
    metalView!.constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: metalView!.modelMatrix).inverse.transpose
    metalView!.needsDisplay = true
  }
  
  @objc func lodSegmentChanged(_ sender: NSSegmentedControl) {
    if sender.selectedSegment == sender.segmentCount - 1 {
      currentLodFilter = "__highest__"
      "__highest__".withCString { pointer in
        dataManager.setLodFilter(pointer)
      }
    } else {
      guard let lodValue = sender.label(forSegment: sender.selectedSegment) else { return }
      currentLodFilter = lodValue
      lodValue.withCString { pointer in
        dataManager.setLodFilter(pointer)
      }
    }
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16*1024*1024)
    self.reloadTriangleBuffers()
    if self.metalView?.showTextures == true {
      self.metalView?.primeTexturesForCurrentBuffers()
    }
    self.updateVisibleStateBuffer()
    self.updateSelectionStateBuffer()
    dataManager.regenerateEdgeBuffers(withMaximumSize: 16*1024*1024)
    self.reloadEdgeBuffers()
    metalView!.needsDisplay = true
    objectsSourceList!.reloadData()
    updateLodMenuStates()
  }
  
  func updateLodSegments() {
    let lods = dataManager.availableLods() ?? []
    guard let control = lodSegmentedControl else { return }
    
    if lods.isEmpty {
      control.isHidden = true
      currentLodFilter = ""
      "".withCString { pointer in
        dataManager.setLodFilter(pointer)
      }
      lodToolbarItem?.menuFormRepresentation = nil
      let emptyMenu = NSMenu(title: "Level of Detail")
      let noneItem = NSMenuItem(title: "None", action: nil, keyEquivalent: "")
      noneItem.isEnabled = false
      emptyMenu.addItem(noneItem)
      lodMenuItem?.submenu = emptyMenu
      lodMenuItem?.isHidden = true
      return
    }
    
    lodMenuItem?.isHidden = false
    control.isHidden = false
    let sortedLods = lods.sorted()
    control.segmentCount = 1 + sortedLods.count
    for (index, lod) in sortedLods.enumerated() {
      control.setLabel("\(lod)", forSegment: index)
    }
    control.setLabel("Highest", forSegment: sortedLods.count)
    control.selectedSegment = sortedLods.count
    currentLodFilter = "__highest__"
    "__highest__".withCString { pointer in
      dataManager.setLodFilter(pointer)
    }
    
    // Build overflow menu representation
    let menuItem = NSMenuItem(title: "LoD", action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: "LoD")
    for lod in sortedLods {
      let item = NSMenuItem(title: "\(lod)", action: #selector(lodMenuItemClicked(_:)), keyEquivalent: "")
      item.target = self
      submenu.addItem(item)
    }
    let highestItem = NSMenuItem(title: "Highest", action: #selector(lodMenuItemClicked(_:)), keyEquivalent: "")
    highestItem.target = self
    submenu.addItem(highestItem)
    menuItem.submenu = submenu
    lodToolbarItem?.menuFormRepresentation = menuItem
    
    // Build View menu submenu
    let viewSubmenu = NSMenu(title: "Level of Detail")
    for lod in sortedLods {
      let item = NSMenuItem(title: "\(lod)", action: #selector(lodMenuItemClicked(_:)), keyEquivalent: "")
      item.target = self
      item.state = currentLodFilter == lod ? .on : .off
      viewSubmenu.addItem(item)
    }
    let viewHighestItem = NSMenuItem(title: "Highest", action: #selector(lodMenuItemClicked(_:)), keyEquivalent: "")
    viewHighestItem.target = self
    viewHighestItem.state = .on
    viewSubmenu.addItem(viewHighestItem)
    lodMenuItem?.submenu = viewSubmenu
    
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16*1024*1024)
    self.reloadTriangleBuffers()
    if self.metalView?.showTextures == true {
      self.metalView?.primeTexturesForCurrentBuffers()
    }
    self.updateVisibleStateBuffer()
    self.updateSelectionStateBuffer()
    dataManager.regenerateEdgeBuffers(withMaximumSize: 16*1024*1024)
    self.reloadEdgeBuffers()
    metalView!.needsDisplay = true
    objectsSourceList!.reloadData()
    for row in 0..<objectsSourceList!.numberOfRows {
      if let item = objectsSourceList!.item(atRow: row), objectsSourceList!.parent(forItem: item) == nil {
        objectsSourceList!.expandItem(item)
      }
    }
  }
  
  @objc func lodMenuItemClicked(_ sender: NSMenuItem) {
    let lodValue = sender.title
    if lodValue == "Highest" {
      currentLodFilter = "__highest__"
      "__highest__".withCString { pointer in
        dataManager.setLodFilter(pointer)
      }
    } else {
      currentLodFilter = lodValue
      lodValue.withCString { pointer in
        dataManager.setLodFilter(pointer)
      }
    }
    dataManager.regenerateTriangleBuffers(withMaximumSize: 16*1024*1024)
    reloadTriangleBuffers()
    updateVisibleStateBuffer()
    updateSelectionStateBuffer()
    dataManager.regenerateEdgeBuffers(withMaximumSize: 16*1024*1024)
    reloadEdgeBuffers()
    metalView!.needsDisplay = true
    objectsSourceList!.reloadData()
    updateLodMenuStates()
  }
  
  func updateLodMenuStates() {
    guard let submenu = lodMenuItem?.submenu else { return }
    for item in submenu.items {
      item.state = (item.title == "Highest" && currentLodFilter == "__highest__") || currentLodFilter == item.title ? .on : .off
    }
  }
  
  func showPreferences(selectColoursTab: Bool = false) {
    if let existing = preferencesWindow {
      existing.makeKeyAndOrderFront(nil)
      if selectColoursTab {
        findTabView(in: existing.contentView)?.selectTabViewItem(at: 1)
      }
      return
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 420, height: 310),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: true
    )
    window.title = "Preferences"
    window.isReleasedWhenClosed = false

    let tabView = NSTabView(frame: window.contentView!.bounds)
    tabView.autoresizingMask = [.width, .height]
    tabView.tabPosition = .top
    window.contentView!.addSubview(tabView)

    // --- Rendering tab ---
    let renderingTab = NSTabViewItem(identifier: "Rendering")
    renderingTab.label = "Rendering"
    let renderingView = NSView()
    renderingTab.view = renderingView

    let lightLabel = NSTextField(labelWithString: "Light mode background:")
    lightLabel.translatesAutoresizingMaskIntoConstraints = false
    renderingView.addSubview(lightLabel)

    let lightWell = NSColorWell()
    lightWell.translatesAutoresizingMaskIntoConstraints = false
    lightWell.tag = 0
    lightWell.action = #selector(preferencesBackgroundColorChanged(_:))
    lightWell.target = self
    if let colorData = UserDefaults.standard.data(forKey: "azulLightBackgroundColor"),
       let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
      lightWell.color = color
    } else {
      lightWell.color = NSColor.white
    }
    renderingView.addSubview(lightWell)

    let darkLabel = NSTextField(labelWithString: "Dark mode background:")
    darkLabel.translatesAutoresizingMaskIntoConstraints = false
    renderingView.addSubview(darkLabel)

    let darkWell = NSColorWell()
    darkWell.translatesAutoresizingMaskIntoConstraints = false
    darkWell.tag = 1
    darkWell.action = #selector(preferencesBackgroundColorChanged(_:))
    darkWell.target = self
    if let colorData = UserDefaults.standard.data(forKey: "azulDarkBackgroundColor"),
       let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
      darkWell.color = color
    } else {
      darkWell.color = NSColor(calibratedWhite: 0.22, alpha: 1.0)
    }
    renderingView.addSubview(darkWell)

    let msaaLabel = NSTextField(labelWithString: "Anti-aliasing (MSAA):")
    msaaLabel.translatesAutoresizingMaskIntoConstraints = false
    renderingView.addSubview(msaaLabel)

    let msaaPopup = NSPopUpButton()
    msaaPopup.translatesAutoresizingMaskIntoConstraints = false
    msaaPopup.addItems(withTitles: ["1x", "2x", "4x"])
    let currentSampleCount = UserDefaults.standard.integer(forKey: "azulSampleCount")
    let sampleIndex: Int
    switch currentSampleCount {
    case 1: sampleIndex = 0
    case 2: sampleIndex = 1
    default: sampleIndex = 2
    }
    msaaPopup.selectItem(at: sampleIndex)
    msaaPopup.action = #selector(preferencesMSAAChanged(_:))
    msaaPopup.target = self
    renderingView.addSubview(msaaPopup)

    let renderingResetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(preferencesReset(_:)))
    renderingResetButton.translatesAutoresizingMaskIntoConstraints = false
    renderingResetButton.bezelStyle = .rounded
    renderingView.addSubview(renderingResetButton)

    NSLayoutConstraint.activate([
      lightLabel.topAnchor.constraint(equalTo: renderingView.topAnchor, constant: 20),
      lightLabel.leadingAnchor.constraint(equalTo: renderingView.leadingAnchor, constant: 20),

      lightWell.centerYAnchor.constraint(equalTo: lightLabel.centerYAnchor),
      lightWell.leadingAnchor.constraint(equalTo: lightLabel.trailingAnchor, constant: 12),
      lightWell.widthAnchor.constraint(equalToConstant: 60),
      lightWell.heightAnchor.constraint(equalToConstant: 28),

      darkLabel.topAnchor.constraint(equalTo: lightLabel.bottomAnchor, constant: 16),
      darkLabel.leadingAnchor.constraint(equalTo: renderingView.leadingAnchor, constant: 20),

      darkWell.centerYAnchor.constraint(equalTo: darkLabel.centerYAnchor),
      darkWell.leadingAnchor.constraint(equalTo: darkLabel.trailingAnchor, constant: 12),
      darkWell.widthAnchor.constraint(equalToConstant: 60),
      darkWell.heightAnchor.constraint(equalToConstant: 28),

      msaaLabel.topAnchor.constraint(equalTo: darkLabel.bottomAnchor, constant: 16),
      msaaLabel.leadingAnchor.constraint(equalTo: renderingView.leadingAnchor, constant: 20),

      msaaPopup.centerYAnchor.constraint(equalTo: msaaLabel.centerYAnchor),
      msaaPopup.leadingAnchor.constraint(equalTo: msaaLabel.trailingAnchor, constant: 12),

      renderingResetButton.topAnchor.constraint(equalTo: msaaLabel.bottomAnchor, constant: 16),
      renderingResetButton.centerXAnchor.constraint(equalTo: renderingView.centerXAnchor),
    ])

    tabView.addTabViewItem(renderingTab)

    // --- Object Type Colours tab ---
    let coloursTab = NSTabViewItem(identifier: "Colours")
    coloursTab.label = "Semantic Surfaces"
    let coloursView = NSView()
    coloursTab.view = coloursView

    let scrollView = NSScrollView()
    scrollView.hasVerticalScroller = true
    scrollView.translatesAutoresizingMaskIntoConstraints = false
    scrollView.borderType = .noBorder
    coloursView.addSubview(scrollView)
    NSLayoutConstraint.activate([
      scrollView.leadingAnchor.constraint(equalTo: coloursView.leadingAnchor),
      scrollView.trailingAnchor.constraint(equalTo: coloursView.trailingAnchor),
      scrollView.topAnchor.constraint(equalTo: coloursView.topAnchor),
      scrollView.bottomAnchor.constraint(equalTo: coloursView.bottomAnchor),
    ])

    let stackView = NSStackView()
    stackView.translatesAutoresizingMaskIntoConstraints = false
    stackView.orientation = .vertical
    stackView.spacing = 4

    let typeCount = dataManager.colourTypeCount()
    colourTypeWells.removeAll()
    colourTypeNames.removeAll()

    for i in 0..<typeCount {
      let typeName = dataManager.colourTypeName(at: i)!
      var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
      dataManager.getRed(&r, green: &g, blue: &b, alpha: &a, forColourTypeAt: i)

      colourTypeNames.append(typeName)

      let row = NSView()
      row.translatesAutoresizingMaskIntoConstraints = false

      let label = NSTextField(labelWithString: typeName)
      label.translatesAutoresizingMaskIntoConstraints = false
      row.addSubview(label)

      let well = NSColorWell()
      well.translatesAutoresizingMaskIntoConstraints = false
      well.color = NSColor(calibratedRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
      well.tag = colourTypeWells.count
      well.action = #selector(typeColourChanged(_:))
      well.target = self
      row.addSubview(well)
      colourTypeWells.append(well)

      NSLayoutConstraint.activate([
        label.leadingAnchor.constraint(equalTo: row.leadingAnchor, constant: 10),
        label.centerYAnchor.constraint(equalTo: well.centerYAnchor),

        well.centerYAnchor.constraint(equalTo: row.centerYAnchor),
        well.trailingAnchor.constraint(equalTo: row.trailingAnchor, constant: -10),
        well.widthAnchor.constraint(equalToConstant: 60),
        well.heightAnchor.constraint(equalToConstant: 28),
        row.heightAnchor.constraint(equalToConstant: 32),
      ])

      stackView.addArrangedSubview(row)
    }

    let resetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(resetTypeColours(_:)))
    resetButton.bezelStyle = .rounded
    stackView.addArrangedSubview(resetButton)

    scrollView.documentView = stackView
    stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor).isActive = true
    tabView.addTabViewItem(coloursTab)

    // --- Selection tab ---
    let selectionTab = NSTabViewItem(identifier: "Selection")
    selectionTab.label = "Selection"
    let selectionView = NSView()
    selectionTab.view = selectionView

    let selHighlightLabel = NSTextField(labelWithString: "Selection highlight colour:")
    selHighlightLabel.translatesAutoresizingMaskIntoConstraints = false
    selectionView.addSubview(selHighlightLabel)

    let selHighlightWell = NSColorWell()
    selHighlightWell.translatesAutoresizingMaskIntoConstraints = false
    selHighlightWell.tag = 0
    selHighlightWell.action = #selector(selectionColourChanged(_:))
    selHighlightWell.target = self
    NSColorPanel.shared.showsAlpha = true
    if let colorData = UserDefaults.standard.data(forKey: "azulSelectionColour"),
       let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
      selHighlightWell.color = color
    } else {
      selHighlightWell.color = NSColor.yellow.withAlphaComponent(0.7)
    }
    selectionView.addSubview(selHighlightWell)

    let selEdgesLabel = NSTextField(labelWithString: "Selected edges colour:")
    selEdgesLabel.translatesAutoresizingMaskIntoConstraints = false
    selectionView.addSubview(selEdgesLabel)

    let selEdgesWell = NSColorWell()
    selEdgesWell.translatesAutoresizingMaskIntoConstraints = false
    selEdgesWell.tag = 1
    selEdgesWell.action = #selector(selectionEdgesColourChanged(_:))
    selEdgesWell.target = self
    if let colorData = UserDefaults.standard.data(forKey: "azulSelectedEdgesColour"),
       let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
      selEdgesWell.color = color
    } else {
      selEdgesWell.color = NSColor.red
    }
    selectionView.addSubview(selEdgesWell)

    let selResetButton = NSButton(title: "Reset to Defaults", target: self, action: #selector(selectionReset(_:)))
    selResetButton.translatesAutoresizingMaskIntoConstraints = false
    selResetButton.bezelStyle = .rounded
    selectionView.addSubview(selResetButton)

    NSLayoutConstraint.activate([
      selHighlightLabel.topAnchor.constraint(equalTo: selectionView.topAnchor, constant: 20),
      selHighlightLabel.leadingAnchor.constraint(equalTo: selectionView.leadingAnchor, constant: 20),

      selHighlightWell.centerYAnchor.constraint(equalTo: selHighlightLabel.centerYAnchor),
      selHighlightWell.leadingAnchor.constraint(equalTo: selHighlightLabel.trailingAnchor, constant: 12),
      selHighlightWell.widthAnchor.constraint(equalToConstant: 60),
      selHighlightWell.heightAnchor.constraint(equalToConstant: 28),

      selEdgesLabel.topAnchor.constraint(equalTo: selHighlightLabel.bottomAnchor, constant: 16),
      selEdgesLabel.leadingAnchor.constraint(equalTo: selectionView.leadingAnchor, constant: 20),

      selEdgesWell.centerYAnchor.constraint(equalTo: selEdgesLabel.centerYAnchor),
      selEdgesWell.leadingAnchor.constraint(equalTo: selEdgesLabel.trailingAnchor, constant: 12),
      selEdgesWell.widthAnchor.constraint(equalToConstant: 60),
      selEdgesWell.heightAnchor.constraint(equalToConstant: 28),

      selResetButton.topAnchor.constraint(equalTo: selEdgesLabel.bottomAnchor, constant: 16),
      selResetButton.centerXAnchor.constraint(equalTo: selectionView.centerXAnchor),
    ])

    tabView.addTabViewItem(selectionTab)

    if selectColoursTab {
      tabView.selectTabViewItem(at: 1)
    }

    window.center()
    window.makeKeyAndOrderFront(nil)
    preferencesWindow = window
  }

  @IBAction func showPreferences(_ sender: Any) {
    showPreferences(selectColoursTab: false)
  }

  @IBAction func showObjectTypeColours(_ sender: Any) {
    showPreferences(selectColoursTab: true)
  }

  @objc func preferencesBackgroundColorChanged(_ sender: NSColorWell) {
    if sender.tag == 0 {
      metalView?.customLightClearColor = sender.color
      if let data = try? NSKeyedArchiver.archivedData(withRootObject: sender.color, requiringSecureCoding: false) {
        UserDefaults.standard.set(data, forKey: "azulLightBackgroundColor")
      }
    } else {
      metalView?.customDarkClearColor = sender.color
      if let data = try? NSKeyedArchiver.archivedData(withRootObject: sender.color, requiringSecureCoding: false) {
        UserDefaults.standard.set(data, forKey: "azulDarkBackgroundColor")
      }
    }
  }

  @objc func preferencesMSAAChanged(_ sender: NSPopUpButton) {
    let titles = ["1", "2", "4"]
    let index = sender.indexOfSelectedItem
    let count = Int(titles[index])!
    metalView?.msaaSampleCount = count
    UserDefaults.standard.set(count, forKey: "azulSampleCount")
  }

  @objc func preferencesReset(_ sender: Any) {
    UserDefaults.standard.removeObject(forKey: "azulLightBackgroundColor")
    UserDefaults.standard.removeObject(forKey: "azulDarkBackgroundColor")
    UserDefaults.standard.removeObject(forKey: "azulSampleCount")
    metalView?.customLightClearColor = nil
    metalView?.customDarkClearColor = nil
    metalView?.msaaSampleCount = 4

    if let window = preferencesWindow {
      for subview in window.contentView!.subviews {
        recursivelyUpdateRenderingControls(subview)
      }
    }
  }

  func recursivelyUpdateRenderingControls(_ view: NSView) {
    for subview in view.subviews {
      if let well = subview as? NSColorWell {
        if well.tag == 0 {
          well.color = NSColor.white
        } else if well.tag == 1 {
          well.color = NSColor(calibratedWhite: 0.22, alpha: 1.0)
        }
      }
      if let popup = subview as? NSPopUpButton {
        popup.selectItem(at: 2)
      }
      recursivelyUpdateRenderingControls(subview)
    }
  }

  func findTabView(in view: NSView?) -> NSTabView? {
    guard let view = view else { return nil }
    for subview in view.subviews {
      if let tabView = subview as? NSTabView { return tabView }
      if let found = findTabView(in: subview) { return found }
    }
    return nil
  }

  func loadPreferences() {
    if let colorData = UserDefaults.standard.data(forKey: "azulLightBackgroundColor"),
       let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
      metalView?.customLightClearColor = color
    }
    if let colorData = UserDefaults.standard.data(forKey: "azulDarkBackgroundColor"),
       let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData) {
      metalView?.customDarkClearColor = color
    }
    let sampleCount = UserDefaults.standard.integer(forKey: "azulSampleCount")
    if sampleCount > 0 {
      metalView?.msaaSampleCount = sampleCount
    }
    if let storedColours = UserDefaults.standard.dictionary(forKey: "azulTypeColours") as? [String: [String: CGFloat]] {
      for (typeName, components) in storedColours {
        if let r = components["r"], let g = components["g"], let b = components["b"], let a = components["a"] {
          typeName.withCString { ptr in
            dataManager.setColourWithRed(Float(r), green: Float(g), blue: Float(b), alpha: Float(a), forType: ptr)
          }
        }
      }
    }
    if let colorData = UserDefaults.standard.data(forKey: "azulSelectionColour"),
       let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData),
       let srgb = color.usingColorSpace(.sRGB) {
      metalView?.selectionColour = SIMD4<Float>(Float(srgb.redComponent), Float(srgb.greenComponent), Float(srgb.blueComponent), Float(srgb.alphaComponent))
    }
    if let colorData = UserDefaults.standard.data(forKey: "azulSelectedEdgesColour"),
       let color = try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSColor.self, from: colorData),
       let srgb = color.usingColorSpace(.sRGB) {
      dataManager.setSelectedEdgesColourWithRed(Float(srgb.redComponent), green: Float(srgb.greenComponent), blue: Float(srgb.blueComponent), alpha: Float(srgb.alphaComponent))
    }
    metalView?.showTextures = false
    dataManager.setUseAppearances(false)
    currentAppearanceTheme.withCString { pointer in
      dataManager.setAppearanceTheme(pointer)
    }
    updateAppearanceThemeOptions()
    metalView?.updateAppearance()
  }

  @objc func typeColourChanged(_ sender: NSColorWell) {
    let index = sender.tag
    guard index >= 0, index < colourTypeNames.count else { return }
    let typeName = colourTypeNames[index]
    let color = sender.color.usingColorSpace(.sRGB) ?? sender.color
    let r = Float(color.redComponent)
    let g = Float(color.greenComponent)
    let b = Float(color.blueComponent)
    let a = Float(color.alphaComponent)

    typeName.withCString { ptr in
      dataManager.setColourWithRed(r, green: g, blue: b, alpha: a, forType: ptr)
    }

    var storedColours = UserDefaults.standard.dictionary(forKey: "azulTypeColours") as? [String: [String: CGFloat]] ?? [:]
    storedColours[typeName] = ["r": CGFloat(r), "g": CGFloat(g), "b": CGFloat(b), "a": CGFloat(a)]
    UserDefaults.standard.set(storedColours, forKey: "azulTypeColours")

    dataManager.regenerateTriangleBuffers(withMaximumSize: 16*1024*1024)
    reloadTriangleBuffers()
    if metalView?.showTextures == true {
      metalView?.primeTexturesForCurrentBuffers()
    }
    updateVisibleStateBuffer()
    updateSelectionStateBuffer()
    dataManager.regenerateEdgeBuffers(withMaximumSize: 16*1024*1024)
    reloadEdgeBuffers()
    metalView?.needsDisplay = true
  }

  @objc func selectionColourChanged(_ sender: NSColorWell) {
    let color = sender.color.usingColorSpace(.sRGB) ?? sender.color
    metalView?.selectionColour = SIMD4<Float>(Float(color.redComponent), Float(color.greenComponent), Float(color.blueComponent), Float(color.alphaComponent))
    if let data = try? NSKeyedArchiver.archivedData(withRootObject: sender.color, requiringSecureCoding: false) {
      UserDefaults.standard.set(data, forKey: "azulSelectionColour")
    }
  }

  @objc func selectionEdgesColourChanged(_ sender: NSColorWell) {
    let color = sender.color.usingColorSpace(.sRGB) ?? sender.color
    let r = Float(color.redComponent), g = Float(color.greenComponent), b = Float(color.blueComponent), a = Float(color.alphaComponent)
    dataManager.setSelectedEdgesColourWithRed(r, green: g, blue: b, alpha: a)
    if let data = try? NSKeyedArchiver.archivedData(withRootObject: sender.color, requiringSecureCoding: false) {
      UserDefaults.standard.set(data, forKey: "azulSelectedEdgesColour")
    }
    dataManager.regenerateEdgeBuffers(withMaximumSize: 16*1024*1024)
    reloadEdgeBuffers()
    metalView?.needsDisplay = true
  }

  @objc func selectionReset(_ sender: Any) {
    UserDefaults.standard.removeObject(forKey: "azulSelectionColour")
    UserDefaults.standard.removeObject(forKey: "azulSelectedEdgesColour")
    metalView?.selectionColour = SIMD4<Float>(1.0, 1.0, 0.0, 0.7)
    dataManager.setSelectedEdgesColourWithRed(1.0, green: 0.0, blue: 0.0, alpha: 1.0)
    dataManager.regenerateEdgeBuffers(withMaximumSize: 16*1024*1024)
    reloadEdgeBuffers()
    metalView?.needsDisplay = true

    if let window = preferencesWindow {
      for subview in window.contentView!.subviews {
        recursivelyUpdateSelectionControls(subview)
      }
    }
  }

  func recursivelyUpdateSelectionControls(_ view: NSView) {
    for subview in view.subviews {
      if let well = subview as? NSColorWell {
        if well.tag == 0 {
          well.color = NSColor.yellow
        } else if well.tag == 1 {
          well.color = NSColor.red
        }
      }
      recursivelyUpdateSelectionControls(subview)
    }
  }

  @objc func resetTypeColours(_ sender: Any) {
    dataManager.resetTypeColours()
    UserDefaults.standard.removeObject(forKey: "azulTypeColours")

    for (i, well) in colourTypeWells.enumerated() {
      var r: Float = 0, g: Float = 0, b: Float = 0, a: Float = 0
      dataManager.getRed(&r, green: &g, blue: &b, alpha: &a, forColourTypeAt: i)
      well.color = NSColor(calibratedRed: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
    }

    dataManager.regenerateTriangleBuffers(withMaximumSize: 16*1024*1024)
    reloadTriangleBuffers()
    if metalView?.showTextures == true {
      metalView?.primeTexturesForCurrentBuffers()
    }
    updateVisibleStateBuffer()
    updateSelectionStateBuffer()
    dataManager.regenerateEdgeBuffers(withMaximumSize: 16*1024*1024)
    reloadEdgeBuffers()
    metalView?.needsDisplay = true
  }

  @IBAction func selectAll(_ sender: Any) {
    guard let outlineView = objectsSourceList else { return }
    let allRows = IndexSet(integersIn: 0..<outlineView.numberOfRows)
    outlineView.selectRowIndexes(allRows, byExtendingSelection: false)
  }

  @objc func copySelectedObjectIds() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.declareTypes([NSPasteboard.PasteboardType.string], owner: self)
    var selectionString = String()
    for row in objectsSourceList!.selectedRowIndexes {
      if let item = objectsSourceList!.item(atRow: row) {
        if let objectId = dataManager.objectId(forItem: item), !objectId.isEmpty {
          if !selectionString.isEmpty {
            selectionString.append("\n")
          }
          selectionString.append(objectId)
        }
      }
    }
    pasteboard.setString(selectionString, forType: NSPasteboard.PasteboardType.string)
  }
  
  func loadViewParameters(url: URL) {
    do {
      let jsonDecoder = JSONDecoder()
      let jsonData = try Data(contentsOf: url)
      let viewParameters = try jsonDecoder.decode(ViewParameters.self, from: jsonData)
      self.metalView!.eye = deserialiseToFloat3(vector: viewParameters.eye)
      self.metalView!.centre = deserialiseToFloat3(vector: viewParameters.centre)
      self.metalView!.fieldOfView = viewParameters.fieldOfView
      self.metalView!.modelTranslationToCentreOfRotationMatrix = deserialiseToMatrix4x4(matrix: viewParameters.modelTranslationToCentreOfRotationMatrix)
      self.metalView!.modelRotationMatrix = deserialiseToMatrix4x4(matrix: viewParameters.modelRotationMatrix)
      self.metalView!.modelShiftBackMatrix = deserialiseToMatrix4x4(matrix: viewParameters.modelShiftBackMatrix)
      self.metalView!.modelMatrix = deserialiseToMatrix4x4(matrix: viewParameters.modelMatrix)
      self.metalView!.viewMatrix = deserialiseToMatrix4x4(matrix: viewParameters.viewMatrix)
      self.metalView!.projectionMatrix = deserialiseToMatrix4x4(matrix: viewParameters.projectionMatrix)
      self.metalView!.viewEdges = viewParameters.viewEdges
      self.metalView!.viewBoundingBox = viewParameters.viewBoundingBox
      let showAppearances = viewParameters.showAppearances ?? false
      self.metalView!.showTextures = showAppearances
      self.currentAppearanceTheme = viewParameters.appearanceTheme ?? ""
      self.toggleViewEdgesMenuItem.state = viewParameters.viewEdges ? .on : .off
      self.toggleViewBoundingBoxMenuItem.state = viewParameters.viewBoundingBox ? .on : .off
      self.toggleEdgesToolbarItem?.image = NSImage(systemSymbolName: viewParameters.viewEdges ? "square.dashed" : "square", accessibilityDescription: "Toggle edges")
      self.updateAppearanceThemeOptions()
      self.refreshAppearanceRendering()
      
      self.metalView!.constants.modelMatrix = self.metalView!.modelMatrix
      self.metalView!.constants.modelViewProjectionMatrix = matrix_multiply(self.metalView!.projectionMatrix, matrix_multiply(self.metalView!.viewMatrix, self.metalView!.modelMatrix))
      self.metalView!.constants.modelMatrixInverseTransposed = matrix_upper_left_3x3(matrix: self.metalView!.modelMatrix).inverse.transpose
      self.metalView!.needsDisplay = true
    } catch {
      Swift.print("Couldn't load view parameters...")
    }
  }
  
  @IBAction func loadViewParameters(_ sender: NSMenuItem) {
    let openPanel = NSOpenPanel()
    openPanel.allowsMultipleSelection = false
    openPanel.canChooseDirectories = false
    openPanel.canChooseFiles = true
    openPanel.allowedContentTypes = [UTType(filenameExtension: "azulview")!]
    openPanel.beginSheetModal(for: window) { (result: NSApplication.ModalResponse) in
      if result == .OK {
        self.loadViewParameters(url: openPanel.url!)
      }
    }
  }
  
  @IBAction func saveViewParameters(_ sender: NSMenuItem) {
    let jsonEncoder = JSONEncoder()
    let viewParameters = ViewParameters(eye: serialise(vector: metalView!.eye),
                                        centre: serialise(vector: metalView!.centre),
                                        fieldOfView: metalView!.fieldOfView,
                                        modelTranslationToCentreOfRotationMatrix: serialise(matrix: metalView!.modelTranslationToCentreOfRotationMatrix),
                                        modelRotationMatrix: serialise(matrix: metalView!.modelRotationMatrix),
                                        modelShiftBackMatrix: serialise(matrix: metalView!.modelShiftBackMatrix),
                                        modelMatrix: serialise(matrix: metalView!.modelMatrix),
                                        viewMatrix: serialise(matrix: metalView!.viewMatrix),
                                        projectionMatrix: serialise(matrix: metalView!.projectionMatrix),
                                        viewEdges: metalView!.viewEdges,
                                        viewBoundingBox: metalView!.viewBoundingBox,
                                        showAppearances: metalView!.showTextures,
                                        appearanceTheme: currentAppearanceTheme)
    do {
      let jsonData = try jsonEncoder.encode(viewParameters)
      let savePanel = NSSavePanel()
      savePanel.allowedContentTypes = [UTType(filenameExtension: "azulview")!]
      savePanel.beginSheetModal(for: window, completionHandler: { (result: NSApplication.ModalResponse) in
        if result == .OK {
          do {
            try jsonData.write(to: savePanel.url!, options: [])
          } catch {
            Swift.print("Couldn't write file...")
          }
        }
      })
    } catch {
      Swift.print("Couldn't encode...")
    }
  }
}
