import UIKit

/// 连接设置：地址、访问密码、布局、缩放。
final class SettingsViewController: UIViewController {

    var onDone: ((Bool) -> Void)?   // true = 保存并连接

    private let store = ServerStore.shared
    private let scroll = UIScrollView()
    private let content = UIStackView()
    private let addressField = UITextField()
    private let passwordField = UITextField()
    private let layoutPicker = UISegmentedControl(items: ["自动", "手机", "电脑"])
    private let scaleSlider = UISlider()
    private let scaleLabel = UILabel()
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemGroupedBackground
        title = "连接"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "连接", style: .done, target: self, action: #selector(saveTapped))

        scroll.translatesAutoresizingMaskIntoConstraints = false
        content.translatesAutoresizingMaskIntoConstraints = false
        content.axis = .vertical
        content.spacing = 18
        content.isLayoutMarginsRelativeArrangement = true
        content.layoutMargins = UIEdgeInsets(top: 20, left: 20, bottom: 40, right: 20)
        view.addSubview(scroll)
        scroll.addSubview(content)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            content.topAnchor.constraint(equalTo: scroll.topAnchor),
            content.leadingAnchor.constraint(equalTo: scroll.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: scroll.trailingAnchor),
            content.widthAnchor.constraint(equalTo: scroll.widthAnchor),
            content.bottomAnchor.constraint(equalTo: scroll.bottomAnchor),
        ])

        // 地址
        addressField.placeholder = "192.168.1.100:3081"
        addressField.text = store.base
        addressField.borderStyle = .roundedRect
        addressField.keyboardType = .URL
        addressField.autocapitalizationType = .none
        addressField.autocorrectionType = .no
        addressField.clearButtonMode = .whileEditing
        addressField.returnKeyType = .next
        addressField.delegate = self

        // 密码
        passwordField.placeholder = "访问密码（没设就留空）"
        passwordField.text = store.password
        passwordField.borderStyle = .roundedRect
        passwordField.isSecureTextEntry = true
        passwordField.autocapitalizationType = .none
        passwordField.autocorrectionType = .no
        passwordField.returnKeyType = .done
        passwordField.delegate = self

        layoutPicker.selectedSegmentIndex = {
            switch store.layout {
            case ServerStore.layoutMobile: return 1
            case ServerStore.layoutDesktop: return 2
            default: return 0
            }
        }()

        scaleSlider.minimumValue = 0.7
        scaleSlider.maximumValue = 1.5
        scaleSlider.value = Float(store.scale)
        scaleSlider.addTarget(self, action: #selector(scaleChanged), for: .valueChanged)
        scaleLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .regular)
        scaleLabel.textColor = .secondaryLabel
        scaleLabel.text = String(format: "缩放 %.2fx", store.scale)

        statusLabel.font = .systemFont(ofSize: 13)
        statusLabel.textColor = .secondaryLabel
        statusLabel.numberOfLines = 0

        content.addArrangedSubview(section(title: "服务器地址", body: addressField))
        content.addArrangedSubview(hint("填 dshgo 插件监听的那个地址，例如 192.168.1.100:3081 或 Tailscale 的 100.x.y.z:3081。"))
        content.addArrangedSubview(section(title: "访问密码", body: passwordField))
        content.addArrangedSubview(section(title: "布局", body: layoutPicker))
        content.addArrangedSubview(hint("自动 = 按屏幕宽度；电脑 = 桌面布局，平板/横屏更顺手。"))

        let scaleStack = UIStackView(arrangedSubviews: [scaleSlider, scaleLabel])
        scaleStack.axis = .vertical
        scaleStack.spacing = 6
        content.addArrangedSubview(section(title: "页面缩放", body: scaleStack))

        let clear = UIButton(type: .system)
        clear.setTitle("清除 Cookie 与网页数据", for: .normal)
        clear.setTitleColor(.systemRed, for: .normal)
        clear.addTarget(self, action: #selector(clearTapped), for: .touchUpInside)
        content.addArrangedSubview(clear)

        content.addArrangedSubview(statusLabel)
    }

    private func section(title: String, body: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .secondaryLabel
        let stack = UIStackView(arrangedSubviews: [label, body])
        stack.axis = .vertical
        stack.spacing = 8
        return stack
    }

    private func hint(_ text: String) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 12)
        label.textColor = .tertiaryLabel
        label.numberOfLines = 0
        return label
    }

    @objc private func scaleChanged() {
        scaleLabel.text = String(format: "缩放 %.2fx", scaleSlider.value)
    }

    @objc private func cancelTapped() {
        onDone?(false)
    }

    @objc private func saveTapped() {
        store.base = addressField.text ?? ""
        store.password = passwordField.text ?? ""
        switch layoutPicker.selectedSegmentIndex {
        case 1: store.layout = ServerStore.layoutMobile
        case 2: store.layout = ServerStore.layoutDesktop
        default: store.layout = ServerStore.layoutAuto
        }
        store.scale = Double(scaleSlider.value)
        onDone?(true)
    }

    @objc private func clearTapped() {
        let alert = UIAlertController(title: "清除网页数据", message: "会清掉会话 cookie，下次要重新解锁。", preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "清除", style: .destructive) { _ in
            WKWebViewCookieBridge.clear {
                ServerStore.shared.wipeCookies()
                DispatchQueue.main.async {
                    self.statusLabel.text = "已清除。"
                }
            }
        })
        present(alert, animated: true)
    }

    func showStatus(_ text: String) {
        statusLabel.text = text
    }
}

extension SettingsViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        if textField === addressField {
            passwordField.becomeFirstResponder()
        } else {
            textField.resignFirstResponder()
        }
        return true
    }
}
