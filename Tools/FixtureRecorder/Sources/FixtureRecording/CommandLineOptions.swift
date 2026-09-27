import Core
import Foundation
import ShopifyKit

/// The parsed command line of `fixture-recorder`.
///
///     fixture-recorder [--shop-domain 45dv93-bk.myshopify.com] [--api-version 2026-07]
///                      [--token <token>] --output <dir>
public struct CommandLineOptions: Sendable, Equatable {
    /// The myshopify domain of the store.
    public var shopDomain: String
    /// The Storefront API version.
    public var apiVersion: String
    /// The public Storefront token, or `nil` to record tokenless.
    public var token: String?
    /// The directory the fixtures are written to.
    public var outputDirectory: URL

    /// The live store's myshopify domain.
    public static let defaultShopDomain = AppConfiguration.preview.shopDomain
    /// The pinned Storefront API version.
    public static let defaultAPIVersion = AppConfiguration.preview.storefrontAPIVersion

    /// The usage text printed by `--help` and on errors.
    public static let usage = """
        Usage: fixture-recorder [--shop-domain <domain>] [--api-version <version>] [--token <token>] --output <dir>

        Records the ShopifyKit test fixtures from the live Storefront API.

          --shop-domain   myshopify domain (default: \(defaultShopDomain))
          --api-version   Storefront API version (default: \(defaultAPIVersion))
          --token         public Storefront access token (default: none, tokenless)
                          Also read from the KX_STOREFRONT_TOKEN environment variable.
          --output        directory for the fixture files and manifest.json (required)
          --help          print this text
        """

    /// Creates options.
    public init(shopDomain: String, apiVersion: String, token: String?, outputDirectory: URL) {
        self.shopDomain = shopDomain
        self.apiVersion = apiVersion
        self.token = token
        self.outputDirectory = outputDirectory
    }

    /// The Storefront configuration for these options.
    public var storefrontConfiguration: StorefrontConfiguration {
        var components = URLComponents()
        components.scheme = "https"
        components.host = shopDomain
        components.path = "/api/\(apiVersion)/graphql.json"
        // Both parts were validated in `parse`, so the URL can always be formed.
        let endpoint = components.url ?? URL(fileURLWithPath: "/")
        return StorefrontConfiguration(endpoint: endpoint, accessToken: token, apiVersion: apiVersion)
    }

    // MARK: - Parsing

    /// Why the command line was rejected.
    public enum ParseError: Error, Equatable, CustomStringConvertible {
        /// `--help` was given.
        case helpRequested
        /// An option needs a value but none followed.
        case missingValue(option: String)
        /// An option is not known.
        case unknownOption(String)
        /// `--output` is missing.
        case missingOutput
        /// A value is invalid.
        case invalidValue(option: String, value: String)

        /// A one-line English message.
        public var description: String {
            switch self {
            case .helpRequested: "Help requested."
            case let .missingValue(option): "Missing value for \(option)."
            case let .unknownOption(option): "Unknown option \(option)."
            case .missingOutput: "The --output directory is required."
            case let .invalidValue(option, value): "Invalid value for \(option): \(value)"
            }
        }
    }

    /// Parses `arguments` (without the executable name).
    ///
    /// - Parameters:
    ///   - arguments: The command line arguments.
    ///   - environment: The process environment; `KX_STOREFRONT_TOKEN` supplies a token when
    ///     `--token` is absent, which keeps the token out of the shell history.
    ///   - currentDirectory: The directory relative output paths are resolved against.
    public static func parse(
        _ arguments: [String],
        environment: [String: String] = [:],
        currentDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    ) throws(ParseError) -> CommandLineOptions {
        var shopDomain = defaultShopDomain
        var apiVersion = defaultAPIVersion
        var token = environment["KX_STOREFRONT_TOKEN"]
        var output: String?

        var iterator = arguments.makeIterator()
        while let argument = iterator.next() {
            switch argument {
            case "--help", "-h":
                throw .helpRequested
            case "--shop-domain", "--api-version", "--token", "--output":
                guard let value = iterator.next(), !value.hasPrefix("--") else {
                    throw .missingValue(option: argument)
                }
                switch argument {
                case "--shop-domain": shopDomain = value.lowercased()
                case "--api-version": apiVersion = value
                case "--token": token = value
                default: output = value
                }
            default:
                throw .unknownOption(argument)
            }
        }

        guard AppConfiguration.isValidHost(shopDomain) else {
            throw .invalidValue(option: "--shop-domain", value: shopDomain)
        }
        guard AppConfiguration.isValidAPIVersion(apiVersion) else {
            throw .invalidValue(option: "--api-version", value: apiVersion)
        }
        guard let output, !output.isEmpty else { throw .missingOutput }

        let trimmedToken = token?.trimmingCharacters(in: .whitespacesAndNewlines)
        let outputDirectory = output.hasPrefix("/")
            ? URL(fileURLWithPath: output, isDirectory: true)
            : currentDirectory.appendingPathComponent(output, isDirectory: true)
        return CommandLineOptions(
            shopDomain: shopDomain,
            apiVersion: apiVersion,
            token: (trimmedToken?.isEmpty ?? true) ? nil : trimmedToken,
            outputDirectory: outputDirectory.standardizedFileURL
        )
    }
}
