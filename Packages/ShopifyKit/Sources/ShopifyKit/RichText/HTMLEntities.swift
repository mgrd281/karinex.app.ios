import Foundation

// MARK: - HTMLEntities

/// Decodes HTML character references: named ones (the complete Latin-1 set, typography,
/// arrows, math and Greek letters) and numeric ones (`&#228;`, `&#xE4;`).
enum HTMLEntities {
    /// Named references without `&` and `;`, mapped to their Unicode scalar value.
    static let named: [String: UInt32] = [
        "quot": 0x0022, "amp": 0x0026, "apos": 0x0027, "lt": 0x003C, "gt": 0x003E, "nbsp": 0x00A0, "iexcl": 0x00A1, "cent": 0x00A2,
        "pound": 0x00A3, "curren": 0x00A4, "yen": 0x00A5, "brvbar": 0x00A6, "sect": 0x00A7, "uml": 0x00A8, "copy": 0x00A9,
        "ordf": 0x00AA, "laquo": 0x00AB, "not": 0x00AC, "shy": 0x00AD, "reg": 0x00AE, "macr": 0x00AF, "deg": 0x00B0, "plusmn": 0x00B1,
        "sup2": 0x00B2, "sup3": 0x00B3, "acute": 0x00B4, "micro": 0x00B5, "para": 0x00B6, "middot": 0x00B7, "cedil": 0x00B8,
        "sup1": 0x00B9, "ordm": 0x00BA, "raquo": 0x00BB, "frac14": 0x00BC, "frac12": 0x00BD, "frac34": 0x00BE, "iquest": 0x00BF,
        "Agrave": 0x00C0, "Aacute": 0x00C1, "Acirc": 0x00C2, "Atilde": 0x00C3, "Auml": 0x00C4, "Aring": 0x00C5, "AElig": 0x00C6,
        "Ccedil": 0x00C7, "Egrave": 0x00C8, "Eacute": 0x00C9, "Ecirc": 0x00CA, "Euml": 0x00CB, "Igrave": 0x00CC, "Iacute": 0x00CD,
        "Icirc": 0x00CE, "Iuml": 0x00CF, "ETH": 0x00D0, "Ntilde": 0x00D1, "Ograve": 0x00D2, "Oacute": 0x00D3, "Ocirc": 0x00D4,
        "Otilde": 0x00D5, "Ouml": 0x00D6, "times": 0x00D7, "Oslash": 0x00D8, "Ugrave": 0x00D9, "Uacute": 0x00DA, "Ucirc": 0x00DB,
        "Uuml": 0x00DC, "Yacute": 0x00DD, "THORN": 0x00DE, "szlig": 0x00DF, "agrave": 0x00E0, "aacute": 0x00E1, "acirc": 0x00E2,
        "atilde": 0x00E3, "auml": 0x00E4, "aring": 0x00E5, "aelig": 0x00E6, "ccedil": 0x00E7, "egrave": 0x00E8, "eacute": 0x00E9,
        "ecirc": 0x00EA, "euml": 0x00EB, "igrave": 0x00EC, "iacute": 0x00ED, "icirc": 0x00EE, "iuml": 0x00EF, "eth": 0x00F0,
        "ntilde": 0x00F1, "ograve": 0x00F2, "oacute": 0x00F3, "ocirc": 0x00F4, "otilde": 0x00F5, "ouml": 0x00F6, "divide": 0x00F7,
        "oslash": 0x00F8, "ugrave": 0x00F9, "uacute": 0x00FA, "ucirc": 0x00FB, "uuml": 0x00FC, "yacute": 0x00FD, "thorn": 0x00FE,
        "yuml": 0x00FF, "OElig": 0x0152, "oelig": 0x0153, "Scaron": 0x0160, "scaron": 0x0161, "Yuml": 0x0178, "fnof": 0x0192,
        "circ": 0x02C6, "tilde": 0x02DC, "Alpha": 0x0391, "Beta": 0x0392, "Gamma": 0x0393, "Delta": 0x0394, "Epsilon": 0x0395,
        "Zeta": 0x0396, "Eta": 0x0397, "Theta": 0x0398, "Iota": 0x0399, "Kappa": 0x039A, "Lambda": 0x039B, "Mu": 0x039C, "Nu": 0x039D,
        "Xi": 0x039E, "Omicron": 0x039F, "Pi": 0x03A0, "Rho": 0x03A1, "Sigma": 0x03A3, "Tau": 0x03A4, "Upsilon": 0x03A5, "Phi": 0x03A6,
        "Chi": 0x03A7, "Psi": 0x03A8, "Omega": 0x03A9, "alpha": 0x03B1, "beta": 0x03B2, "gamma": 0x03B3, "delta": 0x03B4,
        "epsilon": 0x03B5, "zeta": 0x03B6, "eta": 0x03B7, "theta": 0x03B8, "iota": 0x03B9, "kappa": 0x03BA, "lambda": 0x03BB,
        "mu": 0x03BC, "nu": 0x03BD, "xi": 0x03BE, "omicron": 0x03BF, "pi": 0x03C0, "rho": 0x03C1, "sigmaf": 0x03C2, "sigma": 0x03C3,
        "tau": 0x03C4, "upsilon": 0x03C5, "phi": 0x03C6, "chi": 0x03C7, "psi": 0x03C8, "omega": 0x03C9, "ensp": 0x2002, "emsp": 0x2003,
        "thinsp": 0x2009, "zwnj": 0x200C, "zwj": 0x200D, "lrm": 0x200E, "rlm": 0x200F, "ndash": 0x2013, "mdash": 0x2014,
        "lsquo": 0x2018, "rsquo": 0x2019, "sbquo": 0x201A, "ldquo": 0x201C, "rdquo": 0x201D, "bdquo": 0x201E, "dagger": 0x2020,
        "Dagger": 0x2021, "bull": 0x2022, "hellip": 0x2026, "permil": 0x2030, "prime": 0x2032, "Prime": 0x2033, "lsaquo": 0x2039,
        "rsaquo": 0x203A, "oline": 0x203E, "frasl": 0x2044, "euro": 0x20AC, "trade": 0x2122, "larr": 0x2190, "uarr": 0x2191,
        "rarr": 0x2192, "darr": 0x2193, "harr": 0x2194, "lArr": 0x21D0, "rArr": 0x21D2, "hArr": 0x21D4, "minus": 0x2212,
        "lowast": 0x2217, "radic": 0x221A, "infin": 0x221E, "asymp": 0x2248, "ne": 0x2260, "equiv": 0x2261, "le": 0x2264, "ge": 0x2265,
        "sdot": 0x22C5, "loz": 0x25CA, "starf": 0x2605, "star": 0x2606, "spades": 0x2660, "clubs": 0x2663, "hearts": 0x2665,
        "diams": 0x2666, "check": 0x2713, "cross": 0x2717,
    ]

