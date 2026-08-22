import KuyuMojoTrainingRuntime
import Testing

@Suite("Mojo training worker bundle layout")
struct MojoTrainingWorkerBundleLayoutTests {
    @Test(.timeLimit(.minutes(1)))
    func rejectsAWorkerInsideTheAcceleratorRuntime() throws {
        #expect(
            throws: MojoTrainingWorkerBundleLayout.ValidationError
                .overlappingPaths(
                    workerExecutableRelativePath:
                        "AcceleratorRuntime/bin/canonical",
                    acceleratorRuntimeRelativePath: "AcceleratorRuntime"
                )
        ) {
            _ = try MojoTrainingWorkerBundleLayout(
                workerExecutableRelativePath:
                    "AcceleratorRuntime/bin/canonical",
                acceleratorRuntimeRelativePath: "AcceleratorRuntime"
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsWorkerPathTraversal() throws {
        #expect(
            throws: MojoTrainingWorkerBundleLayout.ValidationError
                .invalidWorkerExecutableRelativePath("../bin/worker")
        ) {
            _ = try MojoTrainingWorkerBundleLayout(
                workerExecutableRelativePath: "../bin/worker",
                acceleratorRuntimeRelativePath: "AcceleratorRuntime"
            )
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsAcceleratorRuntimePathTraversal() throws {
        #expect(
            throws: MojoTrainingWorkerBundleLayout.ValidationError
                .invalidAcceleratorRuntimeRelativePath(
                    "Runtimes/../../external"
                )
        ) {
            _ = try MojoTrainingWorkerBundleLayout(
                workerExecutableRelativePath: "bin/worker",
                acceleratorRuntimeRelativePath:
                    "Runtimes/../../external"
            )
        }
    }
}
