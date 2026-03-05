import XCTest
@testable import SolaceDaemon

final class WorkflowStepTests: XCTestCase {

    func testWorkflowStepCreation() {
        let step = WorkflowStep(
            id: "step-1",
            name: "Run Script",
            toolName: "run_command",
            serverName: "shell",
            inputTemplate: ["command": .literal("echo hello")],
            dependsOn: [],
            onError: .stop
        )

        XCTAssertEqual(step.id, "step-1")
        XCTAssertEqual(step.name, "Run Script")
        XCTAssertEqual(step.toolName, "run_command")
        XCTAssertEqual(step.serverName, "shell")
        XCTAssertEqual(step.onError, .stop)
    }

    func testWorkflowStepWithDependencies() {
        let step = WorkflowStep(
            id: "step-2",
            name: "Process Result",
            toolName: "process_data",
            serverName: "processor",
            inputTemplate: ["data": .template("{{step-1.$}}")],
            dependsOn: ["step-1"],
            onError: .skip
        )

        XCTAssertEqual(step.dependsOn, ["step-1"])
        XCTAssertEqual(step.onError, .skip)
    }

    func testWorkflowStepErrorPolicies() {
        // Test all error policy types are supported
        let stopPolicy = WorkflowStep(name: "N", toolName: "T", serverName: "S", inputTemplate: [:], dependsOn: [], onError: ErrorPolicy.stop)
        let skipPolicy = WorkflowStep(name: "N", toolName: "T", serverName: "S", inputTemplate: [:], dependsOn: [], onError: ErrorPolicy.skip)
        let retryPolicy = WorkflowStep(name: "N", toolName: "T", serverName: "S", inputTemplate: [:], dependsOn: [], onError: ErrorPolicy.retry)
        let autofixPolicy = WorkflowStep(name: "N", toolName: "T", serverName: "S", inputTemplate: [:], dependsOn: [], onError: ErrorPolicy.autofix)

        XCTAssertEqual(stopPolicy.onError, ErrorPolicy.stop)
        XCTAssertEqual(skipPolicy.onError, ErrorPolicy.skip)
        XCTAssertEqual(retryPolicy.onError, ErrorPolicy.retry)
        XCTAssertEqual(autofixPolicy.onError, ErrorPolicy.autofix)
    }
}
