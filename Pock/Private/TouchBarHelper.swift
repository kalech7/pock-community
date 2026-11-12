//  TouchBarHelper.swift
//  Pock
//
//  Created by Pierluigi Galdi on 04/01/2020.
//  Copyright © 2020 Pierluigi Galdi. All rights reserved.
//

import CoreFoundation
import Darwin

private let kPresentationModeGlobal  = "PresentationModeGlobal"   as CFString
private let kTouchBarAgentIdentifier = "com.apple.touchbar.agent" as CFString
private var isPockDimRequestInProgress = false
private var closeButtonHideGeneration = 0
private var presentedPockBars = Set<ObjectIdentifier>()

private class CommandLineHelper {
	@discardableResult
	static func execute(launchPath: String, arguments: [String]) -> String? {
		let task = Process()
		task.launchPath = launchPath
		task.arguments = arguments
		let pipe = Pipe()
		task.standardOutput = pipe
		task.launch()
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		let output = String(data: data, encoding: String.Encoding.utf8)
		return output
	}
}

public enum PresentationMode: String, CaseIterable {
	case undefined,
		 app,
		 appWithControlStrip,
		 fullControlStrip,
		 functionKeys,
		 workflows,
		 workflowsWithControlStrip,
		 spaces,
		 spacesWithControlStrip
	public var hasControlStrip: Bool {
		switch self {
		case .appWithControlStrip, .workflowsWithControlStrip, .spacesWithControlStrip:
			return true
		default:
			return false
		}
	}
	public var title: String {
		switch self {
		case .app:
			return "presentation-mode.app".localized
		case .appWithControlStrip, .undefined:
			return "presentation-mode.app-with-control-strip".localized
		case .fullControlStrip:
			return "presentation-mode.full-control-strip".localized
		case .functionKeys:
			return "presentation-mode.function-keys".localized
		case .workflows:
			return "presentation-mode.workflows".localized
		case .workflowsWithControlStrip:
			return "presentation-mode.workflows-with-control-strip".localized
		case .spaces:
			return "presentation-mode.spaces".localized
		case .spacesWithControlStrip:
			return "presentation-mode.spaces-with-control-strip".localized
		}
	}
}

public class TouchBarHelper {

	// MARK: Pock internal's helpers
	private static let applySystemPresentationMode: ((CFString, Bool) -> Bool)? = {
		// The system setter updates the preference and tells TouchBarServer to apply it.
		// Keep the preference-based fallback for versions without these symbols.
		guard let framework = dlopen(nil, RTLD_LAZY),
			  let lookup = dlsym(framework, "_DFRPresentationModeFromKey"),
			  let setter = dlsym(framework, "DFRPresentationModeSetDefault") else {
			return nil
		}
		let modeForKey = unsafeBitCast(lookup, to: (@convention(c) (CFString, Int64) -> Int64).self)
		let setDefaultMode = unsafeBitCast(setter, to: (@convention(c) (Int64) -> Void).self)
		let currentMode = dlsym(framework, "DFRPresentationModeGetCurrent").map {
			unsafeBitCast($0, to: (@convention(c) () -> Int64).self)
		}
		return { key, preferenceChanged in
			let requestedMode = modeForKey(key, -1)
			guard requestedMode >= 0 else { return false }
			// The saved mode can match while TouchBarServer is still using a different mode.
			guard preferenceChanged || currentMode.map({ $0() != requestedMode }) == true else { return false }
			setDefaultMode(requestedMode)
			return true
		}
	}()

	public static var isSystemControlStripVisible: Bool {
		return TouchBarHelper.currentPresentationMode.hasControlStrip
	}

	public static var currentPresentationMode: PresentationMode {
		guard let value = (CFPreferencesCopyAppValue(kPresentationModeGlobal, kTouchBarAgentIdentifier) as? NSObject)?.copy(),
			  let mode  = value as? String else {
			return .appWithControlStrip
		}
		return PresentationMode(rawValue: mode) ?? .appWithControlStrip
	}

