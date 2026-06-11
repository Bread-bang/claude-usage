import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    /// No item with the given service exists (Claude Code never signed in, or signed out).
    case notFound
    /// The item exists but its data could not be read as `Data`.
    case unexpectedData
    /// A raw Security.framework status we don't special-case.
    case osStatus(OSStatus)
    /// `/usr/bin/security` failed in a way we don't special-case.
    case toolFailure(code: Int32, message: String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Claude Code credentials were not found in the Keychain. Sign in with Claude Code first."
        case .unexpectedData:
            return "The Keychain item could not be decoded."
        case .osStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
            return "Keychain error: \(message)"
        case .toolFailure(let code, let message):
            return "Keychain read failed (security exited \(code)). \(message)"
        }
    }
}

/// Thin wrapper over a single generic-password Keychain item.
///
/// Claude Code stores its OAuth bundle as a generic password under
/// service `"Claude Code-credentials"`, account = the macOS short user name.
struct KeychainStore: Sendable {
    /// How `readData()` accesses the item.
    enum ReadPath: Sendable {
        /// Shell out to the Apple-signed `/usr/bin/security` tool. Required for items
        /// *owned by other apps* (like Claude Code's): their partition list only trusts
        /// Apple-signed tools, so a direct `SecItemCopyMatching` from a third-party GUI app
        /// triggers the keychain password prompt on every launch — and the "Always Allow"
        /// grant never sticks (the ACL entry fails to validate for apps outside the item's
        /// partitions). The `security` tool is inside the `apple-tool:` partition and reads
        /// silently; it is the same access path Claude Code itself uses.
        case securityTool
        /// Direct Security.framework call. Correct for items *this app created* — the
        /// creating app always has silent access to its own items.
        case framework
    }

    let service: String
    let account: String
    let readPath: ReadPath

    init(service: String = "Claude Code-credentials",
         account: String = NSUserName(),
         readPath: ReadPath = .securityTool) {
        self.service = service
        self.account = account
        self.readPath = readPath
    }

    /// Reads the raw secret payload for this item.
    func readData() throws -> Data {
        switch readPath {
        case .securityTool: return try readViaSecurityTool()
        case .framework: return try readViaFramework()
        }
    }

    // MARK: - Reading

    private func readViaSecurityTool() throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-w"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        do {
            try process.run()
        } catch {
            throw KeychainError.toolFailure(code: -1, message: error.localizedDescription)
        }
        // Drain both pipes before waiting so a full pipe buffer can never deadlock the child.
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        switch process.terminationStatus {
        case 0:
            var data = outData
            if data.last == 0x0A { data.removeLast() } // trailing newline added by the tool
            guard !data.isEmpty else { throw KeychainError.unexpectedData }
            return data
        case 44: // errSecItemNotFound
            throw KeychainError.notFound
        default:
            let message = String(data: errData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            throw KeychainError.toolFailure(code: process.terminationStatus, message: message)
        }
    }

    private func readViaFramework() throws -> Data {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecItemNotFound else { throw KeychainError.notFound }
        guard status == errSecSuccess else { throw KeychainError.osStatus(status) }
        guard let data = item as? Data else { throw KeychainError.unexpectedData }
        return data
    }

    // MARK: - Writing

    /// Writes secret data into the item, creating it if needed.
    ///
    /// Only ever call this on items **this app owns** (its own refresh cache). Writing to
    /// an item created by another app prompts for the keychain password on every attempt.
    func writeData(_ data: Data) throws {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(base as CFDictionary, update as CFDictionary)
        if updateStatus == errSecSuccess { return }
        if updateStatus == errSecItemNotFound {
            var add = base
            add[kSecValueData as String] = data
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(add as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.osStatus(addStatus) }
            return
        }
        throw KeychainError.osStatus(updateStatus)
    }
}
