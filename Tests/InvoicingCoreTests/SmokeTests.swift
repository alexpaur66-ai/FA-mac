import Testing
@testable import InvoicingCore

@Test("Core module links and reports its version")
func coreVersion() {
    #expect(InvoicingCore.version.hasPrefix("0.1.0"))
}
