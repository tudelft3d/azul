import UIKit

class AttributeTableViewController: UIViewController {

    var dataManager: DataManagerWrapperWrapper!
    var selectedItem: AzulObjectIterator?
    var isPreview: Bool = false

    let tableView = UITableView(frame: .zero, style: .plain)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Attributes"
        view.backgroundColor = .systemBackground

        tableView.delegate = self
        tableView.dataSource = self
        tableView.register(AttributeCell.self, forCellReuseIdentifier: "cell")
        tableView.separatorStyle = .singleLine
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)

        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        if UIDevice.current.userInterfaceIdiom == .pad {
            preferredContentSize = CGSize(width: 400, height: 500)
        }

        if !isPreview && UIDevice.current.userInterfaceIdiom != .pad {
            navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissSelf))
        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if UIDevice.current.userInterfaceIdiom == .pad && !isPreview {
            navigationController?.setNavigationBarHidden(false, animated: animated)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if UIDevice.current.userInterfaceIdiom == .pad && !isPreview {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }

    @objc func dismissSelf() {
        dismiss(animated: true)
    }

    func showAttributes(for item: AzulObjectIterator) {
        selectedItem = item
        let ident = dataManager.identifier(ofItem: item) ?? ""
        title = ident.isEmpty
            ? (dataManager.type(ofItem: item) ?? "")
            : ident
        tableView.reloadData()
    }
}

class AttributeCell: UITableViewCell {
    let keyLabel = UILabel()
    let valueLabel = UILabel()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)

        keyLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        keyLabel.textColor = .systemGray
        valueLabel.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        valueLabel.textColor = .label
        valueLabel.numberOfLines = 0

        contentView.addSubview(keyLabel)
        contentView.addSubview(valueLabel)
        keyLabel.translatesAutoresizingMaskIntoConstraints = false
        valueLabel.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            keyLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            keyLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            keyLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),

            valueLabel.topAnchor.constraint(equalTo: keyLabel.bottomAnchor, constant: 2),
            valueLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            valueLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            valueLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])

        backgroundColor = .secondarySystemBackground
        selectionStyle = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(key: String, value: String) {
        keyLabel.text = key
        valueLabel.text = value

        if Double(value) != nil {
            valueLabel.font = .monospacedSystemFont(ofSize: 15, weight: .regular)
        } else {
            valueLabel.font = .systemFont(ofSize: 15, weight: .regular)
        }
    }
}

extension AttributeTableViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let item = selectedItem else { return 0 }
        return Int(dataManager.numberOfAttributes(ofItem: item))
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath) as! AttributeCell
        guard let item = selectedItem else { return cell }

        let key = dataManager.attributeKey(ofItem: item, at: indexPath.row) ?? ""
        let value = dataManager.attributeValue(ofItem: item, at: indexPath.row) ?? ""
        cell.configure(key: key, value: value)
        return cell
    }

    func tableView(_ tableView: UITableView, contextMenuConfigurationForRowAt indexPath: IndexPath, point: CGPoint) -> UIContextMenuConfiguration? {
        guard let item = selectedItem else { return nil }
        let key = dataManager.attributeKey(ofItem: item, at: indexPath.row) ?? ""
        let value = dataManager.attributeValue(ofItem: item, at: indexPath.row) ?? ""

        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in
            let copyKey = UIAction(title: "Copy Key", image: UIImage(systemName: "doc.on.clipboard")) { _ in
                UIPasteboard.general.string = key
            }
            let copyValue = UIAction(title: "Copy Value", image: UIImage(systemName: "doc.on.clipboard")) { _ in
                UIPasteboard.general.string = value
            }
            return UIMenu(title: "", children: [copyKey, copyValue])
        }
    }
}
