#if os(Windows)
import Foundation
import OpenUsageWindows

exit(await WindowsApp.run(arguments: Array(CommandLine.arguments.dropFirst())))
#endif
