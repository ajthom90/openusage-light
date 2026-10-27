import Foundation
import OpenUsage

exit(await OpenUsageCommandLine.main(arguments: Array(CommandLine.arguments.dropFirst())))
