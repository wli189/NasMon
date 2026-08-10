//
//  DSMFileStationService.swift
//  NasMon
//
//  DSM File Station service - handles file operations for Synology DSM devices.
//  Designed to be extended for other NAS brands by creating separate
//  service modules (e.g., DS365FileStationService, QNAPFileService).
//

import Foundation

// MARK: - DSM File Station Service
/// Handles File Station operations for Synology DSM devices including listing shares,
/// files and folders. Can be replaced with alternative file service implementations
/// for other NAS brands.
extension DSMClient {
    
    // MARK: - File Station Helpers
    
    /// Auth query items for File Station calls.
    ///
    /// DSM docs say File Station accepts `_sid`, `SynoToken`, or the
    /// `X-SYNO-TOKEN` header alone, but on DSM 7.3.2 sending only one returns
    /// error 119 ("session expired"). Sending both via `authQueryItems` is
    /// what actually works.
    private var fileStationAuthQueryItems: [URLQueryItem] { authQueryItems }
    
    /// Percent-encode a folder path for use as a query value.
    /// Encodes ALL special characters — only alphanumeric and a few safe chars pass through.
    /// Example: "/docker/#recycle" → "%2Fdocker%2F%23recycle"
    ///          "my file & name.txt" → "my%20file%20%26%20name.txt"
    private func urlEncodedFolderPath(_ path: String) -> String {
        // Only allow alphanumeric and a minimal set of safe characters.
        // Everything else (including /, #, &, ?, @, space, etc.) gets percent-encoded.
        var allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~!$'()*+,;=@[]")
        return path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path
    }
    
    /// Check if the response body is an HTML error page (e.g. NAS 404 page)
    /// rather than the expected JSON. Returns a user-friendly message.
    private func htmlErrorIfPresent(_ data: Data) -> String? {
        guard let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("<!DOCTYPE html>") || trimmed.hasPrefix("<html") {
            return "NAS returned an HTML error page (404). The API endpoint or parameters may be incorrect."
        }
        return nil
    }
    
    // MARK: - File Station Operations
    
