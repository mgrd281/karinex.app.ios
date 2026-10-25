import Foundation

// MARK: - SHA256

/// SHA-256 (FIPS 180-4) in pure Swift.
///
/// Core must build on Linux, where CryptoKit does not exist, and the only use is hashing short
/// values such as the PKCE code verifier (RFC 7636). It is not meant for bulk data and is never
/// used to protect secrets at rest; the Keychain does that.
public enum SHA256 {
    /// The size of a digest in bytes.
    public static let digestByteCount = 32

    /// Returns the 32-byte digest of `data`.
    public static func hash(_ data: some Sequence<UInt8>) -> [UInt8] {
        var message = Array(data)
        let bitLength = UInt64(message.count) &* 8
        message.append(0x80)
        while message.count % 64 != 56 {
            message.append(0)
        }
        for shift in stride(from: 56, through: 0, by: -8) {
            message.append(UInt8(truncatingIfNeeded: bitLength >> UInt64(shift)))
        }

        var state = initialState
        var schedule = [UInt32](repeating: 0, count: 64)
        for chunkStart in stride(from: 0, to: message.count, by: 64) {
            for index in 0..<16 {
                let offset = chunkStart + index * 4
                schedule[index] = UInt32(message[offset]) << 24
                    | UInt32(message[offset + 1]) << 16
                    | UInt32(message[offset + 2]) << 8
                    | UInt32(message[offset + 3])
            }
            for index in 16..<64 {
                let word15 = schedule[index - 15]
                let word2 = schedule[index - 2]
                let sigma0 = rotateRight(word15, by: 7) ^ rotateRight(word15, by: 18) ^ (word15 >> 3)
                let sigma1 = rotateRight(word2, by: 17) ^ rotateRight(word2, by: 19) ^ (word2 >> 10)
                schedule[index] = schedule[index - 16] &+ sigma0 &+ schedule[index - 7] &+ sigma1
            }
            compress(&state, schedule: schedule)
        }

        var digest: [UInt8] = []
        digest.reserveCapacity(digestByteCount)
        for word in state {
            digest.append(UInt8(truncatingIfNeeded: word >> 24))
            digest.append(UInt8(truncatingIfNeeded: word >> 16))
            digest.append(UInt8(truncatingIfNeeded: word >> 8))
            digest.append(UInt8(truncatingIfNeeded: word))
        }
        return digest
    }

    /// Returns the digest of the UTF-8 bytes of `string`.
    public static func hash(_ string: String) -> [UInt8] {
        hash(Array(string.utf8))
    }

    // MARK: Private

    private static func compress(_ state: inout [UInt32], schedule: [UInt32]) {
        // The eight working variables a to h of FIPS 180-4, section 6.2.2.
        var work = state
        for index in 0..<64 {
            let sum1 = rotateRight(work[4], by: 6) ^ rotateRight(work[4], by: 11) ^ rotateRight(work[4], by: 25)
            let choice = (work[4] & work[5]) ^ (~work[4] & work[6])
            let temp1 = work[7] &+ sum1 &+ choice &+ roundConstants[index] &+ schedule[index]
            let sum0 = rotateRight(work[0], by: 2) ^ rotateRight(work[0], by: 13) ^ rotateRight(work[0], by: 22)
            let majority = (work[0] & work[1]) ^ (work[0] & work[2]) ^ (work[1] & work[2])
            let temp2 = sum0 &+ majority
            work = [temp1 &+ temp2, work[0], work[1], work[2], work[3] &+ temp1, work[4], work[5], work[6]]
        }
        for index in 0..<8 {
            state[index] = state[index] &+ work[index]
        }
    }

    private static func rotateRight(_ value: UInt32, by amount: UInt32) -> UInt32 {
        (value >> amount) | (value << (32 - amount))
    }

    private static let initialState: [UInt32] = [
        0x6A09_E667, 0xBB67_AE85, 0x3C6E_F372, 0xA54F_F53A,
        0x510E_527F, 0x9B05_688C, 0x1F83_D9AB, 0x5BE0_CD19,
    ]

    private static let roundConstants: [UInt32] = [
        0x428A_2F98, 0x7137_4491, 0xB5C0_FBCF, 0xE9B5_DBA5, 0x3956_C25B, 0x59F1_11F1, 0x923F_82A4, 0xAB1C_5ED5,
        0xD807_AA98, 0x1283_5B01, 0x2431_85BE, 0x550C_7DC3, 0x72BE_5D74, 0x80DE_B1FE, 0x9BDC_06A7, 0xC19B_F174,
        0xE49B_69C1, 0xEFBE_4786, 0x0FC1_9DC6, 0x240C_A1CC, 0x2DE9_2C6F, 0x4A74_84AA, 0x5CB0_A9DC, 0x76F9_88DA,
        0x983E_5152, 0xA831_C66D, 0xB003_27C8, 0xBF59_7FC7, 0xC6E0_0BF3, 0xD5A7_9147, 0x06CA_6351, 0x1429_2967,
        0x27B7_0A85, 0x2E1B_2138, 0x4D2C_6DFC, 0x5338_0D13, 0x650A_7354, 0x766A_0ABB, 0x81C2_C92E, 0x9272_2C85,
        0xA2BF_E8A1, 0xA81A_664B, 0xC24B_8B70, 0xC76C_51A3, 0xD192_E819, 0xD699_0624, 0xF40E_3585, 0x106A_A070,
        0x19A4_C116, 0x1E37_6C08, 0x2748_774C, 0x34B0_BCB5, 0x391C_0CB3, 0x4ED8_AA4A, 0x5B9C_CA4F, 0x682E_6FF3,
        0x748F_82EE, 0x78A5_636F, 0x84C8_7814, 0x8CC7_0208, 0x90BE_FFFA, 0xA450_6CEB, 0xBEF9_A3F7, 0xC671_78F2,
    ]
}

// MARK: - Base64URL

/// Base64url without padding (RFC 4648 section 5), as PKCE and JWTs use it.
public enum Base64URL {
    /// Encodes `bytes`: base64 with `+` replaced by `-`, `/` by `_` and the `=` padding removed.
    public static func encode(_ bytes: some Sequence<UInt8>) -> String {
        Data(bytes).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Decodes base64url text with or without padding, or returns `nil` when it is malformed.
    public static func decode(_ text: some StringProtocol) -> Data? {
        var base64 = text
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder == 1 { return nil }
        if remainder > 0 {
            base64 += String(repeating: "=", count: 4 - remainder)
        }
        return Data(base64Encoded: base64)
    }
}

// MARK: - SecureRandom

/// Cryptographically secure random bytes from the system generator (`arc4random_buf` on Apple
/// platforms, `getrandom` on Linux, both behind `SystemRandomNumberGenerator`).
public enum SecureRandom {
    /// Returns `count` random bytes.
    public static func bytes(count: Int) -> [UInt8] {
        var generator = SystemRandomNumberGenerator()
        return (0..<max(count, 0)).map { _ in UInt8.random(in: UInt8.min...UInt8.max, using: &generator) }
    }

    /// Returns `byteCount` random bytes as unpadded base64url text, e.g. for an OAuth `state`.
    public static func token(byteCount: Int = 32) -> String {
        Base64URL.encode(bytes(count: byteCount))
    }
}
