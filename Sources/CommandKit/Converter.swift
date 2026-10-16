import Foundation

/// Unit conversions typed into the search field: "10 km to mi", "70 f in c", "5 GB in MB", "3 cups to ml".
/// The amount can be arithmetic ("6*12 in to cm"). Foundation's units do the conversion, so the factors
/// are Apple's, not a table kept here.
public enum Converter {
    /// Measurements are rarely known to more than a few figures, so results stop at six.
    public static let significantDigits = 6

    public struct Conversion: Equatable, Sendable {
        public var value: Double
        public var unit: String
    }

    struct Unit {
        let dimension: Dimension
        /// How the result is written: "mi", "°F", "fl oz".
        let symbol: String
    }

    /// Words that separate the amount from the unit wanted. Searched from the right, so "5 in in cm" works.
    static let separators = [" to ", " in ", " as ", " into ", " -> ", " → ", " = ", "->", "→", "="]

    /// Converts `input`, or returns nil when it isn't a conversion between two units of one kind.
    public static func convert(_ input: String, locale: Locale = .current) -> Conversion? {
        let text = " " + input.lowercased().trimmingCharacters(in: .whitespaces) + " "
        for separator in separators {
            guard let range = text.range(of: separator, options: .backwards) else { continue }
            let source = text[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            let target = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard let to = units[target], let (amount, from) = amount(source, locale: locale),
                type(of: from.dimension) == type(of: to.dimension)
            else { continue }
            let base = from.dimension.converter.baseUnitValue(fromValue: amount)
            let value = to.dimension.converter.value(fromBaseUnitValue: base)
            guard value.isFinite else { return nil }
            return Conversion(value: value, unit: to.symbol)
        }
        return nil
    }

    /// "10 km" or "10km" → (10, kilometres): the longest unit name the text ends with, after an amount.
    static func amount(_ text: String, locale: Locale) -> (Double, Unit)? {
        for length in stride(from: min(text.count, longestName), through: 1, by: -1) {
            let name = String(text.suffix(length)).trimmingCharacters(in: .whitespaces)
            guard let unit = units[name] else { continue }
            let number = String(text.dropLast(length)).trimmingCharacters(in: .whitespaces)
            guard let value = Calculator.value(of: number, locale: locale, requiringOperation: false) else { continue }
            return (value, unit)
        }
        return nil
    }

    static let longestName = units.keys.map(\.count).max() ?? 0

    static let units: [String: Unit] = {
        var table: [String: Unit] = [:]
        func add(_ dimension: Dimension, _ symbol: String, _ names: String...) {
            for name in names + [symbol.lowercased()] { table[name] = Unit(dimension: dimension, symbol: symbol) }
        }
        add(UnitLength.millimeters, "mm", "millimeter", "millimeters", "millimetre", "millimetres")
        add(UnitLength.centimeters, "cm", "centimeter", "centimeters", "centimetre", "centimetres")
        add(UnitLength.meters, "m", "meter", "meters", "metre", "metres")
        add(UnitLength.kilometers, "km", "kilometer", "kilometers", "kilometre", "kilometres")
        add(UnitLength.inches, "in", "inch", "inches", "\"")
        add(UnitLength.feet, "ft", "foot", "feet", "'")
        add(UnitLength.yards, "yd", "yard", "yards")
        add(UnitLength.miles, "mi", "mile", "miles")
        add(UnitLength.nauticalMiles, "nmi", "nautical mile", "nautical miles")

        add(UnitMass.milligrams, "mg", "milligram", "milligrams")
        add(UnitMass.grams, "g", "gram", "grams")
        add(UnitMass.kilograms, "kg", "kilo", "kilos", "kilogram", "kilograms")
        add(UnitMass.metricTons, "t", "tonne", "tonnes")
        add(UnitMass.ounces, "oz", "ounce", "ounces")
        add(UnitMass.pounds, "lb", "lbs", "pound", "pounds")
        add(UnitMass.stones, "st", "stone", "stones")

        add(UnitTemperature.celsius, "°C", "c", "celsius", "degc")
        add(UnitTemperature.fahrenheit, "°F", "f", "fahrenheit", "degf")
        add(UnitTemperature.kelvin, "K", "k", "kelvin")

        add(UnitVolume.milliliters, "ml", "milliliter", "milliliters", "millilitre", "millilitres")
        add(UnitVolume.centiliters, "cl", "centiliter", "centiliters", "centilitre", "centilitres")
        add(UnitVolume.deciliters, "dl", "deciliter", "deciliters", "decilitre", "decilitres")
        add(UnitVolume.liters, "l", "liter", "liters", "litre", "litres")
        add(UnitVolume.teaspoons, "tsp", "teaspoon", "teaspoons")
        add(UnitVolume.tablespoons, "tbsp", "tablespoon", "tablespoons")
        add(UnitVolume.cups, "cups", "cup")
        add(UnitVolume.fluidOunces, "fl oz", "floz", "fluid ounce", "fluid ounces")
        add(UnitVolume.pints, "pt", "pint", "pints")
        add(UnitVolume.quarts, "qt", "quart", "quarts")
        add(UnitVolume.gallons, "gal", "gallon", "gallons")

        add(UnitSpeed.kilometersPerHour, "km/h", "kmh", "kph")
        add(UnitSpeed.milesPerHour, "mph")
        add(UnitSpeed.metersPerSecond, "m/s")
        add(UnitSpeed.knots, "kn", "knot", "knots")

        add(UnitArea.squareMeters, "m²", "m2", "sqm", "square meters", "square metres")
        add(UnitArea.squareKilometers, "km²", "km2", "square kilometers", "square kilometres")
        add(UnitArea.squareFeet, "ft²", "ft2", "sqft", "square feet")
        add(UnitArea.squareMiles, "mi²", "mi2", "square miles")
        add(UnitArea.acres, "acres", "acre")
        add(UnitArea.hectares, "ha", "hectare", "hectares")

        // Decimal multiples, as Finder counts them; the binary ones have their own names.
        add(UnitInformationStorage.bytes, "B", "byte", "bytes")
        add(UnitInformationStorage.kilobytes, "KB", "kilobyte", "kilobytes")
        add(UnitInformationStorage.megabytes, "MB", "megabyte", "megabytes")
        add(UnitInformationStorage.gigabytes, "GB", "gigabyte", "gigabytes")
        add(UnitInformationStorage.terabytes, "TB", "terabyte", "terabytes")
        add(UnitInformationStorage.kibibytes, "KiB")
        add(UnitInformationStorage.mebibytes, "MiB")
        add(UnitInformationStorage.gibibytes, "GiB")
        add(UnitInformationStorage.tebibytes, "TiB")

        add(UnitDuration.milliseconds, "ms", "millisecond", "milliseconds")
        add(UnitDuration.seconds, "s", "sec", "secs", "second", "seconds")
        add(UnitDuration.minutes, "min", "mins", "minute", "minutes")
        add(UnitDuration.hours, "h", "hr", "hrs", "hour", "hours")
        add(UnitDuration(symbol: "d", converter: UnitConverterLinear(coefficient: 86_400)), "days", "d", "day")
        add(UnitDuration(symbol: "wk", converter: UnitConverterLinear(coefficient: 604_800)), "weeks", "wk", "week")

        add(UnitAngle.degrees, "°", "deg", "degree", "degrees")
        add(UnitAngle.radians, "rad", "radian", "radians")
        return table
    }()
}
