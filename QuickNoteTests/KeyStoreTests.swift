import Testing
@testable import QuickNote

@MainActor
struct KeyStoreTests {
    @Test func startsWithoutAKey() throws {
        let store = InMemoryKeyStore()
        #expect(!store.hasKey())
        #expect(try store.read() == nil)
    }

    @Test func savedKeyCanBeRead() throws {
        let store = InMemoryKeyStore()
        try store.save("abc123")
        #expect(store.hasKey())
        #expect(try store.read() == "abc123")
    }

    @Test func savingReplacesTheKeyAndTrimsWhitespace() throws {
        let store = InMemoryKeyStore(key: "old")
        try store.save("  new-key \n")
        #expect(try store.read() == "new-key")
    }

    @Test func aBlankKeyIsRefusedAndTheOldOneKept() throws {
        let store = InMemoryKeyStore(key: "old")
        #expect(throws: KeyStoreError.empty) { try store.save("  \n") }
        #expect(try store.read() == "old")
    }

    @Test func deletingRemovesTheKey() throws {
        let store = InMemoryKeyStore(key: "old")
        try store.delete()
        #expect(!store.hasKey())
        #expect(try store.read() == nil)
        try store.delete()
    }
}
