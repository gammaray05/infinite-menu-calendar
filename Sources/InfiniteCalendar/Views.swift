import AppKit
import SwiftUI
import ServiceManagement

final class CalendarClock: ObservableObject {
    @Published var now = Date()
}

struct CalendarSurface: NSViewRepresentable {
    let scroll: CalendarScrollView
    @ObservedObject var preferences: Preferences
    func makeNSView(context: Context) -> CalendarScrollView { scroll }
    func updateNSView(_ nsView: CalendarScrollView, context: Context) { nsView.configure() }
}

struct CalendarPopover: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var clock: CalendarClock
    let scroll: CalendarScrollView
    let settings: () -> Void
    let quit: () -> Void

    private var today: String {
        let f = DateFormatter()
        f.locale = preferences.locale; f.calendar = preferences.engine.calendar
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: clock.now)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(today).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
                Button(preferences.text("Oggi", "Today")) { scroll.goTo(Date()) }
                    .buttonStyle(.bordered).controlSize(.small)
                    .help(preferences.text("Torna a oggi (Home)", "Return to today (Home)"))
                Button(action: settings) { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .help(preferences.text("Impostazioni", "Settings"))
                    .accessibilityLabel(preferences.text("Impostazioni", "Settings"))
                Menu {
                    Button(preferences.text("Esci da InfiniteCalendar", "Quit InfiniteCalendar"), action: quit)
                } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel(preferences.text("Menu applicazione", "Application menu"))
            }.padding(.horizontal, 18).padding(.vertical, 12)
            Divider().padding(.horizontal, 16)
            CalendarSurface(scroll: scroll, preferences: preferences)
        }
        .frame(width: 328, height: preferences.height)
        .tint(Color(nsColor: .hex(preferences.accent)))
    }
}

struct SettingsView: View {
    @ObservedObject var p: Preferences
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var loginMessage = ""
    private func t(_ it: String, _ en: String) -> String { p.text(it, en) }
    private func colorBinding(_ key: ReferenceWritableKeyPath<Preferences, String>) -> Binding<Color> {
        Binding(get: { Color(nsColor: .hex(p[keyPath: key])) }, set: { p[keyPath: key] = NSColor($0).hexString })
    }

    var body: some View {
        Form {
            Section(t("Aspetto", "Appearance")) {
                Picker(t("Tema", "Theme"), selection: $p.theme) {
                    Text(t("Automatico", "Automatic")).tag("auto")
                    Text(t("Chiaro", "Light")).tag("light")
                    Text(t("Scuro", "Dark")).tag("dark")
                }
                ColorPicker(t("Colore di accento", "Accent color"), selection: colorBinding(\.accent), supportsOpacity: false)
                ColorPicker(t("Colore di oggi", "Today color"), selection: colorBinding(\.todayColor), supportsOpacity: false)
                Toggle(t("Evidenzia al passaggio del mouse", "Highlight on hover"), isOn: $p.hover)
            }
            Section(t("Calendario", "Calendar")) {
                Picker(t("Inizio settimana", "First weekday"), selection: $p.firstWeekday) {
                    Text(t("Secondo la regione", "Region default")).tag(0)
                    Text(t("Lunedì", "Monday")).tag(2)
                    Text(t("Domenica", "Sunday")).tag(1)
                }
                Picker(t("Lingua", "Language"), selection: $p.language) {
                    Text(t("Sistema", "System")).tag("auto")
                    Text("Italiano").tag("it_IT"); Text("English").tag("en_US")
                    Text("Français").tag("fr_FR"); Text("Deutsch").tag("de_DE")
                    Text("Español").tag("es_ES")
                }
                Toggle(t("Numeri delle settimane", "Week numbers"), isOn: $p.weekNumbers)
                Toggle(t("Evidenzia il fine settimana", "Highlight weekends"), isOn: $p.weekends)
                Picker(t("Dimensione testo", "Text size"), selection: $p.textSize) {
                    Text(t("Piccola", "Small")).tag(0); Text(t("Normale", "Normal")).tag(1); Text(t("Grande", "Large")).tag(2)
                }
                Picker(t("Altezza pannello", "Panel height"), selection: $p.panelHeight) {
                    Text(t("Compatta", "Compact")).tag(0); Text(t("Normale", "Normal")).tag(1); Text(t("Estesa", "Extended")).tag(2)
                }
            }
            Section(t("Comportamento", "Behavior")) {
                Toggle(t("Avvia al login", "Launch at login"), isOn: Binding(get: { loginEnabled }, set: updateLogin))
                if !loginMessage.isEmpty { Text(loginMessage).font(.caption).foregroundStyle(.secondary) }
                Toggle(t("Apri sempre sul mese corrente", "Always open at the current month"), isOn: $p.openToday)
                Toggle(t("Chiudi premendo Esc", "Close with Escape"), isOn: $p.escapeCloses)
                Text(t("Frecce: naviga tra i giorni · Pagina su/giù: scorri · Home: oggi", "Arrows: navigate days · Page Up/Down: scroll · Home: today"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 440, height: 680)
        .tint(Color(nsColor: .hex(p.accent)))
        .onAppear { refreshLogin() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in refreshLogin() }
    }

    private func refreshLogin() {
        loginEnabled = SMAppService.mainApp.status == .enabled
        if SMAppService.mainApp.status == .requiresApproval {
            loginMessage = t("Autorizza InfiniteCalendar in Impostazioni di Sistema → Generali → Elementi login.",
                "Approve InfiniteCalendar in System Settings → General → Login Items.")
        } else { loginMessage = "" }
    }
    private func updateLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshLogin()
        } catch {
            loginEnabled = SMAppService.mainApp.status == .enabled
            loginMessage = error.localizedDescription
        }
    }
}
