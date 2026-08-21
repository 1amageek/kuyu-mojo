import Mojo

@mojo(
    package: "KuyuCanonicalDynamics",
    function: "execute_graph"
)
func executeCanonicalGraph(
    _ input: [Double],
    into output: inout [Double]
) throws
