import XCTest
@testable import RsyncGUI

// MARK: - Mocks

actor MockProfileStore: ProfileStoreProtocol {
    var profiles: [RsyncProfile] = []

    func loadAll() async throws -> [RsyncProfile] {
        profiles
    }

    func save(_ profile: RsyncProfile) async throws {
        if let index = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[index] = profile
        } else {
            profiles.append(profile)
        }
    }

    func delete(id: UUID) async throws {
        profiles.removeAll(where: { $0.id == id })
    }
}

actor MockRsyncExecutor: RsyncExecutorProtocol {
    var shouldSucceed = true
    var outputsToSend: [String] = []

    func execute(
        profile: RsyncProfile,
        executionId: UUID,
        onOutput: @escaping @Sendable (LogLine) -> Void
    ) async -> RsyncExecution {
        for output in outputsToSend {
            onOutput(LogLine(level: .info, message: output))
        }
        return RsyncExecution(
            id: executionId,
            profileId: profile.id,
            command: profile.buildCommand().joined(separator: " "),
            status: shouldSucceed ? .success : .failed,
            finishedAt: Date()
        )
    }

    func cancel(executionId: UUID) async {
        // no-op for mock
    }

    func cancelAll() async {
        // no-op for mock
    }
}

// MARK: - ProfileListViewModel Tests

@MainActor
final class ViewModelTests: XCTestCase {

    func testProfileListLoadEmpty() async {
        let store = MockProfileStore()
        let vm = ProfileListViewModel(store: store)
        await vm.loadProfiles()
        XCTAssertTrue(vm.profiles.isEmpty)
        XCTAssertNil(vm.errorMessage)
    }

    func testProfileListLoadWithData() async throws {
        let store = MockProfileStore()
        let profile = RsyncProfile(name: "Test", sourcePath: "/a", destinationPath: "/b", options: [])
        try await store.save(profile)

        let vm = ProfileListViewModel(store: store)
        await vm.loadProfiles()
        XCTAssertEqual(vm.profiles.count, 1)
        XCTAssertEqual(vm.profiles.first?.name, "Test")
    }

    func testProfileListDelete() async throws {
        let store = MockProfileStore()
        let profile = RsyncProfile(name: "DeleteMe", sourcePath: "/a", destinationPath: "/b", options: [])
        try await store.save(profile)

        let vm = ProfileListViewModel(store: store)
        await vm.loadProfiles()
        XCTAssertEqual(vm.profiles.count, 1)

        await vm.deleteProfile(id: profile.id)
        XCTAssertTrue(vm.profiles.isEmpty)
    }

    func testProfileListSelect() {
        let store = MockProfileStore()
        let vm = ProfileListViewModel(store: store)
        let id = UUID()
        vm.selectProfile(id: id)
        XCTAssertEqual(vm.selectedProfileId, id)
    }

    // MARK: - ProfileEditViewModel Tests

    func testEditViewModelNewProfile() {
        let store = MockProfileStore()
        let vm = ProfileEditViewModel(store: store)
        XCTAssertTrue(vm.profile.name.isEmpty)
        XCTAssertTrue(vm.profile.sourcePath.isEmpty)
        XCTAssertTrue(vm.profile.destinationPath.isEmpty)
        XCTAssertTrue(vm.isNew)
    }

    func testEditViewModelExistingProfile() {
        let store = MockProfileStore()
        let profile = RsyncProfile(name: "Existing", sourcePath: "/src", destinationPath: "/dst", options: ["-a"])
        let vm = ProfileEditViewModel(profile: profile, store: store)
        XCTAssertEqual(vm.profile.name, "Existing")
        XCTAssertFalse(vm.isNew)
    }

    func testEditViewModelSave() async {
        let store = MockProfileStore()
        let vm = ProfileEditViewModel(store: store)
        vm.profile.name = "NewProfile"
        vm.profile.sourcePath = "/src"
        vm.profile.destinationPath = "/dst"
        await vm.save()
        XCTAssertTrue(vm.saveSuccess)
        XCTAssertNil(vm.errorMessage)
    }

    func testEditViewModelUpdate() async throws {
        let store = MockProfileStore()
        var profile = RsyncProfile(name: "Old", sourcePath: "/a", destinationPath: "/b", options: [])
        try await store.save(profile)

        let vm = ProfileEditViewModel(profile: profile, store: store)
        vm.profile.name = "Updated"
        await vm.save()
        XCTAssertTrue(vm.saveSuccess)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.first?.name, "Updated")
    }

    // MARK: - ExecutionViewModel Tests

    func testExecutionSuccess() async {
        let executor = MockRsyncExecutor()
        executor.shouldSucceed = true
        executor.outputsToSend = ["file1", "file2"]

        let vm = ExecutionViewModel(executor: executor)
        let profile = RsyncProfile(name: "Test", sourcePath: "/a", destinationPath: "/b", options: [])

        await vm.execute(profile: profile)

        XCTAssertNotNil(vm.execution)
        XCTAssertEqual(vm.execution?.status, .success)
        XCTAssertEqual(vm.execution?.outputLines.count, 2)
        XCTAssertFalse(vm.isExecuting)
    }

    func testExecutionFailure() async {
        let executor = MockRsyncExecutor()
        executor.shouldSucceed = false

        let vm = ExecutionViewModel(executor: executor)
        let profile = RsyncProfile(name: "Test", sourcePath: "/a", destinationPath: "/b", options: [])

        await vm.execute(profile: profile)

        XCTAssertEqual(vm.execution?.status, .failed)
        XCTAssertFalse(vm.isExecuting)
    }

    func testExecutionCancel() async {
        let executor = MockRsyncExecutor()
        let vm = ExecutionViewModel(executor: executor)
        let profile = RsyncProfile(name: "Test", sourcePath: "/a", destinationPath: "/b", options: [])

        await vm.execute(profile: profile)
        XCTAssertNotNil(vm.execution)

        await vm.cancel()
        // Mock cancel is no-op, so we just verify no crash
        XCTAssertTrue(true)
    }
}
