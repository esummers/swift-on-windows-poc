import Foundation

/**

 This file contains a "basic" CascableCore API that wraps the regular one. It's job is to let us use CascableCore via
 Swift's C++ interop, and exists due to limitations in that interop. In particular:

 - Protocols aren't exposed to C++.

 - Enum cases with more than one associated value disallow that enum to be exposed to C++.

 - Closures/callbacks aren't exposed to C++. This is particulary troublesome since we use this pattern a lot for
   observation and live view streaming.

 - Types from other modules don't appear to be exposed to C++. For instance, when compiling the
   CascableCoreSimulatedCamera module, methods/properties exposing types from the CascableCore module (Camera, etc)
   are omitted from CascableCoreSimulatedCamera's C++ interop header, even though those types are public and accessible.

 Most/all of these can be worked around right now with varying levels of complexity (callbacks being the most complex),
 but this proof-of-concept project is just that - a proof-of-concept. Over time, we hope that the C++ interop will
 improve *and* we get time to flesh this project out further. In the meantime, here we are.

 */

import CascableCore
import CascableCoreSimulatedCamera

// MARK: Configuration and Discovery

/// Configuration values for simulated cameras.
public struct BasicSimulatedCameraConfiguration {

    /// The simulated camera's manufacturer name. The default value is `Cascable`.
    public var manufacturer: String

    /// The simulated camera's model name. The default value is `Simulated Camera`.
    public var model: String

    /// The simulated camera's identifier, which will be used for serial numbers, authentication identifiers, etc.
    /// The default value is the plugin's identifier (`se.cascable.CascableCore.plugin.simulated-camera`).
    public var identifier: String

    /// Apply the settings for newly-discovered simulated cameras. Changes won't be applied to simulated cameras
    /// that have already been discovered or connected to (i.e., you should apply your configuration before starting
    /// camera discovery).
    public func apply() {
        var config = SimulatedCameraConfiguration.default
        config.manufacturer = manufacturer
        config.model = model
        config.identifier = identifier
        config.connectionAuthentication = .none
        config.apply()
    }
}

/// Discovering cameras.
public class BasicCameraDiscovery {

    /// The shared camera discovery instance.
    public static let sharedInstance: BasicCameraDiscovery = BasicCameraDiscovery()

    /// Returns `true` if camera discovery is running, otherwise `false`.
    public private(set) var discoveryRunning: Bool = false

    /// Returns an array of visible cameras.
    public var visibleCameras: [BasicCamera] {
        if let currentSimulatedCamera { return [currentSimulatedCamera] }
        return []
    }

    /// Start camera discovery.
    ///
    /// - Parameter clientName: The client (i.e., app) name. Will be displayed on some cameras during pairing.
    public func startDiscovery(clientName: String) {
        guard !discoveryRunning else { return }
        discoveryRunning = true
        SimulatedCameraDiscovery.shared.delegate = self
        SimulatedCameraDiscovery.shared.startDiscovery(in: .networkAndUSB, clientName: clientName)
    }

    /// Stop camera discovery. This is recommended once you have a camera to connect to in order to save system
    /// resources/battery life.
    public func stopDiscovery() {
        guard discoveryRunning else { return }
        discoveryRunning = false
        SimulatedCameraDiscovery.shared.stopDiscovery()
        currentSimulatedCamera = nil
    }

    // Internal

    private init() {}
    internal var currentSimulatedCamera: BasicCamera? = nil
}

extension BasicCameraDiscovery: CameraDiscoveryProviderDelegate {
    public func cameraDiscoveryProvider(_ provider: CameraDiscoveryProvider, didDiscover camera: Camera) {
        currentSimulatedCamera = BasicCamera(wrapping: camera)
    }

    public func cameraDiscoveryProvider(_ provider: CameraDiscoveryProvider, didLoseSightOf camera: Camera) {
        currentSimulatedCamera = nil
    }
}

// MARK: - Camera

public class BasicCamera: Equatable {

    public static func == (lhs: BasicCamera, rhs: BasicCamera) -> Bool {
        return lhs.wrappedCamera.friendlyIdentifier == rhs.wrappedCamera.friendlyIdentifier
    }

    internal let wrappedCamera: Camera
    internal init(wrapping camera: Camera) { wrappedCamera = camera }

    // Basics

    /// Returns the camera's "friendly" identifier, typically the serial number.
    public var friendlyIdentifier: String? { return wrappedCamera.friendlyIdentifier }

    /// Returns `YES` if the instance is connected to a physical camera, otherwise `NO`.
    ///
    /// The `connectionState` property returns more fine-grained detail about the camera's state.
    /// The value of this property is equivalent to `(connectionState == CBLCameraConnectionStateConnected)`.
    public var connected: Bool { return wrappedCamera.connected }

    /// Returns an object representing information about the device. Will be `nil` if not connected.
    public var deviceInfo: BasicDeviceInfo? { return BasicDeviceInfo(wrapping: wrappedCamera.deviceInfo) }