	@discardableResult
	internal static func setPresentationMode(to mode: PresentationMode) -> Bool {
		let currentMode = currentPresentationMode
		if let applySystemPresentationMode = applySystemPresentationMode {
			guard applySystemPresentationMode(mode.rawValue as CFString, currentMode != mode) else { return false }
			return CFPreferencesAppSynchronize(kTouchBarAgentIdentifier)
		}
		guard currentMode != mode else { return false }
		CFPreferencesSetAppValue(kPresentationModeGlobal, mode.rawValue as CFString, kTouchBarAgentIdentifier)
		let result = CFPreferencesAppSynchronize(kTouchBarAgentIdentifier)
		if result {
			reloadTouchBarAgent()
		}
		Roger.debug("Touch Bar Presentation mode changed: [\(result ? "success" : "error")] \(currentMode) -> \(mode)")
		return result
	}
	
	@objc public static func markTouchBarAsDimmed(_ dimmed: Bool) {
		isPockDimRequestInProgress = true
		defer {
			isPockDimRequestInProgress = false
		}
		NSFunctionRow.markActiveFunctionRows(asDimmed: dimmed)
	}
	
	@objc public static func hideCloseButtonIfNeeded() {
		DFRSystemModalShowsCloseBoxWhenFrontMost(false)
		NSFunctionRow._topLevelViews().compactMap({ $0 as? NSView }).forEach({
			hideCloseButton(in: $0)
		})
	}

	internal static func hideCloseButtonIfNeededRepeatedly() {
		closeButtonHideGeneration += 1
		let generation = closeButtonHideGeneration
		[0.0, 0.05, 0.15, 0.35, 0.75].forEach { delay in
			async(after: delay) {
				guard generation == closeButtonHideGeneration else {
					return
				}
				TouchBarHelper.hideCloseButtonIfNeeded()
			}
		}
	}

	internal static func restoreCloseButtonIfNeeded() {
		closeButtonHideGeneration += 1
		DFRSystemModalShowsCloseBoxWhenFrontMost(true)
	}

	private static func hideCloseButton(in view: NSView) {
		if object_getClass(view) === NSClassFromString("NSFunctionRowBackgroundColorView") {
			view.subviews.compactMap({ $0 as? NSStackView }).forEach({
				hideButtons(in: $0)
			})
			return
		}
		view.subviews.forEach({
			hideCloseButton(in: $0)
		})
	}

	private static func hideButtons(in view: NSView) {
		if view is NSButton {
			view.isHidden = true
			return
		}
		view.subviews.forEach({
			hideButtons(in: $0)
		})
	}

	@objc public static func reloadTouchBarAgent(_ completion: ((Bool) -> Void)? = nil) {
		let result = CommandLineHelper.execute(launchPath: "/usr/bin/pkill", arguments: ["ControlStrip"])
		completion?(result != nil)
	}

	internal static func reloadTouchBarServer(_ completion: ((Bool) -> Void)? = nil) {
		let touchBarServerPid = _DFRGetServerPID().description
		var task = STPrivilegedTask(launchPath: "/bin/kill", arguments: [touchBarServerPid])
		defer {
			task?.terminate()
			task = nil
		}
		guard let error = task?.launch() else {
			completion?(false)
			return
		}
		async(after: 2.525) { [touchBarServerPid, error] in
			switch error {
			case errAuthorizationSuccess:
				completion?(true)
			default:
				completion?(false)
			}
			Roger.debug("[TouchBarServer]: old_pid: `\(touchBarServerPid)` - new_pid: `\(_DFRGetServerPID().description)`")
		}
	}

	// MARK: NSTouchBar helpers
	@objc public static func presentOnTop(_ touchBar: NSTouchBar?) {
		presentOnTop(touchBar, placement: 1)
	}

