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

class Controller: NSObject, NSWindowDelegate, NSApplicationDelegate {
    let defaultServer = "/Volumes/Archief/Artikelen-werkbestanden"
    let defaultLocal = "/Volumes/999 Games/01_Games"
    let updateGitHubOwner = "thomasbriet"
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

    func rsyncFlags(includeUpdate: Bool = false, includePartial: Bool = false, includeInplace: Bool = false, includeDryRun: Bool = false, includeItemize: Bool = false, includeProgress: Bool = false, includePerFileProgress: Bool = false, includeStats: Bool = false, includeXattrs: Bool = true, includePermissions: Bool = true, includeDelete: Bool = false, outFormatMarker: String? = nil) -> String {
        var flags: [String] = ["-ah", "--modify-window=2", "--exclude '.DS_Store'"]
        let cfg = rsyncConfig

        if includeDryRun { flags.append("-n") }
        if includeUpdate { flags.append("--update") }
        if includePartial { flags.append("--partial") }
        if includeInplace { flags.append("--inplace") }
        if includeItemize { flags.append("--itemize-changes") }
        if includeDelete { flags.append("--delete") }
        if !includePermissions { flags.append("--no-perms") }
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
            if includePerFileProgress {
                flags.append("--progress")
            } else if cfg.supportsInfo {
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
    var tabView: NSTabView!
    var moveTabContent: NSView!
    var syncTabContent: NSView!
    var srcTable: NSTableView!
    var dstTable: NSTableView!
    var srcAdapter = TableAdapter()
    var dstAdapter = TableAdapter()
    var srcLabel: NSTextField!
    var dstLabel: NSTextField!
    var srcField: NSTextField!
    var dstField: NSTextField!
    var recentSourcePopup: NSPopUpButton!
    var recentDestinationPopup: NSPopUpButton!
    var favoritePopup: NSPopUpButton!
    var srcSort: NSPopUpButton!
    var dstSort: NSPopUpButton!
    var preScanCheckbox: NSButton!
    var skipEmptyFoldersCheckbox: NSButton!
    var deleteSourceCheckbox: NSButton!
    var xattrsCheckbox: NSButton!
    var startCopyButton: NSButton!
    var debugButton: NSButton!
    var transferLogButton: NSButton!
    var updatesButton: NSButton!
    var resumeButton: NSButton!
    var saveFavoriteButton: NSButton!
    var syncProfilePopup: NSPopUpButton!
    var newSyncProfileButton: NSButton!
    var saveSyncProfileButton: NSButton!
    var toggleSyncProfileButton: NSButton!
    var runSyncProfileButton: NSButton!
    var syncStatusLabel: NSTextField!
    var syncNameLabel: NSTextField!
    var syncSrcLabel: NSTextField!
    var syncDstLabel: NSTextField!
    var syncIntervalLabel: NSTextField!
    var syncNameField: NSTextField!
    var syncSrcField: NSTextField!
    var syncDstField: NSTextField!
    var syncIntervalField: NSTextField!
    var syncEnabledCheckbox: NSButton!
    var syncDeleteExtraCheckbox: NSButton!
    var syncXattrsCheckbox: NSButton!
    var syncAutoReconnectCheckbox: NSButton!
    var chooseSyncSrcButton: NSButton!
    var chooseSyncDstButton: NSButton!
    var syncProgressTitleLabel: NSTextField!
    var syncProgressDetailLabel: NSTextField!
    var syncProgressSpeedLabel: NSTextField!
    var syncProgressBar: NSProgressIndicator!
    var chooseSrcButton: NSButton!
    var swapPathsButton: NSButton!
    var chooseDstButton: NSButton!
    var applySrcButton: NSButton!
    var backSrcButton: NSButton!
    var applyDstButton: NSButton!
    var backDstButton: NSButton!
    var preScanEnabled = false
    var skipEmptyFoldersEnabled = true
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
    var progressSpeedText: String = ""
    var progressCurrentFilePercent: Int?
    var progressTransferStartDate: Date?
    var progressTaskStartDate: Date?
    var isCopying: Bool = false
    var progressTaskOrder: [String] = []
    var progressTaskFileTotals: [String: Int] = [:]
    var progressOverallFileTotal: Int?
    var srcHistory: [String] = []
    var dstHistory: [String] = []
    var recentSourcePaths: [String] = []
    var recentDestinationPaths: [String] = []
    var favoritePresets: [FavoriteTransferPreset] = []
    var lastResumeJob: ResumableTransferJob?
    var syncProfiles: [SyncProfile] = []
    var syncRunningProfileIds: Set<String> = []
    var syncReconnectLastAttempt: [String: Date] = [:]
    var syncTimer: DispatchSourceTimer?
    var selectedSyncProfileId: String?
    var syncProgressStates: [String: SyncProgressState] = [:]
    var srcListToken: Int = 0
    var dstListToken: Int = 0
    let recentSourceDefaults = UserDefaults(suiteName: "com.thomasbriet.MoveFolders") ?? UserDefaults.standard
    let recentSourceDefaultsKey = "recentSourcePaths"
    let recentDestinationDefaultsKey = "recentDestinationPaths"
    let favoritePresetsDefaultsKey = "favoriteTransferPresets"
    let resumeJobDefaultsKey = "lastResumeJob"
    let syncProfilesDefaultsKey = "syncProfiles"
    let recentSourceLimit = 5
    let favoritePresetLimit = 20
    let resumeStateQueue = DispatchQueue(label: "MoveFolders.resumeState")
    let syncStateQueue = DispatchQueue(label: "MoveFolders.syncState")
    let syncReconnectInterval: TimeInterval = 5 * 60
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
    var transferLogWindow: NSWindow?
    var transferLogTextView: NSTextView?
    var transferLogFileHandle: FileHandle?
    let transferLogQueue = DispatchQueue(label: "MoveFolders.transferLog")
    lazy var transferLogURL: URL = {
        let library = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library", isDirectory: true)
        return library
            .appendingPathComponent("Logs", isDirectory: true)
            .appendingPathComponent("MoveFolders", isDirectory: true)
            .appendingPathComponent("overdrachten.log")
    }()
    let logFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "HH:mm:ss"
        return df
    }()
    let logFormatterQueue = DispatchQueue(label: "MoveFolders.logFormatter")
    let transferLogFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df
    }()
    let transferLogFormatterQueue = DispatchQueue(label: "MoveFolders.transferLogFormatter")
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

    struct TransferOptions: Codable {
        let preScanEnabled: Bool
        let skipEmptyFoldersEnabled: Bool
        let deleteSourceEnabled: Bool
        let copyXattrsEnabled: Bool
    }

    struct ResumableTransferJob: Codable {
        let srcPath: String
        let dstPath: String
        let items: [String]
        let options: TransferOptions
        let reason: String
        let createdAt: Date
    }

    struct FavoriteTransferPreset: Codable {
        let id: String
        var name: String
        var srcPath: String
        var dstPath: String
        var options: TransferOptions
        var updatedAt: Date
    }

    struct SyncProfile: Codable {
        let id: String
        var name: String
        var srcPath: String
        var dstPath: String
        var intervalMinutes: Int
        var enabled: Bool
        var deleteExtra: Bool
        var copyXattrs: Bool
        var autoReconnect: Bool?
        var srcRemountURL: String?
        var srcRelativePathOnVolume: String?
        var dstRemountURL: String?
        var dstRelativePathOnVolume: String?
        var lastRunAt: Date?
        var lastStatus: String
        var consecutiveFailures: Int
        var updatedAt: Date
    }

    struct NetworkMountInfo {
        let remountURL: String
        let relativePath: String
    }

    struct SyncProgressState {
        var percent: Int
        var speed: String
        var eta: String
        var detail: String
        var status: String
        var isRunning: Bool
        var succeeded: Bool?
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
        app.delegate = self
        setupApplicationMenu(app)
        setAppIcon()

        let frame = NSRect(x: 0, y: 0, width: 1100, height: 600)
        window = NSWindow(contentRect: frame, styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 980, height: 560)
        window.contentMinSize = NSSize(width: 980, height: 540)
        window.delegate = self
        window.center()
        window.title = (Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String) ?? "MoveFolders"

        let rootContent = window.contentView!
        tabView = NSTabView(frame: rootContent.bounds)
        tabView.autoresizingMask = [.width, .height]
        rootContent.addSubview(tabView)

        moveTabContent = NSView(frame: tabView.bounds)
        syncTabContent = NSView(frame: tabView.bounds)

        let moveItem = NSTabViewItem(identifier: "move")
        moveItem.label = "Move folders"
        moveItem.view = moveTabContent
        tabView.addTabViewItem(moveItem)

        let syncItem = NSTabViewItem(identifier: "sync")
        syncItem.label = "Sync folders"
        syncItem.view = syncTabContent
        tabView.addTabViewItem(syncItem)

        let content = moveTabContent!
        let syncContent = syncTabContent!

        func makeLabel(_ text: String, _ x: CGFloat, _ y: CGFloat, in parent: NSView = content) -> NSTextField {
            let lbl = NSTextField(labelWithString: text)
            lbl.frame = NSRect(x: x, y: y, width: 60, height: 20)
            lbl.autoresizingMask = []
            parent.addSubview(lbl)
            return lbl
        }

        func makeTextField(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ val: String, in parent: NSView = content) -> NSTextField {
            let tf = NSTextField(frame: NSRect(x: x, y: y, width: w, height: 24))
            tf.stringValue = val
            tf.autoresizingMask = []
            parent.addSubview(tf)
            return tf
        }

        func makeButton(_ title: String, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ action: Selector, mask: NSView.AutoresizingMask = [.minYMargin], in parent: NSView = content) -> NSButton {
            let btn = NSButton(frame: NSRect(x: x, y: y, width: w, height: h))
            btn.title = title
            btn.bezelStyle = .rounded
            btn.target = self
            btn.action = action
            btn.autoresizingMask = []
            parent.addSubview(btn)
            return btn
        }

        func makeImageButton(_ imageName: NSImage.Name, _ x: CGFloat, _ y: CGFloat, _ size: CGFloat, _ action: Selector, mask: NSView.AutoresizingMask = [.minYMargin], in parent: NSView = content) -> NSButton {
            let btn = NSButton(frame: NSRect(x: x, y: y, width: size, height: size))
            btn.bezelStyle = .texturedRounded
            btn.image = NSImage(named: imageName)
            btn.imageScaling = .scaleProportionallyDown
            btn.imagePosition = .imageOnly
            btn.target = self
            btn.action = action
            btn.autoresizingMask = []
            parent.addSubview(btn)
            return btn
        }

        func makePopup(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ action: Selector, in parent: NSView = content) -> NSPopUpButton {
            let pop = NSPopUpButton(frame: NSRect(x: x, y: y, width: w, height: 26), pullsDown: true)
            pop.target = self
            pop.action = action
            pop.autoresizingMask = []
            parent.addSubview(pop)
            return pop
        }

        func makeTable(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, in parent: NSView = content) -> NSTableView {
            let scroll = NSScrollView(frame: NSRect(x: x, y: y, width: w, height: h))
            scroll.hasVerticalScroller = true
            scroll.autoresizingMask = []
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
            parent.addSubview(scroll)
            return table
        }

