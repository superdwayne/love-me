import Foundation
import Network

/// Lightweight HTTP server that serves generated images from ~/.solace/generated/
/// Runs on port 9201 alongside the WebSocket server on 9200.
actor ImageServer {
    private var listener: NWListener?
    private let port: UInt16
    private let imageDirectory: String

    init(port: UInt16 = 9201, imageDirectory: String) {
        self.port = port
        self.imageDirectory = imageDirectory
    }

    func start() throws {
        let params = NWParameters.tcp
        let listener = try NWListener(using: params, on: NWEndpoint.Port(integerLiteral: port))

        let dir = imageDirectory
        listener.newConnectionHandler = { [dir] connection in
            connection.start(queue: .global(qos: .utility))
            ImageServer.handleConnection(connection, imageDirectory: dir)
        }

        listener.stateUpdateHandler = { state in
            switch state {
            case .ready:
                Logger.info("ImageServer listening on port \(self.port)")
            case .failed(let error):
                Logger.error("ImageServer failed: \(error)")
            default:
                break
            }
        }

        listener.start(queue: .global(qos: .utility))
        self.listener = listener
    }

    func stop() {
        listener?.cancel()
        listener = nil
        Logger.info("ImageServer stopped")
    }

    // MARK: - Connection Handling

    private static func handleConnection(_ connection: NWConnection, imageDirectory: String) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, error in
            guard let data = data, error == nil,
                  let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }

            // Parse the HTTP request line: "GET /images/filename.png HTTP/1.1"
            let lines = request.components(separatedBy: "\r\n")
            guard let requestLine = lines.first else {
                sendResponse(connection, status: "400 Bad Request", body: "Bad Request")
                return
            }

            let parts = requestLine.split(separator: " ")
            guard parts.count >= 2, parts[0] == "GET" else {
                sendResponse(connection, status: "405 Method Not Allowed", body: "Method Not Allowed")
                return
            }

            let path = String(parts[1])

            // Route: GET /images/{filename}
            guard path.hasPrefix("/images/") else {
                sendResponse(connection, status: "404 Not Found", body: "Not Found")
                return
            }

            let filename = String(path.dropFirst("/images/".count))

            // Security: prevent directory traversal
            guard !filename.contains(".."), !filename.contains("/") else {
                sendResponse(connection, status: "403 Forbidden", body: "Forbidden")
                return
            }

            let filePath = "\(imageDirectory)/\(filename)"
            guard FileManager.default.fileExists(atPath: filePath),
                  let fileData = try? Data(contentsOf: URL(fileURLWithPath: filePath)) else {
                sendResponse(connection, status: "404 Not Found", body: "Not Found")
                return
            }

            let contentType = mimeType(for: filename)
            sendFileResponse(connection, contentType: contentType, data: fileData)
        }
    }

    private static func sendResponse(_ connection: NWConnection, status: String, body: String) {
        let bodyData = body.data(using: .utf8) ?? Data()
        let header = "HTTP/1.1 \(status)\r\nContent-Length: \(bodyData.count)\r\nContent-Type: text/plain\r\nConnection: close\r\n\r\n"
        var response = header.data(using: .utf8) ?? Data()
        response.append(bodyData)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func sendFileResponse(_ connection: NWConnection, contentType: String, data: Data) {
        let header = "HTTP/1.1 200 OK\r\nContent-Length: \(data.count)\r\nContent-Type: \(contentType)\r\nCache-Control: public, max-age=86400\r\nAccess-Control-Allow-Origin: *\r\nConnection: close\r\n\r\n"
        var response = header.data(using: .utf8) ?? Data()
        response.append(data)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func mimeType(for filename: String) -> String {
        let ext = (filename as NSString).pathExtension.lowercased()
        switch ext {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "svg": return "image/svg+xml"
        default: return "application/octet-stream"
        }
    }
}

// MARK: - Shared Image Saving Helper

enum ImageFileHelper {
    /// Save base64-encoded image data to the generated images directory.
    /// Returns the filename on success (e.g., "abc123.png").
    static func saveBase64Image(data base64String: String, mimeType: String, directory: String) -> String? {
        guard let imageData = Data(base64Encoded: base64String) else {
            Logger.error("ImageFileHelper: failed to decode base64 image data")
            return nil
        }

        let ext = fileExtension(for: mimeType)
        let filename = UUID().uuidString + "." + ext
        let filePath = "\(directory)/\(filename)"

        // Ensure directory exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: directory) {
            try? fm.createDirectory(atPath: directory, withIntermediateDirectories: true)
        }

        do {
            try imageData.write(to: URL(fileURLWithPath: filePath), options: .atomic)
            Logger.info("ImageFileHelper: saved image \(filename) (\(imageData.count) bytes)")
            return filename
        } catch {
            Logger.error("ImageFileHelper: failed to write image: \(error)")
            return nil
        }
    }

    private static func fileExtension(for mimeType: String) -> String {
        switch mimeType.lowercased() {
        case "image/png": return "png"
        case "image/jpeg", "image/jpg": return "jpg"
        case "image/gif": return "gif"
        case "image/webp": return "webp"
        case "image/svg+xml": return "svg"
        default: return "png"
        }
    }
}
