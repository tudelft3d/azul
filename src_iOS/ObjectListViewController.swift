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

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        tableView.addGestureRecognizer(longPress)

        rebuildFlatItems()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        rebuildFlatItems()
    }

    @objc func dismissSelf() {
        dismiss(animated: true)
    }

    func rebuildFlatItems() {
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

    @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let point = gesture.location(in: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point),
              indexPath.row < filteredFlatItems.count else { return }
        let item = filteredFlatItems[indexPath.row]

        if dataManager.isItemExpandable(item) {
            selectedItem = item
            tableView.reloadData()
            delegate?.objectListDidSelectItem(item)
        }
        delegate?.objectListDidRequestCenter(item)
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

        let isFile = item.depth == 0
        if isFile {
            let fileExtension = (identifier as NSString).pathExtension
            cell.imageView?.image = UIImage(systemName: sfSymbolForFileExtension(fileExtension))
            cell.imageView?.tintColor = .systemGray
        } else {
            if let icon = UIImage(named: typeName) {
                cell.imageView?.image = icon
            } else {
                cell.imageView?.image = UIImage(systemName: "cube.transparent")
                cell.imageView?.tintColor = .systemGray
            }
        }

        var displayText = typeName
        if !identifier.isEmpty {
            displayText += " — \(identifier)"
        }
        cell.textLabel?.text = displayText
        cell.textLabel?.font = .systemFont(ofSize: UIFont.smallSystemFontSize)
        cell.textLabel?.textColor = .label

        if hasChildren {
            cell.accessoryType = .disclosureIndicator
            cell.accessoryView = nil
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

        cell.backgroundColor = .secondarySystemBackground
        cell.indentationLevel = Int(item.depth)
        cell.indentationWidth = 16
        cell.selectionStyle = .default

        return cell
    }

    @objc func visibilityToggled(_ sender: UISwitch) {
        let point = sender.convert(CGPoint.zero, to: tableView)
        guard let indexPath = tableView.indexPathForRow(at: point),
              indexPath.row < filteredFlatItems.count else { return }
        let item = filteredFlatItems[indexPath.row]
        let newState: Int8 = sender.isOn ? 89 : 78 // 'Y' : 'N'
        dataManager.setVisibleState(newState, forItem: item)
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
}

private func sfSymbolForFileExtension(_ ext: String) -> String {
    "doc"
}
