import Foundation

/// Provides authentication tokens for HTTP requests.
/// Implement this to integrate with your auth system (e.g. Firebase, Auth0, custom).
public protocol TokenProvider: Sendable {
    func accessToken() async throws -> String?
}
