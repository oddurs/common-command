import Foundation

/// Arithmetic typed into the search field: + − × ÷ ^, parentheses, percent, factorial, and a few
/// functions and constants. A hand-written parser, so malformed input fails quietly instead of raising
/// the Objective-C exceptions `NSExpression` throws.
public enum Calculator {
    static let functions: [String: @Sendable (Double) -> Double] = [
        "sqrt": { $0.squareRoot() }, "cbrt": { cbrt($0) }, "abs": { abs($0) },
        "sin": { sin($0) }, "cos": { cos($0) }, "tan": { tan($0) },
        "asin": { asin($0) }, "acos": { acos($0) }, "atan": { atan($0) },
        "ln": { log($0) }, "log": { log10($0) }, "log2": { log2($0) }, "exp": { exp($0) },
        "round": { $0.rounded() }, "floor": { floor($0) }, "ceil": { ceil($0) },
    ]
    static let constants: [String: Double] = ["pi": .pi, "π": .pi, "e": M_E, "tau": 2 * .pi, "τ": 2 * .pi]

    /// The value of `input`, or nil when it isn't arithmetic. A bare number isn't: the field is for
    /// searching, and "2024" or "1Password" shouldn't turn the top result into a calculation.
    public static func evaluate(_ input: String, locale: Locale = .current) -> Double? {
        value(of: input, locale: locale, requiringOperation: true)
    }

    /// `requiringOperation: false` accepts a bare number too, for the amount in "10 km to mi".
    static func value(of input: String, locale: Locale, requiringOperation: Bool) -> Double? {
        let decimal = Character(locale.decimalSeparator ?? ".")
        guard let tokens = tokenize(input, decimalSeparator: decimal),
            !requiringOperation || tokens.contains(where: \.isOperation), tokens.contains(where: \.isNumber)
        else { return nil }
        var parser = Parser(tokens: tokens)
        guard let value = parser.parseExpression(), parser.atEnd, value.isFinite else { return nil }
        return value
    }

    /// The value as people read it in their region, with up to `digits` significant digits.
    public static func format(_ value: Double, locale: Locale = .current, grouping: Bool = true, digits: Int = 12)
        -> String
    {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.usesSignificantDigits = true
        formatter.maximumSignificantDigits = digits
        formatter.usesGroupingSeparator = grouping
        let magnitude = abs(value)
        formatter.numberStyle = magnitude != 0 && (magnitude >= 1e15 || magnitude < 1e-9) ? .scientific : .decimal
        // Rounding error shouldn't show as -0.
        return formatter.string(from: NSNumber(value: value == 0 ? 0 : value)) ?? String(value)
    }

    enum Token: Equatable {
        case number(Double)
        case name(String)
        case op(Character)
        case open, close

        var isNumber: Bool {
            if case .number = self { return true }
            return false
        }

        var isOperation: Bool {
            switch self {
            case .op: true
            case .name(let name): functions[name] != nil
            default: false
            }
        }
    }

