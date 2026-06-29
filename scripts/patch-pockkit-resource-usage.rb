#!/usr/bin/env ruby
# frozen_string_literal: true

require "pathname"

root = Pathname.new(ARGV.fetch(0, Dir.pwd)).expand_path
pockkit = root / "Pods" / "PockKit" / "PockKit"

def replace_once(path, before, after)
  text = path.read
  return if text.include?(after)

  unless text.include?(before)
    return
  end

  path.chmod(path.stat.mode | 0o200)
  path.write(text.sub(before, after))
end

def replace_pattern(path, pattern, after, marker)
  text = path.read
  return if marker && text.include?(marker)

  patched = text.sub(pattern, after)
  if patched == text
    warn "Skipping #{path}: expected source pattern was not found."
    return
  end

  path.chmod(path.stat.mode | 0o200)
  path.write(patched)
end

scrolling_text = pockkit / "3rd" / "ScrollingTextView.swift"
mouse_controller = pockkit / "Sources" / "Controllers" / "PKTouchBarMouseController.swift"
base_controller = pockkit / "Sources" / "Protocols" / "PKScreenEdgeController" / "PKScreenEdgeBaseController.swift"

if scrolling_text.exist?
  replace_once(scrolling_text, "    private weak var timer: Timer?\n", "    private var timer: Timer?\n")

  replace_once(
    scrolling_text,
    <<~'SWIFT',
        open func set(speed: Double) {
            setSpeed(newInterval: speed)
        }
    }
    SWIFT
    <<~'SWIFT'
        open func set(speed: Double) {
            setSpeed(newInterval: speed)
        }

        deinit {
            clearTimer()
        }
    }
    SWIFT
  )

  replace_pattern(
    scrolling_text,
    /if timer == nil, timeInterval > 0\.0, text != nil \{\n\s+if #available\(OSX 10\.12, \*\) \{\n\s+timer = Timer\.scheduledTimer\(timeInterval: newInterval, target: self, selector: #selector\(update\(_:\)\), userInfo: nil, repeats: true\)\n\s+guard let timer = timer else \{ return \}\n\s+RunLoop\.main\.add\(timer, forMode: RunLoop\.Mode\.common\)\n\s+\} else \{/m,
    <<~'SWIFT'.rstrip,
    if timer == nil, timeInterval > 0.0, text != nil, canScroll {
                if #available(OSX 10.12, *) {
                    let timer = Timer(timeInterval: newInterval, target: self, selector: #selector(update(_:)), userInfo: nil, repeats: true)
                    timer.tolerance = min(max(newInterval * 0.25, 0.01), 0.1)
                    RunLoop.main.add(timer, forMode: RunLoop.Mode.common)
                    self.timer = timer
                } else {
    SWIFT
    "timer.tolerance = min(max(newInterval * 0.25, 0.01), 0.1)"
  )

  replace_once(
    scrolling_text,
    "private extension ScrollingTextView {\n    func setSpeed(newInterval: TimeInterval) {\n",
    "private extension ScrollingTextView {\n    var canScroll: Bool {\n        return window != nil || superview != nil\n    }\n\n    func setSpeed(newInterval: TimeInterval) {\n"
  )

  replace_pattern(
    scrolling_text,
    /if #available\(OSX 10\.12, \*\), isDelayed \{\n\s+timer = Timer\.scheduledTimer\(withTimeInterval: delay, repeats: false, block: \{ \[weak self\] timer in\n\s+self\?\.setSpeed\(newInterval: speed\)\n\s+\}\)\n\s+\} else \{/m,
    <<~'SWIFT'.rstrip,
    if #available(OSX 10.12, *), isDelayed {
                    let timer = Timer(timeInterval: delay, repeats: false, block: { [weak self] timer in
                        self?.setSpeed(newInterval: speed)
                    })
                    timer.tolerance = min(max(delay * 0.1, 0.05), 1.0)
                    RunLoop.main.add(timer, forMode: RunLoop.Mode.common)
                    self.timer = timer
                } else {
    SWIFT
    "timer.tolerance = min(max(delay * 0.1, 0.05), 1.0)"
  )

  replace_once(
    scrolling_text,
    <<~'SWIFT',
            if timer == nil, timeInterval > 0.0, text != nil {
                if #available(OSX 10.12, *) {
                    timer = Timer.scheduledTimer(timeInterval: newInterval, target: self, selector: #selector(update(_:)), userInfo: nil, repeats: true)

                    guard let timer = timer else { return }
                    RunLoop.main.add(timer, forMode: RunLoop.Mode.common)
                } else {
    SWIFT
    <<~'SWIFT'
            if timer == nil, timeInterval > 0.0, text != nil, canScroll {
                if #available(OSX 10.12, *) {
                    let timer = Timer(timeInterval: newInterval, target: self, selector: #selector(update(_:)), userInfo: nil, repeats: true)
                    timer.tolerance = min(max(newInterval * 0.25, 0.01), 0.1)
                    RunLoop.main.add(timer, forMode: RunLoop.Mode.common)
                    self.timer = timer
                } else {
    SWIFT
  )

  replace_pattern(
    scrolling_text,
    /func update\(_ sender: Timer\) \{\n\s+point\.x = point\.x - 1\n\s+setNeedsDisplay\(NSRect\(x: 0, y: 0, width: frame\.width, height: frame\.height\)\)\n\s+if Int\(point\.x\) == 0 \{\n\s+let shouldStop = numberOfLoop > 0 && loopCount == numberOfLoop\n\s+#if DEBUG\n\s+NSLog\("Loop count: \\?\(loopCount\)\. Should stop: \\?\(shouldStop\)"\)\n\s+#endif\n\s+if shouldStop \{\n\s+point\.x = 0\n\s+setSpeed\(newInterval: 0\)\n\s+setNeedsDisplay\(NSRect\(x: 0, y: 0, width: frame\.width, height: frame\.height\)\)\n\s+\}\n\s+loopCount \+= 1\n\s+\}\n\s+\}/m,
    <<~'SWIFT'.rstrip,
    func update(_ sender: Timer) {
            point.x = point.x - 1
            if point.x <= -(stringSize.width + spacing) {
                point.x += stringSize.width + spacing
                loopCount += 1
                let shouldStop = numberOfLoop > 0 && loopCount >= numberOfLoop
                #if DEBUG
                NSLog("Loop count: \\(loopCount). Should stop: \\(shouldStop)")
                #endif
                if shouldStop {
                    point.x = 0
                    setSpeed(newInterval: 0)
                    setNeedsDisplay(NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
                    return
                }
            }
            setNeedsDisplay(NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        }
    SWIFT
    "point.x <= -(stringSize.width + spacing)"
  )

  replace_once(
    scrolling_text,
    "    func updateTraits() {\n        clearTimer()\n        \n",
    "    func updateTraits() {\n        clearTimer()\n        guard canScroll else { return }\n        \n"
  )

  replace_once(
    scrolling_text,
    <<~'SWIFT',
                if #available(OSX 10.12, *), isDelayed {
                    timer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false, block: { [weak self] timer in
                        self?.setSpeed(newInterval: speed)
                    })
                } else {
    SWIFT
    <<~'SWIFT'
                if #available(OSX 10.12, *), isDelayed {
                    let timer = Timer(timeInterval: delay, repeats: false, block: { [weak self] timer in
                        self?.setSpeed(newInterval: speed)
                    })
                    timer.tolerance = min(max(delay * 0.1, 0.05), 1.0)
                    RunLoop.main.add(timer, forMode: RunLoop.Mode.common)
                    self.timer = timer
                } else {
    SWIFT
  )

  replace_once(
    scrolling_text,
    <<~'SWIFT',
        func update(_ sender: Timer) {
            point.x = point.x - 1
            setNeedsDisplay(NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
            if Int(point.x) == 0 {
                let shouldStop = numberOfLoop > 0 && loopCount == numberOfLoop
                #if DEBUG
                NSLog("Loop count: \\(loopCount). Should stop: \\(shouldStop)")
                #endif
                if shouldStop {
                    point.x = 0
                    setSpeed(newInterval: 0)
                    setNeedsDisplay(NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
                }
                loopCount += 1
            }
        }
    SWIFT
    <<~'SWIFT'
        func update(_ sender: Timer) {
            point.x = point.x - 1
            if point.x <= -(stringSize.width + spacing) {
                point.x += stringSize.width + spacing
                loopCount += 1
                let shouldStop = numberOfLoop > 0 && loopCount >= numberOfLoop
                #if DEBUG
                NSLog("Loop count: \\(loopCount). Should stop: \\(shouldStop)")
                #endif
                if shouldStop {
                    point.x = 0
                    setSpeed(newInterval: 0)
                    setNeedsDisplay(NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
                    return
                }
            }
            setNeedsDisplay(NSRect(x: 0, y: 0, width: frame.width, height: frame.height))
        }
    SWIFT
  )

  replace_once(
    scrolling_text,
    "    override open func draw(_ dirtyRect: NSRect) {\n        if point.x + stringSize.width < 0 {\n            point.x += stringSize.width + spacing\n        }\n        \n",
    "    override open func draw(_ dirtyRect: NSRect) {\n        "
  )

  replace_once(
    scrolling_text,
    <<~'SWIFT',
        override open func layout() {
            super.layout()
            point.y = (frame.height - stringSize.height) / 2
        }
    }
    SWIFT
    <<~'SWIFT'
        override open func layout() {
            super.layout()
            point.y = (frame.height - stringSize.height) / 2
        }

        override open func viewDidMoveToSuperview() {
            super.viewDidMoveToSuperview()
            updateTraits()
        }

        override open func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            updateTraits()
        }
    }
    SWIFT
  )
end

[mouse_controller, base_controller].each do |path|
  next unless path.exist?

  replace_once(
    path,
    "	/// Dragging info view\n	public var draggingInfoView: PKDraggingInfoView?\n",
    "	/// Dragging info view\n	public var draggingInfoView: PKDraggingInfoView?\n\n\tprivate var pendingDraggingInfoUpdate: DispatchWorkItem?\n"
  )

  replace_once(
    path,
    "	open func showDraggingInfo(_ info: NSDraggingInfo?, filepath: String?) {\n\t\tdraggingInfoView?.removeFromSuperview()\n",
    "	open func showDraggingInfo(_ info: NSDraggingInfo?, filepath: String?) {\n\t\tpendingDraggingInfoUpdate?.cancel()\n\t\tpendingDraggingInfoUpdate = nil\n\t\tdraggingInfoView?.removeFromSuperview()\n"
  )

  replace_once(
    path,
    <<~'SWIFT',
            DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.1275 : 0), execute: {
                view.frame.origin = NSPoint(x: location.x - view.frame.width + 8, y: location.y)
            })
    SWIFT
    <<~'SWIFT'
            pendingDraggingInfoUpdate?.cancel()
            let workItem = DispatchWorkItem { [weak view] in
                guard let view = view else {
                    return
                }
                view.frame.origin = NSPoint(x: location.x - view.frame.width + 8, y: location.y)
            }
            pendingDraggingInfoUpdate = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.1275 : 0), execute: workItem)
    SWIFT
  )

  replace_pattern(
    path,
    /DispatchQueue\.main\.asyncAfter\(deadline: \.now\(\) \+ \(animated \? 0\.1275 : 0\), execute: \{\n\s+view\.frame\.origin = NSPoint\(x: location\.x - view\.frame\.width \+ 8, y: location\.y\)\n\s+\}\)/m,
    <<~'SWIFT'.rstrip,
    pendingDraggingInfoUpdate?.cancel()
            let workItem = DispatchWorkItem { [weak view] in
                guard let view = view else {
                    return
                }
                view.frame.origin = NSPoint(x: location.x - view.frame.width + 8, y: location.y)
            }
            pendingDraggingInfoUpdate = workItem
            DispatchQueue.main.asyncAfter(deadline: .now() + (animated ? 0.1275 : 0), execute: workItem)
    SWIFT
    "let workItem = DispatchWorkItem { [weak view] in"
  )
end
