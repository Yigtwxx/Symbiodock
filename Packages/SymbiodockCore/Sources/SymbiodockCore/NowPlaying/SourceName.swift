public enum SourceName {
    private static let known: [String: String] = [
        "com.apple.Music": "Music",
        "com.spotify.client": "Spotify",
        "com.apple.Safari": "Safari",
        "com.google.Chrome": "Chrome",
    ]

    public static func displayName(forBundleIdentifier identifier: String) -> String {
        if let name = known[identifier] { return name }
        guard let last = identifier.split(separator: ".").last else { return "Unknown" }
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}
