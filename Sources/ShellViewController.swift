import UIKit
import WebKit

final class ShellViewController: UIViewController {

    private let store = ServerStore.shared
    private let unlock = UnlockClient()
    private var webView: WKWebView!
    private var toolbar: UIToolbar!
    private var backItem: UIBarButtonItem!
    private var forwardItem: UIBarButtonItem!
    private var reloadItem: UIBarButtonItem!
    private var layoutItem: UIBarButtonItem!

    private var overlay: UIView!
    private var overlayTitle: UILabel!
    private var overlayDetail: UILabel!
    private var spinner: UIActivityIndicatorView!
    private var retryButton: UIButton!
    private var connecting = false
    private var lastError: String?
    private var settingsShown = false
    private var downloadDests: [ObjectIdentifier: URL] = [:]

    override var preferredStatusBarStyle: UIStatusBarStyle { .default }

    // MARK: - 生命周期

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        buildWebView()
        buildToolbar()
        buildOverlay()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if store.hasBase {
            if webView.url == nil { connect() }
        } else if !settingsShown {
            settingsShown = true
            presentSettings(firstRun: true)
        }
    }

    // MARK: - 构建

    private func buildWebView() {
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.preferences.javaScriptCanOpenWindowsAutomatically = true
        cfg.websiteDataStore = .default()
        cfg.defaultWebpagePreferences.allowsContentJavaScript = true

        webView = WKWebView(frame: .zero, configuration: cfg)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.keyboardDismissMode = .interactive
        webView.isOpaque = false
        webView.backgroundColor = .systemBackground
        webView.scrollView.backgroundColor = .systemBackground
        view.addSubview(webView)

        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            webView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
        ])
    }

    private func buildToolbar() {
        toolbar = UIToolbar()
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        backItem = UIBarButtonItem(image: UIImage(systemName: "chevron.left"), style: .plain, target: self, action: #selector(goBack))
        forwardItem = UIBarButtonItem(image: UIImage(systemName: "chevron.right"), style: .plain, target: self, action: #selector(goForward))
        reloadItem = UIBarButtonItem(image: UIImage(systemName: "arrow.clockwise"), style: .plain, target: self, action: #selector(reload))
        layoutItem = UIBarButtonItem(image: UIImage(systemName: "rectangle.split.2x1"), style: .plain, target: self, action: #selector(cycleLayout))
        let settingsItem = UIBarButtonItem(image: UIImage(systemName: "slider.horizontal.3"), style: .plain, target: self, action: #selector(openSettings))
        let flex = { () -> UIBarButtonItem in
            UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        }

        toolbar.items = [backItem, flex(), forwardItem, flex(), reloadItem, flex(), layoutItem, flex(), settingsItem]
        view.addSubview(toolbar)

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            webView.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
        ])
        updateButtons()
    }

    private func buildOverlay() {
        overlay = UIView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = .systemBackground
        overlay.isHidden = false
        view.addSubview(overlay)
        NSLayoutConstraint.activate([
            overlay.topAnchor.constraint(equalTo: webView.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: toolbar.topAnchor),
        ])

        spinner = UIActivityIndicatorView(style: .medium)
        spinner.translatesAutoresizingMaskIntoConstraints = false
        spinner.startAnimating()

        overlayTitle = UILabel()
        overlayTitle.translatesAutoresizingMaskIntoConstraints = false
        overlayTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        overlayTitle.textAlignment = .center
        overlayTitle.numberOfLines = 0
        overlayTitle.text = "连接中…"

        overlayDetail = UILabel()
        overlayDetail.translatesAutoresizingMaskIntoConstraints = false
        overlayDetail.font = .systemFont(ofSize: 13)
        overlayDetail.textColor = .secondaryLabel
        overlayDetail.textAlignment = .center
        overlayDetail.numberOfLines = 0

        retryButton = UIButton(type: .system)
        retryButton.translatesAutoresizingMaskIntoConstraints = false
        retryButton.setTitle("重试", for: .normal)
        retryButton.titleLabel?.font = .systemFont(ofSize: 15, weight: .semibold)
        retryButton.addTarget(self, action: #selector(connectTapped), for: .touchUpInside)
        retryButton.isHidden = true

        let stack = UIStackView(arrangedSubviews: [spinner, overlayTitle, overlayDetail, retryButton])
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 12
        overlay.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: overlay.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: overlay.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: overlay.leadingAnchor, constant: 32),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: overlay.trailingAnchor, constant: -32),
        ])
    }

    // MARK: - 连接

    @objc private func connectTapped() { connect() }

    private func connect() {
        guard store.hasBase else { presentSettings(firstRun: true); return }
        guard !connecting else { return }
        connecting = true
        showOverlay("连接中…", detail: store.base, spinner: true, retry: false)

        // 布局/缩放可能在设置里改过，先装脚本再加载
        installScripts()

        unlock.probe(base: store.base) { [weak self] p in
            DispatchQueue.main.async {
                guard let self = self else { return }
                guard p.online else {
                    self.connecting = false
                    self.showOverlay("连不上", detail: p.error ?? "检查地址与网络", spinner: false, retry: true)
                    return
                }
                guard p.hasPassword else {
                    self.loadStart()
                    return
                }
                guard !self.store.password.isEmpty else {
                    // 本地没存密码：直接放行，页面侧会出密码页，用户在那里填
                    self.flash("在页面里输入访问密码")
                    self.loadStart()
                    return
                }
                self.unlock.unlock(base: self.store.base, password: self.store.password) { r in
                    DispatchQueue.main.async {
                        switch r {
                        case .ok(let line):
                            let host = URL(string: self.store.base)?.host ?? ""
                            UnlockClient.install(cookieLine: line, host: host) {
                                DispatchQueue.main.async { self.loadStart() }
                            }
                        case .notRequired:
                            self.loadStart()
                        case .badPassword:
                            self.connecting = false
                            self.showOverlay("密码不对", detail: "点设置重新填写", spinner: false, retry: true)
                        case .failed(let msg):
                            self.connecting = false
                            self.showOverlay("解锁失败", detail: msg, spinner: false, retry: true)
                        }
                    }
                }
            }
        }
    }

    private func loadStart() {
        guard let url = store.startURL else {
            connecting = false
            showOverlay("地址无效", detail: "点设置检查地址", spinner: false, retry: true)
            return
        }
        showOverlay("加载中…", detail: url.absoluteString, spinner: true, retry: false)
        webView.load(URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 25))
    }

    private func installScripts() {
        let ucc = webView.configuration.userContentController
        ucc.removeAllUserScripts()
        let start = WKUserScript(source: PageInject.documentStart(layout: store.layout),
                                 injectionTime: .atDocumentStart,
                                 forMainFrameOnly: true)
        ucc.addUserScript(start)
    }

    private func applyZoom() {
        webView.evaluateJavaScript(PageInject.zoom(store.scale), completionHandler: nil)
    }

    // MARK: - 覆盖层

    private func showOverlay(_ title: String, detail: String, spinner on: Bool, retry: Bool) {
        overlayTitle.text = title
        overlayDetail.text = detail
        retryButton.isHidden = !retry
        overlay.isHidden = false
        if on { self.spinner.startAnimating() } else { self.spinner.stopAnimating() }
        self.spinner.isHidden = !on
    }

    private func hideOverlay() {
        overlay.isHidden = true
    }

    // MARK: - 动作

    @objc private func goBack() { webView.goBack() }
    @objc private func goForward() { webView.goForward() }

    @objc private func reload() {
        if webView.url == nil { connect() } else { webView.reload() }
    }

    @objc private func cycleLayout() {
        switch store.layout {
        case ServerStore.layoutAuto: store.layout = ServerStore.layoutMobile
        case ServerStore.layoutMobile: store.layout = ServerStore.layoutDesktop
        default: store.layout = ServerStore.layoutAuto
        }
        installScripts()
        if webView.url != nil { webView.reload() }
        flash("布局：\(layoutName())")
    }

    private func layoutName() -> String {
        switch store.layout {
        case ServerStore.layoutMobile: return "手机"
        case ServerStore.layoutDesktop: return "电脑"
        default: return "自动"
        }
    }

    @objc private func openSettings() { presentSettings(firstRun: false) }

    private func presentSettings(firstRun: Bool) {
        let vc = SettingsViewController()
        let nav = UINavigationController(rootViewController: vc)
        nav.modalPresentationStyle = .formSheet
        vc.onDone = { [weak self, weak nav] save in
            nav?.dismiss(animated: true) {
                guard let self = self else { return }
                if save {
                    self.connecting = false
                    self.installScripts()
                    self.connect()
                } else if firstRun && !self.store.hasBase {
                    self.showOverlay("先填服务器地址", detail: "点下方按钮或右上角设置", spinner: false, retry: true)
                }
            }
        }
        present(nav, animated: true)
    }

    private func flash(_ text: String) {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.backgroundColor = UIColor.black.withAlphaComponent(0.75)
        label.textAlignment = .center
        label.layer.cornerRadius = 8
        label.clipsToBounds = true
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: toolbar.topAnchor, constant: -16),
            label.heightAnchor.constraint(equalToConstant: 32),
            label.widthAnchor.constraint(greaterThanOrEqualToConstant: 120),
        ])
        label.alpha = 0
        UIView.animate(withDuration: 0.18, animations: { label.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.3, delay: 1.1, animations: { label.alpha = 0 }) { _ in
                label.removeFromSuperview()
            }
        }
    }

    private func updateButtons() {
        backItem.isEnabled = webView.canGoBack
        forwardItem.isEnabled = webView.canGoForward
    }
}

