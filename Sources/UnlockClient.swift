import Foundation

/// 宿主（dshgo 插件）的访问闸门。
///
/// 契约来自 lib/gate.mjs + lib/auth.mjs：
/// - GET  /__dshgo__/auth/status  → {"hasPassword": Bool}        （白名单，免解锁）
/// - POST /__dshgo__/unlock       → 200 + Set-Cookie: dshgo-unlock=… / 401 密码错 / 404 没设密码
/// - GET  /__dshgo__/info         → {"name":"dshgo","version":…,"listening":…,"upstreamPort":…}
///
/// UA 带 `DSHGo` 时闸门才当成 App，返回 JSON 而不是 HTML 密码页。
final class UnlockClient {

    static let ua = "DSHGo/4.4.3 (iOS)"
    static let cookieName = "dshgo-unlock"

    struct Probe {
        var online = false
        var version = ""
        var listening = false
        var upstreamPort = 0
        var hasPassword = false
        var error: String?
    }

    enum Unlock {
        case notRequired
        case ok(cookie: String)
        case badPassword
        case failed(String)
    }

    private let session: URLSession

    init() {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 8
        cfg.timeoutIntervalForResource = 10
        cfg.httpShouldSetCookies = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: cfg)
    }

    private func request(_ url: URL, method: String = "GET", json: [String: Any]? = nil) -> URLRequest {
        var r = URLRequest(url: url)
        r.httpMethod = method
        r.setValue(UnlockClient.ua, forHTTPHeaderField: "User-Agent")
        r.setValue("application/json", forHTTPHeaderField: "Accept")
        if let json = json {
            r.setValue("application/json", forHTTPHeaderField: "Content-Type")
            r.httpBody = try? JSONSerialization.data(withJSONObject: json)
        }
        return r
    }

    // MARK: - 探测

    func probe(base: String, completion: @escaping (Probe) -> Void) {
        var p = Probe()
        guard let infoURL = URL(string: base + "/__dshgo__/info") else {
            p.error = "地址格式不对"
            completion(p)
            return
        }
        let started = Date()

        session.dataTask(with: request(infoURL)) { data, resp, err in
            if let err = err {
                p.error = err.localizedDescription
                completion(p)
                return
            }
            guard let http = resp as? HTTPURLResponse, let data = data,
                  let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                p.error = "这个地址上没有 dshgo"
                completion(p)
                return
            }
            _ = started
            guard (obj["name"] as? String) == "dshgo" else {
                p.error = "这个地址上不是 dshgo"
                completion(p)
                return
            }
            p.online = true
            p.version = obj["version"] as? String ?? ""
            p.listening = obj["listening"] as? Bool ?? false
            p.upstreamPort = obj["upstreamPort"] as? Int ?? 0
            _ = http

            // 密码状态是第二个端点，失败不影响「在线」判断。
            guard let stURL = URL(string: base + "/__dshgo__/auth/status") else {
                completion(p)
                return
            }
            self.session.dataTask(with: self.request(stURL)) { d2, _, _ in
                if let d2 = d2,
                   let o2 = (try? JSONSerialization.jsonObject(with: d2)) as? [String: Any] {
                    p.hasPassword = o2["hasPassword"] as? Bool ?? false
                }
                completion(p)
            }.resume()
        }.resume()
    }

    // MARK: - 解锁

    func unlock(base: String, password: String, completion: @escaping (Unlock) -> Void) {
        guard let url = URL(string: base + "/__dshgo__/unlock") else {
            completion(.failed("地址格式不对"))
            return
        }
        session.dataTask(with: request(url, method: "POST", json: ["password": password])) { data, resp, err in
            if let err = err {
                completion(.failed(err.localizedDescription))
                return
            }
            guard let http = resp as? HTTPURLResponse else {
                completion(.failed("没有响应"))
                return
            }
            switch http.statusCode {
            case 200:
                var raw: [String] = []
                for (k, v) in http.allHeaderFields {
                    if String(describing: k).lowercased() == "set-cookie" {
                        raw.append(String(describing: v))
                    }
                }
                let hit = raw.first { $0.hasPrefix(UnlockClient.cookieName + "=") }
                guard let line = hit else {
                    completion(.failed("宿主没有回解锁凭据"))
                    return
                }
                completion(.ok(cookie: String(line.split(separator: ";", maxSplits: 1).first ?? "")))
            case 401:
                completion(.badPassword)
            case 404:
                completion(.notRequired)
            default:
                completion(.failed("宿主返回 HTTP \(http.statusCode)"))
            }
        }.resume()
    }

    /// 把 name=value 写进 WKWebView 的 cookie store —— 真正的页面请求由 WebKit 发，
    /// 不写进去就会出现「App 说解锁成功、页面还是密码页」。
    static func install(cookieLine: String, host: String, completion: @escaping () -> Void) {
        let parts = cookieLine.split(separator: "=", maxSplits: 1).map { String($0) }
        guard parts.count == 2 else { completion(); return }
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: parts[0],
            .value: parts[1],
            .path: "/",
            .domain: host,
            .expires: Date().addingTimeInterval(30 * 24 * 3600),
        ]
        if let c = HTTPCookie(properties: props) {
            WKWebViewCookieBridge.store(c, completion: completion)
        } else {
            props[.domain] = nil
            if let c = HTTPCookie(properties: props) {
                WKWebViewCookieBridge.store(c, completion: completion)
            } else {
                completion()
            }
        }
    }
}
