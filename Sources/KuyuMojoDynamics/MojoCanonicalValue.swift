import KuyuPhysics

public enum MojoCanonicalValue: Sendable, Equatable {
    case scalar(Double)
    case vector3(SIMD3<Double>)
    case vector4(SIMD4<Double>)
    case quaternion(SIMD4<Double>)

    public var shape: CanonicalValueShape {
        switch self {
        case .scalar:
            .scalar
        case .vector3:
            .vector3
        case .vector4:
            .vector4
        case .quaternion:
            .quaternion
        }
    }

    func append(to values: inout [Double]) {
        switch self {
        case let .scalar(value):
            values.append(value)
        case let .vector3(value):
            values.append(value.x)
            values.append(value.y)
            values.append(value.z)
        case let .vector4(value), let .quaternion(value):
            values.append(value.x)
            values.append(value.y)
            values.append(value.z)
            values.append(value.w)
        }
    }

    func appendFloat32(to values: inout [Float]) -> Bool {
        let startCount = values.count
        switch self {
        case let .scalar(value):
            values.append(Float(value))
        case let .vector3(value):
            values.append(Float(value.x))
            values.append(Float(value.y))
            values.append(Float(value.z))
        case let .vector4(value), let .quaternion(value):
            values.append(Float(value.x))
            values.append(Float(value.y))
            values.append(Float(value.z))
            values.append(Float(value.w))
        }
        return values[startCount...].allSatisfy(\.isFinite)
    }

    var isFinite: Bool {
        switch self {
        case let .scalar(value):
            value.isFinite
        case let .vector3(value):
            value.x.isFinite && value.y.isFinite && value.z.isFinite
        case let .vector4(value), let .quaternion(value):
            value.x.isFinite && value.y.isFinite
                && value.z.isFinite && value.w.isFinite
        }
    }

    static func value<Element: BinaryFloatingPoint>(
        shape: CanonicalValueShape,
        elements: ArraySlice<Element>
    ) -> Self? {
        switch shape {
        case .scalar where elements.count == 1:
            .scalar(Double(elements[elements.startIndex]))
        case .vector3 where elements.count == 3:
            .vector3(
                SIMD3<Double>(
                    Double(elements[elements.startIndex]),
                    Double(
                        elements[elements.index(
                            elements.startIndex,
                            offsetBy: 1
                        )]
                    ),
                    Double(
                        elements[elements.index(
                            elements.startIndex,
                            offsetBy: 2
                        )]
                    )
                )
            )
        case .vector4 where elements.count == 4:
            .vector4(vector4(elements))
        case .quaternion where elements.count == 4:
            .quaternion(vector4(elements))
        default:
            nil
        }
    }

    private static func vector4<Element: BinaryFloatingPoint>(
        _ elements: ArraySlice<Element>
    ) -> SIMD4<Double> {
        SIMD4<Double>(
            Double(elements[elements.startIndex]),
            Double(
                elements[elements.index(elements.startIndex, offsetBy: 1)]
            ),
            Double(
                elements[elements.index(elements.startIndex, offsetBy: 2)]
            ),
            Double(
                elements[elements.index(elements.startIndex, offsetBy: 3)]
            )
        )
    }
}
