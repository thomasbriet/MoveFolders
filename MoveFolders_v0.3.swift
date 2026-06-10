import Cocoa
import Darwin

class TableAdapter: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    struct Item {
        let name: String
        let isDir: Bool
        let modDate: Date
    }
    var items: [Item] = []
    func numberOfRows(in tableView: NSTableView) -> Int { items.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let id = NSUserInterfaceItemIdentifier("cell")
        let view: NSTableCellView
        if let existing = tableView.makeView(withIdentifier: id, owner: self) as? NSTableCellView {
            view = existing
        } else {
            view = NSTableCellView(frame: NSRect(x: 0, y: 0, width: tableView.bounds.width, height: 24))
            view.identifier = id
            let tf = NSTextField(frame: NSRect(x: 0, y: 2, width: tableView.bounds.width - 4, height: 20))
            tf.isBordered = false
            tf.isEditable = false
            tf.drawsBackground = false
            view.textField = tf
            view.addSubview(tf)
        }
        let item = items[row]
        if item.name == "Laden..." {
            view.textField?.stringValue = item.name
        } else {
            let prefix = item.isDir ? "📁 " : "📄 "
            view.textField?.stringValue = "\(prefix)\(item.name)"
        }
        return view
    }
}

enum MismatchKind { case missingDest, timeDiff, sizeDiff, extraDest }
struct Mismatch { let kind: MismatchKind; let relPath: String }

struct MismatchDetail {
    let kind: MismatchKind
    let relPath: String
    let reason: String
    let srcInfo: String
    let dstInfo: String
    let canOverwrite: Bool
    var selected: Bool
}

struct FileEntry {
    let size: Int64?
    let modDate: Date?
}

class MismatchTableAdapter: NSObject, NSTableViewDataSource, NSTableViewDelegate {
    var rows: [MismatchDetail]
    var selectionChanged: (() -> Void)?

    init(rows: [MismatchDetail]) {
        self.rows = rows
    }

    func numberOfRows(in tableView: NSTableView) -> Int { rows.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row >= 0 && row < rows.count else { return nil }
        let item = rows[row]
        let columnId = tableColumn?.identifier.rawValue ?? ""

        if columnId == "check" {
            let id = NSUserInterfaceItemIdentifier("checkCell")
            let btn: NSButton
            if let existing = tableView.makeView(withIdentifier: id, owner: self) as? NSButton {
                btn = existing
            } else {
                btn = NSButton(frame: NSRect(x: 6, y: 2, width: 18, height: 18))
                btn.setButtonType(.switch)
                btn.title = ""
                btn.identifier = id
                btn.target = self
                btn.action = #selector(toggleSelection(_:))
            }
            btn.tag = row
            btn.state = item.selected ? .on : .off
            btn.isEnabled = item.canOverwrite
            return btn
        }

        let id = NSUserInterfaceItemIdentifier("textCell_\(columnId)")
        let tf: NSTextField
        if let existing = tableView.makeView(withIdentifier: id, owner: self) as? NSTextField {
            tf = existing
        } else {
            tf = NSTextField(labelWithString: "")
            tf.identifier = id
            tf.lineBreakMode = .byTruncatingMiddle
        }

        switch columnId {
        case "path": tf.stringValue = item.relPath
        case "reason": tf.stringValue = item.reason
        case "src": tf.stringValue = item.srcInfo
        case "dst": tf.stringValue = item.dstInfo
        default: tf.stringValue = ""
        }
        return tf
    }

    @objc func toggleSelection(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < rows.count else { return }
        guard rows[idx].canOverwrite else {
            sender.state = .off
            return
        }
        rows[idx].selected = sender.state == .on
        selectionChanged?()
    }

    func setAll(_ selected: Bool) {
        var changed = false
        for idx in rows.indices {
            guard rows[idx].canOverwrite else { continue }
            if rows[idx].selected != selected {
                rows[idx].selected = selected
                changed = true
            }
        }
        if changed { selectionChanged?() }
    }

    func invertSelection() {
        var changed = false
        for idx in rows.indices {
            guard rows[idx].canOverwrite else { continue }
            rows[idx].selected.toggle()
            changed = true
        }
        if changed { selectionChanged?() }
    }

    func selectWhere(_ predicate: (MismatchDetail) -> Bool) {
        var changed = false
        for idx in rows.indices {
            guard rows[idx].canOverwrite else { continue }
            let newValue = predicate(rows[idx])
            if rows[idx].selected != newValue {
                rows[idx].selected = newValue
                changed = true
            }
        }
        if changed { selectionChanged?() }
    }
}

class MismatchWindowController: NSObject, NSWindowDelegate {
    enum Result { case overwrite([MismatchDetail]), skip }

    private let adapter: MismatchTableAdapter
    private let window: NSWindow
    private let headerLabel: NSTextField
    private let overwriteButton: NSButton
    private let skipButton: NSButton
    private let selectAllButton: NSButton
    private let selectNoneButton: NSButton
    private let invertButton: NSButton
    private let selectNewerButton: NSButton
    private let tableView: NSTableView
    private let headerBaseText: String
    private var result: Result = .skip

    init(details: [MismatchDetail], headerText: String = "Selecteer bestanden om te overschrijven:") {
        self.adapter = MismatchTableAdapter(rows: details)
        self.headerBaseText = headerText

        let frame = NSRect(x: 0, y: 0, width: 1100, height: 520)
        self.window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        self.window.title = "Mismatchs gevonden"

        let content = window.contentView!
        let margin: CGFloat = 20
        let topLabel = NSTextField(labelWithString: headerText)
        topLabel.frame = NSRect(x: margin, y: frame.height - 40, width: frame.width - 2 * margin, height: 20)
        content.addSubview(topLabel)
        headerLabel = topLabel

        let scroll = NSScrollView(frame: NSRect(x: margin, y: 70, width: frame.width - 2 * margin, height: frame.height - 130))
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        let table = NSTableView(frame: scroll.bounds)
        table.autoresizingMask = [.width, .height]
        table.usesAlternatingRowBackgroundColors = true
        table.rowHeight = 22
        table.allowsColumnReordering = false
        table.allowsMultipleSelection = false
        table.allowsEmptySelection = true
        table.headerView = NSTableHeaderView(frame: NSRect(x: 0, y: 0, width: scroll.bounds.width, height: 24))

        let colCheck = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("check"))
        colCheck.title = ""
        colCheck.width = 30
        colCheck.minWidth = 30
        colCheck.maxWidth = 30
        table.addTableColumn(colCheck)

        let colPath = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("path"))
        colPath.title = "Bestand"
        colPath.width = 420
        table.addTableColumn(colPath)

        let colReason = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("reason"))
        colReason.title = "Mismatch"
        colReason.width = 180
        table.addTableColumn(colReason)

        let colSrc = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("src"))
        colSrc.title = "Bron (grootte | datum)"
        colSrc.width = 200
        table.addTableColumn(colSrc)

        let colDst = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("dst"))
        colDst.title = "Doel (grootte | datum)"
        colDst.width = 200
        table.addTableColumn(colDst)

        table.dataSource = adapter
        table.delegate = adapter
        tableView = table
        scroll.documentView = table
        content.addSubview(scroll)

        selectAllButton = NSButton(frame: NSRect(x: margin, y: 20, width: 90, height: 28))
        selectAllButton.title = "Alles"
        selectAllButton.bezelStyle = .rounded
        selectAllButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        content.addSubview(selectAllButton)

        selectNoneButton = NSButton(frame: NSRect(x: margin + 100, y: 20, width: 90, height: 28))
        selectNoneButton.title = "Niets"
        selectNoneButton.bezelStyle = .rounded
        selectNoneButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        content.addSubview(selectNoneButton)

        invertButton = NSButton(frame: NSRect(x: margin + 200, y: 20, width: 100, height: 28))
        invertButton.title = "Inverteer"
        invertButton.bezelStyle = .rounded
        invertButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        content.addSubview(invertButton)

        selectNewerButton = NSButton(frame: NSRect(x: margin + 310, y: 20, width: 190, height: 28))
        selectNewerButton.title = "Alleen bron nieuwer"
        selectNewerButton.bezelStyle = .rounded
        selectNewerButton.autoresizingMask = [.maxXMargin, .maxYMargin]
        content.addSubview(selectNewerButton)

        overwriteButton = NSButton(frame: NSRect(x: frame.width - 300, y: 20, width: 200, height: 28))
        overwriteButton.title = "Overschrijven geselecteerd"
        overwriteButton.bezelStyle = .rounded
        overwriteButton.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(overwriteButton)

        skipButton = NSButton(frame: NSRect(x: frame.width - 90, y: 20, width: 70, height: 28))
        skipButton.title = "Overslaan"
        skipButton.bezelStyle = .rounded
        skipButton.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(skipButton)

        super.init()

        overwriteButton.target = self
        overwriteButton.action = #selector(overwriteAction(_:))
        skipButton.target = self
        skipButton.action = #selector(skipAction(_:))
        selectAllButton.target = self
        selectAllButton.action = #selector(selectAllAction(_:))
        selectNoneButton.target = self
        selectNoneButton.action = #selector(selectNoneAction(_:))
        invertButton.target = self
        invertButton.action = #selector(invertAction(_:))
        selectNewerButton.target = self
        selectNewerButton.action = #selector(selectNewerAction(_:))

        overwriteButton.keyEquivalent = "\r"
        skipButton.keyEquivalent = "\u{1b}"
        selectAllButton.keyEquivalent = "a"
        selectAllButton.keyEquivalentModifierMask = [.command]

        adapter.selectionChanged = { [weak self] in
            self?.updateButtons()
            self?.tableView.reloadData()
        }
        updateButtons()

        window.center()
        window.delegate = self
    }

    func runModal() -> Result {
        window.makeKeyAndOrderFront(nil)
        NSApp.runModal(for: window)
        return result
    }

    private func updateButtons() {
        let hasSelection = adapter.rows.contains { $0.selected }
        overwriteButton.isEnabled = hasSelection
        skipButton.isEnabled = true
        let selectableCount = adapter.rows.filter { $0.canOverwrite }.count
        let selectedCount = adapter.rows.filter { $0.selected }.count
        headerLabel.stringValue = "\(headerBaseText) \(selectedCount)/\(selectableCount) geselecteerd"
    }

    @objc private func overwriteAction(_ sender: Any) {
        let selected = adapter.rows.filter { $0.selected }
        guard !selected.isEmpty else { return }
        result = .overwrite(selected)
        NSApp.stopModal()
        window.orderOut(nil)
    }

    @objc private func skipAction(_ sender: Any) {
        result = .skip
        NSApp.stopModal()
        window.orderOut(nil)
    }

    @objc private func selectAllAction(_ sender: Any) {
        adapter.setAll(true)
        tableView.reloadData()
    }

    @objc private func selectNoneAction(_ sender: Any) {
        adapter.setAll(false)
        tableView.reloadData()
    }

    @objc private func invertAction(_ sender: Any) {
        adapter.invertSelection()
        tableView.reloadData()
    }

    @objc private func selectNewerAction(_ sender: Any) {
        adapter.selectWhere { row in row.reason.contains("Bron nieuwer") || row.kind == .missingDest }
        tableView.reloadData()
    }

    func windowWillClose(_ notification: Notification) {
        result = .skip
        NSApp.stopModal()
    }
}

class Controller: NSObject {
    let defaultServer = "/Volumes/Archief/Artikelen-werkbestanden"
    let defaultLocal = "/Volumes/999 Games/01_Games"
    let updateGitHubOwner = "TODO_GITHUB_OWNER"
    let updateGitHubRepo = "MoveFolders"
    struct RSyncConfig {
        let path: String
        let supportsProtectArgs: Bool
        let supportsInfo: Bool
        let supportsOutFormat: Bool
        let supportsCrtimes: Bool
        let supportsXattrs: Bool
        let supportsExtendedAttributes: Bool
        let supportsNoOwner: Bool
        let supportsNoGroup: Bool
    }

    lazy var rsyncConfig: RSyncConfig = detectRsyncConfig()
    let rsyncOutFormatMarker = "__MF_CUR__:"

    var rsyncPath: String { rsyncConfig.path }

