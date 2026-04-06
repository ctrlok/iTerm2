//
//  ToolStatusCellView.swift
//  iTerm2SharedARC
//
//  Created by George Nachman on 4/5/26.
//

import Foundation

class ToolStatusCellView: NSTableCellView {
    private let dotView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let vStack: NSStackView

    override init(frame: NSRect) {
        let font = NSFont.it_toolbelt()

        // Top row: dot + name
        let topRow = NSStackView(views: [dotView, nameLabel])
        topRow.orientation = .horizontal
        topRow.spacing = 4
        topRow.alignment = .centerY

        vStack = NSStackView(views: [topRow, statusLabel, detailLabel])
        vStack.orientation = .vertical
        vStack.alignment = .leading
        vStack.spacing = 1
        vStack.translatesAutoresizingMaskIntoConstraints = false

        super.init(frame: frame)

        dotView.translatesAutoresizingMaskIntoConstraints = false
        dotView.imageScaling = .scaleProportionallyDown

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = font
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.font = font
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.font = font
        detailLabel.maximumNumberOfLines = 0
        detailLabel.lineBreakMode = .byWordWrapping
        detailLabel.usesSingleLineMode = false
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        detailLabel.isHidden = true

        addSubview(vStack)

        let dotSize: CGFloat = 10
        NSLayoutConstraint.activate([
            dotView.widthAnchor.constraint(equalToConstant: dotSize),
            dotView.heightAnchor.constraint(equalToConstant: dotSize),

            vStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            vStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            vStack.topAnchor.constraint(equalTo: topAnchor, constant: 2),
            vStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -2),
        ])
    }

    required init?(coder: NSCoder) {
        it_fatalError()
    }

    func configure(sessionName: String,
                   dotImage: NSImage?,
                   statusText: String?,
                   statusColor: NSColor?,
                   detail: String?) {
        nameLabel.stringValue = sessionName
        self.dotView.image = dotImage
        dotView.isHidden = dotImage == nil

        statusLabel.stringValue = statusText ?? ""
        if let statusColor {
            statusLabel.textColor = statusColor
        } else {
            statusLabel.textColor = .secondaryLabelColor
        }
        statusLabel.isHidden = (statusText ?? "").isEmpty

        if let detail, !detail.isEmpty {
            detailLabel.stringValue = detail
            detailLabel.isHidden = false
        } else {
            detailLabel.stringValue = ""
            detailLabel.isHidden = true
        }
    }
}
