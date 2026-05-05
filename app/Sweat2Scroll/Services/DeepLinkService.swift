// Services/DeepLinkService.swift
// Handles Universal Link construction and parsing for remote iMessage pairing.
//
// Pairing URL format:
//   https://sweat2scroll.app/pair?payload=<base64url-encoded JSON>
//
// The payload is the same PairingQRPayload used for QR codes, but URL-safe
// base64 encoded and delivered via iMessage instead of a camera scan.
//
// Flow:
//   1. Device A generates ECDH key pair, encodes PairingQRPayload as base64url
//   2. Device A shares the link via iMessage (UIActivityViewController)
//   3. Device B taps the link → iOS opens Sweat2Scroll via Universal Link
//   4. App's onOpenURL handler decodes the payload and runs handleScannedQRCode()
//   5. Device B sends its public key back via CloudKit (same as QR flow)
//   6. Device A polls and completes the ECDH exchange

import Foundation
import CryptoKit

enum DeepLinkService {

    // MARK: - Universal Link Host & Path
    static let scheme = "https"
    static let host   = "sweat2scroll.app"
    static let pairingPath = "/pair"

    // MARK: - Construct Pairing URL from QR Payload JSON
    /// Takes the same JSON string used for QR codes and wraps it in a Universal Link URL.
    /// The payload is base64url-encoded (URL-safe, no padding) to survive iMessage transport.
    static func constructPairingURL(from qrPayloadJSON: String) -> URL? {
        guard let jsonData = qrPayloadJSON.data(using: .utf8) else { return nil }

        // Base64url encoding: standard base64 with + → -, / → _, padding stripped
        let base64url = jsonData.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")

        var components = URLComponents()
        components.scheme = scheme
        components.host   = host
        components.path   = pairingPath
        components.queryItems = [
            URLQueryItem(name: "payload", value: base64url),
            URLQueryItem(name: "v", value: "1")  // Protocol version for forward compat
        ]

        return components.url
    }

    // MARK: - Parse Incoming Universal Link
    /// Decodes an incoming pairing URL back into the JSON payload string.
    /// Returns nil if the URL is not a valid Sweat2Scroll pairing link.
    static func parsePairingURL(_ url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.host == host,
              components.path == pairingPath,
              let payloadItem = components.queryItems?.first(where: { $0.name == "payload" }),
              let base64url = payloadItem.value else {
            return nil
        }

        // Reverse base64url encoding
        var base64 = base64url
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        // Re-add padding
        let remainder = base64.count % 4
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }

        guard let jsonData = Data(base64Encoded: base64),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }

        // Validate it's actually a Sweat2Scroll payload
        guard let decoded = try? JSONDecoder().decode(PairingQRPayload.self, from: jsonData),
              decoded.app == "sweat2scroll" else {
            return nil
        }

        return jsonString
    }

    // MARK: - Check if URL is a Sweat2Scroll pairing link
    static func isPairingURL(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.host == host && components.path == pairingPath
    }

    // MARK: - Construct iMessage Body
    /// Returns a human-readable message with the pairing link embedded.
    static func constructiMessageBody(from pairingURL: URL, displayName: String) -> String {
        """
        \(displayName) wants to pair with you on Sweat2Scroll — \
        the app that gates social media behind real physical activity.

        Tap the link below to complete the secure pairing:
        \(pairingURL.absoluteString)

        This link expires in 10 minutes.
        """
    }
}
