import Foundation

@objc(iTermStatusPrioritySettings)
class StatusPrioritySettings: NSObject {
    @objc static let shared = StatusPrioritySettings()
    static let didChangeNotification = Notification.Name("StatusPrioritySettingsDidChange")

    private static let defaultsKey = "StatusPriorities"
    private static let defaultPatterns = ["wait", "work", "idle"]

    private(set) var patterns: [String] {
        didSet {
            save()
        }
    }

    private func save() {
        iTermUserDefaults.userDefaults().set(patterns, forKey: Self.defaultsKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Restore patterns from an external source (e.g., undo) without a redundant UserDefaults write.
    func restorePatterns(_ newPatterns: [String]) {
        patterns = newPatterns
    }

    private override init() {
        if let saved = iTermUserDefaults.userDefaults().stringArray(forKey: Self.defaultsKey) {
            patterns = saved
        } else {
            patterns = Self.defaultPatterns
        }
        super.init()
    }

    /// Returns priority for the given status text.
    /// Lower numbers = higher priority.
    /// nil statusText gets the lowest priority.
    @objc func priority(for statusText: String?) -> Int {
        guard let statusText else {
            return patterns.count + 1
        }
        let lower = statusText.lowercased()
        for (i, pattern) in patterns.enumerated() {
            if lower.contains(pattern.lowercased()) {
                return i
            }
        }
        return patterns.count
    }

    // MARK: - Mutation

    func add(_ pattern: String, at index: Int) {
        var updated = patterns
        updated.insert(pattern, at: index)
        patterns = updated
    }

    func remove(at indexes: IndexSet) {
        var updated = patterns
        for i in indexes.sorted().reversed() {
            updated.remove(at: i)
        }
        patterns = updated
    }

    func update(_ pattern: String, at index: Int) {
        var updated = patterns
        updated[index] = pattern
        patterns = updated
    }

    func reorder(from sourceIndex: Int, to destinationIndex: Int) {
        var updated = patterns
        let item = updated.remove(at: sourceIndex)
        updated.insert(item, at: destinationIndex)
        patterns = updated
    }
}

// MARK: - Settings Popover

extension StatusPrioritySettings {
    @objc func showSettingsPopover(relativeTo positioningRect: NSRect,
                                   of positioningView: NSView,
                                   preferredEdge edge: NSRectEdge) {
        StatusPriorityPopover.shared.show(relativeTo: positioningRect,
                                          of: positioningView,
                                          preferredEdge: edge)
    }
}

// MARK: - CRUD Support

private struct PriorityRow: CRUDRow {
    var pattern: String
    func format(column: Int) -> CRUDFormatted {
        .string(pattern)
    }
}

private class PriorityDataProvider: CRUDDataProvider {
    weak var viewController: NSViewController?

    var count: Int { StatusPrioritySettings.shared.patterns.count }
    var supportsReorder: Bool { true }
    var supportsInlineEditing: Bool { true }

    subscript(_ index: Int) -> CRUDRow {
        PriorityRow(pattern: StatusPrioritySettings.shared.patterns[index])
    }

    func delete(_ indexes: IndexSet) {
        StatusPrioritySettings.shared.remove(at: indexes)
    }

    func makeNew(completion: @escaping (Int) -> ()) {
        guard let vc = viewController as? StatusPriorityViewController,
              let window = vc.view.window else {
            return
        }
        let alert = NSAlert()
        alert.messageText = "New Priority Pattern"
        alert.informativeText = "Enter a substring to match against status text (case-insensitive)."
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")

        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 200, height: 24))
        alert.accessoryView = textField

        DispatchQueue.main.async {
            textField.becomeFirstResponder()
        }

        alert.beginSheetModal(for: window) { response in
            guard response == .alertFirstButtonReturn else { return }
            let value = textField.stringValue
            guard !value.isEmpty else { return }
            vc.undoableAdd(value, completion: completion)
        }
    }

    func reorder(from sourceIndex: Int, to destinationIndex: Int) {
        StatusPrioritySettings.shared.reorder(from: sourceIndex, to: destinationIndex)
    }
}

// MARK: - Popover

