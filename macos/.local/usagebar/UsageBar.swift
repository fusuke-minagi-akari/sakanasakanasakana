import AppKit

// Menu bar usage monitor. usage.py (run every 60s) prints JSON:
// [{"name", "error", "checked", "windows": [{"kind": "5h"|"wk", "pct", "reset"}]}]
let script = NSString(string: "~/.local/usagebar/usage.py").expandingTildeInPath
func title(_ name: String) -> String { name == "codex" ? "Codex" : "Claude · \(name)" }
func badge(_ name: String) -> String { name == "codex" ? "X" : String(name.prefix(1)).uppercased() }

struct Window: Decodable { let kind: String; let pct: Double; let reset: Double? }
struct Source: Decodable {
    var name: String, error: String?, checked: Double?, windows: [Window]
    // a failed fetch only matters once the cached numbers are >10 min old (e.g. brief 429s)
    var stale: Bool { error != nil && Date().timeIntervalSince1970 - (checked ?? 0) > 600 }
}

// Pace: project the current burn rate to the reset -> (colour, run-out time if before reset).
// green = lasts until reset, orange = runs out before reset, red = at limit or out in < half the time left.
func pace(_ w: Window) -> (NSColor, Double?) {
    let now = Date().timeIntervalSince1970, len: Double = w.kind == "5h" ? 5 * 3600 : 7 * 86400
    if w.pct >= 100 { return (.systemRed, nil) }
    guard let reset = w.reset, reset > now, w.pct > 0 else { return (.systemGreen, nil) }
    let elapsed = len - (reset - now)
    if elapsed < len * 0.1 {  // too early in the window to trust the rate: plain thresholds
        return (w.pct >= 90 ? .systemRed : w.pct >= 70 ? .systemOrange : .systemGreen, nil)
    }
    let out = now + (100 - w.pct) * elapsed / w.pct
    if out >= reset { return (.systemGreen, nil) }
    return (out - now < (reset - now) / 2 ? .systemRed : .systemOrange, out)
}

func ago(_ t: Double?) -> String {
    guard let t else { return "never" }
    let s = Int(Date().timeIntervalSince1970 - t)
    return s < 60 ? "just now" : s < 3600 ? "\(s / 60)m ago" : "\(s / 3600)h ago"
}

func countdown(_ t: Double?) -> String {
    guard let t, t > Date().timeIntervalSince1970 else { return "Not started" }
    let s = Int(t - Date().timeIntervalSince1970)
    let left = s >= 86400 ? "\(s / 86400)d \(s % 86400 / 3600)h" : s >= 3600 ? "\(s / 3600)h \(s % 3600 / 60)m" : "\(s / 60)m"
    let f = DateFormatter()
    f.dateFormat = s >= 86400 ? "EEE HH:mm" : "HH:mm"
    return "Resets \(f.string(from: Date(timeIntervalSince1970: t))) · in \(left)"
}

// MARK: menu bar icon: per source a badge letter + stacked bars (5h on top, weekly below)

func statusImage(_ sources: [Source]) -> NSImage {
    let barW: CGFloat = 20, barH: CGFloat = 4, gap: CGFloat = 2, badgeW: CGFloat = 9, spacing: CGFloat = 7
    let width = CGFloat(sources.count) * (badgeW + 2 + barW) + CGFloat(max(0, sources.count - 1)) * spacing
    return NSImage(size: NSSize(width: max(width, 1), height: 18), flipped: false) { _ in
        var x: CGFloat = 0
        for s in sources {
            let stale = s.stale
            let badge = NSAttributedString(string: badge(s.name), attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold),
                .foregroundColor: stale ? NSColor.tertiaryLabelColor : NSColor.labelColor,
            ])
            badge.draw(at: NSPoint(x: x + (badgeW - badge.size().width) / 2, y: (18 - badge.size().height) / 2))
            x += badgeW + 2
            let rows = ["5h", "wk"].compactMap { k in s.windows.first { $0.kind == k } }
            let total = CGFloat(rows.count) * barH + CGFloat(max(0, rows.count - 1)) * gap
            var y = (18 + total) / 2 - barH
            for w in rows {
                let track = NSRect(x: x, y: y, width: barW, height: barH)
                NSColor.labelColor.withAlphaComponent(0.2).setFill()
                NSBezierPath(roundedRect: track, xRadius: 2, yRadius: 2).fill()
                var fill = track
                fill.size.width = max(barH, barW * CGFloat(min(w.pct, 100)) / 100)
                // stale = faded, so colour keeps meaning only "how full"
                (w.pct > 0 ? pace(w).0.withAlphaComponent(stale ? 0.3 : 1) : .clear).setFill()
                NSBezierPath(roundedRect: fill, xRadius: 2, yRadius: 2).fill()
                y -= barH + gap
            }
            x += barW + spacing
        }
        return true
    }
}

