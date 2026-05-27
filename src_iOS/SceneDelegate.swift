import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        let mainVC = MainViewController()
        let window = UIWindow(windowScene: windowScene)

        if UIDevice.current.userInterfaceIdiom == .pad {
            let objectsVC = ObjectListViewController()
            objectsVC.dataManager = mainVC.dataManager
            objectsVC.delegate = mainVC
            objectsVC.title = "Objects"
            objectsVC.isSidebar = true

            let sidebarNav = UINavigationController(rootViewController: objectsVC)
            let detailNav = UINavigationController(rootViewController: mainVC)
            detailNav.isNavigationBarHidden = true

            let splitVC = UISplitViewController(style: .doubleColumn)
            splitVC.preferredPrimaryColumnWidth = 300
            splitVC.minimumPrimaryColumnWidth = 260
            splitVC.maximumPrimaryColumnWidth = 400
            splitVC.presentsWithGesture = true
            splitVC.setViewController(sidebarNav, for: .primary)
            splitVC.setViewController(detailNav, for: .secondary)

            window.rootViewController = splitVC
        } else {
            window.rootViewController = mainVC
        }

        self.window = window
        window.makeKeyAndVisible()

        if let urlContext = connectionOptions.urlContexts.first {
            mainVC.loadFile(url: urlContext.url)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let url = URLContexts.first?.url else { return }
        if let splitVC = window?.rootViewController as? UISplitViewController,
           let detailNav = splitVC.viewController(for: .secondary) as? UINavigationController,
           let mainVC = detailNav.viewControllers.first as? MainViewController {
            mainVC.loadFile(url: url)
        } else if let mainVC = window?.rootViewController as? MainViewController {
            mainVC.loadFile(url: url)
        }
    }
}