    /// List all shared folders accessible to the logged-in account.
    ///
    /// API: `SYNO.FileStation.List` → `method=list_share` (version 1)
    ///
    /// Optionally requests additional info (size, owner, permissions, volume
    /// free/total space) by passing `additional=["real_path", "size", "owner",
    /// "time", "perm", "volume_status"]` and `additional_owner_user=true`.
    func fetchShares(includeAdditionalInfo: Bool = false) async throws -> [DSMShare] {
        let auth = fileStationAuthQueryItems
        guard !auth.isEmpty else { throw DSMClientError.noSession }
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "api", value: "SYNO.FileStation.List"),
            URLQueryItem(name: "version", value: "1"),
            URLQueryItem(name: "method", value: "list_share"),
        ] + auth
        
        if includeAdditionalInfo {
            // Use raw JSON array string for the additional parameter
            let additionalJson = "[\"real_path\",\"size\",\"owner\",\"time\",\"perm\",\"volume_status\"]"
            queryItems.append(URLQueryItem(name: "additional", value: additionalJson))
            queryItems.append(URLQueryItem(name: "additional_owner_user", value: "true"))
            queryItems.append(URLQueryItem(name: "additional_owner_group", value: "true"))
        }
        
        guard let url = makeURL(path: "/webapi/entry.cgi", queryItems: queryItems)
        else { throw DSMClientError.invalidURL }
        
        let (data, _) = try await session.data(from: url)
        
        if let raw = String(data: data, encoding: .utf8) {
            print("Raw list_share response:\n\(raw)\n")
        }
        
        if htmlErrorIfPresent(data) != nil {
            throw DSMClientError.fileStationFailed(code: nil)
        }
        
        let decoded: DSMListShareResponse
        do {
            decoded = try JSONDecoder().decode(DSMListShareResponse.self, from: data)
        } catch {
            throw DSMClientError.decodingFailed(error)
        }
        
        guard decoded.success, let data = decoded.data else {
            throw DSMClientError.fileStationFailed(code: decoded.error?.code)
        }
        return data.shares
    }
    
    /// List files and folders in the given path.
    ///
    /// API: `SYNO.FileStation.List` → `method=list` (version 2)
    ///
    /// - Parameters:
    ///   - path: e.g. "/home" (shared-folder root) or a subpath like "/home/music".
    ///   - offset: Pagination offset (default 0).
    ///   - limit: Max entries (default 10000, DSM's max).
    func listFiles(in path: String, offset: Int = 0, limit: Int = 10000, includeAdditionalInfo: Bool = false) async throws -> [DSMFile] {
        let auth = fileStationAuthQueryItems
        guard !auth.isEmpty else { throw DSMClientError.noSession }
        
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "api", value: "SYNO.FileStation.List"),
            URLQueryItem(name: "version", value: "2"),
            URLQueryItem(name: "method", value: "list"),
            URLQueryItem(name: "folder_path", value: path),
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "limit", value: "\(limit)")
        ] + auth
        
        if includeAdditionalInfo {
            // Use raw JSON array string for the additional parameter
            let additionalJson = "[\"real_path\",\"size\",\"owner\",\"time\",\"perm\",\"type\",\"mount_point_type\",\"volume_status\"]"
            queryItems.append(URLQueryItem(name: "additional", value: additionalJson))
        }
        
        guard let url = makeURL(path: "/webapi/entry.cgi", queryItems: queryItems)
        else { throw DSMClientError.invalidURL }
        
        // Print the actual URL being accessed for debugging
        print("FileStation URL: https://\(host):\(port)\(url.path)?\(url.query ?? "")")
        
        let (data, _) = try await session.data(from: url)
        
        if let raw = String(data: data, encoding: .utf8) {
            print("Raw list response for \(path):\n\(raw)\n")
        }
        
        if htmlErrorIfPresent(data) != nil {
            throw DSMClientError.fileStationFailed(code: nil)
        }
        
        let decoded: DSMListFilesResponse
        do {
            decoded = try JSONDecoder().decode(DSMListFilesResponse.self, from: data)
        } catch {
            throw DSMClientError.decodingFailed(error)
        }
        
        guard decoded.success, let data = decoded.data else {
            throw DSMClientError.fileStationFailed(code: decoded.error?.code)
        }
        return data.files
    }

    // MARK: - Thumbnail

    /// Download a thumbnail image for the given file path.
    ///
    /// API: `SYNO.FileStation.Thumb` → `method=get` (version 2)
    ///
    /// Returns raw image data (PNG/JPEG). Works for image files and video files
    /// (DSM extracts a representative frame). Returns an error for unsupported types.
    ///
    /// - Parameters:
    ///   - path: Full path of the file on the NAS, e.g. `"/home/photo.jpg"`.
    ///   - size: Thumbnail size — `"small"`, `"medium"`, `"large"`, or `"original"`.
    func downloadThumbnail(path: String, size: String = "large") async throws -> Data {
        let auth = fileStationAuthQueryItems
        guard !auth.isEmpty else { throw DSMClientError.noSession }

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "api", value: "SYNO.FileStation.Thumb"),
            URLQueryItem(name: "version", value: "2"),
            URLQueryItem(name: "method", value: "get"),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "size", value: size),
        ] + auth

        guard let url = makeURL(path: "/webapi/entry.cgi", queryItems: queryItems)
        else { throw DSMClientError.invalidURL }

        let (data, _) = try await session.data(from: url)

        // DSM returns JSON (not image data) when the thumb API fails
        if let errorText = String(data: data, encoding: .utf8),
           errorText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            if let decoded = try? JSONDecoder().decode(DSMFSResponse<DSMEmptyData>.self, from: data),
               !decoded.success {
                throw DSMClientError.fileStationFailed(code: decoded.error?.code)
            }
        }

        if htmlErrorIfPresent(data) != nil {
            throw DSMClientError.fileStationFailed(code: nil)
        }

        return data
    }

    // MARK: - Download (into memory)

    /// Download a file's raw data into memory.
    ///
    /// API: `SYNO.FileStation.Download` → `method=download` (version 2)
    ///
    /// Suitable for smaller files (images, text, PDFs). For large video/audio
    /// files, use `downloadFileToTemp` instead to avoid excessive memory usage.
    ///
    /// - Parameter path: Full path of the file on the NAS, e.g. `"/home/doc.pdf"`.
    func downloadFileData(path: String) async throws -> Data {
        let auth = fileStationAuthQueryItems
        guard !auth.isEmpty else { throw DSMClientError.noSession }

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "api", value: "SYNO.FileStation.Download"),
            URLQueryItem(name: "version", value: "2"),
            URLQueryItem(name: "method", value: "download"),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "mode", value: "download"),
        ] + auth

        guard let url = makeURL(path: "/webapi/entry.cgi", queryItems: queryItems)
        else { throw DSMClientError.invalidURL }

        let (data, _) = try await session.data(from: url)

        // Check for HTML error page
        if htmlErrorIfPresent(data) != nil {
            throw DSMClientError.fileStationFailed(code: nil)
        }

        // Check for JSON error response (DSM returns JSON on failure, not file data)
        if let errorText = String(data: data, encoding: .utf8),
           errorText.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("{") {
            if let decoded = try? JSONDecoder().decode(DSMFSResponse<DSMEmptyData>.self, from: data),
               !decoded.success {
                throw DSMClientError.fileStationFailed(code: decoded.error?.code)
            }
        }

        return data
    }

    // MARK: - Download (to temp file)

    /// Download a file to a temporary location on disk.
    ///
    /// Uses `URLSession.download` so the file is streamed to disk rather than
    /// loaded into memory. Suitable for large files (video, audio).
    ///
    /// - Parameters:
    ///   - path: Full path of the file on the NAS.
    ///   - fileExtension: The file extension to use for the temp file (e.g. `"mp4"`).
    /// - Returns: URL of the downloaded temporary file.
    func downloadFileToTemp(path: String, fileExtension: String) async throws -> URL {
        let auth = fileStationAuthQueryItems
        guard !auth.isEmpty else { throw DSMClientError.noSession }

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "api", value: "SYNO.FileStation.Download"),
            URLQueryItem(name: "version", value: "2"),
            URLQueryItem(name: "method", value: "download"),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "mode", value: "download"),
        ] + auth

        guard let url = makeURL(path: "/webapi/entry.cgi", queryItems: queryItems)
        else { throw DSMClientError.invalidURL }

        let (downloadedURL, response) = try await session.download(from: url)

        // Check HTTP status code
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw DSMClientError.fileStationFailed(code: nil)
        }

        // Move to a temp file with the correct extension so AVPlayer can
        // recognize the format.
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(fileExtension)
        try FileManager.default.moveItem(at: downloadedURL, to: tempURL)

        return tempURL
    }

    // MARK: - Download (to destination)

    /// Download a file directly to a caller-supplied destination on disk.
    ///
    /// Uses `URLSession.download` so the file is streamed to disk rather than
    /// loaded into memory. Used by the preview system to write straight into
    /// the `Caches/PreviewCache/` directory.
    ///
    /// - Parameters:
    ///   - path: Full path of the file on the NAS.
    ///   - destinationURL: The local URL to write the file to.
    func downloadFile(path: String, to destinationURL: URL) async throws {
        let auth = fileStationAuthQueryItems
        guard !auth.isEmpty else { throw DSMClientError.noSession }

        let queryItems: [URLQueryItem] = [
            URLQueryItem(name: "api", value: "SYNO.FileStation.Download"),
            URLQueryItem(name: "version", value: "2"),
            URLQueryItem(name: "method", value: "download"),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "mode", value: "download"),
        ] + auth

        guard let url = makeURL(path: "/webapi/entry.cgi", queryItems: queryItems)
        else { throw DSMClientError.invalidURL }

        let (downloadedURL, response) = try await session.download(from: url)

        // Check HTTP status code
        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            throw DSMClientError.fileStationFailed(code: nil)
        }

        // Move the downloaded file into place at the destination.
        try FileManager.default.moveItem(at: downloadedURL, to: destinationURL)
    }
}

/// Empty Codable struct used for decoding error-only JSON responses from
/// download/thumb APIs (which return `{"success": false, "error": {...}}`
/// with no `data` field).
struct DSMEmptyData: Codable {}