        srcLabel = makeLabel("Bron:", 20, 560)
        dstLabel = makeLabel("Doel:", 570, 560)
        srcField = makeTextField(80, 556, 420, defaultServer)
        dstField = makeTextField(630, 556, 420, defaultLocal)
        recentSourcePaths = loadRecentSourcePaths()
        recentDestinationPaths = loadRecentDestinationPaths()
        favoritePresets = loadFavoritePresets()
        lastResumeJob = loadResumeJob()
        syncProfiles = loadSyncProfiles()
        recentSourcePopup = makePopup(380, 575, 180, #selector(selectRecentSource))
        recentDestinationPopup = makePopup(380, 545, 180, #selector(selectRecentDestination))
        favoritePopup = makePopup(20, 575, 170, #selector(selectFavoritePreset))
        refreshRecentSourceMenu()
        refreshRecentDestinationMenu()
        refreshFavoriteMenu()
        // Sort dropdowns
        func makeSort(_ x: CGFloat, _ y: CGFloat, mask: NSView.AutoresizingMask = [.minYMargin]) -> NSPopUpButton {
            let pop = NSPopUpButton(frame: NSRect(x: x, y: y, width: 150, height: 26), pullsDown: false)
            pop.addItems(withTitles: ["Naam A-Z", "Naam Z-A", "Datum oud-nieuw", "Datum nieuw-oud"])
            pop.autoresizingMask = []
            content.addSubview(pop)
            return pop
        }
        srcSort = makeSort(280, 520)
        dstSort = makeSort(780, 520, mask: [.minXMargin, .minYMargin])
        preScanCheckbox = NSButton(checkboxWithTitle: "Pre-scan (tellen bestanden)", target: self, action: #selector(togglePreScan))
        preScanCheckbox.frame = NSRect(x: 500, y: 520, width: 260, height: 22)
        preScanCheckbox.autoresizingMask = []
        content.addSubview(preScanCheckbox)
        skipEmptyFoldersCheckbox = NSButton(checkboxWithTitle: "Lege mappen overslaan", target: self, action: #selector(toggleSkipEmptyFolders))
        skipEmptyFoldersCheckbox.frame = NSRect(x: 500, y: 498, width: 260, height: 22)
        skipEmptyFoldersCheckbox.state = .on
        skipEmptyFoldersCheckbox.autoresizingMask = []
        content.addSubview(skipEmptyFoldersCheckbox)
        deleteSourceCheckbox = NSButton(checkboxWithTitle: "Bron verwijderen na overdracht", target: self, action: #selector(toggleDeleteSource))
        deleteSourceCheckbox.frame = NSRect(x: 500, y: 476, width: 300, height: 22)
        deleteSourceCheckbox.state = .on
        deleteSourceCheckbox.autoresizingMask = []
        content.addSubview(deleteSourceCheckbox)
        xattrsCheckbox = NSButton(checkboxWithTitle: "Bestandsattributen (xattrs) kopiëren", target: self, action: #selector(toggleXattrs))
        xattrsCheckbox.frame = NSRect(x: 500, y: 454, width: 320, height: 22)
        xattrsCheckbox.state = copyXattrsEnabled ? .on : .off
        xattrsCheckbox.autoresizingMask = []
        content.addSubview(xattrsCheckbox)

        // Keep clear spacing under the option checkboxes and path buttons.
        let tableY: CGFloat = 80
        let tableHeight: CGFloat = 334
        srcTable = makeTable(20, tableY, 520, tableHeight)
        dstTable = makeTable(600, tableY, 520, tableHeight)

        srcTable.dataSource = srcAdapter
        srcTable.delegate = srcAdapter
        srcTable.target = self
        srcTable.doubleAction = #selector(openSrcItem)
        dstTable.dataSource = dstAdapter
        dstTable.delegate = dstAdapter
        dstTable.target = self
        dstTable.doubleAction = #selector(openDstItem)

        startCopyButton = makeButton("Overdracht beginnen", 820, 575, 220, 32, #selector(startCopy), mask: [.minXMargin, .minYMargin])
        debugButton = makeButton("Debug", 700, 575, 110, 32, #selector(toggleDebug), mask: [.minXMargin, .minYMargin])
        transferLogButton = makeButton("Log", 640, 575, 55, 32, #selector(toggleTransferLog), mask: [.minXMargin, .minYMargin])
        updatesButton = makeButton("Updates", 580, 575, 110, 32, #selector(checkForUpdates), mask: [.minXMargin, .minYMargin])
        resumeButton = makeButton("Hervat", 480, 575, 90, 32, #selector(resumeLastTransfer))
        saveFavoriteButton = makeButton("Bewaar", 200, 575, 90, 32, #selector(saveCurrentFavorite))
        chooseSrcButton = makeImageButton(NSImage.folderName, 510, 554, 28, #selector(chooseSrc))
        swapPathsButton = makeImageButton(NSImage.refreshTemplateName, 535, 554, 28, #selector(swapPaths))
        chooseDstButton = makeImageButton(NSImage.folderName, 1060, 554, 28, #selector(chooseDst), mask: [.minXMargin, .minYMargin])
        applySrcButton = makeButton("Gebruik bronpad", 20, 424, 150, 26, #selector(applySrc))
        backSrcButton = makeButton("Terug", 180, 424, 80, 26, #selector(goBackSrc))
        applyDstButton = makeButton("Gebruik doelpad", 700, 424, 150, 26, #selector(applyDst), mask: [.minXMargin, .minYMargin])
        backDstButton = makeButton("Terug", 860, 424, 80, 26, #selector(goBackDst), mask: [.minXMargin, .minYMargin])
        syncProfilePopup = makePopup(20, 480, 220, #selector(selectSyncProfile), in: syncContent)
        newSyncProfileButton = makeButton("Nieuw profiel", 250, 477, 105, 28, #selector(createNewSyncProfile), in: syncContent)
        saveSyncProfileButton = makeButton("Bewaar sync", 365, 477, 110, 28, #selector(saveCurrentSyncProfile), in: syncContent)
        toggleSyncProfileButton = makeButton("Sync aan/uit", 485, 477, 110, 28, #selector(toggleSelectedSyncProfile), in: syncContent)
        runSyncProfileButton = makeButton("Sync nu", 605, 477, 90, 28, #selector(runSelectedSyncProfileNow), in: syncContent)
        syncNameLabel = makeLabel("Naam:", 20, 430, in: syncContent)
        syncNameField = makeTextField(120, 426, 420, "Nieuwe sync", in: syncContent)
        syncSrcLabel = makeLabel("Folder A:", 20, 390, in: syncContent)
        syncSrcField = makeTextField(120, 386, 760, defaultServer, in: syncContent)
        chooseSyncSrcButton = makeImageButton(NSImage.folderName, 890, 384, 28, #selector(chooseSyncSrc), in: syncContent)
        syncDstLabel = makeLabel("Folder B:", 20, 350, in: syncContent)
        syncDstField = makeTextField(120, 346, 760, defaultLocal, in: syncContent)
        chooseSyncDstButton = makeImageButton(NSImage.folderName, 890, 344, 28, #selector(chooseSyncDst), in: syncContent)
        syncIntervalLabel = makeLabel("Interval:", 20, 305, in: syncContent)
        syncIntervalField = makeTextField(120, 301, 90, "15", in: syncContent)
        syncEnabledCheckbox = NSButton(checkboxWithTitle: "Automatisch syncen", target: nil, action: nil)
        syncEnabledCheckbox.state = .on
        syncEnabledCheckbox.autoresizingMask = []
        syncContent.addSubview(syncEnabledCheckbox)
        syncDeleteExtraCheckbox = NSButton(checkboxWithTitle: "Extra bestanden op doel verwijderen", target: nil, action: nil)
        syncDeleteExtraCheckbox.state = .off
        syncDeleteExtraCheckbox.autoresizingMask = []
        syncContent.addSubview(syncDeleteExtraCheckbox)
        syncXattrsCheckbox = NSButton(checkboxWithTitle: "Bestandsattributen (xattrs) kopiëren", target: nil, action: nil)
        syncXattrsCheckbox.state = copyXattrsEnabled ? .on : .off
        syncXattrsCheckbox.autoresizingMask = []
        syncContent.addSubview(syncXattrsCheckbox)
        syncAutoReconnectCheckbox = NSButton(checkboxWithTitle: "Netwerkschijven elke 5 minuten verbinden", target: nil, action: nil)
        syncAutoReconnectCheckbox.state = .on
        syncAutoReconnectCheckbox.autoresizingMask = []
        syncContent.addSubview(syncAutoReconnectCheckbox)
        syncProgressTitleLabel = NSTextField(labelWithString: "Voortgang: geen sync actief")
        syncProgressTitleLabel.lineBreakMode = .byTruncatingMiddle
        syncProgressTitleLabel.autoresizingMask = []
        syncContent.addSubview(syncProgressTitleLabel)
        syncProgressDetailLabel = NSTextField(labelWithString: "Bestand: -")
        syncProgressDetailLabel.lineBreakMode = .byTruncatingMiddle
        syncProgressDetailLabel.autoresizingMask = []
        syncContent.addSubview(syncProgressDetailLabel)
        syncProgressSpeedLabel = NSTextField(labelWithString: "Snelheid: - | ETA: -")
        syncProgressSpeedLabel.lineBreakMode = .byTruncatingMiddle
        syncProgressSpeedLabel.autoresizingMask = []
        syncContent.addSubview(syncProgressSpeedLabel)
        syncProgressBar = NSProgressIndicator(frame: NSRect(x: 0, y: 0, width: 200, height: 12))
        syncProgressBar.minValue = 0
        syncProgressBar.maxValue = 100
        syncProgressBar.doubleValue = 0
        syncProgressBar.isIndeterminate = false
        syncProgressBar.controlSize = .small
        syncProgressBar.style = .bar
        syncProgressBar.autoresizingMask = []
        syncContent.addSubview(syncProgressBar)
        syncStatusLabel = NSTextField(labelWithString: "Sync: geen profiel")
        syncStatusLabel.lineBreakMode = .byTruncatingMiddle
        syncStatusLabel.autoresizingMask = []
        syncContent.addSubview(syncStatusLabel)
        selectedSyncProfileId = syncProfiles.first?.id
        if let profile = selectedSyncProfile() {
            applySyncProfileToFields(profile)
        }
        refreshSyncProfileMenu()
        renderSyncProgress(for: selectedSyncProfile())
        updateResumeButton()
        layoutMainWindow()

        window.makeKeyAndOrderFront(nil)
        setupDebugWindow()
        log("App gestart")
        app.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            self.refreshSrc()
            self.refreshDst()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            self.schedulePendingDeleteCleanup(basePath: self.srcField.stringValue)
        }
        startSyncScheduler()

        app.run()
    }

    func setupApplicationMenu(_ app: NSApplication) {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu(title: "MoveFolders")
        appMenuItem.submenu = appMenu
        appMenu.addItem(withTitle: "Over MoveFolders", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        let showItem = NSMenuItem(title: "Toon MoveFolders", action: #selector(showMainWindow(_:)), keyEquivalent: "0")
        showItem.target = self
        appMenu.addItem(showItem)
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Verberg MoveFolders", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthers = NSMenuItem(title: "Verberg andere", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "Toon alles", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(NSMenuItem.separator())
        appMenu.addItem(withTitle: "Stop MoveFolders", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Venster")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimaliseer", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        let showWindowItem = NSMenuItem(title: "Toon MoveFolders", action: #selector(showMainWindow(_:)), keyEquivalent: "0")
        showWindowItem.target = self
        windowMenu.addItem(showWindowItem)
        windowMenu.addItem(NSMenuItem.separator())
        windowMenu.addItem(withTitle: "Breng alles naar voren", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")

        app.mainMenu = mainMenu
        app.windowsMenu = windowMenu
    }

    @objc func showMainWindow(_ sender: Any?) {
        restoreMainWindow()
    }

    func restoreMainWindow() {
        guard window != nil else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restoreMainWindow()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        guard window != nil, window.isMiniaturized || !window.isVisible else { return }
        restoreMainWindow()
    }

    func windowDidResize(_ notification: Notification) {
        layoutMainWindow()
    }

    func layoutMainWindow() {
        guard let rootContent = window?.contentView,
              tabView != nil,
              moveTabContent != nil,
              syncTabContent != nil,
              srcField != nil,
              dstField != nil,
              srcTable != nil,
              dstTable != nil,
              syncProfilePopup != nil,
              syncNameField != nil else { return }

        tabView.frame = rootContent.bounds
        let tabContentRect = tabView.contentRect
        moveTabContent.frame = tabContentRect
        syncTabContent.frame = tabContentRect

        let bounds = moveTabContent.bounds
        let width = max(bounds.width, 980)
        let height = max(bounds.height, 540)
        let margin: CGFloat = 20
        let columnGap: CGFloat = 60
        let columnWidth = max(420, (width - (2 * margin) - columnGap) / 2)
        let leftX = margin
        let rightX = leftX + columnWidth + columnGap
        let rowHeight: CGFloat = 24
        let iconSize: CGFloat = 28

        let topButtonY = height - 42
        let fieldY = height - 76
        let sortY = height - 112
        let optionX = max(leftX + columnWidth + 10, rightX - 80)
        let pathButtonY = sortY - 96
        let tableY: CGFloat = 20
        let tableHeight = max(170, pathButtonY - tableY - 10)

        let buttonGap: CGFloat = 8
        var toolbarX = margin
        favoritePopup.frame = NSRect(x: toolbarX, y: topButtonY + 3, width: 160, height: 26)
        toolbarX += 160 + buttonGap
        saveFavoriteButton.frame = NSRect(x: toolbarX, y: topButtonY, width: 90, height: 32)
        toolbarX += 90 + buttonGap
        recentSourcePopup.frame = NSRect(x: toolbarX, y: topButtonY + 3, width: 170, height: 26)
        toolbarX += 170 + buttonGap
        resumeButton.frame = NSRect(x: toolbarX, y: topButtonY, width: 85, height: 32)
        toolbarX += 85 + buttonGap
        updatesButton.frame = NSRect(x: toolbarX, y: topButtonY, width: 85, height: 32)
        toolbarX += 85 + buttonGap
        debugButton.frame = NSRect(x: toolbarX, y: topButtonY, width: 75, height: 32)
        toolbarX += 75 + buttonGap
        transferLogButton.frame = NSRect(x: toolbarX, y: topButtonY, width: 55, height: 32)
        toolbarX += 55 + buttonGap
        startCopyButton.frame = NSRect(x: toolbarX, y: topButtonY, width: max(160, width - toolbarX - margin), height: 32)

        srcLabel.frame = NSRect(x: leftX, y: fieldY + 3, width: 50, height: 20)
        let srcIconX = leftX + columnWidth - (2 * iconSize) - 2
        srcField.frame = NSRect(x: leftX + 60, y: fieldY, width: max(180, srcIconX - (leftX + 60) - 8), height: rowHeight)
        chooseSrcButton.frame = NSRect(x: srcIconX, y: fieldY - 2, width: iconSize, height: iconSize)
        swapPathsButton.frame = NSRect(x: srcIconX + iconSize + 2, y: fieldY - 2, width: iconSize, height: iconSize)

        dstLabel.frame = NSRect(x: rightX, y: fieldY + 3, width: 50, height: 20)
        let dstIconX = rightX + columnWidth - iconSize
        dstField.frame = NSRect(x: rightX + 60, y: fieldY, width: max(180, dstIconX - (rightX + 60) - 8), height: rowHeight)
        chooseDstButton.frame = NSRect(x: dstIconX, y: fieldY - 2, width: iconSize, height: iconSize)

        srcSort.frame = NSRect(x: leftX + columnWidth - 150, y: sortY, width: 150, height: 26)
        dstSort.frame = NSRect(x: rightX + columnWidth - 150, y: sortY, width: 150, height: 26)

        preScanCheckbox.frame = NSRect(x: optionX, y: sortY, width: 260, height: 22)
        skipEmptyFoldersCheckbox.frame = NSRect(x: optionX, y: sortY - 22, width: 260, height: 22)
        deleteSourceCheckbox.frame = NSRect(x: optionX, y: sortY - 44, width: 300, height: 22)
        xattrsCheckbox.frame = NSRect(x: optionX, y: sortY - 66, width: 320, height: 22)

        applySrcButton.frame = NSRect(x: leftX, y: pathButtonY, width: 150, height: 26)
        backSrcButton.frame = NSRect(x: leftX + 160, y: pathButtonY, width: 80, height: 26)
        applyDstButton.frame = NSRect(x: rightX, y: pathButtonY, width: 150, height: 26)
        backDstButton.frame = NSRect(x: rightX + 160, y: pathButtonY, width: 80, height: 26)
        recentDestinationPopup.frame = NSRect(x: rightX + columnWidth - 190, y: pathButtonY, width: 190, height: 26)

        let srcTableFrame = NSRect(x: leftX, y: tableY, width: columnWidth, height: tableHeight)
        let dstTableFrame = NSRect(x: rightX, y: tableY, width: columnWidth, height: tableHeight)
        srcTable.enclosingScrollView?.frame = srcTableFrame
        dstTable.enclosingScrollView?.frame = dstTableFrame
        srcTable.frame = NSRect(origin: .zero, size: srcTableFrame.size)
        dstTable.frame = NSRect(origin: .zero, size: dstTableFrame.size)
        srcTable.tableColumns.first?.width = max(100, columnWidth - 20)
        dstTable.tableColumns.first?.width = max(100, columnWidth - 20)

        layoutSyncTab()
    }

    func layoutSyncTab() {
        guard syncTabContent != nil,
              syncProfilePopup != nil,
              syncNameField != nil,
              syncSrcField != nil,
              syncDstField != nil else { return }

        let bounds = syncTabContent.bounds
        let width = max(bounds.width, 980)
        let height = max(bounds.height, 540)
        let margin: CGFloat = 20
        let rowHeight: CGFloat = 24
        let iconSize: CGFloat = 28
        let labelW: CGFloat = 90

        let topY = height - 52
        syncProfilePopup.frame = NSRect(x: margin, y: topY + 3, width: 240, height: 26)
        newSyncProfileButton.frame = NSRect(x: 275, y: topY, width: 105, height: 28)
        saveSyncProfileButton.frame = NSRect(x: 390, y: topY, width: 110, height: 28)
        toggleSyncProfileButton.frame = NSRect(x: 510, y: topY, width: 115, height: 28)
        runSyncProfileButton.frame = NSRect(x: 635, y: topY, width: 90, height: 28)

        let fieldX = margin + labelW + 10
        let fieldRightInset: CGFloat = 58
        let fieldW = max(260, width - fieldX - fieldRightInset - margin)

        let nameY = topY - 56
        syncNameLabel.frame = NSRect(x: margin, y: nameY + 3, width: labelW, height: 20)
        syncNameField.frame = NSRect(x: fieldX, y: nameY, width: min(460, fieldW), height: rowHeight)

        let srcY = nameY - 44
        syncSrcLabel.frame = NSRect(x: margin, y: srcY + 3, width: labelW, height: 20)
        syncSrcField.frame = NSRect(x: fieldX, y: srcY, width: fieldW, height: rowHeight)
        chooseSyncSrcButton.frame = NSRect(x: fieldX + fieldW + 8, y: srcY - 2, width: iconSize, height: iconSize)

        let dstY = srcY - 44
        syncDstLabel.frame = NSRect(x: margin, y: dstY + 3, width: labelW, height: 20)
        syncDstField.frame = NSRect(x: fieldX, y: dstY, width: fieldW, height: rowHeight)
        chooseSyncDstButton.frame = NSRect(x: fieldX + fieldW + 8, y: dstY - 2, width: iconSize, height: iconSize)

        let optionsY = dstY - 52
        syncIntervalLabel.frame = NSRect(x: margin, y: optionsY + 3, width: labelW, height: 20)
        syncIntervalField.frame = NSRect(x: fieldX, y: optionsY, width: 80, height: rowHeight)
        syncEnabledCheckbox.frame = NSRect(x: fieldX + 105, y: optionsY, width: 180, height: 22)
        syncDeleteExtraCheckbox.frame = NSRect(x: fieldX, y: optionsY - 34, width: 290, height: 22)
        syncXattrsCheckbox.frame = NSRect(x: fieldX, y: optionsY - 66, width: 320, height: 22)
        syncAutoReconnectCheckbox.frame = NSRect(x: fieldX, y: optionsY - 98, width: 360, height: 22)

        let progressY = max(72, optionsY - 215)
        syncProgressTitleLabel.frame = NSRect(x: margin, y: progressY + 68, width: width - (2 * margin), height: 20)
        syncProgressBar.frame = NSRect(x: margin, y: progressY + 46, width: width - (2 * margin), height: 12)
        syncProgressDetailLabel.frame = NSRect(x: margin, y: progressY + 20, width: width - (2 * margin), height: 20)
        syncProgressSpeedLabel.frame = NSRect(x: margin, y: progressY - 4, width: width - (2 * margin), height: 20)

        syncStatusLabel.frame = NSRect(x: margin, y: 24, width: width - (2 * margin), height: 20)
    }

    @objc func chooseSrc() {
        if let p = pickFolder(start: srcField.stringValue) {
            setSrcPath(p, rememberRecent: true)
        }
    }

    @objc func chooseDst() {
        if let p = pickFolder(start: dstField.stringValue) {
            setDstPath(p, rememberRecent: true)
        }
    }

    @objc func chooseSyncSrc() {
        if let p = pickFolder(start: syncSrcField.stringValue) {
            syncSrcField.stringValue = p
        }
    }

    @objc func chooseSyncDst() {
        if let p = pickFolder(start: syncDstField.stringValue) {
            syncDstField.stringValue = p
        }
    }

    @objc func applySrc() { setSrcPath(srcField.stringValue, rememberRecent: true) }
    @objc func applyDst() { setDstPath(dstField.stringValue, rememberRecent: true) }
    @objc func goBackSrc() { popHistory(isSource: true) }
    @objc func goBackDst() { popHistory(isSource: false) }
    @objc func togglePreScan(_ sender: NSButton) { preScanEnabled = sender.state == .on }
    @objc func toggleSkipEmptyFolders(_ sender: NSButton) { skipEmptyFoldersEnabled = sender.state == .on }
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
        setDstPath(tmp, rememberRecent: true)
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

    @objc func selectRecentSource(_ sender: NSPopUpButton) {
        defer { sender.selectItem(at: 0) }
        guard let path = sender.selectedItem?.representedObject as? String else { return }
        setSrcPath(path, rememberRecent: true)
    }

    @objc func selectRecentDestination(_ sender: NSPopUpButton) {
        defer { sender.selectItem(at: 0) }
        guard let path = sender.selectedItem?.representedObject as? String else { return }
        setDstPath(path, rememberRecent: true)
    }

    @objc func selectFavoritePreset(_ sender: NSPopUpButton) {
        defer { sender.selectItem(at: 0) }
        guard let id = sender.selectedItem?.representedObject as? String,
              let favorite = favoritePresets.first(where: { $0.id == id }) else { return }
        setSrcPath(favorite.srcPath, rememberRecent: true)
        setDstPath(favorite.dstPath, rememberRecent: true)
        applyTransferOptions(favorite.options)
        log("Favoriet toegepast: \(favorite.name)")
    }

    @objc func saveCurrentFavorite() {
        let alert = NSAlert()
        alert.messageText = "Favoriet bewaren"
        alert.informativeText = "Bewaar de huidige bron, doel en opties als favoriet."
        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        let srcName = (srcField.stringValue as NSString).lastPathComponent
        input.stringValue = srcName.isEmpty ? "Nieuwe favoriet" : srcName
        alert.accessoryView = input
        alert.addButton(withTitle: "Bewaar")
        alert.addButton(withTitle: "Annuleer")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let name = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let preset = FavoriteTransferPreset(
            id: UUID().uuidString,
            name: name,
            srcPath: normalizePath(srcField.stringValue),
            dstPath: normalizePath(dstField.stringValue),
            options: currentTransferOptions(),
            updatedAt: Date()
        )

        favoritePresets.removeAll { $0.name.caseInsensitiveCompare(name) == .orderedSame }
        favoritePresets.insert(preset, at: 0)
        if favoritePresets.count > favoritePresetLimit {
            favoritePresets.removeSubrange(favoritePresetLimit..<favoritePresets.count)
        }
        saveFavoritePresets()
        log("Favoriet bewaard: \(name)")
    }

    @objc func selectSyncProfile(_ sender: NSPopUpButton) {
        defer { sender.selectItem(at: 0) }
        guard let id = sender.selectedItem?.representedObject as? String,
              let profile = syncProfiles.first(where: { $0.id == id }) else { return }
        selectedSyncProfileId = id
        applySyncProfileToFields(profile)
        refreshSyncProfileMenu()
        updateSyncStatusLabel(profile: profile)
        renderSyncProgress(for: profile)
        log("Sync-profiel geselecteerd: \(profile.name)")
    }

    @objc func createNewSyncProfile() {
        selectedSyncProfileId = nil
        syncNameField.stringValue = "Nieuwe sync"
        syncSrcField.stringValue = defaultServer
        syncDstField.stringValue = defaultLocal
        syncIntervalField.stringValue = "15"
        syncEnabledCheckbox.state = .on
        syncDeleteExtraCheckbox.state = .off
        syncXattrsCheckbox.state = copyXattrsEnabled ? .on : .off
        syncAutoReconnectCheckbox.state = .on
        refreshSyncProfileMenu()
        updateSyncStatusLabel(profile: nil)
        renderSyncProgress(for: nil)
        window.makeFirstResponder(syncNameField)
        syncNameField.selectText(nil)
        log("Nieuw sync-profiel gestart")
    }

    @objc func saveCurrentSyncProfile() {
        let existing = selectedSyncProfile()
        let name = syncNameField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let srcPath = normalizePath(syncSrcField.stringValue)
        let dstPath = normalizePath(syncDstField.stringValue)
        guard !srcPath.isEmpty, !dstPath.isEmpty else {
            self.alert("Bron en doel mogen niet leeg zijn.")
            return
        }
        let interval = max(1, Int(syncIntervalField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 15)
        syncIntervalField.stringValue = "\(interval)"
        let id = existing?.id ?? UUID().uuidString
        let srcMountInfo = networkMountInfo(forPath: srcPath)
        let dstMountInfo = networkMountInfo(forPath: dstPath)
        let sourcePathUnchanged = existing.map { normalizePath($0.srcPath) == srcPath } ?? false
        let destinationPathUnchanged = existing.map { normalizePath($0.dstPath) == dstPath } ?? false
        let profile = SyncProfile(
            id: id,
            name: name,
            srcPath: srcPath,
            dstPath: dstPath,
            intervalMinutes: interval,
            enabled: syncEnabledCheckbox.state == .on,
            deleteExtra: syncDeleteExtraCheckbox.state == .on,
            copyXattrs: syncXattrsCheckbox.state == .on,
            autoReconnect: syncAutoReconnectCheckbox.state == .on,
            srcRemountURL: srcMountInfo?.remountURL ?? (sourcePathUnchanged ? existing?.srcRemountURL : nil),
            srcRelativePathOnVolume: srcMountInfo?.relativePath ?? (sourcePathUnchanged ? existing?.srcRelativePathOnVolume : nil),
            dstRemountURL: dstMountInfo?.remountURL ?? (destinationPathUnchanged ? existing?.dstRemountURL : nil),
            dstRelativePathOnVolume: dstMountInfo?.relativePath ?? (destinationPathUnchanged ? existing?.dstRelativePathOnVolume : nil),
            lastRunAt: existing?.lastRunAt,
            lastStatus: existing?.lastStatus ?? "Nog niet gesynct",
            consecutiveFailures: existing?.consecutiveFailures ?? 0,
            updatedAt: Date()
        )

        syncProfiles.removeAll { $0.id == id || $0.name.caseInsensitiveCompare(name) == .orderedSame }
        syncProfiles.insert(profile, at: 0)
        selectedSyncProfileId = profile.id
        saveSyncProfiles()
        updateSyncStatusLabel(profile: profile)
        log("Sync-profiel bewaard: \(profile.name)")
    }

    @objc func toggleSelectedSyncProfile() {
        guard let id = selectedSyncProfileId,
              let idx = syncProfiles.firstIndex(where: { $0.id == id }) else {
            alert("Selecteer eerst een sync-profiel.")
            return
        }
        syncProfiles[idx].enabled.toggle()
        syncProfiles[idx].updatedAt = Date()
        saveSyncProfiles()
        updateSyncStatusLabel(profile: syncProfiles[idx])
        syncEnabledCheckbox.state = syncProfiles[idx].enabled ? .on : .off
        log("Sync-profiel \(syncProfiles[idx].enabled ? "ingeschakeld" : "uitgeschakeld"): \(syncProfiles[idx].name)")
    }

    @objc func runSelectedSyncProfileNow() {
        guard let selectedProfile = selectedSyncProfile() else {
            alert("Selecteer eerst een sync-profiel.")
            return
        }
        let profile = resolveAndCaptureNetworkPaths(for: selectedProfile)
        guard syncProfilePathsAvailable(profile) else {
            let status = syncWaitingStatus(for: profile)
            showSyncWaiting(profile: profile, status: status)
            let requested = syncAutoReconnectEnabled(for: profile) && attemptNetworkReconnect(for: profile, force: true)
            if requested {
                if profile.enabled {
                    alert("MoveFolders heeft macOS gevraagd de ontbrekende netwerkschijf opnieuw te verbinden. De app blijft controleren en start de sync zodra Folder A en Folder B beschikbaar zijn en het profiel aan de beurt is.")
                } else {
                    alert("MoveFolders heeft macOS gevraagd de ontbrekende netwerkschijf opnieuw te verbinden. Dit profiel staat uit; klik opnieuw op ‘Sync nu’ zodra Folder A en Folder B beschikbaar zijn.")
                }
            } else if syncAutoReconnectEnabled(for: profile) {
                alert("De netwerkschijf kan nog niet automatisch worden verbonden. Koppel de share één keer handmatig en bewaar het sync-profiel opnieuw; daarna kan MoveFolders de verbinding onthouden.")
            } else {
                alert("Folder A of Folder B is niet beschikbaar. Automatisch verbinden staat voor dit profiel uit.")
            }
            return
        }
        startSyncRun(profile: profile, manual: true)
    }

    func showProgress(_ message: String, detail: String) {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 780, height: 250),
                            styleMask: [.titled, .closable, .resizable],
                            backing: .buffered,
                            defer: false)
        panel.contentMinSize = NSSize(width: 640, height: 240)
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
        let speedY: CGFloat = 205
        let etaY: CGFloat = 182
        let topY: CGFloat = 145
        let midY: CGFloat = 95
        let bottomY: CGFloat = 45

        func makeLine(_ text: String, _ y: CGFloat, alignment: NSTextAlignment = .center, rightInset: CGFloat = 0) -> NSTextField {
            let lbl = NSTextField(labelWithString: text)
            lbl.frame = NSRect(x: 20, y: y, width: labelWidth - rightInset, height: labelHeight)
            lbl.alignment = alignment
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

        self.progressBarTop = makeProgressBar(130)
        self.progressBarMid = makeProgressBar(80)
        self.progressBarBottom = makeProgressBar(30)

        self.progressSpeed = makeLine("Snelheid: -", speedY, alignment: .left, rightInset: 190)
        self.progressEta = makeLine("ETA bestand: - | map: - | opdracht: -", etaY, alignment: .left)
        self.progressLabel = makeLine(message, topY)
        self.progressDetail = makeLine(detail, midY)
        self.progressPhase = makeLine("Voorbereiden...", bottomY)
        let cancelButton = NSButton(frame: NSRect(x: content.bounds.width - 190, y: 204, width: 170, height: 26))
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
        self.progressTransferStartDate = Date()
        self.progressTaskStartDate = nil
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
        progressSpeedText = ""
        progressCurrentFilePercent = nil
        progressTransferStartDate = nil
        progressTaskStartDate = nil
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard self.srcListToken == token, self.srcTable.isEnabled == false else { return }
            self.srcAdapter.items = [TableAdapter.Item(name: "Volume reageert traag...", isDir: false, modDate: Date())]
            self.srcTable.isEnabled = true
            self.srcTable.reloadData()
            self.log("Bronlijst reageert traag: \(path)")
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
            let withDates = sortIndex >= 2
            guard !names.isEmpty, withDates else { return }
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
            guard self.dstListToken == token, self.dstTable.isEnabled == false else { return }
            self.dstAdapter.items = [TableAdapter.Item(name: "Volume reageert traag...", isDir: false, modDate: Date())]
            self.dstTable.isEnabled = true
            self.dstTable.reloadData()
            self.log("Doellijst reageert traag: \(path)")
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
            let withDates = sortIndex >= 2
            guard !names.isEmpty, withDates else { return }
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

    func rsyncProgressMetrics(from line: String) -> (percent: Int, speed: String?, eta: String?, toCheck: String?)? {
        guard let pctRange = line.range(of: #"([0-9]+)%"#, options: .regularExpression),
              let percent = Int(line[pctRange].replacingOccurrences(of: "%", with: "")) else { return nil }

        let speed = line.range(of: #"[0-9]+(?:[.,][0-9]+)?\s*[KMGTPE]?B/s"#, options: [.regularExpression, .caseInsensitive]).map {
            formatSpeedInMBPerSecond(String(line[$0]))
        }
        let eta = line.range(of: #"[0-9]+:[0-9]{2}:[0-9]{2}"#, options: .regularExpression).map {
            String(line[$0])
        }
        let toCheck = line.range(of: #"(?:to-chk|to-check|ir-chk)=[0-9]+/[0-9]+"#, options: .regularExpression).map {
            String(line[$0])
        }
        return (max(0, min(100, percent)), speed, eta, toCheck)
    }

    func formatSpeedInMBPerSecond(_ raw: String) -> String {
        let cleaned = raw
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard let numberRange = cleaned.range(of: #"[0-9]+(?:\.[0-9]+)?"#, options: .regularExpression),
              let value = Double(cleaned[numberRange]) else {
            return raw
        }

        let lower = cleaned.lowercased()
        let mbps: Double
        if lower.contains("gb/s") {
            mbps = value * 1024.0
        } else if lower.contains("tb/s") {
            mbps = value * 1024.0 * 1024.0
        } else if lower.contains("kb/s") {
            mbps = value / 1024.0
        } else if lower.contains("b/s") && !lower.contains("mb/s") {
            mbps = value / 1024.0 / 1024.0
        } else {
            mbps = value
        }
        return String(format: "%.2f MB/s", mbps)
    }

    func formatEtaDuration(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours >= 100 {
            return "\(hours)u \(minutes)m"
        }
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }

    func estimatedEtaText(startedAt: Date?, percent: Int) -> String {
        let pct = max(0, min(100, percent))
        guard pct > 0 else { return "-" }
        if pct >= 100 { return "0:00:00" }
        guard let startedAt = startedAt else { return "-" }
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed >= 2 else { return "-" }
        let remaining = elapsed * (Double(100 - pct) / Double(pct))
        return formatEtaDuration(remaining)
    }

    func updateProgressMetrics(speed: String?, eta: String?) {
        guard speed != nil || eta != nil else { return }
        DispatchQueue.main.async {
            guard self.isCopying else { return }
            if let speed = speed { self.progressSpeedText = speed }
            if let eta = eta { self.progressEtaText = eta }
            self.refreshProgressLines()
        }
    }

    func setSrcPath(_ path: String, rememberRecent: Bool = true) {
        setPath(field: srcField, newPath: path, history: &srcHistory, refresh: refreshSrc)
        if rememberRecent {
            rememberRecentSource(srcField.stringValue)
        }
        schedulePendingDeleteCleanup(basePath: srcField.stringValue)
    }

    func setDstPath(_ path: String, rememberRecent: Bool = false) {
        setPath(field: dstField, newPath: path, history: &dstHistory, refresh: refreshDst)
        if rememberRecent {
            rememberRecentDestination(dstField.stringValue)
        }
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
            self.progressSpeedText = ""
            self.progressCurrentFilePercent = nil
            self.progressTaskStartDate = Date()
            if self.progressTransferStartDate == nil {
                self.progressTransferStartDate = self.progressTaskStartDate
            }
            self.refreshProgressLines()
        }
    }

    func updateCurrentFileProgress(percent: Int) {
        DispatchQueue.main.async {
            guard self.isCopying else { return }
            self.progressCurrentFilePercent = max(0, min(100, percent))
            self.refreshProgressLines()
        }
    }

    func updateProgressFromRsync(toChk: String?) {
        DispatchQueue.main.async {
            guard self.isCopying else { return }
            if let toChk = toChk {
                let cleaned = toChk
                    .replacingOccurrences(of: "to-chk=", with: "")
                    .replacingOccurrences(of: "to-check=", with: "")
                    .replacingOccurrences(of: "ir-chk=", with: "")
                let parts = cleaned.split(separator: "/")
                if parts.count == 2 {
                    let remaining = Int(parts[0].filter { $0.isNumber })
                    let total = Int(parts[1].filter { $0.isNumber })
                    if let remaining = remaining, let total = total, total > 0 {
                        self.progressFileTotal = total
                        self.progressFileDone = max(0, total - remaining)
                        self.progressPct = Int(round(Double(max(0, total - remaining)) / Double(total) * 100.0))
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
        let fileName = progressCurrentFile
        let filePath = progressCurrentPath.isEmpty ? "" : progressCurrentPath
        let percents = computeProgressPercents()
        let topPercentText = "\(percents.file)%"
        let midPercentText = "\(percents.map)%"
        let bottomPercentText = "\(percents.overall)%"

        let speedText = progressSpeedText.isEmpty ? "Snelheid: -" : "Snelheid: \(progressSpeedText)"
        progressSpeed?.stringValue = speedText
        let fileEtaText = progressEtaText.isEmpty ? "-" : progressEtaText
        let mapEtaText = estimatedEtaText(startedAt: progressTaskStartDate, percent: percents.map)
        let totalEtaText = estimatedEtaText(startedAt: progressTransferStartDate, percent: percents.overall)
        progressEta?.stringValue = "ETA bestand: \(fileEtaText) | map: \(mapEtaText) | opdracht: \(totalEtaText)"

        if fileName.isEmpty {
            top.stringValue = "Bestand: wachten op rsync... (\(topPercentText))"
        } else {
            top.stringValue = "Bestand: \(fileName) (\(topPercentText))"
        }

        let pathLine: String
        if !filePath.isEmpty {
            pathLine = "Doelpad: \(filePath) (\(midPercentText))"
        } else {
            pathLine = "Doelpad: bezig met wachtrij... (\(midPercentText))"
        }
        mid.stringValue = pathLine

        let taskLine: String
        if progressTaskTotal > 0 {
            taskLine = "Taak \(progressTaskIndex)/\(progressTaskTotal)"
        } else {
            taskLine = "Taak"
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
            bottom.stringValue = "\(countPrefix)\(taskLine) (\(bottomPercentText)) | \(overall.done)/\(overall.total) bestanden totaal"
        } else if let done = progressFileDone, let total = progressFileTotal {
            bottom.stringValue = "\(countPrefix)\(taskLine) (\(bottomPercentText)) | \(done)/\(total) bestanden"
        } else {
            bottom.stringValue = "\(countPrefix)\(taskLine) (\(bottomPercentText))"
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
        if let currentFilePercent = progressCurrentFilePercent {
            filePct = max(0, min(100, currentFilePercent))
        } else if let done = progressFileDone, let total = progressFileTotal, total > 0 {
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

    func normalizeSourcePath(_ path: String) -> String {
        normalizePath(path)
    }

    func normalizePath(_ path: String) -> String {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return (trimmed as NSString).standardizingPath
    }

    func compactPathTitle(for path: String) -> String {
        let parts = path.split(separator: "/").map(String.init)
        guard parts.count > 3 else { return path }
        return ".../" + parts.suffix(3).joined(separator: "/")
    }

    func loadRecentSourcePaths() -> [String] {
        let stored = recentSourceDefaults.stringArray(forKey: recentSourceDefaultsKey) ?? []
        return cleanRecentPaths(stored)
    }

    func loadRecentDestinationPaths() -> [String] {
        let stored = recentSourceDefaults.stringArray(forKey: recentDestinationDefaultsKey) ?? []
        return cleanRecentPaths(stored)
    }

    func cleanRecentPaths(_ stored: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for rawPath in stored {
            let path = normalizePath(rawPath)
            guard !path.isEmpty, !seen.contains(path) else { continue }
            seen.insert(path)
            result.append(path)
            if result.count >= recentSourceLimit { break }
        }
        return result
    }

    func recentSourceTitle(for path: String) -> String {
        compactPathTitle(for: path)
    }

    func refreshRecentSourceMenu() {
        guard recentSourcePopup != nil else { return }
        recentSourcePopup.removeAllItems()
        recentSourcePopup.addItem(withTitle: "Laatste bronnen")
        recentSourcePopup.item(at: 0)?.isEnabled = false

        if recentSourcePaths.isEmpty {
            recentSourcePopup.addItem(withTitle: "Geen recente bronnen")
            recentSourcePopup.lastItem?.isEnabled = false
            recentSourcePopup.isEnabled = false
            recentSourcePopup.selectItem(at: 0)
            return
        }

        recentSourcePopup.menu?.addItem(NSMenuItem.separator())
        for path in recentSourcePaths {
            recentSourcePopup.addItem(withTitle: recentSourceTitle(for: path))
            recentSourcePopup.lastItem?.representedObject = path
            recentSourcePopup.lastItem?.toolTip = path
        }
        recentSourcePopup.isEnabled = true
        recentSourcePopup.selectItem(at: 0)
    }

    func refreshRecentDestinationMenu() {
        guard recentDestinationPopup != nil else { return }
        recentDestinationPopup.removeAllItems()
        recentDestinationPopup.addItem(withTitle: "Laatste doelen")
        recentDestinationPopup.item(at: 0)?.isEnabled = false

        if recentDestinationPaths.isEmpty {
            recentDestinationPopup.addItem(withTitle: "Geen recente doelen")
            recentDestinationPopup.lastItem?.isEnabled = false
            recentDestinationPopup.isEnabled = false
            recentDestinationPopup.selectItem(at: 0)
            return
        }

        recentDestinationPopup.menu?.addItem(NSMenuItem.separator())
        for path in recentDestinationPaths {
            recentDestinationPopup.addItem(withTitle: compactPathTitle(for: path))
            recentDestinationPopup.lastItem?.representedObject = path
            recentDestinationPopup.lastItem?.toolTip = path
        }
        recentDestinationPopup.isEnabled = true
        recentDestinationPopup.selectItem(at: 0)
    }

    func refreshFavoriteMenu() {
        guard favoritePopup != nil else { return }
        favoritePopup.removeAllItems()
        favoritePopup.addItem(withTitle: "Favorieten")
        favoritePopup.item(at: 0)?.isEnabled = false

        if favoritePresets.isEmpty {
            favoritePopup.addItem(withTitle: "Geen favorieten")
            favoritePopup.lastItem?.isEnabled = false
            favoritePopup.isEnabled = false
            favoritePopup.selectItem(at: 0)
            return
        }

        favoritePopup.menu?.addItem(NSMenuItem.separator())
        for favorite in favoritePresets {
            favoritePopup.addItem(withTitle: favorite.name)
            favoritePopup.lastItem?.representedObject = favorite.id
            favoritePopup.lastItem?.toolTip = "\(favorite.srcPath) -> \(favorite.dstPath)"
        }
        favoritePopup.isEnabled = true
        favoritePopup.selectItem(at: 0)
    }

    func rememberRecentSource(_ path: String) {
        let normalized = normalizePath(path)
        guard !normalized.isEmpty else { return }
        recentSourcePaths.removeAll { $0 == normalized }
        recentSourcePaths.insert(normalized, at: 0)
        if recentSourcePaths.count > recentSourceLimit {
            recentSourcePaths.removeSubrange(recentSourceLimit..<recentSourcePaths.count)
        }
        recentSourceDefaults.set(recentSourcePaths, forKey: recentSourceDefaultsKey)
        refreshRecentSourceMenu()
    }

    func rememberRecentDestination(_ path: String) {
        let normalized = normalizePath(path)
        guard !normalized.isEmpty else { return }
        recentDestinationPaths.removeAll { $0 == normalized }
        recentDestinationPaths.insert(normalized, at: 0)
        if recentDestinationPaths.count > recentSourceLimit {
            recentDestinationPaths.removeSubrange(recentSourceLimit..<recentDestinationPaths.count)
        }
        recentSourceDefaults.set(recentDestinationPaths, forKey: recentDestinationDefaultsKey)
        refreshRecentDestinationMenu()
    }

    func currentTransferOptions() -> TransferOptions {
        TransferOptions(
            preScanEnabled: preScanEnabled,
            skipEmptyFoldersEnabled: skipEmptyFoldersEnabled,
            deleteSourceEnabled: deleteSourceEnabled,
            copyXattrsEnabled: copyXattrsEnabled
        )
    }

    func applyTransferOptions(_ options: TransferOptions) {
        preScanEnabled = options.preScanEnabled
        skipEmptyFoldersEnabled = options.skipEmptyFoldersEnabled
        deleteSourceEnabled = options.deleteSourceEnabled
        copyXattrsEnabled = options.copyXattrsEnabled
        preScanCheckbox?.state = preScanEnabled ? .on : .off
        skipEmptyFoldersCheckbox?.state = skipEmptyFoldersEnabled ? .on : .off
        deleteSourceCheckbox?.state = deleteSourceEnabled ? .on : .off
        xattrsCheckbox?.state = copyXattrsEnabled ? .on : .off
    }

    func loadFavoritePresets() -> [FavoriteTransferPreset] {
        guard let data = recentSourceDefaults.data(forKey: favoritePresetsDefaultsKey),
              let decoded = try? JSONDecoder().decode([FavoriteTransferPreset].self, from: data) else { return [] }
        return Array(decoded.prefix(favoritePresetLimit))
    }

    func saveFavoritePresets() {
        guard let data = try? JSONEncoder().encode(favoritePresets) else { return }
        recentSourceDefaults.set(data, forKey: favoritePresetsDefaultsKey)
        refreshFavoriteMenu()
    }

    func loadSyncProfiles() -> [SyncProfile] {
        guard let data = recentSourceDefaults.data(forKey: syncProfilesDefaultsKey),
              let decoded = try? JSONDecoder().decode([SyncProfile].self, from: data) else { return [] }
        return decoded
    }

    func saveSyncProfiles() {
        syncProfiles.sort {
            if $0.enabled != $1.enabled { return $0.enabled && !$1.enabled }
            return $0.updatedAt > $1.updatedAt
        }
        if let data = try? JSONEncoder().encode(syncProfiles) {
            recentSourceDefaults.set(data, forKey: syncProfilesDefaultsKey)
            recentSourceDefaults.synchronize()
        }
        refreshSyncProfileMenu()
    }

    func selectedSyncProfile() -> SyncProfile? {
        guard let id = selectedSyncProfileId else { return nil }
        return syncProfiles.first(where: { $0.id == id })
    }

    func applySyncProfileToFields(_ profile: SyncProfile) {
        guard syncNameField != nil else { return }
        syncNameField.stringValue = profile.name
        syncSrcField.stringValue = profile.srcPath
        syncDstField.stringValue = profile.dstPath
        syncIntervalField.stringValue = "\(max(1, profile.intervalMinutes))"
        syncEnabledCheckbox.state = profile.enabled ? .on : .off
        syncDeleteExtraCheckbox.state = profile.deleteExtra ? .on : .off
        syncXattrsCheckbox.state = profile.copyXattrs ? .on : .off
        syncAutoReconnectCheckbox.state = (profile.autoReconnect ?? true) ? .on : .off
    }

    func syncAutoReconnectEnabled(for profile: SyncProfile) -> Bool {
        profile.autoReconnect ?? true
    }

    func directoryExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: normalizePath(path), isDirectory: &isDirectory) && isDirectory.boolValue
    }

    func sanitizedRemountURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.password = nil
        return components.url
    }

    func canonicalRemountKey(_ url: URL) -> String {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString.lowercased()
        }
        let scheme = components.scheme?.lowercased() ?? ""
        let user = components.user?.lowercased() ?? ""
        let host = components.host?.lowercased() ?? ""
        let port = components.port.map(String.init) ?? ""
        let path = components.percentEncodedPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        return "\(scheme)|\(user)|\(host)|\(port)|\(path)"
    }

    func networkMountInfo(forPath path: String) -> NetworkMountInfo? {
        let normalizedPath = normalizePath(path)
        guard directoryExists(atPath: normalizedPath) else { return nil }
        let pathURL = URL(fileURLWithPath: normalizedPath, isDirectory: true).standardizedFileURL
        guard let values = try? pathURL.resourceValues(forKeys: [.volumeURLKey, .volumeURLForRemountingKey]),
              let volumeURL = values.volume?.standardizedFileURL,
              let rawRemountURL = values.volumeURLForRemounting,
              let remountURL = sanitizedRemountURL(rawRemountURL) else { return nil }

        let volumePath = normalizePath(volumeURL.path)
        let requestedPath = normalizePath(pathURL.path)
        let relativePath: String
        if requestedPath == volumePath {
            relativePath = ""
        } else if requestedPath.hasPrefix(volumePath + "/") {
            relativePath = String(requestedPath.dropFirst(volumePath.count + 1))
        } else {
            return nil
        }
        return NetworkMountInfo(remountURL: remountURL.absoluteString, relativePath: relativePath)
    }

    func mountedVolumeURL(forRemountURLString remountURLString: String) -> URL? {
        guard let rawURL = URL(string: remountURLString),
              let remountURL = sanitizedRemountURL(rawURL) else { return nil }
        let expectedKey = canonicalRemountKey(remountURL)
        let keys: [URLResourceKey] = [.volumeURLForRemountingKey]
        let mountedVolumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: []) ?? []
        for volumeURL in mountedVolumes {
            guard let values = try? volumeURL.resourceValues(forKeys: Set(keys)),
                  let candidateRawURL = values.volumeURLForRemounting,
                  let candidateURL = sanitizedRemountURL(candidateRawURL),
                  canonicalRemountKey(candidateURL) == expectedKey else { continue }
            return volumeURL.standardizedFileURL
        }
        return nil
    }

    func resolvedMountedPath(remountURLString: String?, relativePath: String?) -> String? {
        guard let remountURLString = remountURLString,
              let volumeURL = mountedVolumeURL(forRemountURLString: remountURLString) else { return nil }
        let candidateURL: URL
        if let relativePath = relativePath, !relativePath.isEmpty {
            candidateURL = volumeURL.appendingPathComponent(relativePath, isDirectory: true)
        } else {
            candidateURL = volumeURL
        }
        let candidatePath = normalizePath(candidateURL.path)
        return directoryExists(atPath: candidatePath) ? candidatePath : nil
    }

    func resolveAndCaptureNetworkPaths(for original: SyncProfile) -> SyncProfile {
        var resolved = original

        if directoryExists(atPath: resolved.srcPath) {
            if let info = networkMountInfo(forPath: resolved.srcPath) {
                resolved.srcRemountURL = info.remountURL
                resolved.srcRelativePathOnVolume = info.relativePath
            }
        } else if let path = resolvedMountedPath(remountURLString: resolved.srcRemountURL,
                                                  relativePath: resolved.srcRelativePathOnVolume) {
            resolved.srcPath = path
        }

        if directoryExists(atPath: resolved.dstPath) {
            if let info = networkMountInfo(forPath: resolved.dstPath) {
                resolved.dstRemountURL = info.remountURL
                resolved.dstRelativePathOnVolume = info.relativePath
            }
        } else if let path = resolvedMountedPath(remountURLString: resolved.dstRemountURL,
                                                  relativePath: resolved.dstRelativePathOnVolume) {
            resolved.dstPath = path
        }

        if resolved.srcPath != original.srcPath ||
            resolved.dstPath != original.dstPath ||
            resolved.srcRemountURL != original.srcRemountURL ||
            resolved.srcRelativePathOnVolume != original.srcRelativePathOnVolume ||
            resolved.dstRemountURL != original.dstRemountURL ||
            resolved.dstRelativePathOnVolume != original.dstRelativePathOnVolume {
            persistResolvedSyncProfile(resolved, previous: original)
        }
        return resolved
    }

    func persistResolvedSyncProfile(_ resolved: SyncProfile, previous: SyncProfile) {
        DispatchQueue.main.async {
            guard let idx = self.syncProfiles.firstIndex(where: { $0.id == resolved.id }),
                  self.syncProfiles[idx].updatedAt == previous.updatedAt else { return }
            let sourceFieldStillMatches = self.normalizePath(self.syncSrcField?.stringValue ?? "") == self.normalizePath(previous.srcPath)
            let destinationFieldStillMatches = self.normalizePath(self.syncDstField?.stringValue ?? "") == self.normalizePath(previous.dstPath)
            self.syncProfiles[idx].srcPath = resolved.srcPath
            self.syncProfiles[idx].dstPath = resolved.dstPath
            self.syncProfiles[idx].srcRemountURL = resolved.srcRemountURL
            self.syncProfiles[idx].srcRelativePathOnVolume = resolved.srcRelativePathOnVolume
            self.syncProfiles[idx].dstRemountURL = resolved.dstRemountURL
            self.syncProfiles[idx].dstRelativePathOnVolume = resolved.dstRelativePathOnVolume
            self.saveSyncProfiles()
            if self.selectedSyncProfileId == resolved.id {
                if sourceFieldStillMatches { self.syncSrcField.stringValue = resolved.srcPath }
                if destinationFieldStillMatches { self.syncDstField.stringValue = resolved.dstPath }
                self.updateSyncStatusLabel(profile: resolved)
            }
            if resolved.srcPath != previous.srcPath || resolved.dstPath != previous.dstPath {
                self.log("Sync-profiel gebruikt opnieuw gekoppelde schijf: \(resolved.name) | \(resolved.srcPath) -> \(resolved.dstPath)")
            }
        }
    }

    func refreshSyncProfileMenu() {
        guard syncProfilePopup != nil else { return }
        syncProfilePopup.removeAllItems()
        let selectedName = selectedSyncProfile()?.name
        let popupTitle = selectedName.map { "Sync: \($0)" } ?? (syncProfiles.isEmpty ? "Sync-profielen" : "Nieuw sync-profiel")
        syncProfilePopup.addItem(withTitle: popupTitle)
        syncProfilePopup.item(at: 0)?.isEnabled = false

        if syncProfiles.isEmpty {
            syncProfilePopup.addItem(withTitle: "Geen sync-profielen")
            syncProfilePopup.lastItem?.isEnabled = false
            syncProfilePopup.isEnabled = false
            runSyncProfileButton?.isEnabled = false
            toggleSyncProfileButton?.isEnabled = false
            syncProfilePopup.selectItem(at: 0)
            saveSyncProfileButton?.title = "Bewaar sync"
            updateSyncStatusLabel(profile: nil)
            renderSyncProgress(for: nil)
            return
        }

        let runningIds = syncStateQueue.sync { syncRunningProfileIds }
        syncProfilePopup.menu?.addItem(NSMenuItem.separator())
        for profile in syncProfiles {
            let prefix = runningIds.contains(profile.id) ? "Bezig" : (profile.enabled ? "Aan" : "Uit")
            syncProfilePopup.addItem(withTitle: "\(prefix): \(profile.name)")
            syncProfilePopup.lastItem?.representedObject = profile.id
            syncProfilePopup.lastItem?.toolTip = "\(profile.srcPath) -> \(profile.dstPath)"
        }
        syncProfilePopup.isEnabled = true
        runSyncProfileButton?.isEnabled = selectedSyncProfileId != nil
        toggleSyncProfileButton?.isEnabled = selectedSyncProfileId != nil
        saveSyncProfileButton?.title = selectedSyncProfileId == nil ? "Maak sync" : "Bewaar sync"
        syncProfilePopup.selectItem(at: 0)
    }

    func updateSyncStatusLabel(profile: SyncProfile?) {
        guard syncStatusLabel != nil else { return }
        guard let profile = profile else {
            syncStatusLabel.stringValue = "Sync: geen profiel"
            return
        }
        let runText: String
        if let lastRunAt = profile.lastRunAt {
            runText = fileInfoFormatterQueue.sync { fileInfoFormatter.string(from: lastRunAt) }
        } else {
            runText = "nog niet"
        }
        let nextText: String
        if profile.enabled, let next = nextSyncDate(for: profile) {
            nextText = fileInfoFormatterQueue.sync { fileInfoFormatter.string(from: next) }
        } else if profile.enabled {
            nextText = "zodra mogelijk"
        } else {
            nextText = "uit"
        }
        syncStatusLabel.stringValue = "Sync: \(profile.name) | \(profile.enabled ? "aan" : "uit") | laatste: \(runText) | volgende: \(nextText) | \(profile.lastStatus)"
    }

    func nextSyncDate(for profile: SyncProfile) -> Date? {
        guard let lastRunAt = profile.lastRunAt else { return nil }
        let retryMinutes: Int
        if profile.consecutiveFailures <= 0 {
            retryMinutes = max(1, profile.intervalMinutes)
        } else {
            let backoff = [1, 5, 15, 30, 60]
            retryMinutes = backoff[min(profile.consecutiveFailures - 1, backoff.count - 1)]
        }
        return lastRunAt.addingTimeInterval(TimeInterval(retryMinutes * 60))
    }

    func syncProfileIsDue(_ profile: SyncProfile, now: Date = Date()) -> Bool {
        guard profile.enabled else { return false }
        guard let next = nextSyncDate(for: profile) else { return true }
        return now >= next
    }

    func syncProfilesSnapshot() -> [SyncProfile] {
        if Thread.isMainThread { return syncProfiles }
        return DispatchQueue.main.sync { syncProfiles }
    }

    func syncProfilePathsAvailable(_ profile: SyncProfile) -> Bool {
        directoryExists(atPath: profile.srcPath) && directoryExists(atPath: profile.dstPath)
    }

    func syncWaitingStatus(for profile: SyncProfile) -> String {
        var missing: [String] = []
        var reconnectDataMissing = false
        if !directoryExists(atPath: profile.srcPath) {
            missing.append("Folder A")
            reconnectDataMissing = reconnectDataMissing || profile.srcRemountURL == nil
        }
        if !directoryExists(atPath: profile.dstPath) {
            missing.append("Folder B")
            reconnectDataMissing = reconnectDataMissing || profile.dstRemountURL == nil
        }
        let names = missing.joined(separator: " en ")
        if !profile.enabled {
            return "Wacht op \(names); dit sync-profiel staat uit."
        }
        if !syncAutoReconnectEnabled(for: profile) {
            return "Wacht op \(names); automatisch verbinden staat uit."
        }
        if reconnectDataMissing {
            return "Wacht op \(names); koppel de share één keer handmatig en bewaar dit profiel opnieuw."
        }
        return "Wacht op \(names); nieuwe koppelpoging elke 5 minuten."
    }

    func showSyncWaiting(profile: SyncProfile, status: String) {
        DispatchQueue.main.async {
            if let idx = self.syncProfiles.firstIndex(where: { $0.id == profile.id }),
               self.syncProfiles[idx].lastStatus != status {
                self.syncProfiles[idx].lastStatus = status
                self.saveSyncProfiles()
            }
            self.syncProgressStates[profile.id] = SyncProgressState(
                percent: 0,
                speed: "",
                eta: "",
                detail: status,
                status: status,
                isRunning: false,
                succeeded: nil
            )
            if self.selectedSyncProfileId == profile.id {
                let current = self.syncProfiles.first(where: { $0.id == profile.id }) ?? profile
                self.updateSyncStatusLabel(profile: current)
                self.renderSyncProgress(for: current)
            }
        }
    }

    func openReconnectURL(_ url: URL) -> Bool {
        if Thread.isMainThread {
            return NSWorkspace.shared.open(url)
        }
        return DispatchQueue.main.sync {
            NSWorkspace.shared.open(url)
        }
    }

    func attemptNetworkReconnect(for profile: SyncProfile, force: Bool) -> Bool {
        var candidates: [(label: String, urlString: String)] = []
        if !directoryExists(atPath: profile.srcPath), let url = profile.srcRemountURL {
            candidates.append(("Folder A", url))
        }
        if !directoryExists(atPath: profile.dstPath), let url = profile.dstRemountURL {
            candidates.append(("Folder B", url))
        }

        var seen = Set<String>()
        var requested = false
        for candidate in candidates {
            guard let rawURL = URL(string: candidate.urlString),
                  let url = sanitizedRemountURL(rawURL) else { continue }
            let key = canonicalRemountKey(url)
            guard seen.insert(key).inserted else { continue }
            let now = Date()
            let shouldAttempt = syncStateQueue.sync { () -> Bool in
                if !force,
                   let lastAttempt = syncReconnectLastAttempt[key],
                   now.timeIntervalSince(lastAttempt) < syncReconnectInterval {
                    return false
                }
                syncReconnectLastAttempt[key] = now
                return true
            }
            guard shouldAttempt else { continue }

            let opened = openReconnectURL(url)
            requested = requested || opened
            let result = opened ? "koppelpoging aangevraagd" : "macOS kon de koppelpoging niet starten"
            log("Netwerkschijf verbinden: \(profile.name) | \(candidate.label) | \(result)")
            recordTransferLog(
                status: opened ? "NETWERKSCHIJF KOPPELEN" : "NETWERKSCHIJF KOPPELEN MISLUKT",
                relativePath: profile.name,
                detail: "\(candidate.label): \(result)"
            )
        }
        return requested
    }

    func startSyncScheduler() {
        syncTimer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: DispatchQueue.global(qos: .utility))
        timer.schedule(deadline: .now() + 5, repeating: 30)
        timer.setEventHandler { [weak self] in
            self?.tickSyncProfiles()
        }
        syncTimer = timer
        timer.resume()
        log("Sync scheduler gestart")
    }

    func tickSyncProfiles() {
        let now = Date()
        for original in syncProfilesSnapshot() where original.enabled {
            let profile = resolveAndCaptureNetworkPaths(for: original)
            guard syncProfilePathsAvailable(profile) else {
                showSyncWaiting(profile: profile, status: syncWaitingStatus(for: profile))
                if syncAutoReconnectEnabled(for: profile) {
                    _ = attemptNetworkReconnect(for: profile, force: false)
                }
                continue
            }
            if syncProfileIsDue(profile, now: now) {
                startSyncRun(profile: profile, manual: false)
            }
        }
    }

    func markSyncProfileRunning(_ id: String) -> Bool {
        let started = syncStateQueue.sync {
            if syncRunningProfileIds.contains(id) { return false }
            syncRunningProfileIds.insert(id)
            return true
        }
        if started {
            DispatchQueue.main.async { self.refreshSyncProfileMenu() }
        }
        return started
    }

    func unmarkSyncProfileRunning(_ id: String) {
        _ = syncStateQueue.sync {
            syncRunningProfileIds.remove(id)
        }
        DispatchQueue.main.async { self.refreshSyncProfileMenu() }
    }

    func updateSyncProfile(id: String, _ mutate: @escaping (inout SyncProfile) -> Void) {
        DispatchQueue.main.async {
            guard let idx = self.syncProfiles.firstIndex(where: { $0.id == id }) else { return }
            mutate(&self.syncProfiles[idx])
            let updated = self.syncProfiles[idx]
            self.saveSyncProfiles()
            if self.selectedSyncProfileId == id {
                self.updateSyncStatusLabel(profile: updated)
            }
        }
    }

    func resetSyncProgress(profile: SyncProfile) {
        DispatchQueue.main.async {
            self.syncProgressStates[profile.id] = SyncProgressState(
                percent: 0,
                speed: "",
                eta: "",
                detail: "voorbereiden...",
                status: "Bezig...",
                isRunning: true,
                succeeded: nil
            )
            if self.selectedSyncProfileId == profile.id {
                self.renderSyncProgress(for: profile)
            }
        }
    }

    func updateSyncProgress(profileId: String, percent: Int? = nil, speed: String? = nil, eta: String? = nil, detail: String? = nil) {
        DispatchQueue.main.async {
            guard var state = self.syncProgressStates[profileId], state.isRunning else { return }
            if let percent = percent {
                state.percent = max(0, min(100, percent))
            }
            if let speed = speed { state.speed = speed }
            if let eta = eta { state.eta = eta }
            if let detail = detail, !detail.isEmpty {
                state.detail = detail
            }
            self.syncProgressStates[profileId] = state
            if self.selectedSyncProfileId == profileId {
                self.renderSyncProgress(for: self.selectedSyncProfile())
            }
        }
    }

    func finishSyncProgress(profileId: String, profileName: String, status: String, success: Bool) {
        DispatchQueue.main.async {
            var state = self.syncProgressStates[profileId] ?? SyncProgressState(
                percent: 0,
                speed: "",
                eta: "",
                detail: "",
                status: status,
                isRunning: false,
                succeeded: success
            )
            if success { state.percent = 100 }
            state.status = status
            state.isRunning = false
            state.succeeded = success
            if success { state.eta = "0:00:00" }
            self.syncProgressStates[profileId] = state
            if self.selectedSyncProfileId == profileId {
                let profile = self.syncProfiles.first(where: { $0.id == profileId })
                self.renderSyncProgress(for: profile)
            }
        }
    }

    func renderSyncProgress(for profile: SyncProfile?) {
        guard syncProgressTitleLabel != nil else { return }
        guard let profile = profile else {
            syncProgressTitleLabel.stringValue = "Voortgang: selecteer of maak een sync-profiel"
            syncProgressDetailLabel.stringValue = "Bestand: -"
            syncProgressSpeedLabel.stringValue = "Snelheid: - | ETA: -"
            syncProgressBar.isIndeterminate = false
            syncProgressBar.doubleValue = 0
            return
        }

        guard let state = syncProgressStates[profile.id] else {
            syncProgressTitleLabel.stringValue = "Voortgang: \(profile.name) niet actief"
            syncProgressDetailLabel.stringValue = "Laatste resultaat: \(profile.lastStatus)"
            syncProgressSpeedLabel.stringValue = "Snelheid: - | ETA: -"
            syncProgressBar.isIndeterminate = false
            syncProgressBar.doubleValue = 0
            return
        }

        let stateText: String
        if state.isRunning {
            stateText = "\(state.percent)%"
        } else if state.succeeded == nil {
            stateText = "wacht"
        } else {
            stateText = state.succeeded == true ? "klaar" : "gestopt"
        }
        syncProgressTitleLabel.stringValue = "Voortgang: \(profile.name) (\(stateText))"
        syncProgressDetailLabel.stringValue = state.isRunning ? "Bestand: \(state.detail)" : state.status
        let speedText = state.speed.isEmpty ? "-" : state.speed
        let etaText = state.eta.isEmpty ? "-" : state.eta
        syncProgressSpeedLabel.stringValue = "Snelheid: \(speedText) | ETA: \(etaText)"
        syncProgressBar.isIndeterminate = false
        syncProgressBar.doubleValue = Double(state.percent)
    }

    func syncProgressDetail(fromRsyncLine line: String) -> String? {
        var candidate = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !candidate.isEmpty else { return nil }
        let skipPrefixes = [
            "sending incremental file list",
            "sent ",
            "total size is",
            "total bytes",
            "file list size"
        ]
        if skipPrefixes.contains(where: { candidate.hasPrefix($0) }) { return nil }
        if candidate.range(of: #"^[0-9.,]+\s*[KMGTPE]?B\s+[0-9]+%"#, options: [.regularExpression, .caseInsensitive]) != nil {
            return nil
        }
        if candidate.hasPrefix("*deleting") {
            return candidate
        }
        if let first = candidate.first, first == ">" || first == "c" || first == "." || first == "*" {
            if let space = candidate.firstIndex(of: " ") {
                candidate = String(candidate[candidate.index(after: space)...]).trimmingCharacters(in: .whitespaces)
            }
        }
        if candidate.hasPrefix("./") { candidate.removeFirst(2) }
        return candidate.isEmpty ? nil : candidate
    }

    func syncItemizedEntry(from line: String) -> (code: String, path: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
        guard parts.count == 2 else { return nil }
        let code = String(parts[0])
        let codeCharacters = Array(code)
        guard codeCharacters.count >= 2,
              codeCharacters[0] == ">" || codeCharacters[0] == "<" || codeCharacters[0] == "c" || codeCharacters[0] == "h" || codeCharacters[0] == "." else { return nil }
        var path = String(parts[1]).trimmingCharacters(in: .whitespaces)
        if path.hasPrefix("./") { path.removeFirst(2) }
        guard !path.isEmpty else { return nil }
        return (code, path)
    }

    func syncItemizedEntryTransfersContent(_ code: String) -> Bool {
        let characters = Array(code)
        guard characters.count >= 2, characters[1] != "d" else { return false }
        return characters[0] == ">" || characters[0] == "<" || characters[0] == "c" || characters[0] == "h"
    }

    func syncItemizedEntryIsMetadataOnly(_ code: String) -> Bool {
        let characters = Array(code)
        return characters.count >= 2 && characters[0] == "." && characters[1] != "d"
    }

    func startSyncRun(profile: SyncProfile, manual: Bool) {
        guard markSyncProfileRunning(profile.id) else {
            if manual { alert("Dit sync-profiel draait al.") }
            return
        }
        resetSyncProgress(profile: profile)
        updateSyncProfile(id: profile.id) { item in
            item.lastStatus = "Bezig..."
        }
        DispatchQueue.global(qos: .utility).async {
            self.runSyncProfile(profile, manual: manual)
        }
    }

    func runSyncProfile(_ profile: SyncProfile, manual: Bool) {
        defer { unmarkSyncProfileRunning(profile.id) }
        log("Sync start: \(profile.name) | \(profile.srcPath) -> \(profile.dstPath)")
        recordTransferLog(status: "SYNC GESTART", relativePath: profile.name, detail: "Folder A: \(profile.srcPath) | Folder B: \(profile.dstPath)")
        let fm = FileManager.default
        let srcPath = normalizePath(profile.srcPath)
        let dstPath = normalizePath(profile.dstPath)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: srcPath, isDirectory: &isDir), isDir.boolValue else {
            if syncAutoReconnectEnabled(for: profile) {
                showSyncWaiting(profile: profile, status: syncWaitingStatus(for: profile))
                _ = attemptNetworkReconnect(for: profile, force: false)
                return
            }
            finishSyncProfile(profile, success: false, status: "Folder A bestaat niet of is niet gekoppeld: \(srcPath)")
            return
        }
        var dstIsDir: ObjCBool = false
        guard fm.fileExists(atPath: dstPath, isDirectory: &dstIsDir), dstIsDir.boolValue else {
            if syncAutoReconnectEnabled(for: profile) {
                showSyncWaiting(profile: profile, status: syncWaitingStatus(for: profile))
                _ = attemptNetworkReconnect(for: profile, force: false)
                return
            }
            finishSyncProfile(profile, success: false, status: "Folder B bestaat niet of is niet gekoppeld: \(dstPath)")
            return
        }
        guard fm.isWritableFile(atPath: dstPath) else {
            finishSyncProfile(profile, success: false, status: "Geen schrijfrechten op Folder B: \(dstPath)")
            return
        }

        let srcArg = srcPath.hasSuffix("/") ? srcPath : "\(srcPath)/"
        let dstArg = dstPath.hasSuffix("/") ? dstPath : "\(dstPath)/"
        let flags = rsyncFlags(
            includePartial: true,
            includeItemize: true,
            includeProgress: true,
            includeStats: true,
            includeXattrs: profile.copyXattrs,
            includePermissions: false,
            includeDelete: profile.deleteExtra
        )
        let cmd = "\(shellQuote(rsyncPath)) \(flags) \(shellQuote(srcArg)) \(shellQuote(dstArg))"
        let countQueue = DispatchQueue(label: "MoveFolders.sync.count.\(profile.id)")
        var transferred = 0
        var deleted = 0
        var metadataOnly = 0
        var loggedSyncPaths: Set<String> = []
        let result = runCommandStreaming(cmd, timeout: nil, killGrace: commandKillGrace) { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            if trimmed.hasPrefix("*deleting") {
                countQueue.sync { deleted += 1 }
                if let path = self.syncProgressDetail(fromRsyncLine: trimmed) {
                    let cleanPath = path.replacingOccurrences(of: "*deleting", with: "").trimmingCharacters(in: .whitespaces)
                    let shouldLog = countQueue.sync { loggedSyncPaths.insert("delete:\(cleanPath)").inserted }
                    if shouldLog {
                        self.recordTransferLog(status: "SYNC VERWIJDERD", relativePath: cleanPath, dstBase: dstPath, detail: "profiel: \(profile.name)")
                    }
                }
            } else if let entry = self.syncItemizedEntry(from: trimmed) {
                if self.syncItemizedEntryTransfersContent(entry.code) {
                    countQueue.sync { transferred += 1 }
                    let shouldLog = countQueue.sync { loggedSyncPaths.insert("copy:\(entry.path)").inserted }
                    if shouldLog {
                        self.recordTransferLog(status: "SYNC OVERGEZET", relativePath: entry.path, srcBase: srcPath, dstBase: dstPath, detail: "profiel: \(profile.name) | rsync: \(entry.code)")
                    }
                } else if self.syncItemizedEntryIsMetadataOnly(entry.code) {
                    countQueue.sync { metadataOnly += 1 }
                    let shouldLog = countQueue.sync { loggedSyncPaths.insert("metadata:\(entry.path)").inserted }
                    if shouldLog {
                        self.recordTransferLog(status: "SYNC NIET OVERGEZET", relativePath: entry.path, srcBase: srcPath, dstBase: dstPath, detail: "inhoud was al gelijk; alleen metadata/attributen weken af | rsync: \(entry.code)")
                    }
                }
            }
            if let metrics = self.rsyncProgressMetrics(from: trimmed) {
                self.updateSyncProgress(profileId: profile.id, percent: metrics.percent, speed: metrics.speed, eta: metrics.eta)
            }
            if let detail = self.syncProgressDetail(fromRsyncLine: trimmed) {
                self.updateSyncProgress(profileId: profile.id, detail: detail)
            }
            self.log("Sync \(profile.name): \(trimmed)")
        }
        let counts = countQueue.sync { (transferred, deleted, metadataOnly) }
        if result.exitCode == 0 && result.timedOut == false {
            var status = counts.0 == 0 && counts.1 == 0 ? "OK: niets overgezet" : "OK: \(counts.0) bestanden overgezet"
            if counts.1 > 0 { status += ", \(counts.1) verwijderd" }
            if counts.2 > 0 { status += " | \(counts.2) alleen metadata/attributen (inhoud overgeslagen)" }
            finishSyncProfile(profile, success: true, status: status)
        } else {
            let timeoutText = result.timedOut ? " timeout" : ""
            finishSyncProfile(profile, success: false, status: "Fout: rsync code \(result.exitCode)\(timeoutText)")
        }
    }

    func finishSyncProfile(_ profile: SyncProfile, success: Bool, status: String) {
        log("Sync klaar: \(profile.name) | \(status)")
        recordTransferLog(status: success ? "SYNC KLAAR" : "SYNC MISLUKT", relativePath: profile.name, detail: status)
        finishSyncProgress(profileId: profile.id, profileName: profile.name, status: status, success: success)
        updateSyncProfile(id: profile.id) { item in
            item.lastRunAt = Date()
            item.lastStatus = status
            item.consecutiveFailures = success ? 0 : item.consecutiveFailures + 1
            item.updatedAt = Date()
        }
    }

    func loadResumeJob() -> ResumableTransferJob? {
        guard let data = recentSourceDefaults.data(forKey: resumeJobDefaultsKey) else { return nil }
        return try? JSONDecoder().decode(ResumableTransferJob.self, from: data)
    }

    func uniqueResumeItems(_ items: [String]) -> [String] {
        var seen = Set<String>()
        var unique: [String] = []
        for item in items {
            guard !item.isEmpty, !seen.contains(item) else { continue }
            seen.insert(item)
            unique.append(item)
        }
        return unique
    }

    func makeResumeJob(srcPath: String, dstPath: String, items: [String], options: TransferOptions, reason: String, createdAt: Date) -> ResumableTransferJob? {
        let unique = uniqueResumeItems(items)
        guard !unique.isEmpty else { return nil }
        return ResumableTransferJob(
            srcPath: srcPath,
            dstPath: dstPath,
            items: unique,
            options: options,
            reason: reason,
            createdAt: createdAt
        )
    }

    func storeResumeJob(_ job: ResumableTransferJob?, logChange: Bool = true) {
        resumeStateQueue.sync {
            if let job = job, let data = try? JSONEncoder().encode(job) {
                recentSourceDefaults.set(data, forKey: resumeJobDefaultsKey)
            } else {
                recentSourceDefaults.removeObject(forKey: resumeJobDefaultsKey)
            }
            recentSourceDefaults.synchronize()
        }

        let applyState = {
            self.lastResumeJob = job
            self.updateResumeButton()
        }
        if Thread.isMainThread {
            applyState()
        } else {
            DispatchQueue.main.async(execute: applyState)
        }

        guard logChange else { return }
        if let job = job {
            log("Hervatbare overdracht opgeslagen: \(job.items.joined(separator: ", "))")
        } else {
            log("Geen hervatbare overdracht opgeslagen")
        }
    }

    func updateResumeButton() {
        guard resumeButton != nil else { return }
        let count = lastResumeJob?.items.count ?? 0
        resumeButton.isEnabled = count > 0
        resumeButton.toolTip = count > 0 ? "Hervat \(count) item(s) van de vorige mislukte of geannuleerde overdracht" : "Geen mislukte of geannuleerde overdracht om te hervatten"
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

    @objc func openSrcItem() {
        navigateIntoSelection(table: srcTable, basePath: srcField.stringValue) { path in
            self.setSrcPath(path, rememberRecent: false)
        }
    }
    @objc func openDstItem() {
        navigateIntoSelection(table: dstTable, basePath: dstField.stringValue) { path in
            self.setDstPath(path, rememberRecent: false)
        }
    }

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

    func sourceItemIsDirectory(_ name: String, base: String) -> Bool {
        let full = (base as NSString).appendingPathComponent(name)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: full, isDirectory: &isDir) && isDir.boolValue
    }

    func sourceFolderContainsAnyFile(_ name: String, base: String) -> Bool {
        let fm = FileManager.default
        let full = (base as NSString).appendingPathComponent(name)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: full, isDirectory: &isDir), isDir.boolValue else {
            return true
        }
        guard let en = fm.enumerator(atPath: full) else {
            log("Lege-map controle kon niet lezen, kopie wordt niet overgeslagen: \(name)")
            return true
        }
        for case let rel as String in en {
            if isTransferCancelRequested() {
                return true
            }
            if rel == ".DS_Store" || rel.hasSuffix("/.DS_Store") { continue }
            let p = (full as NSString).appendingPathComponent(rel)
            var childIsDir: ObjCBool = false
            if fm.fileExists(atPath: p, isDirectory: &childIsDir), !childIsDir.boolValue {
                return true
            }
        }
        return false
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
                recordTransferLog(status: "NIET OVERGEZET", relativePath: d.relPath, srcBase: srcBase, dstBase: dstBase, detail: "mismatch overschrijven mislukt; rsync code \(lastExitCode)")
            } else {
                recordTransferLog(status: "OVERGEZET", relativePath: d.relPath, srcBase: srcBase, dstBase: dstBase, detail: "mismatch handmatig overschreven")
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
            for detail in details where detail.canOverwrite {
                recordTransferLog(status: "NIET OVERGEZET", relativePath: detail.relPath, srcBase: srcBase, dstBase: dstBase, detail: "mismatch door gebruiker overgeslagen")
            }
            outcomeStatus = .warning("Mismatchs overgeslagen")
        case .overwrite(let selected):
            let selectedPaths = Set(selected.map { $0.relPath })
            for detail in details where detail.canOverwrite && !selectedPaths.contains(detail.relPath) {
                recordTransferLog(status: "NIET OVERGEZET", relativePath: detail.relPath, srcBase: srcBase, dstBase: dstBase, detail: "mismatch niet geselecteerd voor overschrijven")
            }
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
        let transferredPathsQueue = DispatchQueue(label: "MoveFolders.copy.transferredPaths")
        var transferredPaths: Set<String> = []

        func registerTransferredPath(_ rawPath: String) {
            var relativePath = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
            if relativePath.hasPrefix("./") { relativePath.removeFirst(2) }
            while relativePath.hasPrefix("/") { relativePath.removeFirst() }
            guard !relativePath.isEmpty, relativePath != ".", !relativePath.hasSuffix("/") else { return }

            let sourcePath = (srcBase as NSString).appendingPathComponent(relativePath)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDirectory), !isDirectory.boolValue else { return }
            let inserted = transferredPathsQueue.sync { transferredPaths.insert(relativePath).inserted }
            if inserted {
                recordTransferLog(status: "OVERGEZET", relativePath: relativePath, srcBase: srcBase, dstBase: dstBase)
            }
        }

        func logFilesNotTransferred(reason: String) {
            let copied = transferredPathsQueue.sync { transferredPaths }
            let sourceRoot = (srcBase as NSString).appendingPathComponent(name)
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: sourceRoot, isDirectory: &isDirectory) else {
                recordTransferLog(status: "NIET OVERGEZET", relativePath: name, srcBase: srcBase, dstBase: dstBase, detail: "bron niet meer bereikbaar; \(reason)")
                return
            }

            if !isDirectory.boolValue {
                if !copied.contains(name) {
                    recordTransferLog(status: "NIET OVERGEZET", relativePath: name, srcBase: srcBase, dstBase: dstBase, detail: reason)
                }
                return
            }

            guard let enumerator = FileManager.default.enumerator(atPath: sourceRoot) else {
                recordTransferLog(status: "NIET OVERGEZET", relativePath: name, srcBase: srcBase, dstBase: dstBase, detail: "bronmap kon niet voor het log worden gelezen; \(reason)")
                return
            }
            for case let child as String in enumerator {
                if child == ".DS_Store" || child.hasSuffix("/.DS_Store") { continue }
                let fullPath = (sourceRoot as NSString).appendingPathComponent(child)
                var childIsDirectory: ObjCBool = false
                guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &childIsDirectory), !childIsDirectory.boolValue else { continue }
                let relativePath = (name as NSString).appendingPathComponent(child)
                if !copied.contains(relativePath) {
                    recordTransferLog(status: "NIET OVERGEZET", relativePath: relativePath, srcBase: srcBase, dstBase: dstBase, detail: reason)
                }
            }
        }

        func runAttempt(useInplace: Bool, includeXattrs: Bool, attempt: Int, maxAttempts: Int) -> (ok: Bool, exitCode: Int32, output: String, timedOut: Bool) {
            if self.isTransferCancelRequested() {
                return (false, 130, "Geannuleerd door gebruiker", false)
            }
            let srcFull = "\(srcBase)/\(name)"
            let flags = rsyncFlags(includeUpdate: true, includePartial: true, includeInplace: useInplace, includeProgress: true, includePerFileProgress: true, includeXattrs: includeXattrs, outFormatMarker: rsyncOutFormatMarker)
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
                let normalizedChunk = chunk.replacingOccurrences(of: "\r", with: "\n")
                let lines = normalizedChunk.split(separator: "\n")
                for l in lines {
                    let trimmed = l.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        var logLine = trimmed
                        if logLine.hasPrefix(self.rsyncOutFormatMarker) {
                            let rel = String(logLine.dropFirst(self.rsyncOutFormatMarker.count)).trimmingCharacters(in: .whitespaces)
                            registerTransferredPath(rel)
                            logLine = rel.isEmpty ? "bestandsupdate" : "bestandsupdate: \(rel)"
                        } else if !self.rsyncConfig.supportsOutFormat {
                            registerTransferredPath(logLine)
                        }
                        self.log("rsync: \(logLine)")
                    }
                    if let metrics = self.rsyncProgressMetrics(from: trimmed) {
                        self.updateProgressMetrics(speed: metrics.speed, eta: metrics.eta)
                        self.updateCurrentFileProgress(percent: metrics.percent)
                        self.updateProgressFromRsync(toChk: metrics.toCheck)
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
            for outputLine in output.replacingOccurrences(of: "\r", with: "\n").split(separator: "\n") {
                let trimmed = outputLine.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix(self.rsyncOutFormatMarker) {
                    let rel = String(trimmed.dropFirst(self.rsyncOutFormatMarker.count)).trimmingCharacters(in: .whitespaces)
                    registerTransferredPath(rel)
                } else if !self.rsyncConfig.supportsOutFormat {
                    registerTransferredPath(trimmed)
                }
            }
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
                logFilesNotTransferred(reason: "overdracht geannuleerd")
                return .cancelled
            }
            let useInplace = attempt >= 2
            let result = runAttempt(useInplace: useInplace, includeXattrs: includeXattrs, attempt: attempt, maxAttempts: maxAttempts)
            if isTransferCancelRequested() {
                log("Kopie geannuleerd tijdens rsync: \(name)")
                logFilesNotTransferred(reason: "overdracht geannuleerd")
                return .cancelled
            }
            if result.ok {
                logFilesNotTransferred(reason: "rsync heeft het bestand overgeslagen; het was al gelijk of het doel was nieuwer")
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
                    logFilesNotTransferred(reason: "overdracht geannuleerd na xattr-fout")
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
            logFilesNotTransferred(reason: "niet bevestigd als overgezet; rsync eindigde met waarschuwing code 23")
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
        logFilesNotTransferred(reason: "niet bevestigd als overgezet; \(failMsg)")
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
        startTransfer(items: items, srcPath: srcPath, dstPath: dstPath, resumed: false)
    }

    @objc func resumeLastTransfer() {
        guard let job = lastResumeJob, !job.items.isEmpty else {
            alert("Er is geen mislukte of geannuleerde overdracht om te hervatten.")
            return
        }
        let alert = NSAlert()
        alert.messageText = "Overdracht hervatten?"
        alert.informativeText = "Bron: \(job.srcPath)\nDoel: \(job.dstPath)\nItems: \(summarizeList(job.items))\nReden: \(job.reason)"
        alert.addButton(withTitle: "Hervat")
        alert.addButton(withTitle: "Annuleer")
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        setSrcPath(job.srcPath, rememberRecent: true)
        setDstPath(job.dstPath, rememberRecent: true)
        applyTransferOptions(job.options)
        startTransfer(items: job.items, srcPath: job.srcPath, dstPath: job.dstPath, resumed: true)
    }

    func startTransfer(items: [String], srcPath: String, dstPath: String, resumed: Bool) {
        guard !items.isEmpty else { return }
        let optionsAtStart = currentTransferOptions()
        let resumeCreatedAt = Date()
        let activeResumeReason = resumed ? "Hervatte overdracht actief" : "Overdracht actief"
        func remainingItems(from index: Int) -> [String] {
            guard index < items.count else { return [] }
            return Array(items[index..<items.count])
        }
        func remainingItems(after index: Int) -> [String] {
            remainingItems(from: index + 1)
        }
        func persistResumeSnapshot(_ snapshotItems: [String], reason: String, logChange: Bool = false) {
            let job = makeResumeJob(
                srcPath: srcPath,
                dstPath: dstPath,
                items: snapshotItems,
                options: optionsAtStart,
                reason: reason,
                createdAt: resumeCreatedAt
            )
            storeResumeJob(job, logChange: logChange)
        }

        rememberRecentSource(srcPath)
        rememberRecentDestination(dstPath)
        resetTransferCancellation()
        resetXattrRuntimeChoices()
        persistResumeSnapshot(items, reason: activeResumeReason, logChange: true)
        let summary = items.prefix(3).joined(separator: ", ") + (items.count > 3 ? " … (+\(items.count - 3) meer)" : "")
        log("\(resumed ? "Hervat copy" : "Start copy"): \(items.joined(separator: ", "))")
        log("Instelling lege mappen overslaan: \(skipEmptyFoldersEnabled ? "aan" : "uit")")
        log("Instelling xattrs: \(copyXattrsEnabled ? "aan" : "uit")")
        recordTransferLog(
            status: resumed ? "OPDRACHT HERVAT" : "OPDRACHT GESTART",
            relativePath: summary,
            detail: "bronmap: \(srcPath) | doelmap: \(dstPath)"
        )
        DispatchQueue.main.async {
            self.showProgress("Bezig met overdracht...", detail: summary)
            self.setPhase("Controle bron")
            self.progressTaskOrder = items
            self.progressTaskFileTotals = [:]
            self.progressOverallFileTotal = nil
        }

        DispatchQueue.global(qos: .userInitiated).async {
            var summaries: [TransferSummary] = []
            var didCancel = false
            var resumeItems: [String] = []
            var resumeReason = ""
            var preScannedFileCounts: [String: Int] = [:]
            if self.preScanEnabled {
                var totalAll = 0
                for (idx, name) in items.enumerated() {
                    if self.isTransferCancelRequested() {
                        didCancel = true
                        resumeItems = items
                        resumeReason = "Geannuleerd tijdens pre-scan"
                        persistResumeSnapshot(resumeItems, reason: resumeReason, logChange: true)
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
                        resumeItems = items
                        resumeReason = "Geannuleerd tijdens pre-scan"
                        persistResumeSnapshot(resumeItems, reason: resumeReason, logChange: true)
                        break
                    }
                    preScannedFileCounts[name] = total
                    totalAll += total
                    DispatchQueue.main.async {
                        self.progressDetail?.stringValue = "Bestanden totaal: \(total) (map) | Totaal: \(totalAll)"
                    }
                }
                DispatchQueue.main.async {
                    self.progressTaskFileTotals = preScannedFileCounts
                    self.progressOverallFileTotal = totalAll
                }
            }
            transferLoop: for (idx, name) in items.enumerated() {
                if self.isTransferCancelRequested() {
                    didCancel = true
                    resumeItems = self.uniqueResumeItems(resumeItems + remainingItems(from: idx))
                    resumeReason = "Geannuleerd voor \(name)"
                    persistResumeSnapshot(resumeItems, reason: resumeReason, logChange: true)
                    break
                }
                // Controleer lege bronmappen voordat de doelmap wordt beoordeeld.
                DispatchQueue.main.async { self.setPhase("Controle bron \(idx + 1)/\(items.count): \(name)") }
                if self.skipEmptyFoldersEnabled && self.sourceItemIsDirectory(name, base: srcPath) {
                    let hasFiles: Bool
                    if let preScannedCount = preScannedFileCounts[name] {
                        hasFiles = preScannedCount > 0
                    } else {
                        DispatchQueue.main.async {
                            self.setPhase("Controle lege map \(idx + 1)/\(items.count): \(name)")
                            self.progressDetail?.stringValue = "Lege map controleren: \(name)"
                        }
                        hasFiles = self.sourceFolderContainsAnyFile(name, base: srcPath)
                    }
                    if self.isTransferCancelRequested() {
                        didCancel = true
                        resumeItems = self.uniqueResumeItems(resumeItems + remainingItems(from: idx))
                        resumeReason = "Geannuleerd tijdens lege-mapcontrole"
                        persistResumeSnapshot(resumeItems, reason: resumeReason, logChange: true)
                        break
                    }
                    if !hasFiles {
                        self.log("Lege map overgeslagen: \(name)")
                        self.recordTransferLog(status: "OVERGESLAGEN", relativePath: name, srcBase: srcPath, dstBase: dstPath, detail: "lege map")
                        summaries.append(TransferSummary(name: name, status: .warning("Overgeslagen: lege map")))
                        persistResumeSnapshot(self.uniqueResumeItems(resumeItems + remainingItems(after: idx)), reason: activeResumeReason)
                        DispatchQueue.main.async {
                            self.progressDetail?.stringValue = "Overgeslagen: lege map \(name)"
                            self.refreshSrc()
                            self.refreshDst()
                        }
                        continue
                    }
                }

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
                    let msg = "Doelpad bestaat al als bestand"
                    self.recordTransferLog(status: "NIET OVERGEZET", relativePath: name, srcBase: srcPath, dstBase: dstPath, detail: msg)
                    summaries.append(TransferSummary(name: name, status: .failed(msg)))
                    resumeItems.append(name)
                    if resumeReason.isEmpty { resumeReason = msg }
                    persistResumeSnapshot(self.uniqueResumeItems(resumeItems + remainingItems(after: idx)), reason: resumeReason)
                    DispatchQueue.main.async {
                        self.alert("Doelpad bestaat al als bestand:\n\(dstItem)\nKies een andere doelmap.")
                    }
                    continue
                }
                if dstStatus == .hasContent {
                    self.log("Doelmap bestaat al, automatisch doorgaan: \(dstItem)")
                }

                if self.preScanEnabled {
                    let total = preScannedFileCounts[name] ?? 0
                    self.log("Pre-scan count \(name): \(total) bestanden")
                    DispatchQueue.main.async {
                        if let overall = self.progressOverallFileTotal {
                            self.progressDetail?.stringValue = "Bestanden totaal: \(total) (map) | Totaal: \(overall)"
                        } else {
                            self.progressDetail?.stringValue = "Bestanden totaal: \(total)"
                        }
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
                    resumeItems.append(name)
                    if resumeReason.isEmpty { resumeReason = "Kopie mislukt" }
                    persistResumeSnapshot(self.uniqueResumeItems(resumeItems + remainingItems(after: idx)), reason: resumeReason)
                    DispatchQueue.main.async {
                        self.refreshDst()
                        self.refreshSrc()
                    }
                    continue
                case .warning(let msg):
                    self.log("Kopie met waarschuwing: \(name)")
                    summaries.append(TransferSummary(name: name, status: .warning(msg)))
                    resumeItems.append(name)
                    if resumeReason.isEmpty { resumeReason = "Kopie met waarschuwing" }
                    persistResumeSnapshot(self.uniqueResumeItems(resumeItems + remainingItems(after: idx)), reason: resumeReason)
                    DispatchQueue.main.async {
                        self.refreshDst()
                        self.refreshSrc()
                    }
                    continue
                case .cancelled:
                    self.log("Kopie geannuleerd: \(name)")
                    didCancel = true
                    resumeItems = self.uniqueResumeItems(resumeItems + remainingItems(from: idx))
                    resumeReason = "Geannuleerd tijdens kopiëren"
                    persistResumeSnapshot(resumeItems, reason: resumeReason, logChange: true)
                    break transferLoop
                case .success:
                    break
                }

                if self.isTransferCancelRequested() {
                    didCancel = true
                    resumeItems = self.uniqueResumeItems(resumeItems + remainingItems(from: idx))
                    resumeReason = "Geannuleerd na kopiëren"
                    persistResumeSnapshot(resumeItems, reason: resumeReason, logChange: true)
                    break
                }
                // Post-verify + opschonen per map
                DispatchQueue.main.async { self.setPhase("Post-verify \(idx + 1)/\(items.count): \(name)") }
                let summary = self.postCopyCheck(items: [name], srcBase: srcPath, dstBase: dstPath)
                summaries.append(summary)
                if case .failed(let msg) = summary.status {
                    resumeItems.append(name)
                    if resumeReason.isEmpty { resumeReason = msg }
                }
                persistResumeSnapshot(self.uniqueResumeItems(resumeItems + remainingItems(after: idx)), reason: resumeReason.isEmpty ? activeResumeReason : resumeReason)
                DispatchQueue.main.async {
                    self.refreshDst()
                    self.refreshSrc()
                }
            }
            if didCancel {
                summaries.append(TransferSummary(name: "Overdracht", status: .warning("Geannuleerd door gebruiker")))
            }
            let uniqueResumeItems = self.uniqueResumeItems(resumeItems)
            var okCount = 0
            var warningCount = 0
            var failedCount = 0
            for summary in summaries {
                switch summary.status {
                case .success: okCount += 1
                case .warning: warningCount += 1
                case .failed: failedCount += 1
                }
            }
            self.recordTransferLog(
                status: didCancel ? "OPDRACHT GEANNULEERD" : "OPDRACHT KLAAR",
                relativePath: items.joined(separator: ", "),
                detail: "OK: \(okCount) | waarschuwingen: \(warningCount) | fouten: \(failedCount)"
            )
            DispatchQueue.main.async {
                if uniqueResumeItems.isEmpty {
                    self.storeResumeJob(nil)
                } else {
                    let job = ResumableTransferJob(
                        srcPath: srcPath,
                        dstPath: dstPath,
                        items: uniqueResumeItems,
                        options: optionsAtStart,
                        reason: resumeReason.isEmpty ? "Mislukte of geannuleerde items" : resumeReason,
                        createdAt: Date()
                    )
                    self.storeResumeJob(job)
                }
                self.hideProgress()
                self.showSummary(summaries, dstPath: dstPath)
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

    func showSummary(_ summaries: [TransferSummary], dstPath: String? = nil) {
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

        if let job = lastResumeJob, !job.items.isEmpty {
            lines.append("")
            lines.append("Hervatbaar: \(summarizeList(job.items))")
        }

        let alert = NSAlert()
        alert.messageText = "Samenvatting overdrachten"
        alert.informativeText = lines.dropFirst().joined(separator: "\n")

        var actions: [String] = []
        if let job = lastResumeJob, !job.items.isEmpty {
            alert.addButton(withTitle: "Hervat")
            actions.append("resume")
        }
        if dstPath != nil {
            alert.addButton(withTitle: "Open doelmap")
            actions.append("openDestination")
        }
        alert.addButton(withTitle: "Toon log")
        actions.append("showLog")
        alert.addButton(withTitle: "Sluit")
        actions.append("close")

        let response = alert.runModal()
        let first = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let selectedIndex = response.rawValue - first
        guard selectedIndex >= 0 && selectedIndex < actions.count else { return }
        switch actions[selectedIndex] {
        case "resume":
            resumeLastTransfer()
        case "openDestination":
            if let dstPath = dstPath {
                NSWorkspace.shared.open(URL(fileURLWithPath: dstPath))
            }
        case "showLog":
            showTransferLogWindow()
        default:
            break
        }
    }

    func setupTransferLogWindow() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 920, height: 480),
                            styleMask: [.titled, .closable, .resizable],
                            backing: .buffered,
                            defer: false)
        panel.title = "Overdrachtslog"
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentMinSize = NSSize(width: 620, height: 280)

        let scroll = NSScrollView(frame: panel.contentView?.bounds ?? .zero)
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = true
        scroll.autoresizingMask = [.width, .height]
        let textView = NSTextView(frame: scroll.bounds)
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = false
        textView.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.drawsBackground = true
        textView.backgroundColor = NSColor.textBackgroundColor
        textView.textColor = NSColor.textColor
        textView.string = recentTransferLogText()
        scroll.documentView = textView
        panel.contentView?.addSubview(scroll)

        transferLogWindow = panel
        transferLogTextView = textView
        textView.scrollToEndOfDocument(nil)
    }

    func recentTransferLogText(maxBytes: UInt64 = 5 * 1024 * 1024) -> String {
        return transferLogQueue.sync {
            transferLogFileHandle?.synchronizeFile()
            guard FileManager.default.fileExists(atPath: transferLogURL.path),
                  let handle = try? FileHandle(forReadingFrom: transferLogURL) else {
                return "Nog geen overdrachten gelogd.\n"
            }
            defer { handle.closeFile() }
            let size = (try? FileManager.default.attributesOfItem(atPath: transferLogURL.path)[.size] as? NSNumber)?.uint64Value ?? 0
            let start = size > maxBytes ? size - maxBytes : 0
            handle.seek(toFileOffset: start)
            let data = handle.readDataToEndOfFile()
            var text = String(decoding: data, as: UTF8.self)
            if start > 0, let newline = text.firstIndex(of: "\n") {
                text = String(text[text.index(after: newline)...])
                text = "— Alleen de laatste 5 MB wordt hier getoond; het volledige logbestand blijft bewaard. —\n" + text
            }
            return text.isEmpty ? "Nog geen overdrachten gelogd.\n" : text
        }
    }

    func showTransferLogWindow() {
        if transferLogWindow == nil {
            setupTransferLogWindow()
        } else {
            transferLogTextView?.string = recentTransferLogText()
            transferLogTextView?.scrollToEndOfDocument(nil)
        }
        transferLogWindow?.center()
        transferLogWindow?.makeKeyAndOrderFront(nil)
    }

    @objc func toggleTransferLog() {
        guard let win = transferLogWindow else {
            showTransferLogWindow()
            return
        }
        if win.isVisible {
            win.orderOut(nil)
        } else {
            showTransferLogWindow()
        }
    }

    func recordTransferLog(status: String, relativePath: String, srcBase: String? = nil, dstBase: String? = nil, detail: String? = nil) {
        let timestamp = transferLogFormatterQueue.sync { transferLogFormatter.string(from: Date()) }
        let cleanPath = relativePath.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " ")
        var parts = ["[\(timestamp)]", status, cleanPath]
        if let srcBase = srcBase, !srcBase.isEmpty {
            parts.append("bron: \((srcBase as NSString).appendingPathComponent(cleanPath))")
        }
        if let dstBase = dstBase, !dstBase.isEmpty {
            parts.append("doel: \((dstBase as NSString).appendingPathComponent(cleanPath))")
        }
        if let detail = detail, !detail.isEmpty {
            parts.append(detail.replacingOccurrences(of: "\n", with: " ").replacingOccurrences(of: "\r", with: " "))
        }
        let line = parts.joined(separator: " | ") + "\n"

        transferLogQueue.async {
            do {
                let directory = self.transferLogURL.deletingLastPathComponent()
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                if !FileManager.default.fileExists(atPath: self.transferLogURL.path) {
                    FileManager.default.createFile(atPath: self.transferLogURL.path, contents: nil)
                }
                if self.transferLogFileHandle == nil {
                    self.transferLogFileHandle = try FileHandle(forWritingTo: self.transferLogURL)
                    self.transferLogFileHandle?.seekToEndOfFile()
                }
                if let data = line.data(using: .utf8) {
                    self.transferLogFileHandle?.write(data)
                }
            } catch {
                print("MoveFolders overdrachtslog kon niet worden geschreven: \(error.localizedDescription)")
            }

            DispatchQueue.main.async {
                guard self.transferLogWindow?.isVisible == true,
                      let textView = self.transferLogTextView,
                      let storage = textView.textStorage else { return }
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.textColor,
                    .font: textView.font ?? NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
                ]
                storage.append(NSAttributedString(string: line, attributes: attrs))
                textView.scrollToEndOfDocument(nil)
            }
        }
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
        alert.informativeText = "Huidig: \(currentVersion)\nNieuw: \(latestVersion)\n\nMoveFolders downloadt de installer en sluit daarna, zodat de update de bestaande app kan vervangen."
        let hasPackage = packageURLString != nil
        if hasPackage {
            alert.addButton(withTitle: "Download en open installer")
        }
        alert.addButton(withTitle: "Open release")
        alert.addButton(withTitle: "Later")
        let response = alert.runModal()

        if hasPackage, response == .alertFirstButtonReturn, let pkgURLString = packageURLString, let pkgURL = URL(string: pkgURLString) {
            downloadAndOpenUpdate(packageURL: pkgURL, latestVersion: latestVersion)
        } else if response == (hasPackage ? .alertSecondButtonReturn : .alertFirstButtonReturn), let releaseURL = URL(string: releaseURLString) {
            NSWorkspace.shared.open(releaseURL)
        }
    }

    func downloadAndOpenUpdate(packageURL: URL, latestVersion: String) {
        guard progressWindow == nil else {
            alert("Wacht tot de lopende overdracht klaar is voordat je een update installeert.")
            return
        }

        log("Update download start: \(packageURL.absoluteString)")
        let task = URLSession.shared.downloadTask(with: packageURL) { tempURL, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.alert("Update downloaden mislukt:\n\(error.localizedDescription)")
                }
                return
            }
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                DispatchQueue.main.async {
                    self.alert("Update downloaden mislukt: HTTP \(http.statusCode).")
                }
                return
            }
            guard let tempURL = tempURL else {
                DispatchQueue.main.async {
                    self.alert("Update downloaden mislukt: geen tijdelijk bestand ontvangen.")
                }
                return
            }

            let fm = FileManager.default
            let downloads = fm.urls(for: .downloadsDirectory, in: .userDomainMask).first ?? fm.temporaryDirectory
            let fallbackName = "MoveFolders_\(latestVersion.replacingOccurrences(of: "v", with: ""))_installer.pkg"
            let fileName = packageURL.lastPathComponent.isEmpty ? fallbackName : packageURL.lastPathComponent
            let targetURL = downloads.appendingPathComponent(fileName)

            do {
                if fm.fileExists(atPath: targetURL.path) {
                    try fm.removeItem(at: targetURL)
                }
                try fm.moveItem(at: tempURL, to: targetURL)
            } catch {
                DispatchQueue.main.async {
                    self.alert("Update downloaden gelukt, maar bewaren mislukt:\n\(error.localizedDescription)")
                }
                return
            }

            DispatchQueue.main.async {
                self.log("Update installer opgeslagen: \(targetURL.path)")
                if NSWorkspace.shared.open(targetURL) {
                    self.log("Update installer geopend; app sluit voor installatie")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        NSApp.terminate(nil)
                    }
                } else {
                    self.alert("Installer kon niet geopend worden:\n\(targetURL.path)")
                }
            }
        }
        task.resume()
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
