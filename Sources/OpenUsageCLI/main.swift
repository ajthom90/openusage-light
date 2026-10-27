import Foundation
import OpenUsage

exit(await LimitsCommand.main(arguments: Array(CommandLine.arguments.dropFirst())))
