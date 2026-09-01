import UIKit
import UniformTypeIdentifiers

protocol ObjectListViewControllerDelegate: AnyObject {
    func objectListDidSelectItem(_ item: AzulObjectIterator)
    func objectListDidRequestCenter(_ item: AzulObjectIterator)
}

class ObjectListViewController: UIViewController {

    weak var delegate: ObjectListViewControllerDelegate?
    var dataManager: DataManagerWrapperWrapper!
    var allFlatItems: [AzulObjectIterator] = []
    var filteredFlatItems: [AzulObjectIterator] = []
    var expandedItems = Set<AzulObjectIterator>()
    var selectedItem: AzulObjectIterator?
    var isSidebar: Bool = false

    let tableView = UITableView(frame: .zero, style: .plain)
    let searchController = UISearchController(searchResultsController: nil)
    var isSearchActive: Bool { !(searchController.searchBar.text ?? "").isEmpty }

    let sortButton = UIBarButtonItem(image: UIImage(systemName: "arrow.up.arrow.down"), style: .plain, target: nil, action: nil)
    let filterButton = UIBarButtonItem(image: UIImage(systemName: "line.3.horizontal.decrease.circle"), style: .plain, target: nil, action: nil)
    var sortKey: String = "none"
    var sortDescending = false
    var selectedTypes: Set<String> = []

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Objects"
        view.backgroundColor = .systemBackground