    func shellQuote(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    func detectRsyncConfig() -> RSyncConfig {
        let fm = FileManager.default
        let bundled = Bundle.main.bundlePath + "/Contents/Resources/bin/rsync"
        let candidates = [bundled, "/opt/homebrew/bin/rsync", "/usr/local/bin/rsync", "/usr/bin/rsync"]

        for path in candidates {
            guard fm.isExecutableFile(atPath: path) else { continue }
            let quoted = shellQuote(path)
            let version = runCommand("\(quoted) --version")
            if version.exitCode != 0 { continue }

            let help = runCommand("\(quoted) --help").output.lowercased()
            let config = RSyncConfig(
                path: path,
                supportsProtectArgs: help.contains("--protect-args"),
                supportsInfo: help.contains("--info"),
                supportsOutFormat: help.contains("--out-format"),
                supportsCrtimes: help.contains("--crtimes"),
                supportsXattrs: help.contains("--xattrs"),
                supportsExtendedAttributes: help.contains("--extended-attributes"),
                supportsNoOwner: help.contains("--no-owner"),
                supportsNoGroup: help.contains("--no-group")
            )
            log("Rsync geselecteerd: \(path)")
            log("Rsync features: info=\(config.supportsInfo) outFormat=\(config.supportsOutFormat) protectArgs=\(config.supportsProtectArgs) crtimes=\(config.supportsCrtimes) xattrs=\(config.supportsXattrs || config.supportsExtendedAttributes) noOwner=\(config.supportsNoOwner) noGroup=\(config.supportsNoGroup)")
            return config
        }

        let fallback = RSyncConfig(
            path: "/usr/bin/rsync",
            supportsProtectArgs: false,
            supportsInfo: false,
            supportsOutFormat: false,
            supportsCrtimes: false,
            supportsXattrs: false,
            supportsExtendedAttributes: true,
            supportsNoOwner: false,
            supportsNoGroup: false
        )
        log("Waarschuwing: geen bruikbare rsync gevonden, fallback \(fallback.path)")
        return fallback
    }

    func rsyncFlags(includeUpdate: Bool = false, includePartial: Bool = false, includeInplace: Bool = false, includeDryRun: Bool = false, includeItemize: Bool = false, includeProgress: Bool = false, includeStats: Bool = false, includeXattrs: Bool = true, outFormatMarker: String? = nil) -> String {
        var flags: [String] = ["-ah", "--modify-window=2", "--exclude '.DS_Store'"]
        let cfg = rsyncConfig

        if includeDryRun { flags.append("-n") }
        if includeUpdate { flags.append("--update") }
        if includePartial { flags.append("--partial") }
        if includeInplace { flags.append("--inplace") }
        if includeItemize { flags.append("--itemize-changes") }
        if cfg.supportsNoGroup { flags.append("--no-group") }
        if cfg.supportsNoOwner { flags.append("--no-owner") }
        if cfg.supportsProtectArgs { flags.append("--protect-args") }
        if cfg.supportsCrtimes { flags.append("--crtimes") }
        if includeXattrs {
            if cfg.supportsXattrs { flags.append("--xattrs") }
            else if cfg.supportsExtendedAttributes { flags.append("--extended-attributes") }
        }
        if let marker = outFormatMarker, cfg.supportsOutFormat {
            flags.append("--out-format='\(marker)%n'")
        } else if outFormatMarker != nil {
            // Fallback: force per-bestand output wanneer --out-format niet beschikbaar is.
            flags.append("-v")
        }

        if includeProgress {
            if cfg.supportsInfo {
                let infoItems = includeStats ? "progress2,flist2,stats2" : "progress2,flist2"
                flags.append("--info=\(infoItems)")
            } else {
                flags.append("--progress")
                if includeStats { flags.append("--stats") }
            }
        } else if includeStats {
            if cfg.supportsInfo { flags.append("--info=stats2") }
            else { flags.append("--stats") }
        }
        return flags.joined(separator: " ")
    }

    var window: NSWindow!
    var srcTable: NSTableView!
    var dstTable: NSTableView!
    var srcAdapter = TableAdapter()
    var dstAdapter = TableAdapter()
    var srcField: NSTextField!
    var dstField: NSTextField!
    var srcSort: NSPopUpButton!
    var dstSort: NSPopUpButton!
    var preScanCheckbox: NSButton!
    var deleteSourceCheckbox: NSButton!
    var xattrsCheckbox: NSButton!
    var preScanEnabled = false
    var deleteSourceEnabled = true
    var copyXattrsEnabled = false
    var xattrsDisabledForJob = false
    var xattrsDisabledMaps: Set<String> = []
    var progressWindow: NSWindow?
    var progressIndicator: NSProgressIndicator?
    var progressLabel: NSTextField?
    var progressDetail: NSTextField?
    var progressSpeed: NSTextField?
    var progressEta: NSTextField?
    var progressPhase: NSTextField?
    var progressBarTop: NSProgressIndicator?
    var progressBarMid: NSProgressIndicator?
    var progressBarBottom: NSProgressIndicator?
    var progressCancelButton: NSButton?
    var progressPostVerifyBusy: Bool = false
    var progressFallbackMessage: String = ""
    var progressFallbackDetail: String = ""
    var progressPct: Int = 0
    var progressTaskIndex: Int = 0
    var progressTaskTotal: Int = 0
    var progressTaskName: String = ""
    var progressFileDone: Int?
    var progressFileTotal: Int?
    var progressCurrentFile: String = ""
    var progressCurrentPath: String = ""
    var progressCurrentSourcePath: String = ""
    var progressCurrentDestinationPath: String = ""
    var progressEtaText: String = ""
    var isCopying: Bool = false
    var progressTaskOrder: [String] = []
    var progressTaskFileTotals: [String: Int] = [:]
    var progressOverallFileTotal: Int?
    var srcHistory: [String] = []
    var dstHistory: [String] = []
    var srcListToken: Int = 0
    var dstListToken: Int = 0
    let pendingCleanupStateQueue = DispatchQueue(label: "MoveFolders.pendingCleanup.state")
    var pendingCleanupPaths: Set<String> = []
    let transferControlQueue = DispatchQueue(label: "MoveFolders.transferControl")
    var transferCancelRequested = false
    var activeTransferProcess: Process?
    let timeTolerance: TimeInterval = 2.0
    let preScanTimeout: TimeInterval = 120
    let localPreScanTimeout: TimeInterval = 300
    let commandKillGrace: TimeInterval = 5
    // Abort rsync only after a long period without output, not by total runtime.
    let copyTimeout: TimeInterval = 1800
    var debugWindow: NSWindow?
    var debugTextView: NSTextView?
    let logFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()
    let logFormatterQueue = DispatchQueue(label: "MoveFolders.logFormatter")
    let fileInfoFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()
    let fileInfoFormatterQueue = DispatchQueue(label: "MoveFolders.fileInfoFormatter")
    let touchFormatter: DateFormatter = {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyyMMddHHmm.ss"
        return df
    }()
    let touchFormatterQueue = DispatchQueue(label: "MoveFolders.touchFormatter")

    enum XattrChoice {
        case disableMap
        case disableJob
        case continueWithXattrs
        case cancelTransfer
    }

    func setAppIcon() {
        let fm = FileManager.default
        var candidates: [URL] = []

        let bundlePath = Bundle.main.bundlePath
        if bundlePath.hasSuffix(".app"), fm.fileExists(atPath: bundlePath) {
            let icon = NSWorkspace.shared.icon(forFile: bundlePath)
            if icon.isValid {
                NSApplication.shared.applicationIconImage = icon
                return
            }
        }

        if let iconName = Bundle.main.infoDictionary?["CFBundleIconFile"] as? String,
           let resURL = Bundle.main.resourceURL {
            let base = (iconName as NSString).deletingPathExtension
            let ext = (iconName as NSString).pathExtension
            let fullName = ext.isEmpty ? "\(base).icns" : iconName
            candidates.append(resURL.appendingPathComponent(fullName))
            candidates.append(resURL.appendingPathComponent("\(base).png"))
        }

        let exeURL = URL(fileURLWithPath: CommandLine.arguments[0])
        let exeDir = exeURL.deletingLastPathComponent()
        if let files = try? fm.contentsOfDirectory(at: exeDir, includingPropertiesForKeys: nil) {
            if let icns = files.first(where: { $0.pathExtension.lowercased() == "icns" }) {
                candidates.append(icns)
            }
            if let png = files.first(where: { $0.pathExtension.lowercased() == "png" }) {
                candidates.append(png)
            }
        }

        for url in candidates {
            guard fm.fileExists(atPath: url.path) else { continue }
            if let image = NSImage(contentsOf: url) {
                NSApplication.shared.applicationIconImage = image
                return
            }
            let icon = NSWorkspace.shared.icon(forFile: url.path)
            if icon.isValid {
                NSApplication.shared.applicationIconImage = icon
                return
            }
        }
    }

    func run() {
        let app = NSApplication.shared
        app.setActivationPolicy(.regular)
        setAppIcon()

        let frame = NSRect(x: 0, y: 0, width: 1100, height: 600)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.center()
        window.title = (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String) ?? "MoveFolders"

        let content = window.contentView!

        func makeLabel(_ text: String, _ x: CGFloat, _ y: CGFloat) {
            let lbl = NSTextField(labelWithString: text)
            lbl.frame = NSRect(x: x, y: y, width: 60, height: 20)
            lbl.autoresizingMask = [.maxXMargin, .minYMargin]
            content.addSubview(lbl)
        }

        func makeTextField(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ val: String) -> NSTextField {
            let tf = NSTextField(frame: NSRect(x: x, y: y, width: w, height: 24))
            tf.stringValue = val
            tf.autoresizingMask = [.width, .minYMargin]
            content.addSubview(tf)
            return tf
        }

        func makeButton(_ title: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ action: Selector, mask: NSView.AutoresizingMask = [.minYMargin]) {
            let btn = NSButton(frame: NSRect(x: x, y: y, width: w, height: h))
            btn.title = title
            btn.bezelStyle = .rounded
            btn.target = self
            btn.action = action
            btn.autoresizingMask = mask
            content.addSubview(btn)
        }

        func makeImageButton(_ imageName: NSImage.Name, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ action: Selector, mask: NSView.AutoresizingMask = [.minYMargin]) {
            let btn = NSButton(frame: NSRect(x: x, y: y, width: size, height: size))
            btn.bezelStyle = .texturedRounded
            btn.image = NSImage(named: imageName)
            btn.imageScaling = .scaleProportionallyDown
            btn.imagePosition = .imageOnly
            btn.target = self
            btn.action = action
            btn.autoresizingMask = mask
            content.addSubview(btn)
        }

        func makeTable(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSTableView {
            let scroll = NSScrollView(frame: NSRect(x: x, y: y, width: w, height: h))
            scroll.hasVerticalScroller = true
            scroll.autoresizingMask = [.width, .height]
            let table = NSTableView(frame: scroll.bounds)
            table.autoresizingMask = [.width, .height]
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("name"))
            col.width = w - 20
            col.title = " "
            col.resizingMask = .autoresizingMask
            table.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
            table.addTableColumn(col)
            table.usesAlternatingRowBackgroundColors = true
            table.rowHeight = 22
            table.allowsMultipleSelection = true
            table.allowsEmptySelection = true
            table.headerView = nil
            scroll.documentView = table
            content.addSubview(scroll)
            return table
        }

        makeLabel("Bron:", 20, 560)
        makeLabel("Doel:", 570, 560)
        srcField = makeTextField(80, 556, 420, defaultServer)
        dstField = makeTextField(630, 556, 420, defaultLocal)
        dstField.autoresizingMask = [.minXMargin, .width, .minYMargin]
        // Sort dropdowns
        func makeSort(_ x: CGFloat, _ y: CGFloat, mask: NSView.AutoresizingMask = [.minYMargin]) -> NSPopUpButton {
            let pop = NSPopUpButton(frame: NSRect(x: x, y: y, width: 150, height: 26), pullsDown: false)
            pop.addItems(withTitles: ["Naam A-Z", "Naam Z-A", "Datum oud-nieuw", "Datum nieuw-oud"])
            pop.autoresizingMask = mask
            content.addSubview(pop)
            return pop
        }
        srcSort = makeSort(280, 520)
        dstSort = makeSort(780, 520, mask: [.minXMargin, .minYMargin])
        preScanCheckbox = NSButton(checkboxWithTitle: "Pre-scan (tellen bestanden)", target: self, action: #selector(togglePreScan))
        preScanCheckbox.frame = NSRect(x: 500, y: 520, width: 260, height: 22)
        preScanCheckbox.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(preScanCheckbox)
        deleteSourceCheckbox = NSButton(checkboxWithTitle: "Bron verwijderen na overdracht", target: self, action: #selector(toggleDeleteSource))
        deleteSourceCheckbox.frame = NSRect(x: 500, y: 498, width: 300, height: 22)
        deleteSourceCheckbox.state = .on
        deleteSourceCheckbox.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(deleteSourceCheckbox)
        xattrsCheckbox = NSButton(checkboxWithTitle: "Bestandsattributen (xattrs) kopiëren", target: self, action: #selector(toggleXattrs))
        xattrsCheckbox.frame = NSRect(x: 500, y: 476, width: 320, height: 22)
        xattrsCheckbox.state = copyXattrsEnabled ? .on : .off
        xattrsCheckbox.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(xattrsCheckbox)

        // Keep clear spacing under the option checkboxes.
        let tableY: CGFloat = 90
        let tableHeight: CGFloat = 372
        srcTable = makeTable(20, tableY, 520, tableHeight)
        srcTable.enclosingScrollView?.autoresizingMask = [.width, .height]
        dstTable = makeTable(600, tableY, 520, tableHeight)
        dstTable.enclosingScrollView?.autoresizingMask = [.minXMargin, .width, .height]

        srcTable.dataSource = srcAdapter
        srcTable.delegate = srcAdapter
        srcTable.target = self
        srcTable.doubleAction = #selector(openSrcItem)
        dstTable.dataSource = dstAdapter
        dstTable.delegate = dstAdapter
        dstTable.target = self
        dstTable.doubleAction = #selector(openDstItem)

        makeButton("Overdracht beginnen", 820, 575, 220, 32, #selector(startCopy), mask: [.minXMargin, .minYMargin])
        makeButton("Debug", 700, 575, 110, 32, #selector(toggleDebug), mask: [.minXMargin, .minYMargin])
        makeButton("Updates", 580, 575, 110, 32, #selector(checkForUpdates), mask: [.minXMargin, .minYMargin])
        makeImageButton(NSImage.folderName, 510, 554, 28, #selector(chooseSrc))
        makeImageButton(NSImage.refreshTemplateName, 535, 554, 28, #selector(swapPaths))
        makeImageButton(NSImage.folderName, 1060, 554, 28, #selector(chooseDst), mask: [.minXMargin, .minYMargin])
        makeButton("Gebruik bronpad", 20, 480, 150, 26, #selector(applySrc))
        makeButton("Terug", 180, 480, 80, 26, #selector(goBackSrc))
        makeButton("Gebruik doelpad", 700, 480, 150, 26, #selector(applyDst), mask: [.minXMargin, .minYMargin])
        makeButton("Terug", 860, 480, 80, 26, #selector(goBackDst), mask: [.minXMargin, .minYMargin])

        refreshSrc()
        refreshDst()

        window.makeKeyAndOrderFront(nil)
        setupDebugWindow()
        showDebugWindow()
        log("App gestart")
        schedulePendingDeleteCleanup(basePath: srcField.stringValue)
        setAppIcon()
        app.activate(ignoringOtherApps: true)
        app.run()
    }

    @objc func chooseSrc() {
        if let p = pickFolder(start: srcField.stringValue) {
            setSrcPath(p)
        }
    }

    @objc func chooseDst() {
        if let p = pickFolder(start: dstField.stringValue) {
            setDstPath(p)
        }
    }

    @objc func applySrc() { setSrcPath(srcField.stringValue) }
    @objc func applyDst() { setDstPath(dstField.stringValue) }
    @objc func goBackSrc() { popHistory(isSource: true) }
    @objc func goBackDst() { popHistory(isSource: false) }
    @objc func togglePreScan(_ sender: NSButton) { preScanEnabled = sender.state == .on }
    @objc func toggleDeleteSource(_ sender: NSButton) { deleteSourceEnabled = sender.state == .on }
    @objc func toggleXattrs(_ sender: NSButton) { copyXattrsEnabled = sender.state == .on }
    @objc func cancelTransfer() {
        if isTransferCancelRequested() { return }
        log("Annuleren aangevraagd door gebruiker")
        requestTransferCancellation()
        DispatchQueue.main.async {
            self.progressPhase?.stringValue = "Annuleren..."
            self.progressDetail?.stringValue = "Lopende overdracht wordt onderbroken..."
            self.progressCancelButton?.isEnabled = false
        }
    }
    @objc func swapPaths() {
        let tmp = srcField.stringValue
        setSrcPath(dstField.stringValue)
        setDstPath(tmp)
    }

    func pickFolder(start: String) -> String? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        if !start.isEmpty { panel.directoryURL = URL(fileURLWithPath: start) }
        let resp = panel.runModal()
        return resp == .OK ? panel.url?.path : nil
    }

    func showProgress(_ message: String, detail: String) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 1120, height: 190),
                            styleMask: [.titled, .closable],
                            backing: .buffered,
                            defer: false)
        panel.title = "Overdracht bezig..."
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
        panel.isMovableByWindowBackground = false
        panel.isOpaque = true
        panel.backgroundColor = NSColor.windowBackgroundColor
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        let content = panel.contentView ?? NSView(frame: panel.frame)

        let labelWidth = content.bounds.width - 40
        let labelHeight: CGFloat = 20
        let topY: CGFloat = 135
        let midY: CGFloat = 85
        let bottomY: CGFloat = 35

        func makeLine(_ text: String, _ y: CGFloat) -> NSTextField {
            let lbl = NSTextField(labelWithString: text)
            lbl.frame = NSRect(x: 20, y: y, width: labelWidth, height: labelHeight)
            lbl.alignment = .center
            lbl.lineBreakMode = .byTruncatingMiddle
            lbl.textColor = NSColor.labelColor
            lbl.font = NSFont.systemFont(ofSize: 13, weight: .regular)
            lbl.autoresizingMask = [.width, .minYMargin]
            content.addSubview(lbl)
            return lbl
        }

        func makeProgressBar(_ y: CGFloat) -> NSProgressIndicator {
            let bar = NSProgressIndicator(frame: NSRect(x: 20, y: y, width: labelWidth, height: 12))
            bar.minValue = 0
            bar.maxValue = 100
            bar.doubleValue = 0
            bar.isIndeterminate = false
            bar.controlSize = .small
            bar.style = .bar
            bar.autoresizingMask = [.width, .minYMargin]
            content.addSubview(bar)
            return bar
        }

        self.progressBarTop = makeProgressBar(120)
        self.progressBarMid = makeProgressBar(70)
        self.progressBarBottom = makeProgressBar(20)

        self.progressLabel = makeLine(message, topY)
        self.progressDetail = makeLine(detail, midY)
        self.progressPhase = makeLine("Voorbereiden...", bottomY)
        let cancelButton = NSButton(frame: NSRect(x: content.bounds.width - 190, y: 150, width: 170, height: 26))
        cancelButton.title = "Annuleer overdracht"
        cancelButton.bezelStyle = .rounded
        cancelButton.target = self
        cancelButton.action = #selector(cancelTransfer)
        cancelButton.autoresizingMask = [.minXMargin, .minYMargin]
        content.addSubview(cancelButton)
        self.progressCancelButton = cancelButton

        self.progressIndicator = self.progressBarMid

        self.progressFallbackMessage = message
        self.progressFallbackDetail = detail
        self.isCopying = false
        self.updateProgressBars()
        self.progressWindow = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        log("Progress gestart: \(message) | \(detail)")
    }

    func hideProgress() {
        progressIndicator?.stopAnimation(nil)
        progressWindow?.orderOut(nil)
        progressWindow = nil
        progressIndicator = nil
        progressLabel = nil
        progressDetail = nil
        progressSpeed = nil
        progressEta = nil
        progressPhase = nil
        progressBarTop = nil
        progressBarMid = nil
        progressBarBottom = nil
        progressCancelButton = nil
        progressPostVerifyBusy = false
        progressFallbackMessage = ""
        progressFallbackDetail = ""
        progressPct = 0
        progressTaskIndex = 0
        progressTaskTotal = 0
        progressTaskName = ""
        progressFileDone = nil
        progressFileTotal = nil
        progressCurrentFile = ""
        progressCurrentPath = ""
        progressCurrentSourcePath = ""
        progressCurrentDestinationPath = ""
        progressEtaText = ""
        isCopying = false
        progressTaskOrder = []
        progressTaskFileTotals = [:]
        progressOverallFileTotal = nil
        log("Progress gesloten")
    }

    func refreshSrc() {
        let path = srcField.stringValue
        let sortIndex = srcSort.indexOfSelectedItem
        srcListToken += 1
        let token = srcListToken
        DispatchQueue.main.async {
            self.srcAdapter.items = [TableAdapter.Item(name: "Laden...", isDir: false, modDate: Date())]
            self.srcTable.isEnabled = false
            self.srcTable.reloadData()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let names = self.listNames(path)
            let fastSort = sortIndex <= 1 ? sortIndex : 0
            let fastItems = self.sortItems(self.buildFastItems(names), sort: fastSort)
            DispatchQueue.main.async {
                guard self.srcListToken == token else { return }
                self.applyListUpdate(fastItems, to: self.srcTable, adapter: self.srcAdapter)
                self.srcTable.isEnabled = true
            }
            guard !names.isEmpty else { return }
            let withDates = sortIndex >= 2
            let metaItems = self.sortItems(self.buildMetadataItems(names, base: path, includeDates: withDates), sort: sortIndex)
            DispatchQueue.main.async {
                guard self.srcListToken == token else { return }
                self.applyListUpdate(metaItems, to: self.srcTable, adapter: self.srcAdapter)
            }
        }
    }
    func refreshDst() {
        let path = dstField.stringValue
        let sortIndex = dstSort.indexOfSelectedItem
        dstListToken += 1
        let token = dstListToken
        DispatchQueue.main.async {
            self.dstAdapter.items = [TableAdapter.Item(name: "Laden...", isDir: false, modDate: Date())]
            self.dstTable.isEnabled = false
            self.dstTable.reloadData()
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let names = self.listNames(path)
            let fastSort = sortIndex <= 1 ? sortIndex : 0
            let fastItems = self.sortItems(self.buildFastItems(names), sort: fastSort)
            DispatchQueue.main.async {
                guard self.dstListToken == token else { return }
                self.applyListUpdate(fastItems, to: self.dstTable, adapter: self.dstAdapter)
                self.dstTable.isEnabled = true
            }
            guard !names.isEmpty else { return }
            let withDates = sortIndex >= 2
            let metaItems = self.sortItems(self.buildMetadataItems(names, base: path, includeDates: withDates), sort: sortIndex)
            DispatchQueue.main.async {
                guard self.dstListToken == token else { return }
                self.applyListUpdate(metaItems, to: self.dstTable, adapter: self.dstAdapter)
            }
        }
    }

    func selectedNames(in table: NSTableView, adapter: TableAdapter) -> Set<String> {
        var names: Set<String> = []
        for idx in table.selectedRowIndexes {
            guard idx >= 0 && idx < adapter.items.count else { continue }
            names.insert(adapter.items[idx].name)
        }
        return names
    }

    func applyListUpdate(_ items: [TableAdapter.Item], to table: NSTableView, adapter: TableAdapter) {
        let selected = selectedNames(in: table, adapter: adapter)
        adapter.items = items
        table.reloadData()
        guard !selected.isEmpty else { return }
        var indexes = IndexSet()
        for (idx, item) in items.enumerated() {
            if selected.contains(item.name) {
                indexes.insert(idx)
            }
        }
        if !indexes.isEmpty {
            table.selectRowIndexes(indexes, byExtendingSelection: false)
        }
    }

    func listNames(_ path: String) -> [String] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(atPath: path) else { return [] }
        return items.filter { !$0.hasPrefix(".") }
    }

    func buildFastItems(_ names: [String]) -> [TableAdapter.Item] {
        var out: [TableAdapter.Item] = []
        out.reserveCapacity(names.count)
        for nm in names {
            out.append(.init(name: nm, isDir: false, modDate: Date.distantPast))
        }
        return out
    }

    func buildMetadataItems(_ names: [String], base: String, includeDates: Bool) -> [TableAdapter.Item] {
        let fm = FileManager.default
        var out: [TableAdapter.Item] = []
        out.reserveCapacity(names.count)
        for nm in names {
            let full = (base as NSString).appendingPathComponent(nm)
            var isDir: ObjCBool = false
            fm.fileExists(atPath: full, isDirectory: &isDir)
            let mod: Date
            if includeDates {
                let attrs = try? fm.attributesOfItem(atPath: full)
                mod = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
            } else {
                mod = Date.distantPast
            }
            out.append(.init(name: nm, isDir: isDir.boolValue, modDate: mod))
        }
        return out
    }

    func sortItems(_ items: [TableAdapter.Item], sort: Int) -> [TableAdapter.Item] {
        var out = items
        out.sort {
            if $0.isDir != $1.isDir { return $0.isDir && !$1.isDir }
            switch sort {
            case 0: return $0.name.lowercased() < $1.name.lowercased()
            case 1: return $0.name.lowercased() > $1.name.lowercased()
            case 2: return $0.modDate < $1.modDate
            case 3: return $0.modDate > $1.modDate
            default: return $0.name.lowercased() < $1.name.lowercased()
            }
        }
        return out
    }

    func updateSpeedEta(from line: String) {
        guard let etaRange = line.range(of: #"[0-9]+:[0-9]{2}:[0-9]{2}"#, options: .regularExpression) else { return }
        let eta = String(line[etaRange])
        DispatchQueue.main.async {
            guard self.isCopying else { return }
            self.progressEtaText = eta
            self.refreshProgressLines()
        }
    }

    func setSrcPath(_ path: String) {
        setPath(field: srcField, newPath: path, history: &srcHistory, refresh: refreshSrc)
        schedulePendingDeleteCleanup(basePath: srcField.stringValue)
    }

    func setDstPath(_ path: String) {
        setPath(field: dstField, newPath: path, history: &dstHistory, refresh: refreshDst)
    }

    func setPhase(_ text: String) {
        DispatchQueue.main.async {
            self.progressPhase?.stringValue = text
            self.setPostVerifyBusy(text.hasPrefix("Post-verify"))
        }
        log("Fase: \(text)")
    }

    func setPostVerifyBusy(_ busy: Bool) {
        guard let mid = progressBarMid else { return }
        if progressPostVerifyBusy == busy { return }
        progressPostVerifyBusy = busy
        if busy {
            mid.isIndeterminate = true
            mid.startAnimation(nil)
        } else {
            mid.stopAnimation(nil)
            mid.isIndeterminate = false
            mid.doubleValue = Double(max(0, min(100, progressPct)))
        }
    }

    func updateProgressTask(index: Int, total: Int, name: String) {
        DispatchQueue.main.async {
            self.isCopying = true
            self.progressTaskIndex = index
            self.progressTaskTotal = total
            self.progressTaskName = name
            self.progressCurrentFile = ""
            self.progressCurrentPath = ""
            self.progressCurrentSourcePath = ""
            self.progressCurrentDestinationPath = ""
            if let totalFiles = self.progressTaskFileTotals[name] {
                self.progressFileTotal = totalFiles
                self.progressFileDone = 0
            } else {
                self.progressFileDone = nil
                self.progressFileTotal = nil
            }
            self.progressPct = 0
            self.progressEtaText = ""
            self.refreshProgressLines()
        }
    }

    func updateProgressFromRsync(percent: Int, toChk: String?) {
        DispatchQueue.main.async {
            guard self.isCopying else { return }
            self.progressPct = percent
            if let toChk = toChk {
                let cleaned = toChk.replacingOccurrences(of: "to-chk=", with: "")
                let parts = cleaned.split(separator: "/")
                if parts.count == 2 {
                    let remaining = Int(parts[0].filter { $0.isNumber })
                    let total = Int(parts[1].filter { $0.isNumber })
                    if let remaining = remaining, let total = total, total > 0 {
                        self.progressFileTotal = total
                        self.progressFileDone = max(0, total - remaining)
                    }
                }
            }
            self.refreshProgressLines()
        }
    }

    func updateCurrentFile(from line: String, srcBase: String, dstBase: String, taskName: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let skipPrefixes = [
            "sending incremental file list",
            "receiving incremental file list",
            "sent ",
            "total size is",
            "total bytes",
            "file list size",
            "created directory",
            "building file list",
            "deleting "
        ]
        if skipPrefixes.contains(where: { trimmed.hasPrefix($0) }) { return }
        if trimmed.contains(" to-check=") || trimmed.contains(" to-chk=") { return }

        var pathCandidate: String
        if trimmed.hasPrefix(rsyncOutFormatMarker) {
            pathCandidate = String(trimmed.dropFirst(rsyncOutFormatMarker.count)).trimmingCharacters(in: .whitespaces)
        } else {
            pathCandidate = trimmed
            if let idx = pathCandidate.firstIndex(of: " ") {
                let prefix = pathCandidate[..<idx]
                if prefix.contains(">") {
                    let next = pathCandidate.index(after: idx)
                    pathCandidate = String(pathCandidate[next...]).trimmingCharacters(in: .whitespaces)
                }
            }
        }
        if pathCandidate.hasPrefix("./") {
            pathCandidate.removeFirst(2)
        }
        if pathCandidate.isEmpty || pathCandidate == "." { return }

        let relPath: String
        if pathCandidate.hasPrefix(taskName + "/") || pathCandidate == taskName || pathCandidate.hasPrefix("/") {
            relPath = pathCandidate
        } else {
            relPath = (taskName as NSString).appendingPathComponent(pathCandidate)
        }

        let name = (pathCandidate as NSString).lastPathComponent
        let srcPath: String
        let dstPath: String
        if relPath.hasPrefix("/") {
            srcPath = relPath
            dstPath = (dstBase as NSString).appendingPathComponent((relPath as NSString).lastPathComponent)
        } else {
            srcPath = (srcBase as NSString).appendingPathComponent(relPath)
            dstPath = (dstBase as NSString).appendingPathComponent(relPath)
        }
        let dstDisplay: String
        let dstPrefix = dstBase.hasSuffix("/") ? dstBase : (dstBase + "/")
        if dstPath.hasPrefix(dstPrefix) {
            dstDisplay = String(dstPath.dropFirst(dstPrefix.count))
        } else {
            dstDisplay = relPath
        }
        let dstDisplayDirRaw = (dstDisplay as NSString).deletingLastPathComponent
        let dstDisplayDir = (dstDisplayDirRaw.isEmpty || dstDisplayDirRaw == ".") ? "/" : dstDisplayDirRaw
        DispatchQueue.main.async {
            guard self.isCopying else { return }
            self.progressCurrentFile = name
            self.progressCurrentSourcePath = srcPath
            self.progressCurrentDestinationPath = dstPath
            self.progressCurrentPath = dstDisplayDir
            self.refreshProgressLines()
        }
    }

    func refreshProgressLines() {
        guard let top = progressLabel, let mid = progressDetail, let bottom = progressPhase else { return }
        let taskName = progressTaskName.isEmpty ? progressFallbackDetail : progressTaskName
        let fileName = progressCurrentFile.isEmpty ? taskName : progressCurrentFile
        let filePath = progressCurrentPath.isEmpty ? "" : progressCurrentPath
        let etaPart = progressEtaText.isEmpty ? "" : " less than \(progressEtaText)"
        let percents = computeProgressPercents()
        let topPercentText = "\(percents.file)%"
        let midPercentText = "\(percents.map)%"
        let bottomPercentText = "\(percents.overall)%"
        let topCopy = fileName.isEmpty ? "" : "  Bestand: \(fileName)"
        top.stringValue = "Completed (\(topPercentText))\(etaPart)\(topCopy)"

        let pathLine: String
        if !filePath.isEmpty {
            pathLine = "Doelpad: \(filePath) (\(midPercentText))"
        } else {
            pathLine = "Doelpad: bezig met wachtrij... (\(midPercentText))"
        }
        mid.stringValue = "\(pathLine)\(etaPart)"

        let taskLine: String
        if progressTaskTotal > 0 {
            taskLine = "Copying task \(progressTaskIndex) of \(progressTaskTotal) tasks"
        } else {
            taskLine = "Copying task"
        }
        let countPrefix: String
        if let done = progressFileDone, let total = progressFileTotal {
            countPrefix = "Bestand \(done)/\(total) | "
        } else if !taskName.isEmpty {
            countPrefix = "Taak: \(taskName) | "
        } else {
            countPrefix = ""
        }
        if let overall = computeOverallFileProgress() {
            bottom.stringValue = "\(countPrefix)\(taskLine) (\(bottomPercentText)) \(overall.done) of \(overall.total) files total\(etaPart)"
        } else if let done = progressFileDone, let total = progressFileTotal {
            bottom.stringValue = "\(countPrefix)\(taskLine) (\(bottomPercentText)) \(done) of \(total) files\(etaPart)"
        } else {
            bottom.stringValue = "\(countPrefix)\(taskLine) (\(bottomPercentText))\(etaPart)"
        }
        updateProgressBars()
    }

    func updateProgressBars() {
        let percents = computeProgressPercents()
        setProgressBar(progressBarTop, percent: percents.file)
        if progressPostVerifyBusy == false {
            setProgressBar(progressBarMid, percent: percents.map)
        }
        setProgressBar(progressBarBottom, percent: percents.overall)
    }

    func setProgressBar(_ bar: NSProgressIndicator?, percent: Int) {
        guard let bar = bar else { return }
        bar.doubleValue = Double(percent)
    }

    func computeProgressPercents() -> (file: Int, map: Int, overall: Int) {
        let mapPct = max(0, min(100, progressPct))
        let filePct: Int
        if let done = progressFileDone, let total = progressFileTotal, total > 0 {
            filePct = Int(round(Double(done) / Double(total) * 100.0))
        } else {
            filePct = mapPct
        }
        let overallPct: Int
        if progressTaskTotal > 0 {
            let completed = Double(progressTaskIndex - 1) + (Double(mapPct) / 100.0)
            overallPct = Int(round((completed / Double(progressTaskTotal)) * 100.0))
        } else {
            overallPct = mapPct
        }
        return (filePct, mapPct, overallPct)
    }

    func computeOverallFileProgress() -> (done: Int, total: Int)? {
        guard let totalAll = progressOverallFileTotal, totalAll > 0 else { return nil }
        if progressTaskOrder.isEmpty { return nil }
        var done = 0
        if progressTaskIndex > 1 {
            for i in 0..<(progressTaskIndex - 1) {
                let name = progressTaskOrder[i]
                if let count = progressTaskFileTotals[name] {
                    done += count
                }
            }
        }
        if let currentTotal = progressTaskFileTotals[progressTaskName], let currentDone = progressFileDone {
            done += min(currentDone, currentTotal)
        }
        return (done, totalAll)
    }

    func setPath(field: NSTextField, newPath: String, history: inout [String], refresh: () -> Void) {
        let trimmed = newPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let current = field.stringValue
        if !current.isEmpty && current != trimmed {
            history.append(current)
            if history.count > 50 { history.removeFirst(history.count - 50) }
        }
        field.stringValue = trimmed
        refresh()
    }

    func resetXattrRuntimeChoices() {
        xattrsDisabledForJob = false
        xattrsDisabledMaps.removeAll()
    }

    func shouldUseXattrs(forMap mapName: String) -> Bool {
        guard copyXattrsEnabled else { return false }
        if xattrsDisabledForJob { return false }
        if xattrsDisabledMaps.contains(mapName) { return false }
        return true
    }

    func extractXattrPath(from output: String) -> String? {
        for raw in output.split(separator: "\n") {
            let line = String(raw)
            guard line.contains("lsetxattr(\"") else { continue }
            guard let start = line.range(of: "lsetxattr(\"")?.upperBound else { continue }
            guard let end = line[start...].firstIndex(of: "\"") else { continue }
            return String(line[start..<end])
        }
        return nil
    }

    func promptXattrChoice(mapName: String, output: String) -> XattrChoice {
        let showAlert = {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Bestandsattributen (xattrs) geweigerd"
            var info = "Doelschijf weigert xattr metadata (Permission denied).\nMap: \(mapName)"
            if let path = self.extractXattrPath(from: output) {
                info += "\nBestand: \(path)"
            }
            info += "\n\nWat wil je doen?"
            alert.informativeText = info
            alert.addButton(withTitle: "Uitschakelen voor deze map")
            alert.addButton(withTitle: "Uitschakelen voor hele opdracht")
            alert.addButton(withTitle: "Doorgaan met xattrs")
            alert.addButton(withTitle: "Annuleer overdracht")
            let resp = alert.runModal()
            switch resp {
            case .alertFirstButtonReturn: return XattrChoice.disableMap
            case .alertSecondButtonReturn: return XattrChoice.disableJob
            case .alertThirdButtonReturn: return XattrChoice.continueWithXattrs
            default: return XattrChoice.cancelTransfer
            }
        }
        if Thread.isMainThread { return showAlert() }
        return DispatchQueue.main.sync { showAlert() }
    }

    func resetTransferCancellation() {
        transferControlQueue.sync {
            transferCancelRequested = false
            activeTransferProcess = nil
        }
    }

    func isTransferCancelRequested() -> Bool {
        transferControlQueue.sync { transferCancelRequested }
    }

    func setActiveTransferProcess(_ process: Process?) {
        transferControlQueue.sync {
            activeTransferProcess = process
        }
    }

    func requestTransferCancellation() {
        let proc: Process? = transferControlQueue.sync {
            transferCancelRequested = true
            return activeTransferProcess
        }
        guard let process = proc, process.isRunning else { return }
        log("Annuleren: SIGTERM naar proces \(process.processIdentifier)")
        process.terminate()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + commandKillGrace) {
            if process.isRunning {
                self.log("Annuleren: proces \(process.processIdentifier) reageert niet, SIGKILL")
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    func schedulePendingDeleteCleanup(basePath: String) {
        let base = basePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !base.isEmpty else { return }
        pendingCleanupStateQueue.async {
            if self.pendingCleanupPaths.contains(base) { return }
            self.pendingCleanupPaths.insert(base)
            DispatchQueue.global(qos: .utility).async {
                defer {
                    self.pendingCleanupStateQueue.async {
                        self.pendingCleanupPaths.remove(base)
                    }
                }
                self.cleanupPendingDeleteQueue(basePath: base)
            }
        }
    }

    func cleanupPendingDeleteQueue(basePath: String) {
        let fm = FileManager.default
        let queueDir = (basePath as NSString).appendingPathComponent(".MoveFolders_pending_delete")
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: queueDir, isDirectory: &isDir), isDir.boolValue else { return }

        guard let entries = try? fm.contentsOfDirectory(atPath: queueDir) else {
            log("Pending-delete: kan map niet lezen: \(queueDir)")
            return
        }
        if entries.isEmpty {
            try? fm.removeItem(atPath: queueDir)
            return
        }

        var removed = 0
        var stillBusy = 0
        var failed = 0
        for name in entries where !name.hasPrefix(".") {
            let path = (queueDir as NSString).appendingPathComponent(name)
            do {
                try fm.removeItem(atPath: path)
                removed += 1
            } catch {
                let ns = error as NSError
                let busy = (ns.domain == NSPOSIXErrorDomain && ns.code == Int(EBUSY))
                    || ((ns.userInfo[NSUnderlyingErrorKey] as? NSError).map { $0.domain == NSPOSIXErrorDomain && $0.code == Int(EBUSY) } ?? false)
                    || ns.localizedDescription.lowercased().contains("resource busy")
                if busy {
                    stillBusy += 1
                } else {
                    failed += 1
                }
                log("Pending-delete skip \(path): \(ns.domain):\(ns.code) \(error.localizedDescription)")
            }
        }

        if removed > 0 || stillBusy > 0 || failed > 0 {
            log("Pending-delete cleanup \(queueDir): verwijderd \(removed), busy \(stillBusy), fout \(failed)")
        }

        if let left = try? fm.contentsOfDirectory(atPath: queueDir), left.isEmpty {
            do {
                try fm.removeItem(atPath: queueDir)
                log("Pending-delete map verwijderd: \(queueDir)")
            } catch {
                log("Pending-delete map kon niet verwijderd worden: \(queueDir) (\(error.localizedDescription))")
            }
        }
    }

    func popHistory(isSource: Bool) {
        if isSource {
            guard let prev = srcHistory.popLast() else { return }
            srcField.stringValue = prev
            refreshSrc()
        } else {
            guard let prev = dstHistory.popLast() else { return }
            dstField.stringValue = prev
            refreshDst()
        }
    }

    @objc func openSrcItem() { navigateIntoSelection(table: srcTable, basePath: srcField.stringValue, setter: setSrcPath) }
    @objc func openDstItem() { navigateIntoSelection(table: dstTable, basePath: dstField.stringValue, setter: setDstPath) }

    func navigateIntoSelection(table: NSTableView, basePath: String, setter: (String) -> Void) {
        let row = table.clickedRow
        guard row >= 0 else { return }
        let adapter = table === srcTable ? srcAdapter : dstAdapter
        guard row < adapter.items.count else { return }
        let name = adapter.items[row].name
        guard name != "Laden..." else { return }
        let fullPath = (basePath as NSString).appendingPathComponent(name)
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue {
            setter(fullPath)
        }
    }

    enum DestinationStatus { case missing, empty, hasContent, notDirectory }

    func destinationStatus(path: String) -> DestinationStatus {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if !fm.fileExists(atPath: path, isDirectory: &isDir) { return .missing }
        if !isDir.boolValue { return .notDirectory }
        if let items = try? fm.contentsOfDirectory(atPath: path) {
            let hasContent = items.contains { !$0.hasPrefix(".") && $0 != ".DS_Store" }
            return hasContent ? .hasContent : .empty
        }
        return .hasContent
    }

    func confirmDeletion(items: [String], basePath: String) -> Bool {
        guard !items.isEmpty else { return false }
        let summary = items.prefix(5).joined(separator: ", ") + (items.count > 5 ? " … (+\(items.count - 5) meer)" : "")
        let alert = NSAlert()
        alert.messageText = "Verwijder bronitems?"
        alert.informativeText = "Wil je de bron verwijderen na succesvolle overdracht?\nBasis: \(basePath)\nItems: \(summary)"
        alert.addButton(withTitle: "Verwijder")
        alert.addButton(withTitle: "Behoud")
        let resp = alert.runModal()
        return resp == .alertFirstButtonReturn
    }

    func deleteItems(_ items: [String], from basePath: String) -> [String] {
        func isResourceBusyDeleteError(_ error: Error) -> Bool {
            let ns = error as NSError
            if ns.domain == NSPOSIXErrorDomain && ns.code == Int(EBUSY) { return true }
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                if underlying.domain == NSPOSIXErrorDomain && underlying.code == Int(EBUSY) { return true }
            }
            return ns.localizedDescription.lowercased().contains("resource busy")
        }

        func describeDeleteError(_ error: Error) -> String {
            let ns = error as NSError
            var parts: [String] = []
            parts.append(error.localizedDescription)
            parts.append("[\(ns.domain):\(ns.code)]")
            if let underlying = ns.userInfo[NSUnderlyingErrorKey] as? NSError {
                parts.append("onderliggend: \(underlying.domain):\(underlying.code) \(underlying.localizedDescription)")
            }
            return parts.joined(separator: " ")
        }

        func stageForDeferredDelete(path: String, name: String, basePath: String, fileManager: FileManager) -> String? {
            let queueDir = (basePath as NSString).appendingPathComponent(".MoveFolders_pending_delete")
            do {
                try fileManager.createDirectory(atPath: queueDir, withIntermediateDirectories: true)
            } catch {
                log("Kan pending-delete map niet maken \(queueDir): \(error.localizedDescription)")
                return nil
            }

            let ts = Int(Date().timeIntervalSince1970)
            let sanitized = name.replacingOccurrences(of: "/", with: "_")
            var candidate = (queueDir as NSString).appendingPathComponent("\(sanitized).\(ts)")
            var suffix = 1
            while fileManager.fileExists(atPath: candidate) {
                candidate = (queueDir as NSString).appendingPathComponent("\(sanitized).\(ts).\(suffix)")
                suffix += 1
            }

            do {
                try fileManager.moveItem(atPath: path, toPath: candidate)
                log("Delete staged \(path) -> \(candidate)")
                return candidate
            } catch {
                log("Stage delete failed \(path): \(describeDeleteError(error))")
                return nil
            }
        }

        var errors: [String] = []
        let fm = FileManager.default
        let retryDelays: [TimeInterval] = [1, 2, 4, 8, 12, 16]
        for nm in items {
            let path = (basePath as NSString).appendingPathComponent(nm)
            if fm.fileExists(atPath: path) {
                var lastError: Error?
                for attempt in 1...(retryDelays.count + 1) {
                    do {
                        try fm.removeItem(atPath: path)
                        lastError = nil
                        break
                    } catch {
                        lastError = error
                        let busy = isResourceBusyDeleteError(error)
                        if busy && attempt <= retryDelays.count {
                            let wait = retryDelays[attempt - 1]
                            let total = retryDelays.count + 1
                            log("Delete busy \(path): retry \(attempt + 1)/\(total) in \(Int(wait))s")
                            Thread.sleep(forTimeInterval: wait)
                            continue
                        }
                        if busy, let stagedPath = stageForDeferredDelete(path: path, name: nm, basePath: basePath, fileManager: fm) {
                            do {
                                try fm.removeItem(atPath: stagedPath)
                                log("Deferred delete direct opgeschoond: \(stagedPath)")
                            } catch {
                                log("Deferred delete blijft staan voor later: \(stagedPath) (\(describeDeleteError(error)))")
                            }
                            lastError = nil
                        }
                        break
                    }
                }
                if let error = lastError {
                    let detail = describeDeleteError(error)
                    log("Delete failed \(path): \(detail)")
                    errors.append("\(nm): \(detail)")
                }
            }
        }
        return errors
    }

    struct DryRunSummary {
        let newFiles: Int
        let changedFiles: Int
        let totalFiles: Int
        let exitCode: Int32
        let timedOut: Bool
    }

    func dryRunSummary(items: [String], srcBase: String, dstBase: String) -> DryRunSummary {
        let paths = items.map { shellQuote("\(srcBase)/\($0)") }.joined(separator: " ")
        let flags = rsyncFlags(includeUpdate: true, includeDryRun: true, includeItemize: true, includeProgress: true, includeStats: true)
        let cmd = "\(shellQuote(rsyncPath)) \(flags) \(paths) \(shellQuote(dstBase))"
        log("Pre-scan rsync start: \(items.joined(separator: ", "))")
        var newCount = 0
        var changedCount = 0
        let countQueue = DispatchQueue(label: "MoveFolders.prescan.count")
        let result = runCommandStreaming(cmd, timeout: preScanTimeout, killGrace: commandKillGrace) { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            self.log("Pre-scan: \(trimmed)")
            countQueue.sync {
                if trimmed.hasPrefix(">f++++++++") { newCount += 1 }
                else if trimmed.hasPrefix(">f") { changedCount += 1 }
            }
        }
        let counts = countQueue.sync { (newCount, changedCount) }
        if result.exitCode == 0 && result.timedOut == false {
            let totalFiles = countFiles(in: items, base: srcBase)
            log("Pre-scan done: nieuw \(counts.0), gewijzigd \(counts.1), totaal \(totalFiles), exit \(result.exitCode), timeout \(result.timedOut)")
            return DryRunSummary(newFiles: counts.0, changedFiles: counts.1, totalFiles: totalFiles, exitCode: result.exitCode, timedOut: result.timedOut)
        }
        log("Pre-scan rsync failed (exit \(result.exitCode), timeout \(result.timedOut)). Fallback to local scan.")
        return localPreScanSummary(items: items, srcBase: srcBase, dstBase: dstBase, timeout: localPreScanTimeout)
    }

    func localPreScanSummary(items: [String], srcBase: String, dstBase: String, timeout: TimeInterval?) -> DryRunSummary {
        let start = Date()
        let fm = FileManager.default
        var totalFiles = 0
        var newFiles = 0
        var changedFiles = 0
        for nm in items {
            if isTransferCancelRequested() {
                log("Local pre-scan geannuleerd")
                return DryRunSummary(newFiles: newFiles, changedFiles: changedFiles, totalFiles: totalFiles, exitCode: 130, timedOut: false)
            }
            log("Local pre-scan start: \(nm)")
            let srcRoot = (srcBase as NSString).appendingPathComponent(nm)
            let dstRoot = (dstBase as NSString).appendingPathComponent(nm)
            if let en = fm.enumerator(atPath: srcRoot) {
                for case let rel as String in en {
                    if isTransferCancelRequested() {
                        log("Local pre-scan geannuleerd tijdens \(nm)")
                        return DryRunSummary(newFiles: newFiles, changedFiles: changedFiles, totalFiles: totalFiles, exitCode: 130, timedOut: false)
                    }
                    if let timeout = timeout, Date().timeIntervalSince(start) > timeout {
                        log("Local pre-scan timeout after \(Int(timeout))s")
                        return DryRunSummary(newFiles: newFiles, changedFiles: changedFiles, totalFiles: totalFiles, exitCode: 124, timedOut: true)
                    }
                    if rel.hasSuffix(".DS_Store") { continue }
                    let src = (srcRoot as NSString).appendingPathComponent(rel)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: src, isDirectory: &isDir), isDir.boolValue { continue }
                    totalFiles += 1
                    if totalFiles % 500 == 0 {
                        log("Local pre-scan \(nm): \(totalFiles) bestanden, laatste: \(rel)")
                    }
                    let dst = (dstRoot as NSString).appendingPathComponent(rel)
                    if !fm.fileExists(atPath: dst) {
                        newFiles += 1
                        continue
                    }
                    let srcDate = (try? fm.attributesOfItem(atPath: src)[.modificationDate] as? Date) ?? Date.distantPast
                    let dstDate = (try? fm.attributesOfItem(atPath: dst)[.modificationDate] as? Date) ?? Date.distantPast
                    if abs(srcDate.timeIntervalSince1970 - dstDate.timeIntervalSince1970) > timeTolerance {
                        changedFiles += 1
                    }
                }
            }
            log("Local pre-scan klaar: \(nm)")
        }
        log("Local pre-scan done: nieuw \(newFiles), gewijzigd \(changedFiles), totaal \(totalFiles)")
        return DryRunSummary(newFiles: newFiles, changedFiles: changedFiles, totalFiles: totalFiles, exitCode: 0, timedOut: false)
    }

    func countFiles(in items: [String], base: String, progress: ((Int, String) -> Void)? = nil) -> Int {
        let fm = FileManager.default
        var count = 0
        for nm in items {
            if isTransferCancelRequested() {
                log("Tellen geannuleerd")
                return count
            }
            log("Tellen in: \(nm)")
            let full = (base as NSString).appendingPathComponent(nm)
            if let en = fm.enumerator(atPath: full) {
                for case let name as String in en {
                    if isTransferCancelRequested() {
                        log("Tellen geannuleerd tijdens \(nm)")
                        return count
                    }
                    if name == ".DS_Store" { continue }
                    let p = (full as NSString).appendingPathComponent(name)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: p, isDirectory: &isDir), !isDir.boolValue {
                        count += 1
                        if count % 500 == 0 {
                            log("Tellen \(nm): \(count) bestanden, laatste: \(name)")
                            progress?(count, name)
                        }
                    }
                }
            }
            log("Tellen klaar: \(nm)")
        }
        return count
    }

    func timestampsEqual(items: [String], srcBase: String, dstBase: String) -> (allEqual: Bool, firstMismatch: String?) {
        let fm = FileManager.default
        for nm in items {
            let srcRoot = (srcBase as NSString).appendingPathComponent(nm)
            let dstRoot = (dstBase as NSString).appendingPathComponent(nm)
            if let en = fm.enumerator(atPath: srcRoot) {
                for case let rel as String in en {
                    if rel.hasSuffix(".DS_Store") { continue }
                    let src = (srcRoot as NSString).appendingPathComponent(rel)
                    let dst = (dstRoot as NSString).appendingPathComponent(rel)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: src, isDirectory: &isDir), isDir.boolValue { continue }
                    let srcDate = (try? fm.attributesOfItem(atPath: src)[.modificationDate] as? Date) ?? Date.distantPast
                    let dstDate = (try? fm.attributesOfItem(atPath: dst)[.modificationDate] as? Date)
                    if dstDate == nil { return (false, (nm as NSString).appendingPathComponent(rel)) }
                    if let dstDate = dstDate, abs(srcDate.timeIntervalSince1970 - dstDate.timeIntervalSince1970) > timeTolerance {
                        return (false, (nm as NSString).appendingPathComponent(rel))
                    }
                }
            }
        }
        return (true, nil)
    }

    func collectMismatches(items: [String], srcBase: String, dstBase: String) -> [Mismatch] {
        let fm = FileManager.default
        var result: [Mismatch] = []
        for nm in items {
            let srcRoot = (srcBase as NSString).appendingPathComponent(nm)
            let dstRoot = (dstBase as NSString).appendingPathComponent(nm)
            if let en = fm.enumerator(atPath: srcRoot) {
                for case let rel as String in en {
                    if rel.hasSuffix(".DS_Store") { continue }
                    let src = (srcRoot as NSString).appendingPathComponent(rel)
                    let dst = (dstRoot as NSString).appendingPathComponent(rel)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: src, isDirectory: &isDir), isDir.boolValue { continue }
                    if !fm.fileExists(atPath: dst) {
                        result.append(Mismatch(kind: .missingDest, relPath: (nm as NSString).appendingPathComponent(rel)))
                        continue
                    }
                    let srcDate = (try? fm.attributesOfItem(atPath: src)[.modificationDate] as? Date) ?? Date.distantPast
                    let dstDate = (try? fm.attributesOfItem(atPath: dst)[.modificationDate] as? Date) ?? Date.distantPast
                    if abs(srcDate.timeIntervalSince1970 - dstDate.timeIntervalSince1970) > timeTolerance {
                        result.append(Mismatch(kind: .timeDiff, relPath: (nm as NSString).appendingPathComponent(rel)))
                    }
                }
            }
            if let en = fm.enumerator(atPath: dstRoot) {
                for case let rel as String in en {
                    if rel.hasSuffix(".DS_Store") { continue }
                    let dst = (dstRoot as NSString).appendingPathComponent(rel)
                    let src = (srcRoot as NSString).appendingPathComponent(rel)
                    var isDir: ObjCBool = false
                    if fm.fileExists(atPath: dst, isDirectory: &isDir), isDir.boolValue { continue }
                    if !fm.fileExists(atPath: src) {
                        result.append(Mismatch(kind: .extraDest, relPath: (nm as NSString).appendingPathComponent(rel)))
                    }
                }
            }
        }
        return result
    }

    func formatBytes(_ bytes: Int64?) -> String {
        guard let bytes = bytes else { return "-" }
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    func formatDate(_ date: Date?) -> String {
        guard let date = date else { return "-" }
        return fileInfoFormatterQueue.sync { fileInfoFormatter.string(from: date) }
    }

    func fileInfoString(size: Int64?, date: Date?) -> String {
        if size == nil && date == nil { return "-" }
        return "\(formatBytes(size)) | \(formatDate(date))"
    }

    func modificationDate(atPath path: String) -> Date? {
        return try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date
    }

    func modificationDatesMatch(_ a: Date?, _ b: Date?) -> Bool {
        guard let a = a, let b = b else { return false }
        return abs(a.timeIntervalSince1970 - b.timeIntervalSince1970) <= timeTolerance
    }

    func touchTimestampString(for date: Date) -> String {
        return touchFormatterQueue.sync { touchFormatter.string(from: date) }
    }

    func runTouchModificationDate(path: String, date: Date) -> Bool {
        let task = Process()
        task.launchPath = "/usr/bin/touch"
        task.arguments = ["-mt", touchTimestampString(for: date), path]
        do {
            try task.run()
            task.waitUntilExit()
            return task.terminationStatus == 0
        } catch {
            log("touch -mt start mislukt voor \(path): \(error.localizedDescription)")
            return false
        }
    }

    func setModificationDate(path: String, date: Date) -> Bool {
        do {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: path)
            if modificationDatesMatch(modificationDate(atPath: path), date) { return true }
        } catch {
            log("mtime setAttributes mislukt voor \(path): \(error.localizedDescription)")
        }

        if runTouchModificationDate(path: path, date: date),
           modificationDatesMatch(modificationDate(atPath: path), date) {
            return true
        }
        log("mtime herstel mislukt voor \(path)")
        return false
    }

    func buildFileMap(items: [String], base: String, progress: ((Int, String) -> Void)? = nil) -> [String: FileEntry] {
        let fm = FileManager.default
        var result: [String: FileEntry] = [:]
        var scanned = 0
        for nm in items {
            let root = (base as NSString).appendingPathComponent(nm)
            guard let en = fm.enumerator(atPath: root) else {
                log("Kan map niet lezen: \(root)")
                continue
            }
            for case let rel as String in en {
                if rel.hasSuffix(".DS_Store") { continue }
                let full = (root as NSString).appendingPathComponent(rel)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue { continue }
                let attrs = try? fm.attributesOfItem(atPath: full)
                let size = (attrs?[.size] as? NSNumber)?.int64Value
                let mod = attrs?[.modificationDate] as? Date
                let relFull = (nm as NSString).appendingPathComponent(rel)
                result[relFull] = FileEntry(size: size, modDate: mod)
                scanned += 1
                if scanned == 1 || scanned % 250 == 0 {
                    progress?(scanned, relFull)
                }
            }
        }
        progress?(scanned, "klaar")
        return result
    }

    func diffFileMaps(src: [String: FileEntry], dst: [String: FileEntry]) -> [Mismatch] {
        var mismatches: [Mismatch] = []

        for (path, srcInfo) in src {
            guard let dstInfo = dst[path] else {
                mismatches.append(Mismatch(kind: .missingDest, relPath: path))
                continue
            }
            let srcDate = srcInfo.modDate
            let dstDate = dstInfo.modDate
            if srcDate == nil || dstDate == nil {
                mismatches.append(Mismatch(kind: .timeDiff, relPath: path))
                continue
            }
            if let s = srcDate, let d = dstDate, abs(s.timeIntervalSince1970 - d.timeIntervalSince1970) > timeTolerance {
                mismatches.append(Mismatch(kind: .timeDiff, relPath: path))
                continue
            }
            if let s = srcInfo.size, let d = dstInfo.size, s != d {
                mismatches.append(Mismatch(kind: .sizeDiff, relPath: path))
                continue
            }
        }

        return mismatches
    }

    func normalizeTimestampOnlyMismatches(mismatches: [Mismatch], srcMap: [String: FileEntry], dstMap: [String: FileEntry], dstBase: String) -> (fixed: Int, failed: Int) {
        var fixed = 0
        var failed = 0

        for m in mismatches where m.kind == .timeDiff {
            guard let srcInfo = srcMap[m.relPath], let dstInfo = dstMap[m.relPath] else { continue }
            guard let srcDate = srcInfo.modDate else { continue }
            guard let srcSize = srcInfo.size, let dstSize = dstInfo.size, srcSize == dstSize else { continue }
            let dstFull = (dstBase as NSString).appendingPathComponent(m.relPath)
            if setModificationDate(path: dstFull, date: srcDate) {
                fixed += 1
            } else {
                failed += 1
            }
        }
        return (fixed, failed)
    }

    func buildMismatchDetails(_ mismatches: [Mismatch], srcBase: String, dstBase: String) -> [MismatchDetail] {
        let fm = FileManager.default
        var details: [MismatchDetail] = []
        for m in mismatches {
            let srcFull = (srcBase as NSString).appendingPathComponent(m.relPath)
            let dstFull = (dstBase as NSString).appendingPathComponent(m.relPath)

            let srcAttrs = try? fm.attributesOfItem(atPath: srcFull)
            let dstAttrs = try? fm.attributesOfItem(atPath: dstFull)
            let srcSize = (srcAttrs?[.size] as? NSNumber)?.int64Value
            let dstSize = (dstAttrs?[.size] as? NSNumber)?.int64Value
            let srcDate = srcAttrs?[.modificationDate] as? Date
            let dstDate = dstAttrs?[.modificationDate] as? Date

            let reason: String
            let canOverwrite: Bool
            switch m.kind {
            case .missingDest:
                reason = "Ontbreekt op doel"
                canOverwrite = true
            case .timeDiff:
                if let s = srcDate, let d = dstDate {
                    let delta = abs(s.timeIntervalSince1970 - d.timeIntervalSince1970)
                    reason = String(format: "Tijdverschil (%.0fs)", delta)
                } else {
                    reason = "Tijdverschil"
                }
                canOverwrite = true
            case .sizeDiff:
                reason = "Grootte verschilt"
                canOverwrite = true
            case .extraDest:
                reason = "Extra op doel"
                canOverwrite = false
            }

            var ageHint: String?
            if let s = srcDate, let d = dstDate, m.kind == .timeDiff || m.kind == .sizeDiff {
                if s.timeIntervalSince1970 > d.timeIntervalSince1970 {
                    ageHint = "Bron nieuwer"
                } else if s.timeIntervalSince1970 < d.timeIntervalSince1970 {
                    ageHint = "Bron ouder"
                } else {
                    ageHint = "Gelijke datum"
                }
            }
            let reasonText = ageHint != nil ? "\(reason) | \(ageHint!)" : reason

            let srcInfo = (m.kind == .extraDest) ? "-" : fileInfoString(size: srcSize, date: srcDate)
            let dstInfo = (m.kind == .missingDest) ? "-" : fileInfoString(size: dstSize, date: dstDate)

            let detail = MismatchDetail(
                kind: m.kind,
                relPath: m.relPath,
                reason: reasonText,
                srcInfo: srcInfo,
                dstInfo: dstInfo,
                canOverwrite: canOverwrite,
                selected: false
            )
            details.append(detail)
        }
        return details
    }

    func overwriteMismatches(_ details: [MismatchDetail], srcBase: String, dstBase: String, mapName: String) {
        guard !details.isEmpty else { return }
        for d in details where d.canOverwrite {
            if isTransferCancelRequested() { return }
            let dstFull = (dstBase as NSString).appendingPathComponent(d.relPath)
            let dstDir = (dstFull as NSString).deletingLastPathComponent
            try? FileManager.default.createDirectory(atPath: dstDir, withIntermediateDirectories: true)
            let srcFull = (srcBase as NSString).appendingPathComponent(d.relPath)

            var maxAttempts = 3
            var includeXattrs = shouldUseXattrs(forMap: mapName)
            var lastExitCode: Int32 = 1
            var lastOutput = ""
            var success = false

            for attempt in 1...maxAttempts {
                let useInplace = attempt >= 2
                let flags = rsyncFlags(includePartial: true, includeInplace: useInplace, includeXattrs: includeXattrs)
                let cmd = "\(shellQuote(rsyncPath)) \(flags) \(shellQuote(srcFull)) \(shellQuote(dstDir))"
                let mode = useInplace ? "fallback --inplace" : "standaard"
                let xattrMode = includeXattrs ? "met xattrs" : "zonder xattrs"
                log("Mismatch overwrite start: \(d.relPath) (\(attempt)/\(maxAttempts), \(mode), \(xattrMode))")

                let result = runCommand(cmd)
                lastExitCode = result.exitCode
                lastOutput = result.output

                if result.exitCode == 0 {
                    if let srcDate = modificationDate(atPath: srcFull) {
                        if setModificationDate(path: dstFull, date: srcDate) {
                            log("Mismatch overwrite mtime hersteld: \(d.relPath)")
                        }
                    }
                    success = true
                    break
                }

                if includeXattrs && isXattrPermissionFailure(exitCode: result.exitCode, output: result.output, timedOut: false) {
                    let choice = promptXattrChoice(mapName: mapName, output: result.output)
                    switch choice {
                    case .disableMap:
                        xattrsDisabledMaps.insert(mapName)
                        includeXattrs = false
                        if attempt >= maxAttempts { maxAttempts += 1 }
                        log("Xattrs uitgeschakeld voor map \(mapName); mismatch overwrite opnieuw zonder xattrs")
                        continue
                    case .disableJob:
                        xattrsDisabledForJob = true
                        includeXattrs = false
                        if attempt >= maxAttempts { maxAttempts += 1 }
                        log("Xattrs uitgeschakeld voor hele opdracht; mismatch overwrite opnieuw zonder xattrs")
                        continue
                    case .continueWithXattrs:
                        log("Doorgaan met xattrs na permissiefout: \(d.relPath)")
                    case .cancelTransfer:
                        log("Gebruiker annuleerde overdracht na xattr-permissiefout")
                        requestTransferCancellation()
                        return
                    }
                }

                if isRetryableCopyFailure(exitCode: result.exitCode, output: result.output, timedOut: false), attempt < maxAttempts {
                    let waitTime = Double(attempt)
                    log("Mismatch overwrite retry na fout \(result.exitCode), wachten \(Int(waitTime))s: \(d.relPath)")
                    Thread.sleep(forTimeInterval: waitTime)
                    continue
                }
                break
            }

            if success == false {
                let trimmed = lastOutput.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    log("Mismatch overwrite failed: \(d.relPath) (code \(lastExitCode))")
                } else {
                    let head = trimmed.split(separator: "\n").prefix(2).joined(separator: " | ")
                    log("Mismatch overwrite failed: \(d.relPath) (code \(lastExitCode)) | \(head)")
                }
            }
        }
    }

    enum TransferStatus {
        case success
        case warning(String)
        case failed(String)
    }

    struct TransferSummary {
        let name: String
        let status: TransferStatus
    }

    enum CopyResult {
        case success
        case warning(String)
        case failed(String)
        case cancelled
    }

    func postCopyCheck(items: [String], srcBase: String, dstBase: String) -> TransferSummary {
        if isTransferCancelRequested() {
            return TransferSummary(name: items.joined(separator: ", "), status: .warning("Geannuleerd door gebruiker"))
        }
        let mapName = items.first ?? ""
        let preScanEstimate = progressTaskFileTotals[mapName] ?? 0
        var srcScanned = 0
        var dstScanned = 0

        func updatePostVerifyUI(detail: String, estimatedPercent: Int) {
            let pct = max(0, min(100, estimatedPercent))
            DispatchQueue.main.async {
                self.progressPct = pct
                self.progressDetail?.stringValue = "\(detail) | ~\(pct)%"
                self.refreshProgressLines()
            }
        }

        setPhase("Post-verify (bron scannen)")
        updatePostVerifyUI(detail: "Post-verify bron: starten...", estimatedPercent: 1)
        let srcMap = buildFileMap(items: items, base: srcBase) { count, last in
            srcScanned = count
            let srcEstimate = preScanEstimate > 0 ? max(preScanEstimate, srcScanned) : max(srcScanned, 1)
            let pct = Int((Double(min(srcScanned, srcEstimate)) / Double(max(srcEstimate * 2, 1))) * 100.0)
            updatePostVerifyUI(detail: "Post-verify bron: \(count) bestanden | \(last)", estimatedPercent: pct)
        }
        let srcCount = srcMap.count
        updatePostVerifyUI(detail: "Post-verify bron: \(srcCount) bestanden | klaar", estimatedPercent: 50)

        setPhase("Post-verify (doel scannen)")
        updatePostVerifyUI(detail: "Post-verify doel: starten...", estimatedPercent: 51)
        var dstMap = buildFileMap(items: items, base: dstBase) { count, last in
            dstScanned = count
            let dstEstimate = max(srcCount, max(dstScanned, 1))
            let done = srcCount + min(dstScanned, dstEstimate)
            let total = max(srcCount + dstEstimate, 1)
            let pct = Int((Double(done) / Double(total)) * 100.0)
            updatePostVerifyUI(detail: "Post-verify doel: \(count) bestanden | \(last)", estimatedPercent: pct)
        }
        var dstCount = dstMap.count
        var mismatchesInitial = diffFileMaps(src: srcMap, dst: dstMap)
        log("Post-verify counts: src \(srcCount), dst \(dstCount), mismatches \(mismatchesInitial.count)")
        if dstCount > srcCount {
            log("Post-verify: doel bevat \(dstCount - srcCount) extra bestanden; genegeerd volgens instelling")
        }

        if !mismatchesInitial.isEmpty {
            setPhase("Post-verify (timestamps herstellen)")
            let repaired = normalizeTimestampOnlyMismatches(mismatches: mismatchesInitial, srcMap: srcMap, dstMap: dstMap, dstBase: dstBase)
            if repaired.fixed > 0 || repaired.failed > 0 {
                log("Post-verify timestamp herstel: \(repaired.fixed) aangepast, \(repaired.failed) mislukt")
                updatePostVerifyUI(detail: "Post-verify timestamps hersteld: \(repaired.fixed), mislukt: \(repaired.failed)", estimatedPercent: 95)
            }
            if repaired.fixed > 0 {
                dstMap = buildFileMap(items: items, base: dstBase)
                dstCount = dstMap.count
                mismatchesInitial = diffFileMaps(src: srcMap, dst: dstMap)
                log("Post-verify na timestamp-herstel: src \(srcCount), dst \(dstCount), mismatches \(mismatchesInitial.count)")
            }
        }

        let extraText = dstCount > srcCount ? ", extra op doel \(dstCount - srcCount) genegeerd" : ""
        updatePostVerifyUI(detail: "Post-verify: bron \(srcCount), doel \(dstCount), mismatches \(mismatchesInitial.count)\(extraText)", estimatedPercent: 100)

        if mismatchesInitial.isEmpty {
            if deleteSourceEnabled == false {
                setPhase("Bron behouden")
                log("Opschonen overgeslagen (bron behouden): \(items.joined(separator: ", "))")
                return TransferSummary(name: items.joined(separator: ", "), status: .success)
            }
            setPhase("Opschonen")
            let errors = deleteItems(items, from: srcBase)
            if errors.isEmpty {
                return TransferSummary(name: items.joined(separator: ", "), status: .success)
            }
            let msg = errors.joined(separator: "\n")
            if Thread.isMainThread {
                alert("Overdracht voltooid, maar enkele items konden niet verwijderd worden:\n\(msg)")
            } else {
                DispatchQueue.main.sync {
                    self.alert("Overdracht voltooid, maar enkele items konden niet verwijderd worden:\n\(msg)")
                }
            }
            return TransferSummary(name: items.joined(separator: ", "), status: .failed("Bron niet volledig verwijderd"))
        }

        let details = buildMismatchDetails(mismatchesInitial, srcBase: srcBase, dstBase: dstBase)
        let headerText = details.isEmpty
            ? "Geen mismatch-bestanden gevonden, maar telling/timestamps wijken af."
            : "Selecteer bestanden om te overschrijven:"
        let outcome: MismatchWindowController.Result
        if Thread.isMainThread {
            let dialog = MismatchWindowController(details: details, headerText: headerText)
            outcome = dialog.runModal()
        } else {
            outcome = DispatchQueue.main.sync {
                let dialog = MismatchWindowController(details: details, headerText: headerText)
                return dialog.runModal()
            }
        }
        let outcomeStatus: TransferStatus
        switch outcome {
        case .skip:
            outcomeStatus = .warning("Mismatchs overgeslagen")
        case .overwrite(let selected):
            overwriteMismatches(selected, srcBase: srcBase, dstBase: dstBase, mapName: items.first ?? "")
            outcomeStatus = .warning("Mismatchs overschreven")
        }
        if deleteSourceEnabled == false {
            setPhase("Bron behouden")
            log("Opschonen overgeslagen na mismatch-afhandeling (bron behouden): \(items.joined(separator: ", "))")
            return TransferSummary(name: items.joined(separator: ", "), status: outcomeStatus)
        }
        setPhase("Opschonen")
        let errors = deleteItems(items, from: srcBase)
        if errors.isEmpty {
            return TransferSummary(name: items.joined(separator: ", "), status: outcomeStatus)
        }
        let msg = errors.joined(separator: "\n")
        if Thread.isMainThread {
            alert("Overdracht voltooid, maar enkele items konden niet verwijderd worden:\n\(msg)")
        } else {
            DispatchQueue.main.sync {
                self.alert("Overdracht voltooid, maar enkele items konden niet verwijderd worden:\n\(msg)")
            }
        }
        return TransferSummary(name: items.joined(separator: ", "), status: .failed("Bron niet volledig verwijderd"))
    }

    func runCommand(_ cmd: String) -> (exitCode: Int32, output: String) {
        log("Run command: \(cmd)")
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", cmd]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        task.launch()
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(decoding: data, as: UTF8.self)
        log("Command exit: \(task.terminationStatus)")
        return (task.terminationStatus, output)
    }

    func runCommandStreaming(_ cmd: String, timeout: TimeInterval? = nil, killGrace: TimeInterval = 5, onLine: @escaping (String) -> Void) -> (exitCode: Int32, output: String, timedOut: Bool) {
        log("Run command (stream): \(cmd)")
        let task = Process()
        task.launchPath = "/bin/sh"
        task.arguments = ["-c", cmd]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe

        var outputData = Data()
        var buffer = ""
        let sem = DispatchSemaphore(value: 0)
        let lastOutputQueue = DispatchQueue(label: "MoveFolders.runCommandStreaming.lastOutput")
        var lastOutput = Date()
        let timeoutQueue = DispatchQueue(label: "MoveFolders.runCommandStreaming.timeout")
        var didTimeout = false
        let heartbeatTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        heartbeatTimer.schedule(deadline: .now() + 5, repeating: 5)
        heartbeatTimer.setEventHandler {
            let since = lastOutputQueue.sync { Date().timeIntervalSince(lastOutput) }
            if since >= 5 {
                self.log("Command running, no output for \(Int(since))s")
            }
        }
        let timeoutTimer: DispatchSourceTimer?
        if let timeout = timeout {
            let t = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            t.schedule(deadline: .now() + timeout)
            t.setEventHandler {
                let alreadyTimedOut = timeoutQueue.sync { didTimeout }
                if alreadyTimedOut { return }
                timeoutQueue.sync { didTimeout = true }
                self.log("Command timeout after \(Int(timeout))s, sending SIGTERM")
                if task.isRunning {
                    task.terminate()
                    DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + killGrace) {
                        if task.isRunning {
                            self.log("Command still running after \(Int(killGrace))s, sending SIGKILL")
                            kill(task.processIdentifier, SIGKILL)
                        }
                    }
                }
            }
            timeoutTimer = t
        } else {
            timeoutTimer = nil
        }

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard data.count > 0 else { return }
            outputData.append(data)
            guard let chunk = String(data: data, encoding: .utf8) else { return }
            lastOutputQueue.sync { lastOutput = Date() }
            buffer += chunk
            var lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
            if buffer.last != "\n" {
                buffer = String(lines.removeLast())
            } else {
                buffer = ""
            }
            for line in lines {
                onLine(String(line))
            }
        }

        task.terminationHandler = { _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            heartbeatTimer.cancel()
            timeoutTimer?.cancel()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            outputData.append(data)
            if let tail = String(data: data, encoding: .utf8), !tail.isEmpty {
                buffer += tail
            }
            if !buffer.isEmpty {
                onLine(buffer)
                buffer = ""
            }
            sem.signal()
        }

        do {
            try task.run()
        } catch {
            heartbeatTimer.cancel()
            timeoutTimer?.cancel()
            log("Command start failed: \(error.localizedDescription)")
            return (1, "", false)
        }
        log("Command pid: \(task.processIdentifier)")
        heartbeatTimer.resume()
        timeoutTimer?.resume()
        sem.wait()
        log("Command exit: \(task.terminationStatus) reason \(task.terminationReason.rawValue)")
        let timedOut = timeoutQueue.sync { didTimeout }
        return (task.terminationStatus, String(decoding: outputData, as: UTF8.self), timedOut)
    }

    func isRetryableCopyFailure(exitCode: Int32, output: String, timedOut: Bool) -> Bool {
        guard timedOut == false else { return false }
        let lower = output.lowercased()
        if exitCode == 11 {
            if lower.contains("resource busy (16)") { return true }
            if lower.contains("input/output error (5)") { return true }
            if lower.contains("broken pipe (32)") { return true }
        }
        if exitCode == 23 {
            if lower.contains("read errors mapping") { return true }
            if lower.contains("input/output error (5)") { return true }
        }
        return false
    }

    func isXattrPermissionFailure(exitCode: Int32, output: String, timedOut: Bool) -> Bool {
        guard timedOut == false else { return false }
        guard exitCode == 23 || exitCode == 13 || exitCode == 1 else { return false }
        let lower = output.lowercased()
        if lower.contains("rsync_xal_set") && lower.contains("permission denied (13)") { return true }
        if lower.contains("com.apple.provenance") && lower.contains("permission denied (13)") { return true }
        return false
    }

    func copySingleItem(name: String, srcBase: String, dstBase: String, index: Int, total: Int) -> CopyResult {
        func runAttempt(useInplace: Bool, includeXattrs: Bool, attempt: Int, maxAttempts: Int) -> (ok: Bool, exitCode: Int32, output: String, timedOut: Bool) {
            if self.isTransferCancelRequested() {
                return (false, 130, "Geannuleerd door gebruiker", false)
            }
            let srcFull = "\(srcBase)/\(name)"
            let flags = rsyncFlags(includeUpdate: true, includePartial: true, includeInplace: useInplace, includeProgress: true, includeXattrs: includeXattrs, outFormatMarker: rsyncOutFormatMarker)
            let cmd = "\(shellQuote(rsyncPath)) \(flags) \(shellQuote(srcFull)) \(shellQuote(dstBase))"
            let baseMode = useInplace ? "fallback --inplace" : "standaard"
            let mode = includeXattrs ? baseMode : "\(baseMode), zonder xattrs"
            log("Copy rsync start: \(name) (\(attempt)/\(maxAttempts), \(mode))")

            let task = Process()
            task.launchPath = "/bin/sh"
            task.arguments = ["-c", cmd]
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe

            var outputData = Data()
            let sem = DispatchSemaphore(value: 0)
            let lastOutputQueue = DispatchQueue(label: "MoveFolders.copy.lastOutput")
            var lastOutput = Date()
            let timeoutQueue = DispatchQueue(label: "MoveFolders.copy.timeout")
            var didTimeout = false
            let heartbeatTimer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
            heartbeatTimer.schedule(deadline: .now() + 5, repeating: 5)
            heartbeatTimer.setEventHandler {
                let since = lastOutputQueue.sync { Date().timeIntervalSince(lastOutput) }
                if since >= 5 {
                    self.log("Copy running, no output for \(Int(since))s")
                }
                if self.isTransferCancelRequested() {
                    if task.isRunning {
                        self.log("Copy annuleren: stop actief rsync-proces")
                        task.terminate()
                    }
                    return
                }
                if self.copyTimeout > 0 && since >= self.copyTimeout {
                    let alreadyTimedOut = timeoutQueue.sync { didTimeout }
                    if alreadyTimedOut { return }
                    timeoutQueue.sync { didTimeout = true }
                    self.log("Copy idle timeout after \(Int(self.copyTimeout))s, sending SIGTERM")
                    if task.isRunning {
                        task.terminate()
                        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + self.commandKillGrace) {
                            if task.isRunning {
                                self.log("Copy still running after \(Int(self.commandKillGrace))s, sending SIGKILL")
                                kill(task.processIdentifier, SIGKILL)
                            }
                        }
                    }
                }
            }
            pipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                guard data.count > 0 else { return }
                outputData.append(data)
                guard let chunk = String(data: data, encoding: .utf8) else { return }
                lastOutputQueue.sync { lastOutput = Date() }
                let lines = chunk.split(separator: "\n")
                for l in lines {
                    let trimmed = l.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        var logLine = trimmed
                        if logLine.hasPrefix(self.rsyncOutFormatMarker) {
                            let rel = String(logLine.dropFirst(self.rsyncOutFormatMarker.count)).trimmingCharacters(in: .whitespaces)
                            logLine = rel.isEmpty ? "bestandsupdate" : "bestandsupdate: \(rel)"
                        }
                        self.log("rsync: \(logLine)")
                    }
                    self.updateSpeedEta(from: trimmed)
                    if let pctRange = trimmed.range(of: #"([0-9]+)%"#, options: .regularExpression) {
                        let pctStr = String(trimmed[pctRange]).replacingOccurrences(of: "%", with: "")
                        var toChk: String?
                        if let toChkRange = trimmed.range(of: #"to-chk=[^)]+"#, options: .regularExpression) {
                            toChk = String(trimmed[toChkRange])
                        }
                        if let pctVal = Double(pctStr) {
                            DispatchQueue.main.async {
                                self.progressIndicator?.doubleValue = pctVal
                                self.updateProgressFromRsync(percent: Int(pctVal), toChk: toChk)
                            }
                        }
                    } else if !trimmed.isEmpty {
                        self.updateCurrentFile(from: trimmed, srcBase: srcBase, dstBase: dstBase, taskName: name)
                    }
                }
            }

            task.terminationHandler = { _ in
                pipe.fileHandleForReading.readabilityHandler = nil
                heartbeatTimer.cancel()
                self.setActiveTransferProcess(nil)
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                outputData.append(data)
                sem.signal()
            }

            do { try task.run() } catch {
                let output = "Kan rsync niet starten: \(error.localizedDescription)"
                self.log(output)
                return (false, 1, output, false)
            }
            self.setActiveTransferProcess(task)
            log("Copy command pid: \(task.processIdentifier)")
            heartbeatTimer.resume()
            sem.wait()
            self.setActiveTransferProcess(nil)

            let timedOut = timeoutQueue.sync { didTimeout }
            let output = String(decoding: outputData, as: UTF8.self)
            if task.terminationStatus != 0 {
                let extra = timedOut ? " (timeout)" : ""
                self.log("rsync fout \(name): code \(task.terminationStatus)\(extra)")
            }
            return (task.terminationStatus == 0 && timedOut == false, task.terminationStatus, output, timedOut)
        }

        var maxAttempts = 3
        var finalOutput = ""
        var finalExitCode: Int32 = 1
        var finalTimedOut = false
        var includeXattrs = shouldUseXattrs(forMap: name)

        for attempt in 1...maxAttempts {
            if isTransferCancelRequested() {
                log("Kopie geannuleerd: \(name)")
                return .cancelled
            }
            let useInplace = attempt >= 2
            let result = runAttempt(useInplace: useInplace, includeXattrs: includeXattrs, attempt: attempt, maxAttempts: maxAttempts)
            if isTransferCancelRequested() {
                log("Kopie geannuleerd tijdens rsync: \(name)")
                return .cancelled
            }
            if result.ok {
                return .success
            }
            finalOutput = result.output
            finalExitCode = result.exitCode
            finalTimedOut = result.timedOut

            if includeXattrs && isXattrPermissionFailure(exitCode: result.exitCode, output: result.output, timedOut: result.timedOut) {
                let choice = promptXattrChoice(mapName: name, output: result.output)
                switch choice {
                case .disableMap:
                    xattrsDisabledMaps.insert(name)
                    includeXattrs = false
                    if attempt >= maxAttempts { maxAttempts += 1 }
                    log("Xattrs uitgeschakeld voor map \(name); herstart kopie zonder xattrs")
                    continue
                case .disableJob:
                    xattrsDisabledForJob = true
                    includeXattrs = false
                    if attempt >= maxAttempts { maxAttempts += 1 }
                    log("Xattrs uitgeschakeld voor hele opdracht; herstart kopie zonder xattrs")
                    continue
                case .continueWithXattrs:
                    log("Doorgaan met xattrs na permissiefout in map \(name)")
                case .cancelTransfer:
                    log("Gebruiker annuleerde overdracht na xattr-permissiefout")
                    requestTransferCancellation()
                    return .cancelled
                }
            }

            let retryable = isRetryableCopyFailure(exitCode: result.exitCode, output: result.output, timedOut: result.timedOut)
            if retryable && attempt < maxAttempts {
                let waitTime = Double(attempt)
                log("Retry kopie \(name) na fout \(result.exitCode), wachten \(Int(waitTime))s")
                Thread.sleep(forTimeInterval: waitTime)
                continue
            }
            break
        }

        if finalExitCode == 23 && finalTimedOut == false {
            let lower = finalOutput.lowercased()
            var warning = "Rsync waarschuwing (code 23): niet alle files/attrs gekopieerd; bron blijft staan."
            if lower.contains("read errors mapping") || lower.contains("[sender] read errors") {
                warning += " Bronbestand gaf een leesfout op de netwerkschijf."
            }
            log("Kopie waarschuwing \(name): \(warning)")
            return .warning(warning)
        }

        let extra = finalTimedOut ? " (timeout)" : ""
        let lower = finalOutput.lowercased()
        var hint = ""
        if lower.contains("read errors mapping") || lower.contains("[sender] read errors") {
            hint = " | bronbestand gaf een leesfout op de netwerkschijf"
        }
        let failMsg = "Kopie mislukt (code \(finalExitCode)\(extra)\(hint))"
        log("Kopie fout \(name): \(failMsg)")
        return .failed(failMsg)
    }

