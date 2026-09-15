//
//  Types.swift
//  Adapted from exelban/stats (Kit/types.swift, Kit/helpers.swift) — MIT License.
//  See Vendor/STATS-LICENSE. Trimmed to the types this app needs.
//

import Cocoa

// MARK: - KeyValue

public protocol KeyValue_p {
    var key: String { get }
    var value: String { get }
}

public struct KeyValue_t: KeyValue_p {
    public let key: String
    public let value: String
    public let additional: Any?

    public init(key: String, value: String, additional: Any? = nil) {
        self.key = key
        self.value = value
        self.additional = additional
    }
}

// MARK: - Chart value types

public struct DoubleValue {
    public var ts: Date = Date()
    public let value: Double

    public init(_ value: Double = 0) {
        self.value = value
    }
}

public struct ColorValue: Equatable {
    public var ts: Date = Date()
    public let value: Double
    public var color: NSColor?

    public init(_ value: Double, color: NSColor? = nil) {
        self.value = value
        self.color = color
    }

    public static func ==(lhs: ColorValue, rhs: ColorValue) -> Bool {
        return lhs.value == rhs.value
    }
}

public enum DataSizeBase: String {
    case bit
    case byte
}

public struct Scale: KeyValue_p, Equatable {
    public let key: String
    public let value: String

    public static func == (lhs: Scale, rhs: Scale) -> Bool {
        return lhs.key == rhs.key
    }
}

extension Scale: CaseIterable {
    public static var none: Scale { return Scale(key: "none", value: "None") }
    public static var linear: Scale { return Scale(key: "linear", value: "Linear") }
    public static var square: Scale { return Scale(key: "square", value: "Square") }
    public static var cube: Scale { return Scale(key: "cube", value: "Cube") }
    public static var logarithmic: Scale { return Scale(key: "logarithmic", value: "Logarithmic") }
    public static var fixed: Scale { return Scale(key: "fixed", value: "Fixed scale") }

    public static var allCases: [Scale] {
        return [.none, .linear, .square, .cube, .logarithmic, .fixed]
    }

    public static func fromString(_ key: String, defaultValue: Scale = .linear) -> Scale {
        return Scale.allCases.first{ $0.key == key } ?? defaultValue
    }
}

// MARK: - Network speed units

public let NetworkSpeedUnitAuto = "auto"

public func networkSpeedUnit(from key: String) -> KeyValue_t {
    let units: [KeyValue_t] = [
        KeyValue_t(key: NetworkSpeedUnitAuto, value: "Auto"),
        KeyValue_t(key: "KB", value: "KB/Kb"),
        KeyValue_t(key: "MB", value: "MB/Mb"),
        KeyValue_t(key: "GB", value: "GB/Gb"),
        KeyValue_t(key: "TB", value: "TB/Tb")
    ]
    return units.first(where: { $0.key.lowercased() == key.lowercased() }) ?? units[0]
}

public func networkSpeedSizeUnit(from key: String) -> SizeUnit? {
    let unit = networkSpeedUnit(from: key)
    return unit.key == NetworkSpeedUnitAuto ? nil : SizeUnit.fromString(unit.key)
}

public func networkSpeedPrefix(from key: String) -> String? {
    let unit = networkSpeedUnit(from: key)
    return unit.key == NetworkSpeedUnitAuto ? nil : String(unit.key.prefix(1))
}

public struct SizeUnit: KeyValue_p, Equatable {
    public let key: String
    public let value: String

    public static func == (lhs: SizeUnit, rhs: SizeUnit) -> Bool {
        return lhs.key == rhs.key
    }
}

extension SizeUnit: CaseIterable {
    public static var byte: SizeUnit { return SizeUnit(key: "byte", value: "Bytes") }
    public static var KB: SizeUnit { return SizeUnit(key: "KB", value: "KB") }
    public static var MB: SizeUnit { return SizeUnit(key: "MB", value: "MB") }
    public static var GB: SizeUnit { return SizeUnit(key: "GB", value: "GB") }
    public static var TB: SizeUnit { return SizeUnit(key: "TB", value: "TB") }

    public static var allCases: [SizeUnit] {
        [.byte, .KB, .MB, .GB, .TB]
    }

    public static func fromString(_ key: String, defaultValue: SizeUnit = .byte) -> SizeUnit {
        return SizeUnit.allCases.first{ $0.key == key } ?? defaultValue
    }
}

// MARK: - Byte formatting (adapted from stats Kit/helpers.swift Units)

public struct Units {
    public let bytes: Int64

    public init(bytes: Int64) {
        self.bytes = bytes
    }

    public var kilobytes: Double { return Double(bytes) / 1_000 }
    public var megabytes: Double { return kilobytes / 1_000 }
    public var gigabytes: Double { return megabytes / 1_000 }
    public var terabytes: Double { return gigabytes / 1_000 }

