import Foundation

public extension Array where Element == UIMessage {
    /// Encode messages to JSON data for persistence.
    func jsonData() throws -> Data {
        try JSONEncoder().encode(self)
    }

    /// Decode messages from JSON data.
    init(jsonData: Data) throws {
        self = try JSONDecoder().decode([UIMessage].self, from: jsonData)
    }
}
