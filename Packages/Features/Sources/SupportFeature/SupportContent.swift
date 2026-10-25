import BackendKit
import Foundation

// MARK: - SupportContact

/// The ways to reach KARINEX: exactly WhatsApp, e-mail and live chat (PROMPT.md 2). There is
/// no phone support, so there is no such channel here.
struct SupportContact: Sendable, Equatable {
    /// The WhatsApp link with the prefilled message, if the backend provides a number.
    let whatsApp: URL?
    /// The `mailto:` link with the prefilled subject.
    let email: URL?
    /// The live chat page, if the owner offers one.
    let liveChat: URL?
    /// The support e-mail address, shown as text.
    let emailAddress: String

    /// The contact options for `config`, with the order name in the messages when given.
    ///
    /// - Parameters:
    ///   - config: The remote config (or its fallback).
    ///   - orderName: The order the customer asks about, e.g. `#1042`.
    init(config: RemoteAppConfig, orderName: String?) {
        let orderName = orderName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        let message: String
        let subject: String
        if let orderName {
            message = String(localized: "support.whatsapp.message.order \(orderName)", bundle: .module)
            subject = String(localized: "support.email.subject.order \(orderName)", bundle: .module)
        } else {
            message = String(localized: "support.whatsapp.message", bundle: .module)
            subject = String(localized: "support.email.subject", bundle: .module)
        }
        whatsApp = config.whatsAppURL(message: message)
        email = Self.mailtoURL(address: config.supportEmail, subject: subject)
        liveChat = config.liveChatURL
        emailAddress = config.supportEmail
    }

    /// `mailto:<address>?subject=<subject>`, or `nil` for an address that is not plausible.
    static func mailtoURL(address: String, subject: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), !trimmed.contains(" "), !trimmed.contains("?") else { return nil }
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = trimmed
        components.queryItems = [URLQueryItem(name: "subject", value: subject)]
        return components.url
    }
}

// MARK: - SupportHoursText

/// The support hours as text in the user's locale, computed from times in Europe/Berlin.
enum SupportHoursText {
    /// "Montag bis Sonntag, 6:00 bis 23:00 Uhr (deutsche Zeit)" for the standard hours, or the
    /// times alone with the days left out when support is not open every day.
    static func text(for hours: SupportHours, on date: Date, locale: Locale) -> String {
        guard let interval = hours.interval(on: date) else { return "" }
        var style = Date.FormatStyle(date: .omitted, time: .shortened).locale(locale)
        style.timeZone = TimeZone(identifier: hours.timeZoneIdentifier) ?? .current
        let opens = interval.opens.formatted(style)
        let closes = interval.closes.formatted(style)
        if hours.isEveryDay {
            return String(localized: "support.hours.everyday \(opens) \(closes)", bundle: .module)
        }
        return String(localized: "support.hours.daily \(opens) \(closes)", bundle: .module)
    }
}

extension String {
    /// `nil` for an empty string.
    fileprivate var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
