import Foundation

enum NamingUtils {
    /// generate,, auto
    /// - Parameters:
    ///   - baseName:
    ///   - existingNames:
    /// - Returns:
    static func generateUniqueName(for baseName: String, among existingNames: [String]) -> String {
        let pattern = "^(.+?)\\s*(\\d+)$"
        let regex = try? NSRegularExpression(pattern: pattern)
        let nsString = baseName as NSString
        let results = regex?.firstMatch(in: baseName, range: NSRange(location: 0, length: nsString.length))

        var nameWithoutNumber: String
        var nextNumber: Int

        if let match = results {
            nameWithoutNumber = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
            let numberString = nsString.substring(with: match.range(at: 2))
            nextNumber = (Int(numberString) ?? 1) + 1
        } else {
            nameWithoutNumber = baseName
            nextNumber = 2
        }

        var newName = "\(nameWithoutNumber) \(nextNumber)"

        // ensure
        while existingNames.contains(newName) {
            nextNumber += 1
            newName = "\(nameWithoutNumber) \(nextNumber)"
        }

        return newName
    }
}
