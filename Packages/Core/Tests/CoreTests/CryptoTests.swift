@testable import Core
import Foundation
import Testing

@Suite("SHA256, Base64URL and SecureRandom")
struct CryptoTests {
    private static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    @Test("SHA-256 matches the FIPS 180-4 and NIST test vectors")
    func knownVectors() {
        #expect(Self.hex(SHA256.hash("")) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(Self.hex(SHA256.hash("abc")) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        #expect(
            Self.hex(SHA256.hash("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq"))
                == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
        )
        let million = [UInt8](repeating: UInt8(ascii: "a"), count: 1_000_000)
        #expect(Self.hex(SHA256.hash(million)) == "cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0")
    }

    @Test("Messages around the 55, 56 and 64 byte padding boundaries hash to 32 bytes")
    func paddingBoundaries() {
        for length in [55, 56, 63, 64, 65, 119, 120] {
            #expect(SHA256.hash([UInt8](repeating: 0x61, count: length)).count == SHA256.digestByteCount)
        }
        #expect(
            Self.hex(SHA256.hash([UInt8](repeating: 0x61, count: 64)))
                == "ffe054fe7ae0cb6dc65c3af9b61d5209f439851db43d0ba5997337df154668eb"
        )
    }

    @Test("The PKCE example of RFC 7636 appendix B")
    func pkceExample() {
        let verifier = "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"
        #expect(Base64URL.encode(SHA256.hash(verifier)) == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test("Base64url has no padding and no + or /, and decodes with or without padding")
    func base64URL() {
        let bytes: [UInt8] = [0xFB, 0xFF, 0xBF, 0x01]
        let encoded = Base64URL.encode(bytes)
        #expect(encoded == "-_-_AQ")
        #expect(Base64URL.decode(encoded) == Data(bytes))
        #expect(Base64URL.decode("-_-_AQ==") == Data(bytes))
        #expect(Base64URL.decode("abcde") == nil)
        #expect(Base64URL.decode("") == Data())
    }

    @Test("Random tokens have the requested size and differ")
    func randomTokens() {
        #expect(SecureRandom.bytes(count: 16).count == 16)
        #expect(SecureRandom.bytes(count: -1).isEmpty)
        let first = SecureRandom.token()
        let second = SecureRandom.token()
        #expect(first != second)
        #expect(Base64URL.decode(first)?.count == 32)
        #expect(!first.contains("="))
    }
}
