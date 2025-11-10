import UIKit

protocol DoubleMaths {
    static func + (lhs: Self, rhs: Self) -> Self
    static func - (lhs: Self, rhs: Self) -> Self
    static func * (lhs: Self, rhs: Self) -> Self
    static func / (lhs: Self, rhs: Self) -> Self
    
    static func mult(_ lhs: Double, _ rhs: Self) -> Self
}

extension Float: DoubleMaths {
    static func mult(_ lhs: Double, _ rhs: Float) -> Float {
        Float(lhs) * rhs
    }
}

extension Double: DoubleMaths {
    static func mult(_ lhs: Double, _ rhs: Double) -> Double {
        lhs * rhs
    }
}

extension Array: DoubleMaths where Element: DoubleMaths {
    static func mult (_ lhs: Double, _ rhs: Array<Element>) -> Array<Element> {
        rhs.map { val in Element.mult(lhs, val) }
    }

    static func + (lhs: Array<Element>, rhs: Array<Element>) -> Array<Element> {
        assert(lhs.count == rhs.count)
        
        return zip(lhs, rhs).map(+)
    }
    static func - (lhs: Array<Element>, rhs: Array<Element>) -> Array<Element> {
        assert(lhs.count == rhs.count)
        return zip(lhs, rhs).map(-)
    }
    
    static func * (lhs: Array<Element>, rhs: Array<Element>) -> Array<Element> {
        assert(lhs.count == rhs.count)
        return zip(lhs, rhs).map(*)
    }
    
    static func / (lhs: Array<Element>, rhs: Array<Element>) -> Array<Element> {
        assert(lhs.count == rhs.count)
        return zip(lhs, rhs).map(/)
    }
}

struct VariableAnimation<Variable: DoubleMaths>: ~Copyable {
    let startTime: TimeInterval
    let duration: Double
    let endTime: Double
    let from: Variable
    let to: Variable
    let range: Variable
    let curve: Curve
    
    init(
        startTime: TimeInterval,
        duration: Double,
        from: Variable,
        to: Variable,
        curve: Curve
    ) {
        self.startTime = startTime
        self.duration = duration
        self.from = from
        self.to = to
        self.curve = curve
        
        self.range = to - from
        self.endTime = startTime + duration
    }
    
    func value(at time: TimeInterval) -> Variable {
        let t = (time - startTime) / duration
        let curved = curve.value(t: t)
        
        let result = from + Variable.mult(curved, range)
        return result
    }
}

enum Curve {
    case linear
    case easeInEaseOut
    
    func value(t: Double) -> Double {
        switch self {
            case .linear:
                return t
            case .easeInEaseOut:
                let tSquare = t * t

                return tSquare / (2.0 * (tSquare - t) + 1.0)
        }
    }
}