    /// Returns the friendly, user-set name of the camera, if available. May be `nil` until the camera is connected.
    public var friendlyDisplayName: String? { return wrappedCamera.friendlyDisplayName }

    /// Attempt to connect to the device.
    public func connect() {
        wrappedCamera.connect(authenticationRequestCallback: { context in
            print("WARNING: Camera wants auth, and the basic API doesn't support that yet. Cancelling.")
            context.submitCancellation()
        }, authenticationResolvedCallback: {

        }, completionCallback: { error, warnings in
            if let error { print("Connection failed: \(error)") }
            if let warnings, !warnings.isEmpty { print("Connection got warnings: \(warnings)") }
        })
    }

    /// Attempt to disconnect from the device.
    public func disconnect() {
        wrappedCamera.disconnect({ error in
            if let error { print("Disconnection failed: \(error)") }
        }, callbackQueue: .main)
    }

    // TODO: Functionality and categories
    // TODO: Live view
    // TODO: Filesystem
    // TODO: Focus and shutter
    // TODO: Camera-initiated transfer
    // TODO: Video recording

    // Camera Properties

    /// The known property identifiers.
    public var knownPropertyIdentifiers: [BasicPropertyIdentifier] {
        return wrappedCamera.knownPropertyIdentifiers.compactMap({ BasicPropertyIdentifier(rawValue: $0.uintValue) })
    }

    /// Returns a property object for the given identifier. If the property is currently unknown, returns an object
    /// with `currentValue`, `validSettableValues`, etc set to `nil`.
    ///
    /// The returned object is owned by the receiver, and the same object will be returned on subsequent calls to this
    /// method with the same identifier.
    ///
    /// @param identifier The property identifier to get a property object for.
    public func property(with identifier: BasicPropertyIdentifier) -> BasicCameraProperty {
        if let property = propertyStorage[identifier] { return property }
        let property = wrappedCamera.property(with: PropertyIdentifier(rawValue: identifier.rawValue)!)
        let wrappedProperty = BasicCameraProperty(wrapping: property, on: self)
        propertyStorage[identifier] = wrappedProperty
        return wrappedProperty
    }

    private var propertyStorage: [BasicPropertyIdentifier: BasicCameraProperty] = [:]

}

// MARK: - Camera Properties

// (This wrapper is particularly yucky - it's just a copypaste of the CascableCore declaration)
/// Property identifiers.
public enum BasicPropertyIdentifier: UInt {
    /// The camera's ISO speed setting.
    case isoSpeed
    /// The camera's shutter speed setting.
    case shutterSpeed
    /// The camera's aperture setting.
    case aperture
    /// The camera's exposure compensation setting.
    case exposureCompensation
    /// The camera's battery level. Common values will be of type `CBLPropertyCommonValueBatteryLevel`.
    case batteryLevel
    /// The camera's power source. Common values will be of type `CBLPropertyCommonValuePowerSource`.
    case powerSource
    /// The camera's autofocus system setting (area, face detection, etc). Common values will be of type `CBLPropertyCommonValueAFSystem`.
    case afSystem
    /// The camera's focus mode setting (manual, single, continuous, etc). Common values will be of type `CBLPropertyCommonValueFocusMode`.
    case focusMode
    /// The camera's drive mode setting (single, continuous, timer, etc). Common values will be of type `CBLPropertyCommonValueDriveMode`.
    case driveMode
    /// The camera's autoexposure mode setting (M, P, Tv, Av, etc). Common values will be of type `CBLPropertyCommonValueAutoExposureMode`.
    case autoExposureMode
    /// The camera's in-camera bracketing setting. Common values will be of type `CBLPropertyCommonValueBoolean`.
    case inCameraBracketingEnabled
    /// The camera's mirror lockup enabled setting. Common values will be of type `CBLPropertyCommonValueBoolean`.
    case mirrorLockupEnabled
    /// The camera's current mirror lockup stage. Common values will be of type `CBLPropertyCommonValueMirrorLockupStage`.
    case mirrorLockupStage
    /// Whether the camera is current executing depth-of-field preview. Common values will be of type `CBLPropertyCommonValueBoolean`.
    case dofPreviewEnabled
    /// The camera's reading of how many shots are available on its storage card(s). The common value will be a freeform integer containing the reading.
    case shotsAvailable
    /// The camera's lens status.
    case lensStatus
    /// The camera's "Color Tone" setting.
    case colorTone
    /// The camera's "Art Filter" setting.
    case artFilter
    /// Whether the camera is currently using digital zoom. Common values will be of type `CBLPropertyCommonValueBoolean`.
    case digitalZoom
    /// The camera's white balance setting. Common values will be of type `CBLPropertyCommonValueWhiteBalance`.
    case whiteBalance
    /// The camera's noise reduction setting.
    case noiseReduction
    /// The camera's image quality setting.
    case imageQuality
    /// The camera's light meter status. Common values will be of type `CBLPropertyCommonValueLightMeterStatus`.
    case lightMeterStatus
    /// The camera's current light meter reading. Common values will be of type CBLExposureCompensationValue.
    case lightMeterReading
    /// The camera's exposure metering mode setting.
    case exposureMeteringMode
    /// Whether the camera is ready to take a shot. Common values will be of type `CBLPropertyCommonValueBoolean`.
    case readyForCapture
    /// The target destination for images when connected to a host like CascableCore. Common values will be of type `CBLPropertyCommonValueImageDestination`.
    case imageDestination
    /// The camera's video recording format.
    case videoRecordingFormat
    /// The camera's live view zoom level.
    case liveViewZoomLevel
    case max

