import Foundation

/// used fordata
/// can data(Data, NSNumber)
enum DictionarySerializer {
    // MARK: - Public Methods

    /// Data, not JSON
    /// - Parameter dictionary:
    /// - Returns: Data, iffailed nil
    static func encodeDictionaryToData(_ dictionary: [String: Any]) -> Data? {
        // 1: use PropertyListSerialization ()
        // PropertyList supportnative, Data
        if let plistData = try? PropertyListSerialization.data(
            fromPropertyList: dictionary,
            format: .binary,
            options: 0
        ) {
            return plistData
        }

        // 2: if PropertyList failed, downgrade JSON(need to clean updata)
        let cleanedDictionary = cleanDictionaryForSerialization(dictionary)
        return try? JSONSerialization.data(withJSONObject: cleanedDictionary, options: [])
    }

    /// Data
    /// - Parameter data: Data
    /// - Returns:, iffailed nil
    static func decodeDictionaryFromData(_ data: Data) -> [String: Any]? {
        // PropertyList
        if let plistResult = try? PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] {
            return plistResult
        }

        // if PropertyList failed, JSON
        if let jsonResult = try? JSONSerialization.jsonObject(
            with: data,
            options: []
        ) as? [String: Any] {
            return jsonResult
        }

        return nil
    }

    // MARK: - Private Methods

    /// clean upnot JSON data
    /// - Parameter dictionary: original
    /// - Returns: clean up
    private static func cleanDictionaryForSerialization(_ dictionary: [String: Any]) -> [String: Any] {
        var cleaned: [String: Any] = [:]

        for (key, value) in dictionary {
            if let cleanedValue = cleanValue(value) {
                cleaned[key] = cleanedValue
            }
        }

        return cleaned
    }

    /// clean up, not can
    /// - Parameter value: clean up
    /// - Returns: clean up, ifno clean up nil
    private static func cleanValue(_ value: Any) -> Any? {
        switch value {
        case let data as Data:
            // Data Base64
            return data.base64EncodedString()
        case let dict as [String: Any]:
            // clean up
            return cleanDictionaryForSerialization(dict)
        case let array as [Any]:
            // clean up
            return array.compactMap { cleanValue($0) }
        case let number as NSNumber:
            // ensure NSNumber
            return number
        case let string as String:
            return string
        case let bool as Bool:
            return bool
        case is NSNull:
            return NSNull()
        default:
            // not,
            return String(describing: value)
        }
    }
}
