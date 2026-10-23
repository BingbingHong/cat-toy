// 逗猫桌宠：一个铺满主屏幕的透明、点击穿透窗口，里面用 WebView 跑 cat.html。
// 外壳负责：全局鼠标位置、Dock 高度（猫的地面）、菜单（开关 / 换品种 / 退出）。
// 菜单有两个入口：点小猫本身，或菜单栏的爪印图标（菜单栏太挤时图标可能被刘海挡住）。
import Cocoa
import WebKit

final class AppDelegate: NSObject, NSApplicationDelegate, WKNavigationDelegate, WKScriptMessageHandler {
    var window: NSWindow!
    var web: WKWebView!
    var statusItem: NSStatusItem!
    var timer: Timer?
    var ready = false
    var lastMouse = NSPoint(x: CGFloat.nan, y: CGFloat.nan)
    var catRect = NSRect.zero        // 猫在窗口里的范围（左上角为原点），由网页每 0.1 秒报一次
    var hovering = false

    let breeds = [("orange", "橘猫"), ("cow", "奶牛猫"), ("calico", "三花")]
    var breed = UserDefaults.standard.string(forKey: "breed") ?? "orange"
    var playing = true

    // 有菜单栏的那块屏幕
    var screen: NSScreen { NSScreen.screens.first ?? NSScreen.main! }

    func applicationDidFinishLaunching(_ notification: Notification) {
        window = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true                 // 点击全部穿透到下面的窗口
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "log")
        config.userContentController.add(self, name: "cat")
        let boot = """
        window.DESKTOP = true;
        window.onerror = (m, s, l) => webkit.messageHandlers.log.postMessage('JS error: ' + m + ' (line ' + l + ')');
        """
        config.userContentController.addUserScript(WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        web = WKWebView(frame: window.contentView!.bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = self
        window.contentView!.addSubview(web)

        let url = Bundle.main.url(forResource: "cat", withExtension: "html")!
        web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        window.orderFrontRegardless()

        setupStatusItem()
        NotificationCenter.default.addObserver(self, selector: #selector(fitScreen),
                                               name: NSApplication.didChangeScreenParametersNotification, object: nil)

        let t = Timer(timeInterval: 1.0 / 60, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t

        // 鼠标在猫身上时窗口才接收点击；点猫 → 弹出菜单
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] e in
            guard let self, e.window === self.window, self.hovering else { return e }
            self.buildMenu().popUp(positioning: nil, at: e.locationInWindow, in: self.window.contentView)
            return nil
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        ready = true
        fitScreen()
        js("catHost.setBreed('\(breed)'); catHost.setPlay(\(playing))")
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if message.name == "cat", let r = message.body as? [Double], r.count == 4 {
            catRect = NSRect(x: r[0], y: r[1], width: r[2], height: r[3])
        } else {
            print(message.body)
        }
    }

    func js(_ code: String) {
        guard ready else { return }
        web.evaluateJavaScript(code, completionHandler: nil)
    }

    // 窗口铺满屏幕；地面 = Dock 的上沿（Dock 隐藏或在侧边时就是屏幕底部）
    @objc func fitScreen() {
        let f = screen.frame
        window.setFrame(f, display: true)
        let dockHeight = max(0, screen.visibleFrame.minY - f.minY)
        js("catHost.setGround(\(f.height - dockHeight - 7))")   // 留几像素，爪子不会被屏幕底边截掉
        lastMouse = NSPoint(x: CGFloat.nan, y: CGFloat.nan)
    }

    // 全局鼠标位置 → 网页坐标（左上角为原点）
    func tick() {
        let m = NSEvent.mouseLocation
        let f = window.frame
        let p = NSPoint(x: m.x - f.minX, y: f.maxY - m.y)
        let over = catRect.contains(p)
        if over != hovering {
            hovering = over
            window.ignoresMouseEvents = !over
            js("catHost.setHover(\(over))")
        }
        if m == lastMouse { return }
        lastMouse = m
        js("catHost.setMouse(\(p.x), \(p.y))")
    }

    // ---------- 菜单栏 ----------
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let img = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "逗猫") {
            img.isTemplate = true
            statusItem.button?.image = img
        } else {
            statusItem.button?.title = "🐾"
        }
        rebuildMenu()
    }

    func rebuildMenu() {
        statusItem.menu = buildMenu()
    }

    func buildMenu() -> NSMenu {
        let menu = NSMenu()
        let play = NSMenuItem(title: "拿出逗猫棒", action: #selector(togglePlay), keyEquivalent: "")
        play.target = self
        play.state = playing ? .on : .off
        menu.addItem(play)

        menu.addItem(.separator())
        let header = NSMenuItem(title: "品种", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for (key, name) in breeds {
            let item = NSMenuItem(title: name, action: #selector(pickBreed(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = key
            item.state = key == breed ? .on : .off
            item.indentationLevel = 1
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "退出逗猫", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        return menu
    }

    @objc func togglePlay() {
        playing.toggle()
        js("catHost.setPlay(\(playing))")
        rebuildMenu()
    }

    @objc func pickBreed(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        breed = key
        UserDefaults.standard.set(key, forKey: "breed")
        js("catHost.setBreed('\(key)')")
        rebuildMenu()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)   // 不出现在 Dock 和 ⌘Tab 里
app.run()