        searchController.searchResultsUpdater = self
        searchController.obscuresBackgroundDuringPresentation = false
        searchController.searchBar.placeholder = "Filter objects..."
        navigationItem.searchController = searchController
        navigationItem.hidesSearchBarWhenScrolling = false

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "cell")
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        if UIDevice.current.userInterfaceIdiom == .pad && !isSidebar {
            preferredContentSize = CGSize(width: 400, height: 600)
        }

        if !isSidebar {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissSelf))
        }

        sortKey = UserDefaults.standard.string(forKey: "azulSortKey") ?? "none"
        sortDescending = UserDefaults.standard.bool(forKey: "azulSortDescending")
        applySortOrderToDataManager()
        sortButton.target = nil
        filterButton.target = self
        filterButton.action = #selector(showTypeFilter)
        sortButton.menu = makeSortMenu()
        if isSidebar {
            navigationItem.rightBarButtonItems = [filterButton, sortButton]
        } else {
            navigationItem.leftBarButtonItems = [sortButton, filterButton]
        }

        rebuildFlatItems()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuildFlatItems()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        NotificationCenter.default.addObserver(self, selector: #selector(handleFileLoaded), name: Notification.Name("AzulFileLoaded"), object: nil)
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        NotificationCenter.default.removeObserver(self, name: Notification.Name("AzulFileLoaded"), object: nil)
    }

    @objc func dismissSelf() {
        dismiss(animated: true)
    }

    @objc func handleFileLoaded() {
        // Type availability is file-specific, so a stale filter makes no sense
        selectedTypes.removeAll()
        applyTypeFilter()
    }

    @objc func rebuildFlatItems() {
        allFlatItems.removeAll()
        let fileCount = dataManager.numberOfParsedFiles()
        for i in 0..<fileCount {
            let file = dataManager.iteratorForFile(at: i) as! AzulObjectIterator
            if dataManager.isItemExpandable(file) {
                expandedItems.insert(file)
            }
            appendFlattened(file)
        }
        applyFilter()
    }

    // MARK: - Sorting

    private func makeSortMenu() -> UIMenu {
        func keyAction(_ key: String, _ title: String) -> UIAction {
            UIAction(title: title, state: sortKey == key ? .on : .off) { [weak self] _ in
                self?.updateSortOrder(key: key, descending: self?.sortDescending ?? false)
            }
        }
        let ascending = UIAction(title: "Ascending", state: sortDescending ? .off : .on) { [weak self] _ in
            self?.updateSortOrder(key: self?.sortKey ?? "none", descending: false)
        }
        let descending = UIAction(title: "Descending", state: sortDescending ? .on : .off) { [weak self] _ in
            self?.updateSortOrder(key: self?.sortKey ?? "none", descending: true)
        }
        return UIMenu(title: "Sort By", children: [
            UIMenu(options: .displayInline, children: [
                keyAction("id", "Sort by ID"),
                keyAction("type", "Sort by Type"),
                keyAction("none", "Document Order"),
            ]),
            UIMenu(options: .displayInline, children: [ascending, descending]),
        ])
    }

    private func updateSortOrder(key: String, descending: Bool) {
        sortKey = key
        sortDescending = descending
        UserDefaults.standard.set(sortKey, forKey: "azulSortKey")
        UserDefaults.standard.set(sortDescending, forKey: "azulSortDescending")
        applySortOrderToDataManager()
        sortButton.menu = makeSortMenu()
        rebuildFlatItems()
    }

    private func applySortOrderToDataManager() {
        sortKey.withCString { pointer in
            dataManager.setSortOrder(key: pointer, descending: sortDescending)
        }
    }

    // MARK: - Type filtering

    @objc func showTypeFilter() {
        let picker = TypeFilterViewController()
        let counts = (dataManager.availableObjectTypesWithCounts() as? [String: NSNumber]) ?? [:]
        picker.availableTypes = counts
            .map { (name: $0.key, count: $0.value.intValue) }
            .sorted { $0.name < $1.name }
        picker.selectedTypes = selectedTypes
        picker.delegate = self
        let nav = UINavigationController(rootViewController: picker)
        nav.preferredContentSize = picker.preferredContentSize
        present(nav, animated: true)
    }

    private func applyTypeFilter() {
        dataManager.setObjectTypeFilter(selectedTypes.sorted())
        filterButton.image = UIImage(systemName: selectedTypes.isEmpty
            ? "line.3.horizontal.decrease.circle"
            : "line.3.horizontal.decrease.circle.fill")
        rebuildFlatItems()
    }

    private func appendFlattened(_ item: AzulObjectIterator) {
        allFlatItems.append(item)
        if expandedItems.contains(item), dataManager.isItemExpandable(item) {
            let childCount = dataManager.numberOfChildren(ofItem: item)
            for i in 0..<childCount {
                let child = dataManager.child(ofItem: item, at: i) as! AzulObjectIterator
                child.depth = item.depth + 1
                appendFlattened(child)
            }
        }
    }

    func toggleExpandItem(_ item: AzulObjectIterator) {
        if expandedItems.contains(item) {
            expandedItems.remove(item)
        } else {
            expandedItems.insert(item)
        }
        rebuildFlatItems()
    }

    private func applyFilter() {
        let rawText = searchController.searchBar.text ?? ""
        let query = rawText.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty {
            filteredFlatItems = allFlatItems
        } else {
            filteredFlatItems = allFlatItems.filter { item in
                let type = (dataManager.type(ofItem: item) ?? "").lowercased()
                let ident = (dataManager.identifier(ofItem: item) ?? "").lowercased()
                if type.contains(query) || ident.contains(query) {
                    return true
                }
                let attrCount = Int(dataManager.numberOfAttributes(ofItem: item))
                for i in 0..<attrCount {
                    let key = (dataManager.attributeKey(ofItem: item, at: i) ?? "").lowercased()
                    let value = (dataManager.attributeValue(ofItem: item, at: i) ?? "").lowercased()
                    if key.contains(query) || value.contains(query) {
                        return true
                    }
                }
                return false
            }
        }
        tableView.reloadData()
    }
}

extension ObjectListViewController: UISearchResultsUpdating {
    func updateSearchResults(for searchController: UISearchController) {
        applyFilter()
    }
}

extension ObjectListViewController: TypeFilterPickerDelegate {
    func typeFilterPicker(_ picker: TypeFilterViewController, didUpdateSelectedTypes selected: Set<String>) {
        selectedTypes = selected
        applyTypeFilter()
    }
}