// MARK: dropdown rows

final class Bar: NSView {
    var limit = Window(kind: "wk", pct: 0, reset: nil)
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: 6) }
    override func draw(_: NSRect) {
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 3, yRadius: 3).fill()
        guard limit.pct > 0 else { return }
        var f = bounds
        f.size.width = max(bounds.height, bounds.width * CGFloat(min(limit.pct, 100)) / 100)
        pace(limit).0.setFill()
        NSBezierPath(roundedRect: f, xRadius: 3, yRadius: 3).fill()
    }
}

func label(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, _ c: NSColor = .labelColor, mono: Bool = false) -> NSTextField {
    let l = NSTextField(labelWithString: s)
    l.font = mono ? .monospacedDigitSystemFont(ofSize: size, weight: weight) : .systemFont(ofSize: size, weight: weight)
    l.textColor = c
    return l
}

func row(_ views: [NSView]) -> NSStackView {
    let r = NSStackView(views: views)
    r.orientation = .horizontal
    r.distribution = .fill
    views.first?.setContentHuggingPriority(.defaultLow, for: .horizontal)
    return r
}

func sourceView(_ s: Source) -> NSView {
    let status = s.stale ? "⚠ \(s.error!) · data from \(ago(s.checked))" : "Updated \(ago(s.checked))"
    var views: [NSView] = [row([
        label(title(s.name), 13, .semibold),
        label(status, 11, .regular, s.stale ? .systemOrange : .secondaryLabelColor),
    ])]
    for w in s.windows {
        let bar = Bar()
        bar.limit = w
        let (c, out) = pace(w)
        var caption = countdown(w.reset)
        if let out {
            let f = DateFormatter()
            f.dateFormat = out - Date().timeIntervalSince1970 >= 86400 ? "EEE HH:mm" : "HH:mm"
            caption += " · runs out ~\(f.string(from: Date(timeIntervalSince1970: out)))"
        }
        views += [
            row([label(w.kind == "5h" ? "5-hour limit" : "Weekly limit", 12, .regular, .secondaryLabelColor),
                 label("\(Int(w.pct.rounded()))%", 12, .semibold, c == .systemGreen ? .labelColor : c, mono: true)]),
            bar,
            label(caption, 11, .regular, out == nil ? .tertiaryLabelColor : c),
        ]
    }
    if s.windows.isEmpty { views.append(label("No data yet", 12, .regular, .secondaryLabelColor)) }
    let stack = NSStackView(views: views)
    stack.orientation = .vertical
    stack.alignment = .leading
    stack.spacing = 4
    stack.edgeInsets = NSEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    stack.widthAnchor.constraint(equalToConstant: 300).isActive = true
    for v in views { v.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28).isActive = true }
    // extra space after each limit's caption, before the next limit
    for (i, v) in views.enumerated() where i > 0 && (i % 3 == 0) && i < views.count - 1 { stack.setCustomSpacing(10, after: v) }
    stack.setCustomSpacing(8, after: views[0])
    stack.frame = NSRect(x: 0, y: 0, width: 300, height: 10)
    stack.layoutSubtreeIfNeeded()
    stack.frame.size.height = stack.fittingSize.height
    return stack
}

// MARK: app

