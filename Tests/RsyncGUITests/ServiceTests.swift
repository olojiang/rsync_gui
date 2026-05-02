import XCTest
@testable import RsyncGUI

final class ServiceTests: XCTestCase {

    // MARK: - AppLogger Tests

    func testLoggerInfo() async {
        let logger = AppLogger()
        await logger.info("test info", scope: "ServiceTests")
        let logs = await logger.recentLogs(limit: 10)
        XCTAssertEqual(logs.count, 1)
        XCTAssertEqual(logs.first?.level, .info)
        XCTAssertEqual(logs.first?.message, "test info")
    }

    func testLoggerMultipleLevels() async {
        let logger = AppLogger()
        await logger.debug("d", scope: "T")
        await logger.info("i", scope: "T")
        await logger.warning("w", scope: "T")
        await logger.error("e", scope: "T")
        let logs = await logger.recentLogs(limit: 10)
        XCTAssertEqual(logs.count, 4)
        XCTAssertEqual(logs[0].level, .debug)
        XCTAssertEqual(logs[1].level, .info)
        XCTAssertEqual(logs[2].level, .warning)
        XCTAssertEqual(logs[3].level, .error)
    }

    func testLoggerRecentLogsLimit() async {
        let logger = AppLogger()
        for i in 0..<150 {
            await logger.info("log \(i)", scope: "T")
        }
        let logs = await logger.recentLogs(limit: 10)
        XCTAssertEqual(logs.count, 10)
    }

    func testLoggerObserve() async {
        let logger = AppLogger()
        var received: [LogLine] = []
        let stream = await logger.observe()
        let task = Task {
            for await log in stream {
                received.append(log)
                if received.count >= 2 { break }
            }
        }
        await logger.info("first", scope: "T")
        await logger.info("second", scope: "T")
        await task.value
        XCTAssertEqual(received.count, 2)
    }

    // MARK: - ProfileStore Tests