extension ObjectListViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        filteredFlatItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = filteredFlatItems[indexPath.row]

        let typeName = dataManager.type(ofItem: item) ?? ""
        let identifier = dataManager.identifier(ofItem: item) ?? ""
        let hasChildren = dataManager.isItemExpandable(item)
        let visible = dataManager.visibleState(ofItem: item)

        let image: UIImage? = {
            let isFile = item.depth == 0
            if isFile {
                let fileExtension = (identifier as NSString).pathExtension
                return UIImage(systemName: sfSymbolForFileExtension(fileExtension))
            } else if let icon = UIImage(named: typeName) {
                return icon
            } else {
                // CityGML uses the class names for a few types whose icons
                // follow the CityJSON names
                let gmlAlias = ["ReliefFeature": "TINRelief", "Square": "TransportSquare"]
                return UIImage(named: gmlAlias[typeName] ?? "")
                    ?? UIImage(systemName: "cube.transparent")
            }
        }()

        var displayText = typeName
        if !identifier.isEmpty {
            displayText += " — \(identifier)"
        }

        var config = cell.defaultContentConfiguration()
        config.text = displayText
        config.textProperties.font = .systemFont(ofSize: UIFont.smallSystemFontSize)
        config.textProperties.color = .label
        config.image = image
        config.imageProperties.tintColor = .systemGray
        config.imageToTextPadding = 6
        cell.contentConfiguration = config

        cell.indentationLevel = Int(item.depth)
        cell.indentationWidth = 16
        cell.selectionStyle = .default
        cell.backgroundColor = .secondarySystemBackground

        if hasChildren {
            cell.accessoryType = .none
            let switchView = UISwitch()
            switchView.isOn = visible != 78 // 'N' (on for 'Y' and 'P')
            switchView.addTarget(self, action: #selector(visibilityToggled(_:)), for: .valueChanged)
            cell.accessoryView = switchView
        } else {
            cell.accessoryType = .none
            if let sel = selectedItem, sel == item {
                cell.accessoryType = .checkmark
                cell.accessoryView = nil
            } else {
                let switchView = UISwitch()
                switchView.isOn = visible != 78 // 'N'
                switchView.addTarget(self, action: #selector(visibilityToggled(_:)), for: .valueChanged)
                cell.accessoryView = switchView
            }
        }

        return cell
    }

    @objc func visibilityToggled(_ sender: UISwitch) {
        let point = sender.convert(CGPoint.zero, to: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point),
              indexPath.row < filteredFlatItems.count else { return }
        let item = filteredFlatItems[indexPath.row]
        let newState: Int8 = sender.isOn ? 89 : 78 // 'Y' : 'N'
        dataManager.setVisibleState(newState, forItem: item)
        rebuildFlatItems()
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = filteredFlatItems[indexPath.row]

        if dataManager.isItemExpandable(item) {
            toggleExpandItem(item)
        } else {
            selectedItem = item
            tableView.reloadData()
            delegate?.objectListDidSelectItem(item)
        }
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        let item = filteredFlatItems[indexPath.row]

        let previewProvider: UIContextMenuContentPreviewProvider? = {
            guard !self.dataManager.isItemExpandable(item) else { return nil }
            let attrsVC = AttributeTableViewController()
            attrsVC.dataManager = self.dataManager
            let ident = self.dataManager.identifier(ofItem: item) ?? ""
            attrsVC.title = ident.isEmpty ? (self.dataManager.type(ofItem: item) ?? "") : ident
            attrsVC.selectedItem = item
            attrsVC.tableView.reloadData()
            attrsVC.isPreview = true
            return attrsVC
        }

        return UIContextMenuConfiguration(identifier: nil, previewProvider: previewProvider) { [weak self] _ in
            guard let self = self else { return UIMenu() }
            var actions = [UIAction]()

            if self.dataManager.isItemExpandable(item) {
                let title = self.expandedItems.contains(item) ? "Collapse" : "Expand"
                actions.append(UIAction(title: title, image: UIImage(systemName: "chevron.down")) { _ in
                    self.toggleExpandItem(item)
                })
            } else {
                let visible = self.dataManager.visibleState(ofItem: item)
                let isVisible = visible != 78 // 'N'
                let visTitle = isVisible ? "Hide" : "Show"
                let visImage = isVisible ? "eye.slash" : "eye"
                actions.append(UIAction(title: visTitle, image: UIImage(systemName: visImage)) { _ in
                    let newState: Int8 = isVisible ? 78 : 89 // 'N' : 'Y'
                    self.dataManager.setVisibleState(newState, forItem: item)
                    self.rebuildFlatItems()
                })

                actions.append(UIAction(title: "Attributes", image: UIImage(systemName: "info.circle")) { _ in
                    self.selectedItem = item
                    self.tableView.reloadData()
                    self.delegate?.objectListDidSelectItem(item)
                })
            }

            actions.append(UIAction(title: "Select and centre", image: UIImage(systemName: "location")) { _ in
                self.delegate?.objectListDidRequestCenter(item)
                if !self.isSidebar {
                    self.dismiss(animated: true)
                }
            })

            return UIMenu(title: "", children: actions)
        }
    }
}

private func sfSymbolForFileExtension(_ ext: String) -> String {
    "doc"
}
