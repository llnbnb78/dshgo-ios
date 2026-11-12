# DSH Go for iOS

Android 版 `com.dshgo.app` 的 iOS 同构实现：原生解锁 + WKWebView 载入 DSH 页面。
代码对应上游 `xiazhi88/dshgo` 的 `android/app/src/main/java/com/dshgo/app`。

## 与 Android 版的对应关系

| Android | iOS | 说明 |
|---|---|---|
| `data/UnlockClient.kt` | `Sources/UnlockClient.swift` | `/__dshgo__/info`、`/__dshgo__/auth/status`、`POST /__dshgo__/unlock`，UA `DSHGo/4.4.3 (iOS)` |
| `data/WebViewCookies.kt` | `Sources/CookieBridge.swift` | 解锁 Cookie 写进 `WKHTTPCookieStore`（不写就会出现"App 说成功、页面还是密码页"） |
| `web/PageInject.kt` | `Sources/PageInject.swift` | polyfill + `matchMedia` 布局覆盖，改走 `WKUserScript(.atDocumentStart)` |
| `MainActivity` 的 WebView 池 | `Sources/ShellViewController.swift` | 单 WebView + 工具栏；下载、外链、`window.open`、`getUserMedia` 权限 |
| `Prefs` | `Sources/ServerStore.swift` | 地址 / 密码 / 布局 / 缩放 / 上次路径 |

Android 独有的部分没有搬：通知栏审批回执（`WatchService` + `DshApi` 的 `/api/remote.mux` 长连）、主屏小组件、应用内 APK 更新。这几块在 iOS 上分别对应推送（需服务端 APNs）、WidgetKit（需 Xcode 工程）、App Store 更新机制，都不属于"把 APK 转成 IPA"这一步。

## 关键实现点

1. **ATS**：`NSAllowsArbitraryLoads = true`，否则 `http://192.168.x.x:3081` 直接被系统拦掉。
2. **本地网络权限**：`NSLocalNetworkUsageDescription`，iOS 14+ 首次连局域网会弹授权，不填描述会静默失败。
3. **布局**：DSH 在页面启动时 `matchMedia('(max-width: 1023px)')` 判一次窄/宽屏，判定发生在页面自己的 JS 里。`WKUserScript` 在 `.atDocumentStart` 注入，抢在页面脚本之前改写结果；改 CSS 或加载后改都无效。
4. **polyfill**：`crypto.randomUUID` 在 `http://<IP>` 下非安全上下文，原生是 `undefined`；`AbortSignal.any` 要 iOS 17.4+。两个都按"缺失才补"注入。
5. **WebView 的 UA 不动**：和解锁请求分开，页面侧保持 Safari UA，DSH 才按视口宽度给布局；`DSHGo` 只出现在解锁 HTTP 请求上，闸门据此回 JSON 而不是 HTML 密码页。

## 出 IPA

### 路线一：GitHub Actions（手机就能做完）

1. GitHub 新建仓库 → 把本目录全部文件传上去（网页端可直接拖文件夹）。
2. `Actions` → `build-ipa` → `Run workflow`。
3. 跑完在 run 页面底部下载 `DSHGo-unsigned-ipa`，里面是 `DSHGo-unsigned.ipa`。

### 路线二：自己的 Mac

```bash
chmod +x build.sh
./build.sh          # 产出 DSHGo-unsigned.ipa
```

需要 Xcode 命令行工具，`xcode-select --install` 一次即可。

### 签名

产出的是未签名 IPA，用你已有的证书签：

- **Sideloadly / AltStore**：免费 Apple ID，7 天有效，到期重签。
- **ESign / 轻松签 / GBox**：导入自己的 p12 + mobileprovision，直接签。
- **TrollStore**：A12 以下或对应版本，可永久安装。

签名时 Bundle ID 换成你证书里的那个，或让工具自动改。