    public func getReadableTuple(base: DataSizeBase = .byte, unit: String = NetworkSpeedUnitAuto) -> (String, String) {
        let stringBase = base == .byte ? "B" : "b"
        let multiplier: Double = base == .byte ? 1 : 8

        if let fixedUnit = networkSpeedSizeUnit(from: unit), let speedPrefix = networkSpeedPrefix(from: unit) {
            let value = self.toUnit(fixedUnit) * multiplier
            return (self.formatSpeedValue(value), "\(speedPrefix)\(stringBase)/s")
        }

        let value: Double = Double(bytes) * multiplier
        switch value {
        case ..<1_000:
            return ("0", "K\(stringBase)/s")
        case 1_000..<1_000_000:
            return (String(format: "%.0f", value/1_000), "K\(stringBase)/s")
        case 1_000_000..<100_000_000:
            return (String(format: "%.1f", value/1_000_000), "M\(stringBase)/s")
        case 100_000_000..<1_000_000_000:
            return (String(format: "%.0f", value/1_000_000), "M\(stringBase)/s")
        case 1_000_000_000..<1_000_000_000_000:
            return (String(format: "%.1f", value/1_000_000_000), "G\(stringBase)/s")
        default:
            return (String(format: "%.1f", value/1_000_000_000_000), "T\(stringBase)/s")
        }
    }

    public func getReadableSpeed(base: DataSizeBase = .byte, unit: String = NetworkSpeedUnitAuto, omitUnits: Bool = false) -> String {
        let readable = self.getReadableTuple(base: base, unit: unit)
        return omitUnits ? readable.0 : "\(readable.0) \(readable.1)"
    }

    public func getReadableMemory(style: ByteCountFormatter.CountStyle = .file) -> String {
        let formatter: ByteCountFormatter = ByteCountFormatter()
        formatter.countStyle = style
        formatter.includesUnit = true
        formatter.isAdaptive = true

        var value = formatter.string(fromByteCount: Int64(self.bytes))
        if let idx = value.lastIndex(of: ",") {
            value.replaceSubrange(idx...idx, with: ".")
        }

        return value
    }

    public func toUnit(_ unit: SizeUnit) -> Double {
        switch unit {
        case .KB: return self.kilobytes
        case .MB: return self.megabytes
        case .GB: return self.gigabytes
        case .TB: return self.terabytes
        default: return Double(self.bytes)
        }
    }

    private func formatSpeedValue(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.decimalSeparator = "."
        formatter.usesGroupingSeparator = false
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}

// MARK: - Notifications

public extension Notification.Name {
    static let toggleSettings = Notification.Name("toggleSettings")
    static let togglePopup = Notification.Name("togglePopup")
    static let popupVisibilityChanged = Notification.Name("popupVisibilityChanged")
    static let toggleWidget = Notification.Name("toggleWidget")
    static let widgetRearrange = Notification.Name("widgetRearrange")
}

// MARK: - Appearance / strings

var isDarkMode: Bool {
    switch NSAppearance.currentDrawing().name {
    case .darkAqua, .vibrantDark, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastVibrantDark:
        return true
    default:
        return false
    }
}

/// stats 本地化函数的直通版本：本项目 UI 文案直接写中文，无需翻译表。
public func localizedString(_ key: String, _ params: String..., comment: String = "") -> String {
    var string = NSLocalizedString(key, comment: comment)
    if !params.isEmpty {
        for (index, param) in params.enumerated() {
            string = string.replacingOccurrences(of: "%\(index)", with: param)
        }
    }
    return string
}

// MARK: - NSColor hex

public extension String {
    func widthOfString(usingFont font: NSFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: fontAttributes)
        return size.width
    }

    func heightOfString(usingFont font: NSFont) -> CGFloat {
        let fontAttributes = [NSAttributedString.Key.font: font]
        let size = self.size(withAttributes: fontAttributes)
        return size.height
    }

    func sizeOfString(usingFont font: NSFont) -> CGSize {
        let fontAttributes = [NSAttributedString.Key.font: font]
        return self.size(withAttributes: fontAttributes)
    }
}

public extension Double {
    func rounded(toPlaces places: Int) -> Double {
        let divisor = pow(10.0, Double(places))
        return (self * divisor).rounded() / divisor
    }
}

public extension NSColor {
    var hexString: String {
        guard let color = self.usingColorSpace(.deviceRGB) else { return "#000000" }
        let r = Int(round(color.redComponent * 0xFF))
        let g = Int(round(color.greenComponent * 0xFF))
        let b = Int(round(color.blueComponent * 0xFF))
        return String(format: "#%02lX%02lX%02lX", r, g, b)
    }

    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let rgb = UInt64(value, radix: 16) else { return nil }
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255.0,
            green: CGFloat((rgb >> 8) & 0xFF) / 255.0,
            blue: CGFloat(rgb & 0xFF) / 255.0,
            alpha: 1
        )
    }
}