private final class StatusPriorityPopover: NSObject {
    static let shared = StatusPriorityPopover()

    private var popover: NSPopover?

    func show(relativeTo positioningRect: NSRect,
              of positioningView: NSView,
              preferredEdge edge: NSRectEdge) {
        if let popover, popover.isShown {
            popover.close()
            return
        }
        let vc = StatusPriorityViewController()
        let popover = NSPopover()
        popover.contentViewController = vc
        popover.behavior = .semitransient
        popover.contentSize = NSSize(width: 220, height: 260)
        popover.show(relativeTo: positioningRect, of: positioningView, preferredEdge: edge)
        self.popover = popover
    }
}

private final class StatusPriorityViewController: NSViewController, CRUDTableViewControllerDelegate {
    typealias CRUDState = [String]

    private var crudController: CRUDTableViewController<StatusPriorityViewController>?

    var crudState: CRUDState {
        get { StatusPrioritySettings.shared.patterns }
        set {
            StatusPrioritySettings.shared.restorePatterns(newValue)
        }
    }

    override func loadView() {
        let width: CGFloat = 220
        let height: CGFloat = 260
        let margin: CGFloat = 10
        let segmentHeight: CGFloat = 24
        let labelHeight: CGFloat = 32

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))

        // Instructional label at top
        let label = NSTextField(wrappingLabelWithString: "Statuses are sorted by priority. Items near the top have higher priority. Drag to reorder. Click to edit.")
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: margin,
                             y: height - margin - labelHeight,
                             width: width - 2 * margin,
                             height: labelHeight)
        label.autoresizingMask = [.width, .minYMargin]
        container.addSubview(label)

        // +/- segmented control at bottom
        let addRemove = NSSegmentedControl(images: [
            NSImage(systemSymbolName: "plus", accessibilityDescription: "Add")!,
            NSImage(systemSymbolName: "minus", accessibilityDescription: "Remove")!
        ], trackingMode: .momentary, target: nil, action: nil)
        addRemove.frame = NSRect(x: margin, y: margin, width: 60, height: segmentHeight)
        addRemove.autoresizingMask = [.maxXMargin, .maxYMargin]
        container.addSubview(addRemove)

        // Table view between label and segmented control
        let scrollY = margin + segmentHeight + 4
        let scrollHeight = height - margin - labelHeight - 4 - scrollY
        let scrollView = NSScrollView(frame: NSRect(x: margin, y: scrollY,
                                                     width: width - 2 * margin,
                                                     height: scrollHeight))
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]

        let tv = CompetentTableView(frame: scrollView.bounds)
        tv.headerView = nil
        tv.rowHeight = 20
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("Pattern"))
        column.title = "Pattern"
        column.isEditable = true
        tv.addTableColumn(column)
        scrollView.documentView = tv
        container.addSubview(scrollView)

        let dataProvider = PriorityDataProvider()
        dataProvider.viewController = self
        let schema = CRUDSchema(columns: [CRUDColumn(type: .string)],
                                dataProvider: dataProvider)
        crudController = CRUDTableViewController(tableView: tv,
                                                  addRemove: addRemove,
                                                  schema: schema)
        crudController?.delegate = self

        self.view = container
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        crudController?.reload()
    }

    func undoableAdd(_ value: String, completion: @escaping (Int) -> ()) {
        crudController?.undoable {
            let index = StatusPrioritySettings.shared.patterns.count
            StatusPrioritySettings.shared.add(value, at: index)
            completion(index)
        }
    }

    // MARK: - CRUDTableViewControllerDelegate

    func crudTableSelectionDidChange(_ sender: CRUDTableViewController<StatusPriorityViewController>,
                                     selectedRows: IndexSet) {
    }

    func crudTextFieldDidChange(_ sender: CRUDTableViewController<StatusPriorityViewController>,
                                row: Int,
                                column: Int,
                                newValue: String) {
        crudController?.undoable {
            StatusPrioritySettings.shared.update(newValue, at: row)
        }
    }

    func crudDoubleClick(_ sender: CRUDTableViewController<StatusPriorityViewController>,
                         row: Int,
                         column: Int) {
    }
}
