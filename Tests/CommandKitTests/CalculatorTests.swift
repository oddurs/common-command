import Foundation
import Testing

@testable import CommandKit

@Suite struct CalculatorTests {
    let us = Locale(identifier: "en_US")
    let de = Locale(identifier: "de_DE")

    func value(_ input: String, _ locale: Locale = Locale(identifier: "en_US")) -> Double? {
        Calculator.evaluate(input, locale: locale)
    }

    @Test(arguments: [
        ("1+2*3", 7.0), ("(1+2)*3", 9), ("2^3^2", 512), ("-2^2", -4), ("2^-1", 0.5), ("10/4", 2.5),
        ("7 − 2 × 3", 1), ("8 ÷ 2", 4), ("50%", 0.5), ("200*15%", 30), ("5!", 120), ("0!", 1),
        ("sqrt(16)+1", 5), ("2(3+4)", 14), ("(1+2)(3+4)", 21), ("2pi/pi", 2), ("1,000*2", 2000),
        ("log(1000)", 3), ("abs(-3)*1", 3), (".5+.5", 1), ("--2+0", 2),
    ])
    func evaluates(input: String, expected: Double) throws {
        let result = try #require(value(input))
        #expect(abs(result - expected) < 1e-9)
    }

    @Test(arguments: [
        "", "2024", "pi", "e", "1Password", "2fa", "hello", "1+", "(1+2", "1+2)", "1/0", "3.5!", "171!",
        "sqrt 4", "1..2+1", "safari", "x+1", "2+2=",
    ])
    func rejects(input: String) {
        #expect(value(input) == nil)
    }

    @Test func readsTheRegionsDecimalComma() throws {
        #expect(try abs(#require(value("1,5+1", de)) - 2.5) < 1e-9)
        #expect(try abs(#require(value("1.5+1", de)) - 2.5) < 1e-9)
    }

    @Test func deepNestingFailsInsteadOfOverflowing() {
        #expect(value(String(repeating: "(", count: 10_000) + "1" + String(repeating: ")", count: 10_000)) == nil)
    }

    @Test func formatsForTheRegion() {
        #expect(Calculator.format(1234.5, locale: us) == "1,234.5")
        #expect(Calculator.format(1234.5, locale: de) == "1.234,5")
        #expect(Calculator.format(0.1 + 0.2, locale: us) == "0.3")
        #expect(Calculator.format(-0.0, locale: us) == "0")
        #expect(Calculator.format(1e20, locale: us).contains("E"))
    }
}

@Suite struct WebTests {
    @Test(arguments: [
        ("github.com", "https://github.com"), ("github.com/apple/swift", "https://github.com/apple/swift"),
        ("https://example.org/a?b=c", "https://example.org/a?b=c"), ("localhost:3000", "http://localhost:3000"),
        ("192.168.1.1", "http://192.168.1.1"), ("news.ycombinator.com", "https://news.ycombinator.com"),
    ])
    func recognisesAddresses(input: String, expected: String) {
        #expect(Web.address(input)?.absoluteString == expected)
    }

    @Test(arguments: [
        "notes.md", "Info.plist", "safari", "hello world.com", "a..com", "localhost:abc", "https://", "1.2.3",
    ])
    func leavesEverythingElseAlone(input: String) {
        #expect(Web.address(input) == nil)
    }

    @Test func searchURLsEscapeTheQuery() {
        let url = SearchEngine.duckDuckGo.url(searching: "a&b c")
        #expect(url?.absoluteString == "https://duckduckgo.com/?q=a%26b%20c")
    }
}
