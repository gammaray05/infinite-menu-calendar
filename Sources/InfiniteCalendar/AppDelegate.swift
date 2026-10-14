import AppKit
import SwiftUI
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private let preferences = Preferences()
    private let clock = CalendarClock()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var scroll: CalendarScrollView!
    private var settingsWindow: NSWindow?
    private var preferenceSubscription: AnyCancellable?
    private var notificationTokens: [NSObjectProtocol] = []
    private var dayTimer: Timer?
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        scroll = CalendarScrollView(preferences: preferences)
        scroll.onEscape = { [weak self] in self?.popover.performClose(nil) }
        let root = CalendarPopover(preferences: preferences, clock: clock, scroll: scroll,
            settings: { [weak self] in self?.showSettings() }, quit: { NSApp.terminate(nil) })
        let controller = NSHostingController(rootView: root)
        popover.contentViewController = controller
        popover.contentSize = NSSize(width: 328, height: preferences.height)
        popover.behavior = .transient
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.delegate = self
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "calendar", accessibilityDescription: "InfiniteCalendar")
            image?.isTemplate = true
            button.image = image
            button.target = self
            button.action = #selector(statusClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.setAccessibilityLabel("InfiniteCalendar")
            button.toolTip = "InfiniteCalendar"
        }
        preferenceSubscription = preferences.objectWillChange.sink { [weak self] _ in
            // Published emits before assignment; refresh after preferences have changed.
            DispatchQueue.main.async { self?.applyPreferences() }
        }
        let center = NotificationCenter.default
        for name in [NSLocale.currentLocaleDidChangeNotification, NSNotification.Name.NSSystemTimeZoneDidChange,
                     NSNotification.Name.NSSystemClockDidChange, NSNotification.Name.NSCalendarDayChanged] {
            notificationTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.environmentChanged()
            })
        }
        notificationTokens.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification,
            object: nil, queue: .main) { [weak self] _ in self?.environmentChanged() })
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown, event.keyCode == 53 else { return event }
            if self.preferences.escapeCloses { self.popover.performClose(nil) }
            return nil
        }
        applyPreferences()
        scheduleDayRefresh()
    }

    private func applyPreferences() {
        popover.appearance = preferences.appearance
        settingsWindow?.appearance = preferences.appearance
        popover.contentSize = NSSize(width: 328, height: preferences.height)
        scroll.configure()
    }

    @objc private func statusClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            let settings = NSMenuItem(title: preferences.text("Impostazioni…", "Settings…"), action: #selector(showSettings), keyEquivalent: ",")
            settings.target = self; menu.addItem(settings)
            menu.addItem(.separator())
            let quit = NSMenuItem(title: preferences.text("Esci", "Quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp; menu.addItem(quit)
            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
            return
        }
        if popover.isShown { popover.performClose(nil); return }
        guard let button = statusItem.button else { return }
        clock.now = Date()
        popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        scroll.open()
    }

    func popoverDidClose(_ notification: Notification) { scroll.remember() }

    @objc private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: SettingsView(p: preferences))
            let window = NSWindow(contentViewController: controller)
            window.title = preferences.text("Impostazioni — InfiniteCalendar", "Settings — InfiniteCalendar")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.appearance = preferences.appearance
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func environmentChanged() {
        clock.now = Date()
        scroll.configure(force: true)
        scheduleDayRefresh()
    }

    private func scheduleDayRefresh() {
        dayTimer?.invalidate()
        let calendar = Calendar.autoupdatingCurrent
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date()))!
        dayTimer = Timer.scheduledTimer(withTimeInterval: max(1, next.timeIntervalSinceNow + 0.1), repeats: false) { [weak self] _ in
            self?.environmentChanged()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        scroll.remember()
        dayTimer?.invalidate()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        for token in notificationTokens {
            NotificationCenter.default.removeObserver(token)
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
    }
}
