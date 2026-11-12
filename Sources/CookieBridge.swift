import Foundation
import WebKit

/// WKWebView 的 Cookie 写入/读取。
enum WKWebViewCookieBridge {
    static func store(_ cookie: HTTPCookie, completion: @escaping () -> Void) {
        let s = WKWebsiteDataStore.default().httpCookieStore
        s.setCookie(cookie) {
            // 同步一份到 NSHTTPCookieStorage，URLSession 侧也认得
            HTTPCookieStorage.shared.setCookie(cookie)
            completion()
        }
    }

    static func all(_ completion: @escaping ([HTTPCookie]) -> Void) {
        WKWebsiteDataStore.default().httpCookieStore.getAllCookies { cookies in
            completion(cookies)
        }
    }

    static func clear(_ completion: @escaping () -> Void) {
        let store = WKWebsiteDataStore.default()
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        store.removeData(ofTypes: types, modifiedSince: Date(timeIntervalSince1970: 0)) {
            completion()
        }
    }
}
