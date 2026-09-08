import UIKit

@UIApplicationMain
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        let info = Bundle.main.infoDictionary ?? [:]
        let apiKey = (info["API_ENCRYPTION_KEY"] as? String) ?? ""
        let wsURL = (info["WS_URL"] as? String) ?? "wss://api.tenclass.net/xiaozhi/v1/"
        let otaURL = (info["OTA_URL"] as? String) ?? "https://api.tenclass.net/xiaozhi/ota/"

        let ok = LilySharedBridge.initializeShared(
            withAPIKey: apiKey,
            wsURL: wsURL,
            otaURL: otaURL
        )

        UserDefaults.standard.set(ok, forKey: "LilyKoinInitOK")

        let root = LilyStatusViewController(initializationSucceeded: ok)
        window = UIWindow(frame: UIScreen.main.bounds)
        window?.rootViewController = UINavigationController(rootViewController: root)
        window?.makeKeyAndVisible()
        return true
    }
}

final class LilyStatusViewController: UIViewController {
    private let succeeded: Bool

    init(initializationSucceeded: Bool) {
        self.succeeded = initializationSucceeded
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = "Lily"

        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.text = "Lily"
        titleLabel.font = .preferredFont(forTextStyle: .largeTitle)

        let statusLabel = UILabel()
        statusLabel.text = succeeded
            ? "Shared.framework loaded\nKoin initialization invoked"
            : "Shared.framework initialization failed"
        statusLabel.numberOfLines = 0
        statusLabel.textAlignment = .center
        statusLabel.font = .preferredFont(forTextStyle: .body)

        let stageLabel = UILabel()
        stageLabel.text = "Stage 1 — Shared/Koin bootstrap"
        stageLabel.textColor = .secondaryLabel
        stageLabel.font = .preferredFont(forTextStyle: .footnote)

        stack.addArrangedSubview(titleLabel)
        stack.addArrangedSubview(statusLabel)
        stack.addArrangedSubview(stageLabel)
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -24),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
}
