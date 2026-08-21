import KuyuPhysics

public enum MojoFloat64Value: Sendable, Equatable {
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

    static func value(
        shape: CanonicalValueShape,
        elements: ArraySlice<Double>
    ) -> Self? {
        switch shape {
        case .scalar where elements.count == 1:
            .scalar(elements[elements.startIndex])
        case .vector3 where elements.count == 3:
            .vector3(
                SIMD3<Double>(
                    elements[elements.startIndex],
                    elements[elements.index(elements.startIndex, offsetBy: 1)],
                    elements[elements.index(elements.startIndex, offsetBy: 2)]
                )
            )
        case .vector4 where elements.count == 4:
            .vector4(
                SIMD4<Double>(
                    elements[elements.startIndex],
                    elements[elements.index(elements.startIndex, offsetBy: 1)],
                    elements[elements.index(elements.startIndex, offsetBy: 2)],
                    elements[elements.index(elements.startIndex, offsetBy: 3)]
                )
            )
        case .quaternion where elements.count == 4:
            .quaternion(
                SIMD4<Double>(
                    elements[elements.startIndex],
                    elements[elements.index(elements.startIndex, offsetBy: 1)],
                    elements[elements.index(elements.startIndex, offsetBy: 2)],
                    elements[elements.index(elements.startIndex, offsetBy: 3)]
                )
            )
        default:
            nil
        }
    }
}
