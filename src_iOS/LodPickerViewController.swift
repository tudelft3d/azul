import UIKit

protocol LodPickerDelegate: AnyObject {
    func lodPickerDidSelect(_ lod: String)
}

class LodPickerViewController: UIViewController {

    weak var delegate: LodPickerDelegate?
    var availableLods: [String] = []
    var currentLod: String = ""

    private let cellReuseId = "cell"

    private var allItems: [(name: String, lod: String, icon: String)] {
        var items = [(name: String, lod: String, icon: String)]()
        items.append(("Highest", "__highest__", "star"))
        for lod in availableLods {
            items.append(("LoD \(lod)", lod, "cube"))
        }
        return items
    }

    let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Level of Detail"
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
            preferredContentSize = CGSize(width: 300, height: min(CGFloat(availableLods.count + 1) * 44 + 44, 400))
        }

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissSelf))
    }

    @objc func dismissSelf() {
        dismiss(animated: true)
    }
}

extension LodPickerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        allItems.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: cellReuseId, for: indexPath)
        let item = allItems[indexPath.row]
        cell.textLabel?.text = item.name
        cell.imageView?.image = UIImage(systemName: item.icon)
        cell.imageView?.tintColor = .systemGray
        cell.accessoryType = currentLod == item.lod ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = allItems[indexPath.row]
        delegate?.lodPickerDidSelect(item.lod)
        dismiss(animated: true)
    }
}
