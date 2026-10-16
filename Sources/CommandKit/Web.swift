import Foundation

public enum SearchEngine: String, CaseIterable, Sendable, Identifiable {
    case google, duckDuckGo, bing, kagi, ecosia, startpage

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .google: "Google"
        case .duckDuckGo: "DuckDuckGo"
        case .bing: "Bing"
        case .kagi: "Kagi"
        case .ecosia: "Ecosia"
        case .startpage: "Startpage"
        }
    }

    var base: String {
        switch self {
        case .google: "https://www.google.com/search"
        case .duckDuckGo: "https://duckduckgo.com/"
        case .bing: "https://www.bing.com/search"
        case .kagi: "https://kagi.com/search"
        case .ecosia: "https://www.ecosia.org/search"
        case .startpage: "https://www.startpage.com/do/search"
        }
    }

    public func url(searching query: String) -> URL? {
        var components = URLComponents(string: base)
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }
}

public enum Web {
    /// Endings that make "word.ending" a web address rather than a file name. Kept short on purpose:
    /// "notes.md" and "Info.plist" are files someone is looking for, not sites.
    static let domains: Set<String> = [
        "com", "org", "net", "io", "dev", "app", "ai", "co", "edu", "gov", "me", "info", "xyz", "tv", "fm",
        "page", "site", "blog", "news", "uk", "us", "ca", "de", "fr", "is", "nl", "se", "no", "dk", "fi", "es",
        "it", "eu", "jp", "au", "nz", "ch", "at", "be", "ie", "in", "br",
    ]

    /// The address `query` names, if it is one: "https://…", "github.com/apple", "localhost:3000".
    public static func address(_ query: String) -> URL? {
        let text = query.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        let lower = text.lowercased()
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") {
            guard let url = URL(string: text), url.host?.isEmpty == false else { return nil }
            return url
        }
        let host = lower.prefix { $0 != "/" && $0 != "?" && $0 != "#" }
        let hostname = host.split(separator: ":", maxSplits: 1).first.map(String.init) ?? ""
        if let port = host.split(separator: ":", maxSplits: 1).dropFirst().first, Int(port) == nil { return nil }
        let labels = hostname.split(separator: ".", omittingEmptySubsequences: false)
        let isLocal = hostname == "localhost"
        let isDomain =
            labels.count >= 2
            && labels.allSatisfy { !$0.isEmpty && $0.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" } }
            && domains.contains(String(labels.last!))
        let isIPv4 = labels.count == 4 && labels.allSatisfy { UInt8($0) != nil }
        guard isLocal || isDomain || isIPv4 else { return nil }
        return URL(string: (isLocal || isIPv4 ? "http://" : "https://") + text)
    }
}
