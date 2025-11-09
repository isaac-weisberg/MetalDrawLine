import UIKit

protocol DoubleMaths {
    static func + (lhs: Self, rhs: Self) -> Self
    static func - (lhs: Self, rhs: Self) -> Self
    static func * (lhs: Self, rhs: Self) -> Self
    static func / (lhs: Self, rhs: Self) -> Self
    static func + (lhs: Double, rhs: Self) -> Self
    static func - (lhs: Double, rhs: Self) -> Self
    static func * (lhs: Double, rhs: Self) -> Self
    static func / (lhs: Double, rhs: Self) -> Self
}

extension Double: DoubleMaths { }

extension Array<Double>: DoubleMaths {
    static func + (lhs: Double, rhs: Array<Element>) -> Array<Element> {
        rhs.map { val in val + lhs }
    }

    static func - (lhs: Double, rhs: Array<Element>) -> Array<Element> {
        rhs.map { val in val - lhs }
    }
    
    static func * (lhs: Double, rhs: Array<Element>) -> Array<Element> {
        rhs.map { val in val * lhs }
    }
    
    static func / (lhs: Double, rhs: Array<Element>) -> Array<Element> {
        rhs.map { val in val / lhs }
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
    }
    
    func value(at time: TimeInterval) -> Variable {
        let t = (time - startTime) / duration
        let curved = curve.value(t: t)
        
        let result = from + curved * range
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