// MARK: - WKNavigationDelegate

extension ShellViewController: WKNavigationDelegate {

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        updateButtons()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        connecting = false
        lastError = nil
        hideOverlay()
        updateButtons()
        applyZoom()
        if let u = webView.url, u.scheme?.hasPrefix("http") == true {
            let path = u.path.isEmpty ? "/" : u.path
            store.lastPath = path + (u.query.map { "?\($0)" } ?? "")
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        failLoad(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        failLoad(error)
    }

    private func failLoad(_ error: Error) {
        let ns = error as NSError
        if ns.code == NSURLErrorCancelled { return }
        connecting = false
        updateButtons()
        showOverlay("页面加载失败", detail: ns.localizedDescription, spinner: false, retry: true)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }
        let scheme = (url.scheme ?? "").lowercased()
        if scheme == "http" || scheme == "https" || scheme == "about" || scheme == "data" {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
            return
        }
        if scheme == "file" {
            decisionHandler(.cancel)
            return
        }
        // tel:/mailto:/weixin: 交给系统
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.canShowMIMEType {
            decisionHandler(.allow)
        } else {
            decisionHandler(.download)
        }
    }

    @available(iOS 14.5, *)
    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    @available(iOS 14.5, *)
    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    @available(iOS 15.0, *)
    func webView(_ webView: WKWebView,
                 requestMediaCapturePermissionFor origin: WKSecurityOrigin,
                 initiatedByFrame frame: WKFrameInfo,
                 type: WKMediaCaptureType,
                 decisionHandler: @escaping (WKPermissionDecision) -> Void) {
        // 语音输入 / 拍照上传 —— 页面内的 getUserMedia
        decisionHandler(.grant)
    }
}

