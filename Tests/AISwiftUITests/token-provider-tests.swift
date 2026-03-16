import Testing
import Foundation
@testable import AISwiftUI

// MARK: - Mock Token Providers

private struct StaticTokenProvider: TokenProvider {
    let token: String?
    func accessToken() async throws -> String? { token }
}

private struct ThrowingTokenProvider: TokenProvider {
    struct TokenError: Error {}
    func accessToken() async throws -> String? { throw TokenError() }
}

// MARK: - Token Provider Tests

struct TokenProviderTests {

    @Test func tokenInjectedAsBearerHeader() async throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!,
            tokenProvider: StaticTokenProvider(token: "my-access-token")
        )

        let request = TransportSendRequest(id: "s1", messages: [])
        let urlReq = try await transport.buildURLRequestAsync(for: request)

        #expect(urlReq.value(forHTTPHeaderField: "Authorization") == "Bearer my-access-token")
    }

    @Test func nilTokenSkipsAuthorizationHeader() async throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!,
            tokenProvider: StaticTokenProvider(token: nil)
        )

        let request = TransportSendRequest(id: "s2", messages: [])
        let urlReq = try await transport.buildURLRequestAsync(for: request)

        // nil token should not add Authorization header
        #expect(urlReq.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func noTokenProviderSkipsAuthorizationHeader() async throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!
        )

        let request = TransportSendRequest(id: "s3", messages: [])
        let urlReq = try await transport.buildURLRequestAsync(for: request)

        #expect(urlReq.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func tokenProviderResultOverridesStaticHeaders() async throws {
        // If static headers also provide Authorization, tokenProvider should overwrite it
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!,
            tokenProvider: StaticTokenProvider(token: "dynamic-token"),
            headers: { ["Authorization": "Bearer static-token"] }
        )

        let request = TransportSendRequest(id: "s4", messages: [])
        let urlReq = try await transport.buildURLRequestAsync(for: request)

        // Token provider result wins (applied after static headers)
        #expect(urlReq.value(forHTTPHeaderField: "Authorization") == "Bearer dynamic-token")
    }

    @Test func throwingTokenProviderPropagatesError() async throws {
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!,
            tokenProvider: ThrowingTokenProvider()
        )

        let request = TransportSendRequest(id: "s5", messages: [])
        var threwError = false
        do {
            _ = try await transport.buildURLRequestAsync(for: request)
        } catch {
            threwError = true
        }

        #expect(threwError)
    }

    @Test func buildURLRequestAsyncUsedWhenTokenProviderSet() async throws {
        // Verify that buildURLRequestAsync includes token when tokenProvider is configured
        let token = "async-token-abc"
        let transport = HTTPChatTransport(
            apiURL: URL(string: "https://example.com/chat")!,
            tokenProvider: StaticTokenProvider(token: token)
        )

        let request = TransportSendRequest(id: "s6", messages: [])

        // Sync version should NOT have the token
        let syncReq = try transport.buildURLRequest(for: request)
        #expect(syncReq.value(forHTTPHeaderField: "Authorization") == nil)

        // Async version SHOULD have the token
        let asyncReq = try await transport.buildURLRequestAsync(for: request)
        #expect(asyncReq.value(forHTTPHeaderField: "Authorization") == "Bearer \(token)")
    }
}
