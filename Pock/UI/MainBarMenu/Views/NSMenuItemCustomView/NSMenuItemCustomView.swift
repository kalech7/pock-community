//
//  NSMenuItemCustomView.swift
//  Pock
//
//  Created by Pierluigi Galdi on 05/02/21.
//  Copyright © 2021 Pierluigi Galdi. All rights reserved.
//

import Cocoa
import Magnet

@IBDesignable
internal class NSMenuItemCustomView: NSView {

	@IBOutlet internal private(set) weak var view: NSView!
	@IBOutlet internal private(set) weak var mainLabel: NSTextField!
	@IBOutlet internal private(set) weak var keyModifier: NSTextField!
	@IBOutlet internal private(set) weak var keyChar: NSTextField!

	internal weak var item: NSMenuItem?

	override var intrinsicContentSize: NSSize {
		mainLabel.sizeToFit()
		keyModifier.sizeToFit()
		var orig = super.intrinsicContentSize
		orig.width = mainLabel.frame.width + keyModifier.frame.width
		orig.width += 48
		return orig
	}

	internal static func new(title: String, target: AnyObject?, selector: Selector?, keyEquivalent: String?, isAlternate: Bool = false, height: CGFloat = 23) -> NSMenuItem {
		let item = NSMenuItem(title: title, action: selector, keyEquivalent: keyEquivalent ?? "")
		item.target = target
		item.isAlternate = isAlternate
		item.view = NSMenuItemCustomView(item: item, height: height)
		return item
	}
	
	convenience init(item: NSMenuItem, height: CGFloat = 23) {
		self.init(frame: .zero)
		self.item = item
		self.item?._setViewHandlesEvents(false)
		self.translatesAutoresizingMaskIntoConstraints = false
		self.heightAnchor.constraint(equalToConstant: height).isActive = true
		let frameworkBundle = Bundle(for: Self.self)
		guard frameworkBundle.loadNibNamed(String(Self.self), owner: self, topLevelObjects: nil) else {
			fatalError("[NSMenuItemCustomView] Can't find nib for name: `\(String(Self.self)))`")
		}
		addSubview(view)
		view.translatesAutoresizingMaskIntoConstraints = false
		view.leadingAnchor.constraint(equalTo: leadingAnchor).isActive = true
		view.trailingAnchor.constraint(equalTo: trailingAnchor).isActive = true
		view.topAnchor.constraint(equalTo: topAnchor).isActive = true
		view.bottomAnchor.constraint(equalTo: bottomAnchor).isActive = true
		layoutSubtreeIfNeeded()
	}

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		mainLabel.textColor = .labelColor
		guard item?.submenu == nil, item?.keyEquivalent.isEmpty == false else {
			keyModifier.isHidden = true
			keyChar.isHidden = true
			return
		}
		keyModifier.textColor = item?.isHighlighted == true ? .labelColor : .tertiaryLabelColor
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		mainLabel.stringValue = item?.title ?? ""
		updateShortcutLabels()
	}

	internal func updateShortcutLabels() {
		guard item?.submenu == nil, item?.keyEquivalent.isEmpty == false else {
			keyModifier.isHidden = true
			keyChar.isHidden = true
			keyModifier.stringValue = ""
			keyChar.stringValue = ""
			return
		}
		keyModifier.isHidden = false
		keyChar.isHidden = true
		keyChar.stringValue = ""
		keyModifier.alignment = .right
		keyModifier.stringValue = [
			item?.keyEquivalentModifierMask.pockMenuShortcutModifierString ?? "",
			item?.keyEquivalent.uppercased() ?? ""
		].joined()
		updateShortcutContainerWidth()
	}

	private func updateShortcutContainerWidth() {
		let font = keyModifier.font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize)
		let width = ceil((keyModifier.stringValue as NSString).size(withAttributes: [.font: font]).width) + 6
		let containerWidth = max(24, min(width, 76))
		keyModifier.superview?.constraints.first(where: { constraint in
			constraint.firstAttribute == .width && constraint.secondItem == nil
		})?.constant = containerWidth
		invalidateIntrinsicContentSize()
	}
}

extension NSEvent.ModifierFlags {
	var pockMenuShortcutModifierString: String {
		return keyEquivalentStrings().joined()
	}
}
