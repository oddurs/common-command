import Foundation
import Testing

@testable import CommandKit

@Suite struct ConverterTests {
    let us = Locale(identifier: "en_US")

    func convert(_ input: String, _ locale: Locale = Locale(identifier: "en_US")) -> Converter.Conversion? {
        Converter.convert(input, locale: locale)
    }

    // Foundation's cup is the 240 ml US legal cup, as on nutrition labels, not the 236.6 ml customary one.
    @Test(arguments: [
        ("10 km to mi", 6.21371192, "mi"), ("10km to miles", 6.21371192, "mi"), ("212 f in c", 100, "°C"),
        ("-40 c to f", -40, "°F"), ("0 c to k", 273.15, "K"), ("5 in in cm", 12.7, "cm"),
        ("6*12 in to cm", 182.88, "cm"), ("1 lb to g", 453.59237, "g"), ("2 cups to ml", 480, "ml"),
        ("5 GB in MB", 5000, "MB"), ("1 GiB in MiB", 1024, "MiB"), ("90 min to h", 1.5, "h"),
        ("2 weeks in days", 14, "days"), ("100 kmh to mph", 62.1371192, "mph"), ("1 acre to m2", 4046.8564224, "m²"),
        ("180 deg to rad", .pi, "rad"), ("10km=mi", 6.21371192, "mi"), ("3 FT → M", 0.9144, "m"),
    ])
    func converts(input: String, value: Double, unit: String) throws {
        let result = try #require(convert(input))
        #expect(abs(result.value - value) < 1e-6 * max(1, abs(value)))
        #expect(result.unit == unit)
    }

    @Test(arguments: [
        "10 km", "km to mi", "10 km to kg", "notes in m", "photos to mb", "3 in", "10 km to", "x km to mi",
        "10 parsecs to km", "safari", "2+2",
    ])
    func leavesEverythingElseAlone(input: String) {
        #expect(convert(input) == nil)
    }

    @Test func readsTheRegionsDecimalComma() throws {
        let result = try #require(convert("1,5 km to m", Locale(identifier: "de_DE")))
        #expect(abs(result.value - 1500) < 1e-9)
    }

    @Test func showsAsACopyableResultAboveEverythingElse() {
        var options = SearchOptions()
        options.locale = us
        let results = Results.compose(
            query: "1 mi to km", candidates: [app("Miro")], files: [], usage: Usage(), now: Date(), options: options)
        #expect(results.first?.title == "Conversion")
        #expect(results.rows.first?.item.title == "1.60934 km")
        #expect(results.rows.first?.item.action == .copy("1.60934"))
        #expect(results.rows.filter { $0.item.kind == .calculation }.count == 1)
    }

    @Test func showsSixFiguresAndCopiesWhatItShows() {
        var options = SearchOptions()
        options.locale = us
        let results = Results.compose(
            query: "70 f in c", candidates: [], files: [], usage: Usage(), now: Date(), options: options)
        #expect(results.rows.first?.item.title == "21.1111 °C")
        #expect(results.rows.first?.item.action == .copy("21.1111"))
    }

    @Test func turnsOffWithTheCalculator() {
        var options = SearchOptions()
        options.calculator = false
        let results = Results.compose(
            query: "1 mi to km", candidates: [], files: [], usage: Usage(), now: Date(), options: options)
        #expect(!results.rows.contains { $0.item.kind == .calculation })
    }
}
