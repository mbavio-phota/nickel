import XCTest

@testable import ConductorMobile

/// Round-trips a real Keychain item inside the test host app. This is the regression test
/// for the signed-in-but-couldn't-save bug: an unsigned app (no application identifier)
/// gets errSecMissingEntitlement (-34018) from SecItemAdd, so this test only passes when
/// the app is signed (ad-hoc `CODE_SIGN_IDENTITY: "-"` or better).
final class KeychainStoreTests: XCTestCase {
    private let store = KeychainStore(service: "dev.mrbavio.conductor-mobile.tests", account: "apiKey")

    override func tearDown() {
        try? store.delete()
    }

    func testSaveReadUpdateDeleteRoundTrip() throws {
        XCTAssertNil(try store.read())

        try store.save("cond_first")
        XCTAssertEqual(try store.read(), "cond_first")

        try store.save("cond_second")
        XCTAssertEqual(try store.read(), "cond_second")

        try store.delete()
        XCTAssertNil(try store.read())

        // Deleting again is a documented no-op, not an error.
        XCTAssertNoThrow(try store.delete())
    }
}