    @objc func startCopy() {
        let idxs = srcTable.selectedRowIndexes
        guard idxs.count > 0 else {
            alert("Geen selectie in de bron.")
            return
        }
        let srcPath = srcField.stringValue
        let dstPath = dstField.stringValue
        let items = idxs.compactMap { i -> String? in
            guard i >= 0 && i < srcAdapter.items.count else { return nil }
            return srcAdapter.items[i].name
        }
        resetTransferCancellation()
        resetXattrRuntimeChoices()
        let summary = items.prefix(3).joined(separator: ", ") + (items.count > 3 ? " … (+\(items.count - 3) meer)" : "")
        log("Start copy: \(items.joined(separator: ", "))")
        log("Instelling xattrs: \(copyXattrsEnabled ? "aan" : "uit")")
        DispatchQueue.main.async {
            self.showProgress("Bezig met overdracht...", detail: summary)
            self.setPhase("Controle doel")
            self.progressTaskOrder = items
            self.progressTaskFileTotals = [:]
            self.progressOverallFileTotal = nil
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var summaries: [TransferSummary] = []
            var didCancel = false
            if self.preScanEnabled {
                var totalAll = 0
                var perMap: [String: Int] = [:]
                for (idx, name) in items.enumerated() {
                    if self.isTransferCancelRequested() {
                        didCancel = true
                        break
                    }
                    DispatchQueue.main.async { self.setPhase("Pre-scan \(idx + 1)/\(items.count): \(name)") }
                    let total = self.countFiles(in: [name], base: srcPath) { count, last in
                        DispatchQueue.main.async {
                            self.progressDetail?.stringValue = "Tellen: \(count) | \(last)"
                        }
                    }
                    if self.isTransferCancelRequested() {
                        didCancel = true
                        break
                    }
                    perMap[name] = total
                    totalAll += total
                    DispatchQueue.main.async {
                        self.progressDetail?.stringValue = "Bestanden totaal: \(total) (map) | Totaal: \(totalAll)"
                    }
                }
                DispatchQueue.main.async {
                    self.progressTaskFileTotals = perMap
                    self.progressOverallFileTotal = totalAll
                }
            }
            transferLoop: for (idx, name) in items.enumerated() {
                if self.isTransferCancelRequested() {
                    didCancel = true
                    break
                }
                // Snelle doelcheck (geen volledige pre-scan)
                DispatchQueue.main.async { self.setPhase("Controle doel \(idx + 1)/\(items.count): \(name)") }
                let dstItem = (dstPath as NSString).appendingPathComponent(name)
                let dstStatus = self.destinationStatus(path: dstItem)
                let statusText: String
                switch dstStatus {
                case .missing: statusText = "ontbreekt"
                case .empty: statusText = "leeg"
                case .hasContent: statusText = "bevat bestanden"
                case .notDirectory: statusText = "geen map"
                }
                self.log("Doelstatus \(name): \(statusText)")
                if dstStatus == .notDirectory {
                    DispatchQueue.main.async {
                        self.alert("Doelpad bestaat al als bestand:\n\(dstItem)\nKies een andere doelmap.")
                    }
                    continue
                }
                if dstStatus == .hasContent {
                    self.log("Doelmap bestaat al, automatisch doorgaan: \(dstItem)")
                }

                if self.preScanEnabled {
                    let total = self.progressTaskFileTotals[name] ?? 0
                    self.log("Pre-scan count \(name): \(total) bestanden")
                    DispatchQueue.main.async {
                        if let overall = self.progressOverallFileTotal {
                            self.progressDetail?.stringValue = "Bestanden totaal: \(total) (map) | Totaal: \(overall)"
                        } else {
                            self.progressDetail?.stringValue = "Bestanden totaal: \(total)"
                        }
                    }
                    if total == 0 {
                        DispatchQueue.main.async {
                            self.alert("Geen bestanden gevonden in \(name).")
                        }
                        continue
                    }
                }

                // Kopiëren per map
                DispatchQueue.main.async {
                    self.setPhase("Kopiëren \(idx + 1)/\(items.count): \(name)")
                    self.updateProgressTask(index: idx + 1, total: items.count, name: name)
                    self.progressIndicator?.doubleValue = 0
                }
                let copyResult = self.copySingleItem(name: name, srcBase: srcPath, dstBase: dstPath, index: idx + 1, total: items.count)
                switch copyResult {
                case .failed(let msg):
                    self.log("Kopie mislukt: \(name)")
                    summaries.append(TransferSummary(name: name, status: .failed(msg)))
                    DispatchQueue.main.async {
                        self.refreshDst()
                        self.refreshSrc()
                    }
                    continue
                case .warning(let msg):
                    self.log("Kopie met waarschuwing: \(name)")
                    summaries.append(TransferSummary(name: name, status: .warning(msg)))
                    DispatchQueue.main.async {
                        self.refreshDst()
                        self.refreshSrc()
                    }
                    continue
                case .cancelled:
                    self.log("Kopie geannuleerd: \(name)")
                    didCancel = true
                    break transferLoop
                case .success:
                    break
                }

                if self.isTransferCancelRequested() {
                    didCancel = true
                    break
                }
                // Post-verify + opschonen per map
                DispatchQueue.main.async { self.setPhase("Post-verify \(idx + 1)/\(items.count): \(name)") }
                let summary = self.postCopyCheck(items: [name], srcBase: srcPath, dstBase: dstPath)
                summaries.append(summary)
                DispatchQueue.main.async {
                    self.refreshDst()
                    self.refreshSrc()
                }
            }
            if didCancel {
                summaries.append(TransferSummary(name: "Overdracht", status: .warning("Geannuleerd door gebruiker")))
            }
            DispatchQueue.main.async {
                self.hideProgress()
                self.showSummary(summaries)
            }
        }
    }