final class App: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    var sources: [Source] = []
    var inFlight = false  // timer + "Refresh now" must not run usage.py concurrently

    func applicationDidFinishLaunching(_: Notification) {
        item.button?.title = "…"
        item.menu = NSMenu()
        item.menu?.delegate = self
        refresh()
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in self.refresh() }
    }

    @objc func refresh() {
        guard !inFlight else { return }
        inFlight = true
        DispatchQueue.global().async {
            let new = fetch()
            DispatchQueue.main.async {
                self.inFlight = false
                if let new {
                    self.sources = new
                } else {  // usage.py itself broke: flag every source so a frozen bar is visible
                    for i in self.sources.indices where self.sources[i].error == nil { self.sources[i].error = "fetcher failed (see err.log)" }
                }
                self.item.button?.title = new == nil && self.sources.isEmpty ? "usage ⚠" : ""
                self.item.button?.image = statusImage(self.sources)
            }
        }
    }

    // rebuilt on open so countdowns / "updated" are current
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        for (i, s) in sources.enumerated() {
            if i > 0 { menu.addItem(.separator()) }
            let mi = NSMenuItem()
            mi.view = sourceView(s)
            menu.addItem(mi)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Refresh now", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Open Claude usage page", action: #selector(openClaude), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Open Codex usage page", action: #selector(openCodex), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc func openClaude() { NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!) }
    @objc func openCodex() { NSWorkspace.shared.open(URL(string: "https://chatgpt.com/codex/settings/usage")!) }
}

func fetch() -> [Source]? {
    let p = Process(), out = Pipe()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    p.arguments = ["python3", script]
    p.environment = ["PATH": "/opt/homebrew/bin:/usr/bin:/bin"]
    p.standardOutput = out
    guard (try? p.run()) != nil else { return nil }
    DispatchQueue.global().asyncAfter(deadline: .now() + 45) { if p.isRunning { p.terminate() } }  // hung keychain/DNS
    let data = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return try? JSONDecoder().decode([Source].self, from: data)
}

// `UsageBar --snapshot DIR`: render icon + dropdown to PNGs (light & dark) for checking the design
func snapshot(_ dir: String) {
    let sources = fetch() ?? []
    for (name, look) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
        NSAppearance(named: look)!.performAsCurrentDrawingAppearance {
            let views = [NSImageView(image: statusImage(sources))] + sources.map(sourceView)
            let w: CGFloat = 300, h = views.reduce(0) { $0 + max($1.frame.height, 24) }
            let canvas = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            canvas.appearance = NSAppearance(named: look)
            canvas.wantsLayer = true
            canvas.layer?.backgroundColor = (look == .aqua ? NSColor(white: 0.96, alpha: 1) : NSColor(white: 0.16, alpha: 1)).cgColor
            var y = h
            for v in views {
                let vh = max(v.frame.height, 24)
                y -= vh
                v.frame = NSRect(x: 0, y: y, width: v is NSImageView ? v.fittingSize.width + 20 : w, height: vh)
                canvas.addSubview(v)
            }
            canvas.layoutSubtreeIfNeeded()
            let rep = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds)!
            canvas.cacheDisplay(in: canvas.bounds, to: rep)
            try? rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
        }
    }
}

// `UsageBar --selftest`: pace colour rules
func selftest() {
    let now = Date().timeIntervalSince1970, h = 3600.0
    let wk = { (pct: Double, left: Double) in pace(Window(kind: "wk", pct: pct, reset: now + left * h)) }
    precondition(wk(100, 50).0 == .systemRed)                           // at limit
    precondition(wk(50, 84).0 == .systemGreen && wk(50, 84).1 == nil)  // exactly on pace
    precondition(wk(84, 136).0 == .systemRed && wk(84, 136).1 != nil)  // codex case: out in ~6h, reset in 136h
    precondition(wk(70, 60).0 == .systemOrange)                         // out in ~46h, reset in 60h
    precondition(wk(80, 160).0 == .systemOrange)                        // <10% into window: plain threshold
    precondition(pace(Window(kind: "5h", pct: 0, reset: nil)).0 == .systemGreen)
    print("selftest ok")
}

let app = NSApplication.shared
if CommandLine.arguments.last == "--selftest" { selftest(); exit(0) }
if CommandLine.arguments.count > 2, CommandLine.arguments[1] == "--snapshot" {
    snapshot(CommandLine.arguments[2])
    exit(0)
}
let delegate = App()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
