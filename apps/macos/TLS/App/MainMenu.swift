import AppKit

/// Native menu bar. WKWebView only receives Edit shortcuts (copy, paste, undo)
/// through responder-chain menu items, so the Edit menu is required, not cosmetic.
enum MainMenu {
    static func install() {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(windowMenu()))
        main.addItem(submenu(helpMenu()))
        NSApp.mainMenu = main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func appMenu() -> NSMenu {
        let menu = NSMenu(title: "TLS")
        menu.addItem(withTitle: "Acerca de TLS", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(MenuAction.item("Ajustes…", key: ",") { delegate?.emitToMain("settings:open") })
        menu.addItem(.separator())
        menu.addItem(withTitle: "Ocultar TLS", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let others = menu.addItem(withTitle: "Ocultar otros", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        others.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(withTitle: "Mostrar todo", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Salir de TLS", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edición")
        menu.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = menu.addItem(withTitle: "Rehacer", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(.separator())
        menu.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        let plain = menu.addItem(withTitle: "Pegar sin formato", action: #selector(NSTextView.pasteAsPlainText(_:)), keyEquivalent: "v")
        plain.keyEquivalentModifierMask = [.command, .option, .shift]
        menu.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "Visualización")
        let fullScreen = menu.addItem(withTitle: "Pantalla completa", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Ventana")
        menu.addItem(MenuAction.item("Cerrar pestaña", key: "w") {
            if let controller = NSApp.keyWindow?.windowController as? BrowserWindowController, controller.context.isIssue {
                controller.close()
            } else {
                delegate?.emitToMain("tab:close-active")
            }
        })
        menu.addItem(withTitle: "Minimizar", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        for index in 1...9 {
            menu.addItem(MenuAction.item("Pestaña \(index)", key: "\(index)") {
                delegate?.emitToMain("tab:select-by-shortcut", index)
            })
        }
        NSApp.windowsMenu = menu
        return menu
    }

    private static func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "Ayuda")
        menu.addItem(MenuAction.item("Licencia y avisos de Multica", key: "") {
            if let url = Bundle.main.url(forResource: "NOTICE", withExtension: nil) {
                NSWorkspace.shared.open(url)
            }
        })
        menu.addItem(MenuAction.item("Multica en GitHub", key: "") {
            NSWorkspace.shared.open(URL(string: "https://github.com/multica-ai/multica")!)
        })
        NSApp.helpMenu = menu
        return menu
    }

    private static var delegate: AppDelegate? { NSApp.delegate as? AppDelegate }
}

/// Closure-backed menu item target; the item retains its action.
final class MenuAction: NSObject {
    private let handler: () -> Void

    private init(_ handler: @escaping () -> Void) { self.handler = handler }

    @objc private func perform(_ sender: Any?) { handler() }

    static func item(_ title: String, key: String, handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler)
        let item = NSMenuItem(title: title, action: #selector(perform(_:)), keyEquivalent: key)
        item.target = action
        item.representedObject = action
        return item
    }
}
