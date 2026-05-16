import AppKit

@main
enum KeyCastrMain {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppController()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
