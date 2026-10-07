import AppKit

let arguments = CommandLine.arguments
if arguments.contains("--version") {
    print("BlackTea \(BuildInfo.version)")
    exit(0)
}
if arguments.contains("--self-test") {
    exit(MainActor.assumeIsolated { SelfTest.run() })
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let controller = AppController()
    app.delegate = controller
    app.setActivationPolicy(.accessory)
    withExtendedLifetime(controller) { app.run() }
}