    func alert(_ msg: String) {
        log("Alert: \(msg)")
        let alert = NSAlert()
        alert.messageText = msg
        alert.runModal()
    }

    func summarizeList(_ items: [String], maxItems: Int = 5) -> String {
        guard !items.isEmpty else { return "-" }
        let shown = items.prefix(maxItems).joined(separator: ", ")
        if items.count > maxItems {
            return "\(shown) (+\(items.count - maxItems) meer)"
        }
        return shown
    }

    func showSummary(_ summaries: [TransferSummary]) {
        guard !summaries.isEmpty else { return }
        var ok: [String] = []
        var warn: [String] = []
        var fail: [String] = []

        for s in summaries {
            switch s.status {
            case .success:
                ok.append(s.name)
            case .warning(let msg):
                warn.append("\(s.name): \(msg)")
            case .failed(let msg):
                fail.append("\(s.name): \(msg)")
            }
        }

        var lines: [String] = []
        lines.append("Samenvatting overdrachten:")
        lines.append("OK: \(summarizeList(ok))")
        lines.append("Waarschuwingen: \(summarizeList(warn))")
        lines.append("Fouten: \(summarizeList(fail))")
        alert(lines.joined(separator: "\n"))
    }

    func setupDebugWindow() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 700, height: 300),
                            styleMask: [.titled, .closable, .resizable],
                            backing: .buffered,
                            defer: false)
        panel.title = "Debug logs"
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false

        let scroll = NSScrollView(frame: panel.contentView?.bounds ?? .zero)
        scroll.hasVerticalScroller = true
        scroll.autoresizingMask = [.width, .height]
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.black
        textView.textColor = NSColor.white
        textView.insertionPointColor = NSColor.white
        textView.selectedTextAttributes = [.backgroundColor: NSColor.darkGray, .foregroundColor: NSColor.white]
        textView.typingAttributes = [.foregroundColor: NSColor.white]
        textView.autoresizingMask = [.width, .height]
        scroll.documentView = textView
        panel.contentView?.addSubview(scroll)

        self.debugWindow = panel
        self.debugTextView = textView
    }

    func showDebugWindow() {
        debugWindow?.center()
        debugWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func toggleDebug() {
        guard let win = debugWindow else {
            setupDebugWindow()
            showDebugWindow()
            return
        }
        if win.isVisible {
            win.orderOut(nil)
        } else {
            showDebugWindow()
        }
    }

    @objc func checkForUpdates() {
        guard updateGitHubOwner != "TODO_GITHUB_OWNER", updateGitHubOwner.isEmpty == false else {
            alert("Updatecontrole is nog niet gekoppeld aan GitHub.\nStel updateGitHubOwner/updateGitHubRepo in en publiceer releases met een .pkg installer.")
            return
        }
        guard let url = URL(string: "https://api.github.com/repos/\(updateGitHubOwner)/\(updateGitHubRepo)/releases/latest") else {
            alert("Update-URL is ongeldig.")
            return
        }

        log("Updatecontrole start: \(url.absoluteString)")
        let task = URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async { self.alert("Updatecontrole mislukt:\n\(error.localizedDescription)") }
                return
            }
            guard let data = data else {
                DispatchQueue.main.async { self.alert("Updatecontrole mislukt: geen response.") }
                return
            }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                DispatchQueue.main.async { self.alert("Updatecontrole mislukt: response kon niet gelezen worden.") }
                return
            }
            if let message = json["message"] as? String, json["tag_name"] == nil {
                DispatchQueue.main.async { self.alert("Updatecontrole mislukt:\n\(message)") }
                return
            }

            let latestVersion = (json["tag_name"] as? String) ?? (json["name"] as? String) ?? ""
            let releaseURLString = (json["html_url"] as? String) ?? ""
            let assets = json["assets"] as? [[String: Any]] ?? []
            let pkgURLString = assets.compactMap { asset -> String? in
                guard let name = asset["name"] as? String,
                      name.lowercased().hasSuffix(".pkg") else { return nil }
                return asset["browser_download_url"] as? String
            }.first

            DispatchQueue.main.async {
                self.handleUpdateResult(latestVersion: latestVersion, releaseURLString: releaseURLString, packageURLString: pkgURLString)
            }
        }
        task.resume()
    }

    func handleUpdateResult(latestVersion: String, releaseURLString: String, packageURLString: String?) {
        let currentVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "0"
        guard compareVersions(latestVersion, currentVersion) == .orderedDescending else {
            alert("Je gebruikt de nieuwste versie.\nHuidig: \(currentVersion)\nLaatste: \(latestVersion.isEmpty ? "-" : latestVersion)")
            return
        }

        let alert = NSAlert()
        alert.messageText = "Update beschikbaar"
        alert.informativeText = "Huidig: \(currentVersion)\nNieuw: \(latestVersion)"
        let hasPackage = packageURLString != nil
        if hasPackage {
            alert.addButton(withTitle: "Download installer")
        }
        alert.addButton(withTitle: "Open release")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()

        if hasPackage, response == .alertFirstButtonReturn, let pkgURLString = packageURLString, let pkgURL = URL(string: pkgURLString) {
            NSWorkspace.shared.open(pkgURL)
        } else if response == (hasPackage ? .alertSecondButtonReturn : .alertFirstButtonReturn), let releaseURL = URL(string: releaseURLString) {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionParts(lhs)
        let right = versionParts(rhs)
        let count = max(left.count, right.count)
        for idx in 0..<count {
            let l = idx < left.count ? left[idx] : 0
            let r = idx < right.count ? right[idx] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    func versionParts(_ version: String) -> [Int] {
        version
            .split { !$0.isNumber }
            .compactMap { Int($0) }
    }

    func log(_ message: String) {
        let ts = logFormatterQueue.sync { logFormatter.string(from: Date()) }
        let line = "[\(ts)] \(message)"
        print(line)
        DispatchQueue.main.async {
            guard let textView = self.debugTextView, let storage = textView.textStorage else { return }
            let font = textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: NSColor.white,
                .font: font
            ]
            storage.append(NSAttributedString(string: line + "\n", attributes: attrs))
            if storage.length > 200_000 {
                let trim = storage.length - 150_000
                storage.deleteCharacters(in: NSRange(location: 0, length: trim))
            }
            textView.scrollToEndOfDocument(nil)
        }
    }
}

let controller = Controller()
controller.run()
