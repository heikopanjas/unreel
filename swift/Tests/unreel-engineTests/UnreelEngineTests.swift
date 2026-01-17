import Testing
@testable import unreel_engine

@Test func libraryVersion() async throws {
    #expect(unreelEngineVersion == "0.1.0")
}
