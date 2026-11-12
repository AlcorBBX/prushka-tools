import Foundation

struct AgentRequest: Equatable, Sendable {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data
}

struct AgentHTTPResponse: Sendable {
    var status: Int
    var body: Data

    static func json(_ status: Int, _ value: JSONValue) -> AgentHTTPResponse {
        AgentHTTPResponse(status: status, body: value.data())
    }
}

enum AgentParse: Equatable, Sendable {
    case incomplete
    case tooLarge
    case ready(AgentRequest)
}

enum AgentHTTP {
    static let maxBody = 262_144

    static func parse(_ buffer: Data) -> AgentParse {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = buffer.range(of: separator) else {
            return buffer.count > 65_536 ? .tooLarge : .incomplete
        }
        guard let head = String(data: buffer[..<headerEnd.lowerBound], encoding: .isoLatin1) else {
            return .tooLarge
        }
        let lines = head.split(separator: "\r\n", omittingEmptySubsequences: false)
        guard let requestLine = lines.first else { return .tooLarge }
        let pieces = requestLine.split(separator: " ")
        guard pieces.count >= 2 else { return .tooLarge }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[name] = String(value)
        }

        let length = Int(headers["content-length"] ?? "") ?? 0
        if length < 0 || length > maxBody {
            return .tooLarge
        }
        let body = buffer[headerEnd.upperBound...]
        guard body.count >= length else { return .incomplete }
        let target = splitTarget(String(pieces[1]))
        return .ready(
            AgentRequest(
                method: String(pieces[0]),
                path: target.path,
                query: target.query,
                headers: headers,
                body: Data(body.prefix(length))
            )
        )
    }

    static func response(status: Int, body: Data) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 400: reason = "Bad Request"
        case 401: reason = "Unauthorized"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 409: reason = "Conflict"
        case 413: reason = "Payload Too Large"
        default: reason = "Error"
        }
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: application/json; charset=utf-8\r\n"
        header += "Content-Length: \(body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(body)
        return data
    }

    static func splitTarget(_ target: String) -> (path: String, query: [String: String]) {
        let pieces = target.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = decode(String(pieces.first ?? "/"))
        var query: [String: String] = [:]
        guard pieces.count == 2 else { return (path, query) }
        for pair in pieces[1].split(separator: "&") where !pair.isEmpty {
            let bits = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = decode(String(bits[0]))
            let value = bits.count > 1 ? decode(String(bits[1])) : ""
            if !name.isEmpty {
                query[name] = value
            }
        }
        return (path, query)
    }

    static func decode(_ value: String) -> String {
        let plus = value.replacingOccurrences(of: "+", with: " ")
        return plus.removingPercentEncoding ?? plus
    }
}
