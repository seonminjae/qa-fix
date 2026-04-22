import Foundation

final class NotionAPIClient: NotionService {
    private let session: URLSession
    private let baseURL = URL(string: "https://api.notion.com/v1")!
    private let retryPolicy: RetryPolicy
    private let limiter = ConcurrencyLimiter(limit: 3)
    private let tokenProvider: () -> String?

    init(
        session: URLSession = .shared,
        retryPolicy: RetryPolicy = .default,
        tokenProvider: @escaping () -> String? = { KeychainManager.load(for: .notionToken) }
    ) {
        self.session = session
        self.retryPolicy = retryPolicy
        self.tokenProvider = tokenProvider
    }

    // MARK: - Public API

    func fetchOpenedTickets(databaseID: String, version: String?) async throws -> [Ticket] {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw NotionError.missingToken
        }
        var filters: [[String: Any]] = [
            ["property": "상태", "select": ["equals": "Opened"]]
        ]
        if let version, !version.isEmpty {
            filters.append([
                "property": "검증 프로젝트 태그",
                "multi_select": ["contains": version]
            ])
        }
        let body: [String: Any] = [
            "filter": ["and": filters]
        ]
        let data: Data = try await perform(
            path: "databases/\(databaseID)/query",
            method: "POST",
            token: token,
            jsonBody: body
        )
        do {
            let decoded = try JSONDecoder().decode(NotionQueryResponse.self, from: data)
            var tickets = decoded.results.map { Ticket.build(from: $0) }
            tickets.sort { $0.severity < $1.severity }
            return tickets
        } catch {
            throw NotionError.decoding(error)
        }
    }

    func fetchComments(pageID: String) async throws -> [TicketComment] {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw NotionError.missingToken
        }
        let data: Data = try await perform(
            path: "comments?block_id=\(pageID)",
            method: "GET",
            token: token,
            jsonBody: nil
        )
        do {
            let decoded = try JSONDecoder().decode(NotionCommentsResponse.self, from: data)
            return decoded.results.map {
                TicketComment(author: $0.author, createdTime: $0.createdTime, text: $0.text)
            }
        } catch {
            throw NotionError.decoding(error)
        }
    }

    func fetchImageBlocks(pageID: String) async throws -> [String] {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw NotionError.missingToken
        }
        let data: Data = try await perform(
            path: "blocks/\(pageID)/children?page_size=50",
            method: "GET",
            token: token,
            jsonBody: nil
        )
        do {
            let decoded = try JSONDecoder().decode(NotionBlocksResponse.self, from: data)
            return decoded.results.compactMap { block in
                guard block.type == "image", let image = block.image else { return nil }
                return image.bestURL
            }
        } catch {
            throw NotionError.decoding(error)
        }
    }

    func patchStatus(pageID: String, statusName: String) async throws {
        guard let token = tokenProvider(), !token.isEmpty else {
            throw NotionError.missingToken
        }
        let body: [String: Any] = [
            "properties": [
                "상태": ["select": ["name": statusName]]
            ]
        ]
        _ = try await perform(
            path: "pages/\(pageID)",
            method: "PATCH",
            token: token,
            jsonBody: body
        )
    }

    // MARK: - Core

    private func perform(
        path: String,
        method: String,
        token: String,
        jsonBody: [String: Any]?
    ) async throws -> Data {
        await limiter.acquire()
        defer { Task { await limiter.release() } }

        let url = baseURL.appendingPathComponent("")
            .appendingPathComponent(path, isDirectory: false)
        // appendingPathComponent escapes the query string; rebuild via URLComponents when needed.
        let finalURL: URL
        if path.contains("?") {
            finalURL = URL(string: baseURL.absoluteString + "/" + path)!
        } else {
            finalURL = url
        }

        var lastError: Error?
        for attempt in 1...retryPolicy.maxAttempts {
            var request = URLRequest(url: finalURL)
            request.httpMethod = method
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.addValue("2022-06-28", forHTTPHeaderField: "Notion-Version")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            if let jsonBody {
                request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody)
            }

            do {
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else {
                    throw NotionError.network(URLError(.badServerResponse))
                }
                if (200..<300).contains(http.statusCode) {
                    return data
                }
                if retryPolicy.shouldRetry(status: http.statusCode), attempt < retryPolicy.maxAttempts {
                    let retryAfter = (http.value(forHTTPHeaderField: "Retry-After") as NSString?)?.doubleValue
                    let delay = retryPolicy.delay(forAttempt: attempt, retryAfterSeconds: retryAfter)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                let bodyText = String(data: data, encoding: .utf8) ?? ""
                throw NotionError.httpError(http.statusCode, bodyText)
            } catch let error as NotionError {
                throw error
            } catch {
                lastError = error
                if attempt < retryPolicy.maxAttempts {
                    let delay = retryPolicy.delay(forAttempt: attempt)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                    continue
                }
                throw NotionError.network(error)
            }
        }
        throw NotionError.network(lastError ?? URLError(.unknown))
    }
}
