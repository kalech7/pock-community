import CoreAudio
import Foundation

internal struct AudioOutputDevice: Equatable {
	let id: AudioDeviceID
	let name: String
	let symbolName: String
	let uid: String
}

internal struct AudioOutputSnapshot: Equatable {
	let devices: [AudioOutputDevice]
	let defaultDeviceID: AudioDeviceID
}

internal final class AudioOutputService {
	private enum Failure: Error {
		case deviceUnavailable
		case coreAudio(OSStatus)
	}

	private static let systemObject = AudioObjectID(kAudioObjectSystemObject)
	private static let observedSelectors = [kAudioHardwarePropertyDevices, kAudioHardwarePropertyDefaultOutputDevice]
	private var listener: AudioObjectPropertyListenerBlock?
	private var listeningSelectors: [AudioObjectPropertySelector] = []

	deinit {
		stopObserving()
	}

	func snapshot() throws -> AudioOutputSnapshot {
		let ids = try Self.deviceIDs()
		let devices = ids.compactMap(Self.outputDevice).sorted { first, second in
			let order = first.name.localizedStandardCompare(second.name)
			return order == .orderedSame ? first.id < second.id : order == .orderedAscending
		}
		let selected = try Self.integerProperty(kAudioHardwarePropertyDefaultOutputDevice, on: Self.systemObject)
		return AudioOutputSnapshot(devices: devices, defaultDeviceID: selected)
	}

	func select(_ device: AudioOutputDevice) throws {
		guard Self.isAvailableOutput(device.id),
			  Self.stringProperty(kAudioDevicePropertyDeviceUID, on: device.id) == device.uid else {
			throw Failure.deviceUnavailable
		}
		var id = device.id
		var address = Self.propertyAddress(kAudioHardwarePropertyDefaultOutputDevice)
		// System alert sounds have a separate output property and retain their configured route.
		let status = AudioObjectSetPropertyData(Self.systemObject, &address, 0, nil,
											   UInt32(MemoryLayout<AudioDeviceID>.size), &id)
		guard status == noErr else { throw Failure.coreAudio(status) }
	}

	func startObserving(_ didChange: @escaping () -> Void) {
		stopObserving()
		let listener: AudioObjectPropertyListenerBlock = { _, _ in didChange() }
		self.listener = listener
		for selector in Self.observedSelectors {
			var address = Self.propertyAddress(selector)
			if AudioObjectAddPropertyListenerBlock(Self.systemObject, &address, .main, listener) == noErr {
				listeningSelectors.append(selector)
			}
		}
	}

	func stopObserving() {
		guard let listener = listener else { return }
		for selector in listeningSelectors {
			var address = Self.propertyAddress(selector)
			AudioObjectRemovePropertyListenerBlock(Self.systemObject, &address, .main, listener)
		}
		listeningSelectors.removeAll()
		self.listener = nil
	}

	private static func deviceIDs() throws -> [AudioDeviceID] {
		var address = propertyAddress(kAudioHardwarePropertyDevices)
		var byteCount: UInt32 = 0
		let stride = MemoryLayout<AudioDeviceID>.stride
		// A device can connect between the size query and the read.
		for _ in 0..<2 {
			let sizeStatus = AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &byteCount)
			guard sizeStatus == noErr else { throw Failure.coreAudio(sizeStatus) }
			guard byteCount != 0 else { return [] }
			guard Int(byteCount) % stride == 0 else { throw Failure.coreAudio(kAudioHardwareBadPropertySizeError) }
			var ids = [AudioDeviceID](repeating: 0, count: Int(byteCount) / stride)
			let status = ids.withUnsafeMutableBytes { buffer -> OSStatus in
				guard let data = buffer.baseAddress else { return kAudioHardwareBadPropertySizeError }
				return AudioObjectGetPropertyData(systemObject, &address, 0, nil, &byteCount, data)
			}
			if status == noErr { return Array(ids.prefix(Int(byteCount) / stride)) }
			guard status == kAudioHardwareBadPropertySizeError else { throw Failure.coreAudio(status) }
		}
		throw Failure.coreAudio(kAudioHardwareBadPropertySizeError)
	}

	private static func outputDevice(_ id: AudioDeviceID) -> AudioOutputDevice? {
		guard isAvailableOutput(id),
			  let name = stringProperty(kAudioObjectPropertyName, on: id),
			  let uid = stringProperty(kAudioDevicePropertyDeviceUID, on: id) else { return nil }
		let transport = try? integerProperty(kAudioDevicePropertyTransportType, on: id)
		let model = stringProperty(kAudioObjectPropertyModelName, on: id)
		return AudioOutputDevice(id: id, name: name, symbolName: symbolName(name, model: model, transport: transport), uid: uid)
	}

	private static func isAvailableOutput(_ id: AudioDeviceID) -> Bool {
		guard (try? integerProperty(kAudioDevicePropertyDeviceIsAlive, on: id)) == 1,
			  (try? integerProperty(kAudioDevicePropertyDeviceCanBeDefaultDevice,
									on: id, scope: kAudioDevicePropertyScopeOutput)) == 1 else { return false }
		var streams = propertyAddress(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeOutput)
		var byteCount: UInt32 = 0
		return AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &byteCount) == noErr && byteCount > 0
	}

	private static func symbolName(_ name: String, model: String?, transport: UInt32?) -> String {
		switch transport {
		case kAudioDeviceTransportTypeBluetooth, kAudioDeviceTransportTypeBluetoothLE:
			let description = [name, model].compactMap { $0 }.joined(separator: " ").lowercased()
			if description.contains("airpods max") { return "airpodsmax" }
			if description.contains("airpods pro") { return "airpodspro" }
			return description.contains("airpods") ? "airpods" : "headphones"
		case kAudioDeviceTransportTypeHDMI, kAudioDeviceTransportTypeDisplayPort:
			return "display"
		case kAudioDeviceTransportTypeAirPlay:
			return "airplay.audio"
		case kAudioDeviceTransportTypeUSB:
			return "hifispeaker"
		default:
			return "speaker.wave.2"
		}
	}

	private static func integerProperty(_ selector: AudioObjectPropertySelector, on object: AudioObjectID,
										scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) throws -> UInt32 {
		var address = propertyAddress(selector, scope: scope)
		var value: UInt32 = 0
		var size = UInt32(MemoryLayout<UInt32>.size)
		let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
		guard status == noErr else { throw Failure.coreAudio(status) }
		return value
	}

	private static func stringProperty(_ selector: AudioObjectPropertySelector, on object: AudioObjectID) -> String? {
		var address = propertyAddress(selector)
		var value: Unmanaged<CFString>?
		var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
		let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value)
		guard status == noErr else { return nil }
		return value?.takeRetainedValue() as String?
	}

	private static func propertyAddress(_ selector: AudioObjectPropertySelector,
										scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
		AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
	}
}
