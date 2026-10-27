import Foundation

/// What the `openusage` command was asked to do, parsed by hand: two flags and an optional provider
/// don't justify a dependency.
package enum LimitsArguments: Equatable {
    case limits(provider: String?, force: Bool)
    case help
    case version

    package struct Invalid: Error, Equatable {
        package let message: String
    }

    package static let usage = """
    Usage: openusage [provider] [--force]

    Prints the usage limits OpenUsage Light's accounts report, as JSON, and exits.

      provider     A provider (claude, codex, …) for every account of it, or one account's id from
                   the output's "order". Omit it for every account.
      --force      Refresh now instead of reusing results less than five minutes old.
      --help       Show this help.
      --version    Show the version.

    Exit codes: 0 success, 2 invalid arguments or unknown provider, 4 a refresh failed.
    """

    package static func parse(_ arguments: [String]) -> Result<LimitsArguments, Invalid> {
        var provider: String?
        var force = false
        for argument in arguments {
            switch argument {
            case "--help", "-h":
                return .success(.help)
            case "--version", "-v":
                return .success(.version)
            case "--force", "-f":
                force = true
            case _ where argument.hasPrefix("-"):
                return .failure(Invalid(message: "Unknown option \(argument)."))
            default:
                guard provider == nil else {
                    return .failure(Invalid(message: "Only one provider can be named."))
                }
                provider = argument
            }
        }
        return .success(.limits(provider: provider, force: force))
    }
}