    /// The longest name in `named`, which bounds the look-ahead of the decoder.
    static let longestName = named.keys.map(\.count).max() ?? 0

    /// The replacement for numeric references to invalid code points.
    static let replacementCharacter: Unicode.Scalar = "\u{FFFD}"

    /// Decodes the character reference starting at `scalars[index]`, which must be `&`.
    ///
    /// Named references need their `;`; numeric ones may omit it. Numeric references to
    /// zero, surrogates or values beyond U+10FFFF decode as U+FFFD.
    ///
    /// - Returns: The decoded scalar and the number of scalars consumed, or `nil` when the
    ///   text is not a known reference (the `&` is then literal text).
    static func decode(_ scalars: [Unicode.Scalar], at index: Int) -> (scalar: Unicode.Scalar, length: Int)? {
        let next = index + 1
        guard next < scalars.count else { return nil }
        if scalars[next] == "#" {
            return decodeNumeric(scalars, at: index)
        }
        var name = ""
        var cursor = next
        while cursor < scalars.count, name.unicodeScalars.count < longestName, isASCIIAlphanumeric(scalars[cursor]) {
            name.unicodeScalars.append(scalars[cursor])
            cursor += 1
        }
        guard cursor < scalars.count, scalars[cursor] == ";", let value = named[name], let scalar = Unicode.Scalar(value) else {
            return nil
        }
        return (scalar, cursor - index + 1)
    }

    private static func decodeNumeric(_ scalars: [Unicode.Scalar], at index: Int) -> (scalar: Unicode.Scalar, length: Int)? {
        var cursor = index + 2
        var radix: UInt32 = 10
        if cursor < scalars.count, scalars[cursor] == "x" || scalars[cursor] == "X" {
            radix = 16
            cursor += 1
        }
        var value: UInt32 = 0
        var digits = 0
        while cursor < scalars.count, let digit = digitValue(scalars[cursor], radix: radix) {
            // Saturate instead of overflowing; anything above U+10FFFF is invalid anyway.
            value = min(value &* radix &+ digit, 0x110000)
            digits += 1
            cursor += 1
        }
        guard digits > 0 else { return nil }
        if cursor < scalars.count, scalars[cursor] == ";" {
            cursor += 1
        }
        let scalar = value == 0 ? replacementCharacter : Unicode.Scalar(value) ?? replacementCharacter
        return (scalar, cursor - index)
    }

    private static func digitValue(_ scalar: Unicode.Scalar, radix: UInt32) -> UInt32? {
        switch scalar.value {
        case 0x30...0x39:
            scalar.value - 0x30
        case 0x41...0x46 where radix == 16:
            scalar.value - 0x41 + 10
        case 0x61...0x66 where radix == 16:
            scalar.value - 0x61 + 10
        default:
            nil
        }
    }

    /// Whether `scalar` is `[A-Za-z0-9]`.
    static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0x30...0x39, 0x41...0x5A, 0x61...0x7A: true
        default: false
        }
    }
}