    static func tokenize(_ input: String, decimalSeparator: Character) -> [Token]? {
        var tokens: [Token] = []
        let chars = Array(input)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace {
                i += 1
            } else if c.isASCII && c.isNumber || c == "." || c == decimalSeparator {
                var digits = ""
                var seenPoint = false
                while i < chars.count {
                    let d = chars[i]
                    if d.isASCII && d.isNumber {
                        digits.append(d)
                    } else if (d == "." || d == decimalSeparator) && !seenPoint {
                        seenPoint = true
                        digits.append(".")
                    } else if d == "," && decimalSeparator == "." && i + 1 < chars.count && chars[i + 1].isNumber {
                        // A thousands separator, as in 1,000.
                    } else {
                        break
                    }
                    i += 1
                }
                guard let value = Double(digits) else { return nil }
                tokens.append(.number(value))
            } else if c.isLetter {
                var name = ""
                while i < chars.count && (chars[i].isLetter || chars[i].isNumber && !name.isEmpty) {
                    name.append(contentsOf: chars[i].lowercased())
                    i += 1
                }
                guard functions[name] != nil || constants[name] != nil else { return nil }
                tokens.append(.name(name))
            } else {
                switch c {
                case "+", "-", "−", "*", "×", "·", "/", "÷", "^", "%", "!":
                    let normal: [Character: Character] = ["−": "-", "×": "*", "·": "*", "÷": "/"]
                    tokens.append(.op(normal[c] ?? c))
                case "(": tokens.append(.open)
                case ")": tokens.append(.close)
                default: return nil
                }
                i += 1
            }
        }
        return tokens
    }

    struct Parser {
        let tokens: [Token]
        var index = 0
        var depth = 0

        var atEnd: Bool { index == tokens.count }
        var peek: Token? { index < tokens.count ? tokens[index] : nil }

        mutating func take(_ token: Token) -> Bool {
            guard peek == token else { return false }
            index += 1
            return true
        }

        // expression := term (('+' | '-') term)*
        mutating func parseExpression() -> Double? {
            depth += 1
            defer { depth -= 1 }
            guard depth < 64, var value = parseTerm() else { return nil }
            while true {
                if take(.op("+")) {
                    guard let rhs = parseTerm() else { return nil }
                    value += rhs
                } else if take(.op("-")) {
                    guard let rhs = parseTerm() else { return nil }
                    value -= rhs
                } else {
                    return value
                }
            }
        }

        // term := unary (('*' | '/') unary | implicit unary)*, where "2pi" and "3(4+5)" multiply. Two
        // numbers in a row don't: "1..2" is a typo, not 1 × .2.
        mutating func parseTerm() -> Double? {
            guard var value = parseUnary() else { return nil }
            while true {
                if take(.op("*")) {
                    guard let rhs = parseUnary() else { return nil }
                    value *= rhs
                } else if take(.op("/")) {
                    guard let rhs = parseUnary(), rhs != 0 else { return nil }
                    value /= rhs
                } else if let next = peek, next == .open || isName(next) {
                    guard let rhs = parsePower() else { return nil }
                    value *= rhs
                } else {
                    return value
                }
            }
        }

        func isName(_ token: Token) -> Bool {
            if case .name = token { return true }
            return false
        }

        // unary := ('-' | '+') unary | power, so -2^2 is -4 as on paper.
        mutating func parseUnary() -> Double? {
            if take(.op("-")) { return parseUnary().map { -$0 } }
            if take(.op("+")) { return parseUnary() }
            return parsePower()
        }

        // power := postfix ('^' unary)?, right-associative.
        mutating func parsePower() -> Double? {
            guard let base = parsePostfix() else { return nil }
            guard take(.op("^")) else { return base }
            guard let exponent = parseUnary() else { return nil }
            return pow(base, exponent)
        }

        // postfix := primary ('%' | '!')*
        mutating func parsePostfix() -> Double? {
            guard var value = parsePrimary() else { return nil }
            while true {
                if take(.op("%")) {
                    value /= 100
                } else if take(.op("!")) {
                    guard value >= 0, value <= 170, value == value.rounded() else { return nil }
                    value = value == 0 ? 1 : (1...Int(value)).reduce(1.0) { $0 * Double($1) }
                } else {
                    return value
                }
            }
        }

        // primary := number | constant | function '(' expression ')' | '(' expression ')'
        mutating func parsePrimary() -> Double? {
            guard let token = peek else { return nil }
            index += 1
            switch token {
            case .number(let value):
                return value
            case .open:
                guard let value = parseExpression(), take(.close) else { return nil }
                return value
            case .name(let name):
                if let constant = constants[name] { return constant }
                guard let function = functions[name], take(.open), let argument = parseExpression(), take(.close)
                else { return nil }
                return function(argument)
            default:
                return nil
            }
        }
    }
}
