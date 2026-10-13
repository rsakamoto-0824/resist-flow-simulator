import AppKit
import WebKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
    private var window: NSWindow!
    private var webView: WKWebView!
    private var resourceDirectory: URL!
    private var savePanelOpen = false
    private var runtimeErrors: [String] = []
    private var smokeReportURL: URL?
    private var smokeResults: [[String: Any]] = []
    private var smokeStarted = Date()
    private let smokeModes = ["leveling", "spin", "infiltration"]

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        if let index = CommandLine.arguments.firstIndex(of: "--self-test"), CommandLine.arguments.count > index + 1 {
            smokeReportURL = URL(fileURLWithPath: CommandLine.arguments[index + 1])
        }
        configureMenu()
        let contentController = WKUserContentController()
        contentController.add(self, name: "saveFile")
        contentController.add(self, name: "diagnostics")
        let errorReporting = """
        window.addEventListener('error', e => window.webkit.messageHandlers.diagnostics.postMessage(String(e.message)));
        window.addEventListener('unhandledrejection', e => window.webkit.messageHandlers.diagnostics.postMessage(String(e.reason)));
        """
        contentController.addUserScript(WKUserScript(source: errorReporting, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = contentController
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.autoresizingMask = [.width, .height]
        let screen = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = NSRect(x: screen.minX + 30, y: screen.minY + 25,
                           width: min(1440, screen.width - 60), height: min(940, screen.height - 50))
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Resist Flow Lab — Mac テスト版"
        window.minSize = NSSize(width: 800, height: 620)
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        guard let resources = Bundle.main.resourceURL else {
            showError("アプリのリソースが見つかりません。再ビルドしてください。")
            return
        }
        resourceDirectory = resources.appendingPathComponent("web", isDirectory: true)
        let page = resourceDirectory.appendingPathComponent("index.html")
        guard FileManager.default.fileExists(atPath: page.path) else {
            showError("画面ファイルが見つかりません。再ビルドしてください。")
            return
        }
        webView.loadFileURL(page, allowingReadAccessTo: resourceDirectory)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    private func configureMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Resist Flow Lab")
        appMenu.addItem(withTitle: "Resist Flow Lab について", action: #selector(showAbout), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Resist Flow Lab を終了", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "編集")
        for (title, selector, key) in [("取り消す", "undo:", "z"), ("切り取り", "cut:", "x"), ("コピー", "copy:", "c"), ("貼り付け", "paste:", "v"), ("すべて選択", "selectAll:", "a")] {
            editMenu.addItem(withTitle: title, action: Selector(selector), keyEquivalent: key)
        }
        editItem.submenu = editMenu
        main.addItem(editItem)
        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "ウィンドウ")
        windowMenu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        windowMenu.addItem(withTitle: "拡大・縮小", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)
        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    @objc private func showAbout() {
        let alert = NSAlert()
        alert.messageText = "Resist Flow Lab — Mac テスト版"
        alert.informativeText = "3つのレジスト流体モデルを試すためのローカルアプリです。\n\nMATLAB のコンパイル版ではありません。計算は同じ式を用いた JavaScript 参照実装で行います。入力は端末内で処理し、外部へ送信しません。"
        alert.addButton(withTitle: "閉じる")
        alert.beginSheetModal(for: window)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        let prefix = resourceDirectory.standardizedFileURL.path + "/"
        if url.isFileURL && url.standardizedFileURL.path.hasPrefix(prefix) {
            decisionHandler(.allow)
        } else {
            decisionHandler(.cancel)
        }
    }

    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.title = "条件または膜厚データを選択"
        panel.allowedContentTypes = [.json, .commaSeparatedText, .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.beginSheetModal(for: window) { response in completionHandler(response == .OK ? panel.urls : nil) }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let url = message.frameInfo.request.url,
              url.isFileURL, url.standardizedFileURL.path.hasPrefix(resourceDirectory.standardizedFileURL.path + "/") else { return }
        if message.name == "diagnostics" {
            runtimeErrors.append(String(describing: message.body))
            return
        }
        guard message.name == "saveFile", !savePanelOpen,
              let body = message.body as? [String: Any],
              let proposedName = body["name"] as? String,
              let content = body["content"] as? String,
              content.utf8.count <= 25_000_000 else { return }
        let name = URL(fileURLWithPath: proposedName).lastPathComponent
        let encoding = body["encoding"] as? String ?? "utf8"
        guard let data = encoding == "base64" ? Data(base64Encoded: content) : content.data(using: .utf8) else {
            showError("保存するデータを読み取れませんでした。")
            return
        }
        let allowedExtensions = ["json", "csv", "png"]
        let suffix = URL(fileURLWithPath: name).pathExtension.lowercased()
        guard allowedExtensions.contains(suffix) else { showError("保存形式を確認してください。"); return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        if let type = UTType(filenameExtension: suffix) { panel.allowedContentTypes = [type] }
        savePanelOpen = true
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self = self else { return }
            self.savePanelOpen = false
            guard response == .OK, let destination = panel.url else {
                self.notifySave(ok: false, cancelled: true, name: name)
                return
            }
            do {
                try data.write(to: destination, options: .atomic)
                self.notifySave(ok: true, cancelled: false, name: destination.lastPathComponent)
            } catch {
                self.notifySave(ok: false, cancelled: false, name: name)
                self.showError("ファイルを保存できませんでした。\n" + error.localizedDescription)
            }
        }
    }

    private func notifySave(ok: Bool, cancelled: Bool, name: String) {
        let detail: [String: Any] = ["ok": ok, "cancelled": cancelled, "name": name]
        if let data = try? JSONSerialization.data(withJSONObject: detail), let json = String(data: data, encoding: .utf8) {
            webView.evaluateJavaScript("window.dispatchEvent(new CustomEvent('native-save-result',{detail:\(json)}));")
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "処理を確認してください"
        alert.informativeText = message
        alert.beginSheetModal(for: window)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard smokeReportURL != nil else { return }
        smokeStarted = Date()
        runSmokeMode(index: 0)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        runtimeErrors.append(error.localizedDescription)
        if smokeReportURL != nil { finishSmoke(success: false) }
    }

    private func runSmokeMode(index: Int) {
        guard index < smokeModes.count else { finishSmoke(success: runtimeErrors.isEmpty); return }
        let mode = smokeModes[index]
        webView.evaluateJavaScript("window.ResistPreviewTest.selectPreset('\(mode)'); window.ResistPreviewTest.run(); true;") { [weak self] _, error in
            guard let self = self else { return }
            if let error = error { self.runtimeErrors.append(error.localizedDescription); self.finishSmoke(success: false); return }
            self.pollSmokeMode(index: index)
        }
    }

    private func pollSmokeMode(index: Int) {
        if Date().timeIntervalSince(smokeStarted) > 120 {
            runtimeErrors.append("Native UI smoke test exceeded 120 seconds")
            finishSmoke(success: false)
            return
        }
        webView.evaluateJavaScript("JSON.stringify(window.ResistPreviewTest.getState())") { [weak self] value, error in
            guard let self = self else { return }
            guard error == nil, let json = value as? String, let data = json.data(using: .utf8),
                  let state = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
                self.runtimeErrors.append(error?.localizedDescription ?? "Could not read application state")
                self.finishSmoke(success: false)
                return
            }
            if state["running"] as? Bool == true {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { self.pollSmokeMode(index: index) }
                return
            }
            self.smokeResults.append(state)
            if state["failed"] as? Bool == true {
                self.runtimeErrors.append("Simulation reported failure in \(self.smokeModes[index])")
                self.finishSmoke(success: false)
                return
            }
            self.runSmokeMode(index: index + 1)
        }
    }

    private func finishSmoke(success: Bool) {
        guard let destination = smokeReportURL else { return }
        smokeReportURL = nil
        let report: [String: Any] = ["success": success, "runtimeErrors": runtimeErrors, "modes": smokeResults, "host": "native WKWebView", "elapsedSeconds": Date().timeIntervalSince(smokeStarted)]
        do {
            let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: destination, options: .atomic)
            print("NATIVE_SMOKE_TEST=\(success ? "PASS" : "FAIL") \(destination.path)")
        } catch { print("Could not save native smoke test: \(error)") }
        NSApp.terminate(nil)
    }
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
