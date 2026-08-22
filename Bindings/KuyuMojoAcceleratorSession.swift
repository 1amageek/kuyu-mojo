import Mojo

@mojo(
  package: "KuyuAcceleratorSession",
  function: "create_accelerator_session",
  shutdown: "shutdown_accelerator_session"
)
func createKuyuMojoAcceleratorSession(
  _ requirements: MojoSessionRequirements
) throws -> MojoSessionOwner

@mojo(
  package: "KuyuAcceleratorSession",
  function: "execute_graph_float32_accelerator_session",
  sessionFactory: "createKuyuMojoAcceleratorSession"
)
func executeKuyuMojoAcceleratorBatch(
  _ session: MojoSessionOwner,
  _ request: [Float],
  into workspaces: inout [Float]
) throws
