import AppKit
import SwiftUI
import ServiceManagement
#if SWIFT_PACKAGE
import CalendarCore
#endif

final class Preferences: ObservableObject {
    private let defaults = UserDefaults.standard
    @Published var theme: String { didSet { defaults.set(theme, forKey: "theme") } }
    @Published var accent: String { didSet { defaults.set(accent, forKey: "accent") } }
    @Published var todayColor: String { didSet { defaults.set(todayColor, forKey: "todayColor") } }
    @Published var hover: Bool { didSet { defaults.set(hover, forKey: "hover") } }
    @Published var firstWeekday: Int { didSet { defaults.set(firstWeekday, forKey: "firstWeekday") } }
    @Published var language: String { didSet { defaults.set(language, forKey: "language") } }
    @Published var weekNumbers: Bool { didSet { defaults.set(weekNumbers, forKey: "weekNumbers") } }
    @Published var textSize: Int { didSet { defaults.set(textSize, forKey: "textSize") } }
    @Published var panelHeight: Int { didSet { defaults.set(panelHeight, forKey: "panelHeight") } }
    @Published var weekends: Bool { didSet { defaults.set(weekends, forKey: "weekends") } }
    @Published var openToday: Bool { didSet { defaults.set(openToday, forKey: "openToday") } }
    @Published var escapeCloses: Bool { didSet { defaults.set(escapeCloses, forKey: "escapeCloses") } }

    init() {
        let d = UserDefaults.standard
        d.register(defaults: ["theme": "auto", "accent": "3478F6", "todayColor": "3478F6",
            "hover": true, "firstWeekday": 0, "language": "auto", "weekNumbers": false,
            "textSize": 1, "panelHeight": 1, "weekends": true, "openToday": true, "escapeCloses": true])
        theme = d.string(forKey: "theme")!; accent = d.string(forKey: "accent")!
        todayColor = d.string(forKey: "todayColor")!; hover = d.bool(forKey: "hover")
        firstWeekday = d.integer(forKey: "firstWeekday"); language = d.string(forKey: "language")!
        weekNumbers = d.bool(forKey: "weekNumbers"); textSize = d.integer(forKey: "textSize")
        panelHeight = d.integer(forKey: "panelHeight"); weekends = d.bool(forKey: "weekends")
        openToday = d.bool(forKey: "openToday"); escapeCloses = d.bool(forKey: "escapeCloses")
    }

    var locale: Locale { language == "auto" ? .autoupdatingCurrent : Locale(identifier: language) }
    var engine: CalendarEngine {
        var c = Calendar.autoupdatingCurrent
        c.locale = locale
        c.timeZone = .autoupdatingCurrent
        if language != "auto", firstWeekday == 0 { c.firstWeekday = locale.calendar.firstWeekday }
        if firstWeekday != 0 { c.firstWeekday = firstWeekday }
        return CalendarEngine(calendar: c)
    }
    var fontSize: CGFloat { [12, 14, 16][min(2, max(0, textSize))] }
    var rowHeight: CGFloat { fontSize + 18 }
    var height: CGFloat { CGFloat([4, 5, 6][min(2, max(0, panelHeight))]) * rowHeight + 70 }
    var layoutKey: String {
        "\(engine.calendar.identifier)|\(locale.identifier)|\(engine.calendar.timeZone.identifier)|\(engine.calendar.firstWeekday)|\(textSize)|\(weekNumbers)"
    }
    var appearance: NSAppearance? {
        switch theme { case "light": return NSAppearance(named: .aqua)
        case "dark": return NSAppearance(named: .darkAqua); default: return nil }
    }
    func text(_ italian: String, _ english: String) -> String {
        locale.language.languageCode?.identifier == "it" ? italian : english
    }
    var lastWeek: Date { Date(timeIntervalSince1970: defaults.object(forKey: "lastVisibleWeek") as? Double ?? Date().timeIntervalSince1970) }
    var lastOffset: Double { defaults.double(forKey: "lastWeekOffset") }
    func remember(week: Date, offset: Double) {
        defaults.set(week.timeIntervalSince1970, forKey: "lastVisibleWeek")
        defaults.set(offset, forKey: "lastWeekOffset")
    }
}

enum StatusDayIcon {
    static func dayText(date: Date, calendar: Calendar, locale: Locale) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar; formatter.locale = locale; formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter.string(from: date)
    }

    static func make(date: Date, calendar: Calendar, locale: Locale) -> NSImage {
        let day = dayText(date: date, calendar: calendar, locale: locale)
        let size = NSSize(width: 28, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 4, yRadius: 4).fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .bold), .foregroundColor: NSColor.black]
            let text = day as NSString
            let measured = text.size(withAttributes: attrs)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current?.compositingOperation = .destinationOut
            NSGraphicsContext.current?.cgContext.setBlendMode(.destinationOut)
            text.draw(at: NSPoint(x: rect.midX - measured.width / 2, y: rect.midY - measured.height / 2), withAttributes: attrs)
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        return image
    }
}

extension NSColor {
    static func hex(_ value: String) -> NSColor {
        let n = UInt32(value, radix: 16) ?? 0x3478F6
        return NSColor(srgbRed: CGFloat((n >> 16) & 255) / 255,
            green: CGFloat((n >> 8) & 255) / 255, blue: CGFloat(n & 255) / 255, alpha: 1)
    }
    var hexString: String {
        let c = usingColorSpace(.sRGB) ?? .systemBlue
        return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
    var contrastingText: NSColor {
        let c = usingColorSpace(.sRGB) ?? .systemBlue
        let luminance = 0.2126 * c.redComponent + 0.7152 * c.greenComponent + 0.0722 * c.blueComponent
        return luminance > 0.65 ? .black : .white
    }
}