    // This needs to be NSNotFound, or UInt.max
    case unknown = 18446744073709551615
}

/// An object representing the values for a property on the camera.
public class BasicCameraProperty {

    internal let wrappedProperty: CameraProperty
    internal weak var parentCamera: BasicCamera?
    private var observerToken: CameraPropertyObservation!

    internal init(wrapping property: CameraProperty, on camera: BasicCamera) {
        wrappedProperty = property
        parentCamera = camera
        updateValues()
        observerToken = property.addObserver { [weak self] _, _ in
            self?.updateValues()
        }
    }

    deinit {
        wrappedProperty.removeObserver(observerToken)
    }

    private func updateValues() {
        if let value = wrappedProperty.currentValue {
            currentValue = BasicPropertyValue(wrapping: value)
        } else {
            currentValue = nil
        }
        if let pending = wrappedProperty.pendingValue {
            pendingValue = BasicPropertyValue(wrapping: pending)
        } else {
            pendingValue = nil
        }
        if let settable = wrappedProperty.validSettableValues {
            validSettableValues = settable.map({ BasicPropertyValue(wrapping: $0) })
        } else {
            validSettableValues = nil
        }
    }

    // API

    /// The property's identifier.
    public var identifier: BasicPropertyIdentifier {
        return BasicPropertyIdentifier(rawValue: wrappedProperty.identifier.rawValue)!
    }

    /// The property's owning camera.
    public var camera: BasicCamera? { return parentCamera }

    /// The property's display name.
    public var localizedDisplayName: String? { return wrappedProperty.localizedDisplayName }

    /// The current value of the property.
    public private(set) var currentValue: BasicPropertyValue? = nil

    /// Returns the value currently in the process of being set, if any. Only valid
    /// if the property's `valueSetType` is `CBLPropertyValueSetTypeEnumeration`.
    public private(set) var pendingValue: BasicPropertyValue? = nil

    /// The values that are considered valid for this property. Only valid if the
    /// property's `valueSetType` is `CBLPropertyValueSetTypeEnumeration`.
    public private(set) var validSettableValues: [BasicPropertyValue]? = nil

    /// Attempt to set a new value for the property. The value must be in the `validSettableValues` property. As such,
    /// this method is only useable if the property's `valueSetType` contains `CBLPropertyValueSetTypeEnumeration`.
    public func setValue(_ newValue: BasicPropertyValue) {
        guard wrappedProperty.valueSetType == .enumeration else {
            print("Asked to set value on a stepped property! Nothing will happen.")
            return
        }

        wrappedProperty.setValue(newValue.wrappedValue, completionQueue: .main) { error in
            if let error { print("Setting value of property failed: \(error)") }
        }
    }
}

/// A property value. This could either be the current value of a property, or something in the list of values that can be set.
public class BasicPropertyValue: Equatable {

    public static func == (lhs: BasicPropertyValue, rhs: BasicPropertyValue) -> Bool {
        return lhs.wrappedValue.isEqual(rhs.wrappedValue)
    }

    internal let wrappedValue: PropertyValue
    internal init(wrapping value: PropertyValue) { wrappedValue = value }

    /// A localized display value for the value. May be `nil` if the value is unknown to CascableCore and
    /// a display value is not provided by the camera.
    public var localizedDisplayValue: String? { return wrappedValue.localizedDisplayValue }

    /// A string value for the value. Will always return *something*, but the quality is not guaranteed — particularly
    /// if the value is unknown to CascableCore and a display value is not provided by the camera.
    public var stringValue: String { return wrappedValue.stringValue }
}

// MARK: - Metadata and Misc

/// Information about a connected camera.
public class BasicDeviceInfo {
    internal let wrappedValue: DeviceInfo
    internal init?(wrapping value: DeviceInfo?) {
        guard let value else { return nil }
        wrappedValue = value
    }

    /// Returns the device's manufacturer (for instance, 'Canon').
    public var manufacturer: String? { return wrappedValue.manufacturer }

    /// Returns the device's model (for instance, 'EOS M3').
    public var model: String? { return wrappedValue.model }

    /// Returns the device's software version (for instance, 'V1.01').
    ///
    /// @note This will sometimes differ from the user-visible software version the camera displays in its own UI.
    public var version: String? { return wrappedValue.version }

    /// Returns the device's serial number.
    public var serialNumber: String? { return wrappedValue.serialNumber }
}