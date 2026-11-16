import Foundation

/// Where a conversion's result goes and what it is called.
public enum OutputNaming {
    /// Next to the source, same stem, new extension ("" makes a folder name); " 2", " 3"… while taken.
    public static func output(
        for source: URL, pathExtension: String, exists: (URL) -> Bool
    ) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        return free(beside: source, stem: stem, pathExtension: pathExtension, exists: exists)
    }

    /// The folder a PDF's pages go into: "<stem> pages".
    public static func pagesFolder(for source: URL, exists: (URL) -> Bool) -> URL {
        let stem = source.deletingPathExtension().lastPathComponent
        return free(beside: source, stem: "\(stem) pages", pathExtension: "", exists: exists)
    }

    /// "report-01.png": the number is padded to the digits of the page count, at least two.
    public static func pageName(stem: String, index: Int, count: Int, pathExtension: String) -> String {
        let width = max(2, String(count).count)
        let number = String(index + 1)
        let padded = String(repeating: "0", count: max(0, width - number.count)) + number
        return "\(stem)-\(padded).\(pathExtension)"
    }

    /// A hidden name beside the output, so a half-written result never looks finished.
    public static func temporary(for output: URL, token: String) -> URL {
        output.deletingLastPathComponent()
            .appendingPathComponent(".\(token)-\(output.lastPathComponent)")
    }

    private static func free(
        beside source: URL, stem: String, pathExtension: String, exists: (URL) -> Bool
    ) -> URL {
        let folder = source.deletingLastPathComponent()
        func candidate(_ number: Int) -> URL {
            let name = number == 1 ? stem : "\(stem) \(number)"
            return folder.appendingPathComponent(
                pathExtension.isEmpty ? name : "\(name).\(pathExtension)")
        }
        var number = 1
        while exists(candidate(number)) { number += 1 }
        return candidate(number)
    }
}