	internal static func presentOnTop(_ touchBar: NSTouchBar?, placement: Int64) {
		guard let touchBar = touchBar else {
			return
		}
		presentedPockBars.insert(ObjectIdentifier(touchBar))
		DFRSystemModalShowsCloseBoxWhenFrontMost(false)
		if #available (macOS 10.14, *) {
			NSTouchBar.presentSystemModalTouchBar(touchBar, placement: placement, systemTrayItemIdentifier: nil)
		} else {
			NSTouchBar.presentSystemModalFunctionBar(touchBar, placement: placement, systemTrayItemIdentifier: nil)
		}
		hideCloseButtonIfNeededRepeatedly()
	}

	@objc public static func dismissFromTop(_ touchBar: NSTouchBar?) {
		guard let touchBar = touchBar else {
			restoreCloseButtonIfNeeded()
			return
		}
		presentedPockBars.remove(ObjectIdentifier(touchBar))
		if #available (macOS 10.14, *) {
			NSTouchBar.dismissSystemModalTouchBar(touchBar)
		} else {
			NSTouchBar.dismissSystemModalFunctionBar(touchBar)
		}
		restoreCloseButtonIfNeeded()
	}

	@objc public static func minimizeFromTop(_ touchBar: NSTouchBar?) {
		guard let touchBar = touchBar else {
			restoreCloseButtonIfNeeded()
			return
		}
		presentedPockBars.remove(ObjectIdentifier(touchBar))
		if #available (macOS 10.14, *) {
			NSTouchBar.minimizeSystemModalTouchBar(touchBar)
		} else {
			NSTouchBar.minimizeSystemModalFunctionBar(touchBar)
		}
		restoreCloseButtonIfNeeded()
	}

	@objc public static func mainNavigationController() -> Any? {
		return AppController.shared.navigationController
	}
	
	@objc public static func swizzleFunctions() {
		NSFunctionRow.swizzleFunctionMarkActiveFunctionRows
		NSFunctionRow.swizzleFunctionCloseButtonPadding
	}

}

// MARK: Swizzle - markActiveFunctionRows
extension NSFunctionRow {
	
	// The call through the swapped selector must use Objective-C dispatch in Release builds.
	@objc dynamic static func s_markActiveFunctionRowsAsDimmed(_ dimmed: Bool) {
		Roger.debug("[Pock]: Swizzled method: `NSFunctionRow.markActiveFunctionRowsAsDimmed` - [dimmed: \(dimmed)]")
		guard isPockDimRequestInProgress else {
			if presentedPockBars.isEmpty {
				s_markActiveFunctionRowsAsDimmed(dimmed)
			}
			return
		}
		if dimmed {
			AppController.shared.tearDownTouchBar()
		} else {
			AppController.shared.prepareTouchBar()
		}
	}
	
	internal static let swizzleFunctionMarkActiveFunctionRows: Void = {
		let sel1 = #selector(NSFunctionRow.markActiveFunctionRows(asDimmed:))
		let sel2 = #selector(NSFunctionRow.s_markActiveFunctionRowsAsDimmed(_:))
		if let met1 = class_getClassMethod(NSFunctionRow.self, sel1), let met2 = class_getClassMethod(NSFunctionRow.self, sel2) {
			method_exchangeImplementations(met1, met2)
		}
	}()
	
}

// MARK: Swizzle - escapeKeyPaddingForCloseButton
extension NSFunctionRow {
	
	@objc dynamic func s_escapeKeyPaddingForCloseButton(_ isForCloseButton: Bool) -> Double {
		let original = self.s_escapeKeyPaddingForCloseButton(isForCloseButton)
		Roger.debug("[Pock]: Swizzled method: `_NSFunctionRow.escapeKeyPaddingForCloseButton` - [padding: \(original), isForCloseButton: \(isForCloseButton)]")
		guard !presentedPockBars.isEmpty else { return original }
		async {
			if !presentedPockBars.isEmpty {
				TouchBarHelper.hideCloseButtonIfNeeded()
			}
		}
		return isForCloseButton ? 0 : original
	}
	
	internal static let swizzleFunctionCloseButtonPadding: Void = {
		let sel1 = NSSelectorFromString("escapeKeyPaddingForCloseButton:")
		let sel2 = #selector(NSFunctionRow.s_escapeKeyPaddingForCloseButton(_:))
		if let met1 = class_getInstanceMethod(NSClassFromString("_NSFunctionRow"), sel1), let met2 = class_getInstanceMethod(NSFunctionRow.self, sel2) {
			method_exchangeImplementations(met1, met2)
		}
	}()
	
}