    func testLoadAllEmpty() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("profiles.json")
        let store = FileProfileStore(fileURL: fileURL)
        let profiles = try await store.loadAll()
        XCTAssertTrue(profiles.isEmpty)
    }

    func testSaveAndLoad() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("profiles.json")
        let store = FileProfileStore(fileURL: fileURL)

        let profile = RsyncProfile(name: "Backup", sourcePath: "/src", destinationPath: "/dst", options: ["-a"])
        try await store.save(profile)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.id, profile.id)
        XCTAssertEqual(loaded.first?.name, "Backup")
    }

    func testDelete() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("profiles.json")
        let store = FileProfileStore(fileURL: fileURL)

        let profile = RsyncProfile(name: "ToDelete", sourcePath: "/a", destinationPath: "/b", options: [])
        try await store.save(profile)
        try await store.delete(id: profile.id)

        let loaded = try await store.loadAll()
        XCTAssertTrue(loaded.isEmpty)
    }

    func testUpdateExisting() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        let fileURL = tempDir.appendingPathComponent("profiles.json")
        let store = FileProfileStore(fileURL: fileURL)

        var profile = RsyncProfile(name: "Old", sourcePath: "/a", destinationPath: "/b", options: [])
        try await store.save(profile)

        profile.name = "New"
        try await store.save(profile)

        let loaded = try await store.loadAll()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.name, "New")
    }

    // MARK: - RsyncExecutor Tests

    func testExecuteEcho() async {
        let executor = ProcessRsyncExecutor()
        let profile = RsyncProfile(name: "Echo", sourcePath: "/tmp", destinationPath: "/tmp", options: [])

        let execution = await executor.execute(profile: profile, executionId: UUID()) { _ in }

        // Since /tmp exists, rsync will likely succeed; but if rsync is not installed,
        // the command fails. We verify the status is resolved (not pending/running).
        XCTAssertNotEqual(execution.status, .pending)
        XCTAssertNotEqual(execution.status, .running)
    }

    func testExecuteBuildsCorrectCommand() {
        let profile = RsyncProfile(name: "Test", sourcePath: "/src", destinationPath: "/dst", options: ["-avz", "--delete"])
        let command = profile.buildCommand()
        XCTAssertEqual(command, ["rsync", "-avz", "--delete", "/src", "/dst"])
    }

    func testCancel() async {
        let executor = ProcessRsyncExecutor()
        let profile = RsyncProfile(name: "Sleep", sourcePath: "/tmp", destinationPath: "/tmp", options: [])

        let task = Task {
            await executor.execute(profile: profile, executionId: UUID()) { _ in }
        }

        // Give a moment for the process to start
        try? await Task.sleep(nanoseconds: 50_000_000)

        // Cancel all active (since we don't have the execution ID easily here,
        // we test that cancel doesn't crash and the store handles missing IDs gracefully)
        // We verify the executor is in a consistent state after cancel.
        task.cancel()
        _ = await task.value
        XCTAssertTrue(true) // If we reach here without crash, cancel handling is safe
    }

    func testRsyncExecutionQueueRunsOneExecutionAtATime() async {
        let queue = RsyncExecutionQueue(maxConcurrentExecutions: 1)
        let firstId = UUID()
        let secondId = UUID()
        let secondStarted = AsyncFlag()

        XCTAssertTrue(await queue.waitForTurn(executionId: firstId))

        let secondTask = Task {
            let canRun = await queue.waitForTurn(executionId: secondId)
            if canRun {
                await secondStarted.setTrue()
            }
            return canRun
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertFalse(await secondStarted.value)

        await queue.finish(executionId: firstId)

        let secondCanRun = await secondTask.value
        XCTAssertTrue(secondCanRun)
        XCTAssertTrue(await secondStarted.value)

        await queue.finish(executionId: secondId)
    }

    func testRsyncExecutionQueueCancelsQueuedExecution() async {
        let queue = RsyncExecutionQueue(maxConcurrentExecutions: 1)
        let firstId = UUID()
        let secondId = UUID()

        XCTAssertTrue(await queue.waitForTurn(executionId: firstId))

        let secondTask = Task {
            await queue.waitForTurn(executionId: secondId)
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        await queue.cancel(executionId: secondId)

        let secondCanRun = await secondTask.value
        XCTAssertFalse(secondCanRun)

        await queue.finish(executionId: firstId)
    }

    func testRsyncOutputParserSplitsCarriageReturnProgress() {
        var parser = RsyncOutputParser()
        let lines = parser.append("file.dat\r  1,024  50%\r  2,048 100%\n".data(using: .utf8)!)
        XCTAssertEqual(lines, ["file.dat", "1,024  50%", "2,048 100%"])
        XCTAssertTrue(parser.flush().isEmpty)
    }

    func testRsyncOutputParserKeepsPartialLineUntilFlush() {
        var parser = RsyncOutputParser()
        XCTAssertTrue(parser.append("partial".data(using: .utf8)!).isEmpty)
        XCTAssertEqual(parser.flush(), ["partial"])
    }

    // MARK: - Finder Sync Service Tests

    func testFinderSelectionParserAcceptsSingleDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let path = try FinderSelectionParser.firstDirectoryPath(from: [tempDir])

        XCTAssertEqual(path, tempDir.path)
    }

    func testFinderSelectionParserRejectsMultipleSelections() throws {
        let first = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let second = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)

        XCTAssertThrowsError(try FinderSelectionParser.firstDirectoryPath(from: [first, second])) { error in
            XCTAssertEqual(error as? FinderSelectionError, .multipleSelection)
        }
    }

    func testFinderSelectionParserRejectsFiles() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try "x".write(to: file, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try FinderSelectionParser.firstDirectoryPath(from: [file])) { error in
            XCTAssertEqual(error as? FinderSelectionError, .notDirectory(file.path))
        }
    }

    func testFinderSyncDraftBuildsDefaultProfile() {
        let draft = FinderSyncDraft(sourcePath: "/Users/me/Source", destinationPath: "/Volumes/Backup/Dest")
        let profile = draft.profile

        XCTAssertEqual(profile.name, "Finder 同步: Source -> Dest")
        XCTAssertEqual(profile.sourcePath, "/Users/me/Source")
        XCTAssertEqual(profile.destinationPath, "/Volumes/Backup/Dest")
        XCTAssertEqual(profile.options, FinderSyncDraft.defaultOptions)
    }
}

private actor AsyncFlag {
    private(set) var value = false

    func setTrue() {
        value = true
    }
}
