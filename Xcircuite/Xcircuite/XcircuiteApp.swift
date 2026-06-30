import SwiftUI
import struct CircuitStudioApp.CircuitStudioApp

@main
struct Xcircuite {
    typealias HostedApp = CircuitStudioApp

    static var hostedAppTypeName: String {
        String(describing: HostedApp.self)
    }

    static func main() {
        HostedApp.main()
    }
}
