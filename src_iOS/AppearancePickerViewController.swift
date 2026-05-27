import UIKit

protocol AppearancePickerDelegate: AnyObject {
    func appearancePickerDidSelect(type: String, theme: String)
}

class AppearancePickerViewController: UIViewController {

    weak var delegate: AppearancePickerDelegate?
    var availableThemes: [String] = []
    var currentType: String = ""
    var currentTheme: String = ""

    struct AppearanceItem {
        let title: String
        let icon: UIImage?
        let isSemantics: Bool // true for "By Type", false for themes
        let themeName: String // empty for semantics
    }

    var items: [AppearanceItem] {
        var result = [AppearanceItem]()
        let multicolorConfig = UIImage.SymbolConfiguration.preferringMulticolor()
        result.append(AppearanceItem(
            title: "By Type",
            icon: UIImage(systemName: "paintpalette.fill", withConfiguration: multicolorConfig),
            isSemantics: true,
            themeName: ""))
        for theme in availableThemes {
            let icon: UIImage?
            if theme == "Materials" {
                icon = UIImage(systemName: "paintbrush.fill")
            } else if theme == "Textures" {
                icon = UIImage(systemName: "photo.fill")
            } else {
                icon = UIImage(systemName: "paintpalette")
            }
            result.append(AppearanceItem(
                title: theme,
                icon: icon,
                isSemantics: false,
                themeName: theme))
        }
        return result
    }

    let tableView = UITableView(frame: .zero, style: .insetGrouped)

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Appearance"
        view.backgroundColor = .systemBackground

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

        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(dismissSelf))
    }

    @objc func dismissSelf() {
        dismiss(animated: true)
    }

    func isSelected(_ item: AppearanceItem) -> Bool {
        if item.isSemantics {
            return currentType == "semantics"
        }
        return currentType == "theme" && currentTheme == item.themeName
    }
}

extension AppearancePickerViewController: UITableViewDataSource, UITableViewDelegate {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        items.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell", for: indexPath)
        let item = items[indexPath.row]
        cell.textLabel?.text = item.title
        cell.imageView?.image = item.icon
        cell.imageView?.tintColor = .systemGray
        cell.accessoryType = isSelected(item) ? .checkmark : .none
        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        let item = items[indexPath.row]
        if item.isSemantics {
            delegate?.appearancePickerDidSelect(type: "semantics", theme: "")
        } else {
            delegate?.appearancePickerDidSelect(type: "theme", theme: item.themeName)
        }
        dismiss(animated: true)
    }
}
