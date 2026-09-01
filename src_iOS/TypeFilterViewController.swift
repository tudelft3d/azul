import UIKit

protocol TypeFilterPickerDelegate: AnyObject {
    func typeFilterPicker(_ picker: TypeFilterViewController, didUpdateSelectedTypes selected: Set<String>)
}

/// Multi-select picker for the object type filter. Toggles apply live through
/// the delegate; an empty selection means all types are shown.
class TypeFilterViewController: UIViewController {

    weak var delegate: TypeFilterPickerDelegate?
    var availableTypes: [(name: String, count: Int)] = []
    var selectedTypes: Set<String> = []

    private let cellReuseId = "cell"

    let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Object Type Filter"
        view.backgroundColor = .systemBackground

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: cellReuseId)
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        if UIDevice.current.userInterfaceIdiom == .pad {
            preferredContentSize = CGSize(width: 300, height: min(CGFloat(availableTypes.count + 2) * 44 + 44, 400))
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissSelf))
    }

    @objc func dismissSelf() {
        dismiss(animated: true)
    }
}

extension TypeFilterViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        availableTypes.count + 1
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseId, for: indexPath)
        if indexPath.row == 0 {
            cell.textLabel?.text = "All Types"
            cell.imageView?.image = UIImage(systemName: "square.grid.2x2")
            cell.accessoryType = selectedTypes.isEmpty ? .checkmark : .none
        } else {
            let type = availableTypes[indexPath.row - 1]
            cell.textLabel?.text = "\(type.name) (\(type.count))"
            cell.imageView?.image = UIImage(named: type.name) ?? UIImage(systemName: "cube.transparent")
            cell.imageView?.tintColor = .systemGray
            cell.accessoryType = selectedTypes.contains(type.name) ? .checkmark : .none
        }
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.row == 0 {
            selectedTypes.removeAll()
        } else {
            let type = availableTypes[indexPath.row - 1].name
            if selectedTypes.contains(type) {
                selectedTypes.remove(type)
            } else {
                selectedTypes.insert(type)
            }
        }
        delegate?.typeFilterPicker(self, didUpdateSelectedTypes: selectedTypes)
        tableView.reloadData()
    }
}
