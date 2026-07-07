//
//  HotKey.swift
//  Pock
//
//  Created by Pierluigi Galdi on 10/03/21.
//

import Foundation

public class HotKey {

	/// Target & Selector
	private var target: AnyObject?
	private var selector: Selector?
	private var eventMonitors: [Any] = []

	/// Hit-count
	private var hitCount: Int = 0
	private var hitTimer: Timer?

	/// Initialiser
	public init(key: NSEvent.ModifierFlags, double: Bool = false, target: AnyObject, selector: Selector) {
		self.target = target
		self.selector = selector
		if let monitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
			guard key == event.modifierFlags.intersection(.deviceIndependentFlagsMask) else {
				return
			}
			if double {
				self?.hitCount += 1
				self?.hitTimer?.invalidate()
				let timer = Timer.scheduledTimer(withTimeInterval: 0.6, repeats: false, block: { [weak self] _ in
					defer {
						self?.hitCount = 0
						self?.hitTimer = nil
					}
					guard self?.hitCount == 2 else {
						return
					}
					_ = self?.target?.perform(self?.selector)
				})
				timer.tolerance = 0.05
				self?.hitTimer = timer
			} else {
				_ = self?.target?.perform(self?.selector)
			}
		}) {
			eventMonitors.append(monitor)
		}
	}

	/// Initialiser
	public init(keyEquivalent: String, modifiers: NSEvent.ModifierFlags, target: AnyObject, selector: Selector) {
		self.target = target
		self.selector = selector
		let normalizedKey = keyEquivalent.lowercased()
		let normalizedModifiers = modifiers.intersection(.deviceIndependentFlagsMask)
		if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
			self?.performIfNeeded(event: event, keyEquivalent: normalizedKey, modifiers: normalizedModifiers)
		}) {
			eventMonitors.append(globalMonitor)
		}
		if let localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
			guard self?.performIfNeeded(event: event, keyEquivalent: normalizedKey, modifiers: normalizedModifiers) == true else {
				return event
			}
			return nil
		}) {
			eventMonitors.append(localMonitor)
		}
	}

	deinit {
		hitTimer?.invalidate()
		eventMonitors.forEach { eventMonitor in
			NSEvent.removeMonitor(eventMonitor)
		}
	}

	@discardableResult
	private func performIfNeeded(event: NSEvent, keyEquivalent: String, modifiers: NSEvent.ModifierFlags) -> Bool {
		guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers,
			  let selector = selector,
			  event.charactersIgnoringModifiers?.lowercased() == keyEquivalent else {
			return false
		}
		_ = target?.perform(selector)
		return true
	}

}
