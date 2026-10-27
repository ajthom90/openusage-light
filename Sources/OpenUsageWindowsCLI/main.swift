#if os(Windows)
import Foundation
import OpenUsageWindows

exit(await WindowsCommandLine.main(arguments: Array(CommandLine.arguments.dropFirst())))
#endif
