import Mojo

@mojo(
    package: "KuyuCanonicalDynamics",
    function: "execute_graph_float32"
)
func executeCanonicalGraphFloat32(
    _ input: [Float],
    into output: inout [Float]
) throws
