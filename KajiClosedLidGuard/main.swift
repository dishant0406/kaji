import ClosedLidCore
import Darwin
import Foundation

func parseParentPID(arguments: [String]) -> pid_t? {
    guard arguments.count == 2,
          arguments[0] == "--parent-pid",
          let value = Int32(arguments[1]),
          value > 1
    else { return nil }
    return value
}

guard let parentPID = parseParentPID(arguments: Array(CommandLine.arguments.dropFirst())) else {
    Darwin.exit(64)
}

let session = ClosedLidGuardSession(driver: IOPMRootDomainClosedLidSelectorDriver())
let runtime = ClosedLidGuardRuntime(parentPID: parentPID, session: session)
Darwin.exit(runtime.run())
