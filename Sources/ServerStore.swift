import Foundation

/// 连接配置：服务器地址、访问密码、布局模式、缩放。
final class ServerStore {
    static let shared = ServerStore()

    private let d = UserDefaults.standard

    private enum K {
        static let base = "base"
        static let password = "password"
        static let layout = "layout"
        static let scale = "scale"
        static let lastPath = "lastPath"
    }

    static let layoutAuto = "auto"
    static let layoutMobile = "mobile"
    static let layoutDesktop = "desktop"

    var base: String {
        get { d.string(forKey: K.base) ?? "" }
        set {
            var v = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !v.isEmpty && !v.contains("://") { v = "http://" + v }
            while v.hasSuffix("/") { v.removeLast() }
            d.set(v, forKey: K.base)
        }
    }

    var hasBase: Bool { !base.isEmpty }

    var password: String {
        get { d.string(forKey: K.password) ?? "" }
        set { d.set(newValue, forKey: K.password) }
    }

    var layout: String {
        get { d.string(forKey: K.layout) ?? ServerStore.layoutAuto }
        set { d.set(newValue, forKey: K.layout) }
    }

    var scale: Double {
        get {
            let v = d.double(forKey: K.scale)
            return v <= 0 ? 1.0 : v
        }
        set { d.set(newValue, forKey: K.scale) }
    }

    /// 上次停留的路径，冷启动直接回到同一个会话页。
    var lastPath: String {
        get { d.string(forKey: K.lastPath) ?? "/" }
        set { d.set(newValue, forKey: K.lastPath) }
    }

    var startURL: URL? {
        guard hasBase else { return nil }
        let p = lastPath.hasPrefix("/") ? lastPath : "/" + lastPath
        return URL(string: base + p) ?? URL(string: base)
    }

    func wipeCookies() {
        if #available(iOS 15.0, *) {
            HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
        }
    }
}
