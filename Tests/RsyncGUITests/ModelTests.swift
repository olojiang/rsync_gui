import XCTest
@testable import RsyncGUI

final class ModelTests: XCTestCase {

    // MARK: - TaskStatus Tests

    func testTaskStatusRawValues() {
        XCTAssertEqual(TaskStatus.pending.rawValue, "pending")
        XCTAssertEqual(TaskStatus.running.rawValue, "running")
        XCTAssertEqual(TaskStatus.success.rawValue, "success")
        XCTAssertEqual(TaskStatus.failed.rawValue, "failed")
        XCTAssertEqual(TaskStatus.cancelled.rawValue, "cancelled")
    }

    func testTaskStatusDecodable() throws {
        let json = "\"success\"".data(using: .utf8)!
        let status = try JSONDecoder().decode(TaskStatus.self, from: json)
        XCTAssertEqual(status, .success)
    }

    func testTaskStatusInvalidDecoding() {
        let json = "\"unknown\"".data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(TaskStatus.self, from: json))
    }

    // MARK: - LogLevel Tests

    func testLogLevelRawValues() {
        XCTAssertEqual(LogLevel.debug.rawValue, "debug")
        XCTAssertEqual(LogLevel.info.rawValue, "info")
        XCTAssertEqual(LogLevel.warning.rawValue, "warning")
        XCTAssertEqual(LogLevel.error.rawValue, "error")
    }

    // MARK: - LogLine Tests

    func testLogLineCreation() {
        let line = LogLine(level: .info, message: "test message")
        XCTAssertEqual(line.level, .info)
        XCTAssertEqual(line.message, "test message")
        XCTAssertFalse(line.id.uuidString.isEmpty)
    }

    func testLogLineEquatable() {
        let line1 = LogLine(level: .info, message: "same")
        let line2 = LogLine(id: line1.id, timestamp: line1.timestamp, level: .info, message: "same")
        XCTAssertEqual(line1, line2)
    }

    func testLogLineNotEqual() {
        let line1 = LogLine(level: .info, message: "a")
        let line2 = LogLine(level: .error, message: "a")
        XCTAssertNotEqual(line1, line2)
    }

    // MARK: - RsyncProfile Tests

    func testProfileCreation() {
        let profile = RsyncProfile(
            name: "Backup",
            sourcePath: "/Users/me/docs",
            destinationPath: "/Users/me/backup",
            options: ["-avz", "--delete"]
        )
        XCTAssertEqual(profile.name, "Backup")
        XCTAssertEqual(profile.sourcePath, "/Users/me/docs")
        XCTAssertEqual(profile.destinationPath, "/Users/me/backup")
        XCTAssertEqual(profile.options, ["-avz", "--delete"])
        XCTAssertFalse(profile.id.uuidString.isEmpty)
        XCTAssertEqual(profile.createdAt, profile.updatedAt)
    }

    func testProfileCodableRoundTrip() throws {
        let original = RsyncProfile(
            name: "Test",
            sourcePath: "/src",
            destinationPath: "/dst",
            options: ["-a"]
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(RsyncProfile.self, from: data)

        XCTAssertEqual(original.id, decoded.id)
        XCTAssertEqual(original.name, decoded.name)
        XCTAssertEqual(original.sourcePath, decoded.sourcePath)
        XCTAssertEqual(original.destinationPath, decoded.destinationPath)
        XCTAssertEqual(original.options, decoded.options)
        XCTAssertEqual(original.createdAt, decoded.createdAt)
        XCTAssertEqual(original.updatedAt, decoded.updatedAt)
    }

    func testProfileEquatable() {
        let profile1 = RsyncProfile(name: "A", sourcePath: "/a", destinationPath: "/b", options: ["-a"])
        let profile2 = RsyncProfile(id: profile1.id, name: "A", sourcePath: "/a", destinationPath: "/b", options: ["-a"], createdAt: profile1.createdAt, updatedAt: profile1.updatedAt)
        XCTAssertEqual(profile1, profile2)
    }

    func testProfileBuildCommand() {
        let profile = RsyncProfile(
            name: "Sync",
            sourcePath: "/source",
            destinationPath: "/dest",
            options: ["-avz", "--delete"]
        )
        let command = profile.buildCommand()
        XCTAssertEqual(command, ["rsync", "-avz", "--delete", "/source", "/dest"])
    }

    func testProfileBuildCommandWithEmptyOptions() {
        let profile = RsyncProfile(
            name: "Sync",
            sourcePath: "/source",
            destinationPath: "/dest",
            options: []
        )
        let command = profile.buildCommand()
        XCTAssertEqual(command, ["rsync", "/source", "/dest"])
    }

    func testOptionPresetsIncludeTwitterScriptMode() {
        let preset = RsyncOptionPreset.allPresets.first { $0.name == "增量更新（脚本同款）" }
        XCTAssertEqual(preset?.options, ["-a", "--human-readable", "--info=progress2"])
    }

    func testOptionPresetsAreGroupedInDisplayOrder() {
        let groupNames = RsyncOptionPreset.groupedPresets.map(\.name)
        XCTAssertEqual(groupNames, ["自定义", "本地同步", "镜像删除", "备份保留", "测试检查", "远程 SSH", "大文件/恢复"])
    }

    // MARK: - RsyncExecution Tests

    func testExecutionCreation() {
        let profileId = UUID()
        let execution = RsyncExecution(profileId: profileId, command: "rsync -a /src /dst")
        XCTAssertEqual(execution.profileId, profileId)
        XCTAssertEqual(execution.command, "rsync -a /src /dst")
        XCTAssertEqual(execution.status, .pending)
        XCTAssertTrue(execution.outputLines.isEmpty)
        XCTAssertNil(execution.finishedAt)
    }

    func testExecutionStatusTransition() {
        let execution = RsyncExecution(profileId: UUID(), command: "rsync -a /src /dst")
        var mutable = execution
        mutable.status = .running
        XCTAssertEqual(mutable.status, .running)
        mutable.status = .success
        XCTAssertEqual(mutable.status, .success)
        mutable.finishedAt = Date()
        XCTAssertNotNil(mutable.finishedAt)
    }

    func testExecutionAppendLog() {
        var execution = RsyncExecution(profileId: UUID(), command: "rsync -a /src /dst")
        let line = LogLine(level: .info, message: "sending file")
        execution.outputLines.append(line)
        XCTAssertEqual(execution.outputLines.count, 1)
        XCTAssertEqual(execution.outputLines.first?.message, "sending file")
    }
}
