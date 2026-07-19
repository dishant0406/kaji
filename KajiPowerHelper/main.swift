import Foundation
import KajiPowerHelperProtocol

final class PowerHelperListenerDelegate: NSObject, NSXPCListenerDelegate {
    private let service: PowerHelperService
    private let clientRequirement: String

    init(service: PowerHelperService, clientRequirement: String) {
        self.service = service
        self.clientRequirement = clientRequirement
    }

    func listener(_: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.setCodeSigningRequirement(clientRequirement)
        connection.exportedInterface = NSXPCInterface(with: KajiPowerHelperXPCProtocol.self)
        connection.exportedObject = service
        connection.activate()
        return true
    }
}

guard let clientRequirement = currentKajiClientRequirement() else {
    fputs("KajiPowerHelper could not verify its containing Kaji app.\n", stderr)
    exit(EXIT_FAILURE)
}

let service = PowerHelperService()
guard service.restoreAtStartup() else {
    fputs("KajiPowerHelper could not restore normal sleep at startup.\n", stderr)
    exit(EXIT_FAILURE)
}

let delegate = PowerHelperListenerDelegate(service: service, clientRequirement: clientRequirement)
let watchdog = DispatchSource.makeTimerSource(queue: .global(qos: .utility))
watchdog.schedule(deadline: .now() + 5, repeating: 5)
watchdog.setEventHandler { [service] in
    service.watchdogTick()
}

watchdog.resume()
let listener = NSXPCListener(machServiceName: kajiPowerHelperMachServiceName)
listener.delegate = delegate
listener.resume()
RunLoop.current.run()
