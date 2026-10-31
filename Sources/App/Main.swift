import AppKit
import InputMethodKit

@main
enum VoiceTextApp {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--register") {
            do { try InputInstaller.register(Bundle.main.bundleURL); print("VoiceText 输入源已注册。") }
            catch { fputs("\(error.localizedDescription)\n", stderr); exit(1) }
            return
        }
        guard let connectionName = Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String,
              let server = IMKServer(name: connectionName, bundleIdentifier: Bundle.main.bundleIdentifier) else {
            NSLog("VoiceText: 无法建立输入法服务连接。")
            exit(1)
        }
        let app = NSApplication.shared
        let delegate = ApplicationDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        let menu = NSMenu()
        let application = NSMenuItem(); let submenu = NSMenu()
        let preferences = NSMenuItem(title: "设置…", action: #selector(ApplicationDelegate.openPreferences), keyEquivalent: ",")
        preferences.target = delegate; submenu.addItem(preferences); submenu.addItem(.separator())
        submenu.addItem(withTitle: "退出 VoiceText", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        application.submenu = submenu; menu.addItem(application)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        edit.submenu = NSMenu(title: "编辑")
        for (title, selector, key) in [("撤销", Selector(("undo:")), "z"), ("剪切", #selector(NSText.cut(_:)), "x"), ("复制", #selector(NSText.copy(_:)), "c"), ("粘贴", #selector(NSText.paste(_:)), "v"), ("全选", #selector(NSText.selectAll(_:)), "a")] {
            edit.submenu?.addItem(withTitle: title, action: selector, keyEquivalent: key)
        }
        menu.addItem(edit); app.mainMenu = menu
        withExtendedLifetime((delegate, server)) { app.run() }
    }
}