// MARK: - WKUIDelegate

extension ShellViewController: WKUIDelegate {

    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        // 站内的 window.open / target=_blank 一律在当前视图里打开
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webViewDidClose(_ webView: WKWebView) {}

    func webView(_ webView: WKWebView,
                 runJavaScriptAlertPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping () -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default) { _ in completionHandler() })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptConfirmPanelWithMessage message: String,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (Bool) -> Void) {
        let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(false) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in completionHandler(true) })
        present(alert, animated: true)
    }

    func webView(_ webView: WKWebView,
                 runJavaScriptTextInputPanelWithPrompt prompt: String,
                 defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo,
                 completionHandler: @escaping (String?) -> Void) {
        let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
        alert.addTextField { $0.text = defaultText }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel) { _ in completionHandler(nil) })
        alert.addAction(UIAlertAction(title: "确定", style: .default) { _ in
            completionHandler(alert.textFields?.first?.text)
        })
        present(alert, animated: true)
    }
}

// MARK: - WKDownloadDelegate

extension ShellViewController: WKDownloadDelegate {

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("dshgo-downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = dir.appendingPathComponent(suggestedFilename)
        try? FileManager.default.removeItem(at: dest)
        self.downloadDests[ObjectIdentifier(download)] = dest
        completionHandler(dest)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadDests[ObjectIdentifier(download)] else { return }
        downloadDests[ObjectIdentifier(download)] = nil
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        sheet.popoverPresentationController?.sourceView = view
        sheet.popoverPresentationController?.sourceRect = CGRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1)
        present(sheet, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        flash("下载失败：\(error.localizedDescription)")
    }
}
