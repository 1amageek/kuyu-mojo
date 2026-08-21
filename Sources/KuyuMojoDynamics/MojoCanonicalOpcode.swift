import KuyuPhysics

enum MojoCanonicalOpcode: Int, Sendable {
    case constant = 0
    case add = 1
    case subtract = 2
    case multiply = 3
    case multiplyComponents = 4
    case divide = 5
    case divideComponents = 6
    case negate = 7
    case component = 8
    case composeVector3 = 9
    case cross3 = 10
    case length3 = 11
    case normalize3OrZero = 12
    case quaternionRotate3 = 13
    case quaternionInverseRotate3 = 14
    case quaternionDerivative = 15

    init(_ opcode: CanonicalOpcode) {
        switch opcode {
        case .constant:
            self = .constant
        case .add:
            self = .add
        case .subtract:
            self = .subtract
        case .multiply:
            self = .multiply
        case .multiplyComponents:
            self = .multiplyComponents
        case .divide:
            self = .divide
        case .divideComponents:
            self = .divideComponents
        case .negate:
            self = .negate
        case .component:
            self = .component
        case .composeVector3:
            self = .composeVector3
        case .cross3:
            self = .cross3
        case .length3:
            self = .length3
        case .normalize3OrZero:
            self = .normalize3OrZero
        case .quaternionRotate3:
            self = .quaternionRotate3
        case .quaternionInverseRotate3:
            self = .quaternionInverseRotate3
        case .quaternionDerivative:
            self = .quaternionDerivative
        }
    }
}
