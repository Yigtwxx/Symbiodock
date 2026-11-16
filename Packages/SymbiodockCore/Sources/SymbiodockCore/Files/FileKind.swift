/// The extensions each kind of file is recognised by, lowercase.
public enum FileExtensions {
    /// Pictures and photos, raw formats included.
    public static let image: Set<String> = [
        "png", "jpg", "jpeg", "heic", "heif", "tiff", "tif", "gif", "bmp", "webp", "avif", "jp2",
        "psd", "ico", "icns", "svg", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2",
    ]
    /// Text documents `textutil` reads, and rich-text packages.
    public static let document: Set<String> = [
        "docx", "doc", "rtf", "rtfd", "txt", "md", "html", "htm", "odt", "webarchive",
    ]
    /// Sound files.
    public static let audio: Set<String> = [
        "mp3", "m4a", "aac", "wav", "aif", "aiff", "flac", "caf", "ogg", "opus",
    ]
    /// Movies and clips.
    public static let video: Set<String> = ["mov", "mp4", "m4v", "avi", "mkv", "webm"]
    /// Archives and disk images.
    public static let archive: Set<String> = [
        "zip", "tar", "gz", "tgz", "bz2", "xz", "7z", "rar", "dmg",
    ]
}

/// What a held file is, which decides its tile and what it can be converted to.
public enum FileKind: String, CaseIterable, Sendable {
    case image, pdf, document, audio, video, archive, folder, other

    /// By extension first (case-insensitive); an unknown extension is a folder or other.
    public static func of(pathExtension: String, isDirectory: Bool) -> FileKind {
        let ext = pathExtension.lowercased()
        // A rich-text package is a folder on disk but one document to the person.
        if ext == "rtfd" { return .document }
        if isDirectory { return .folder }
        if ext == "pdf" { return .pdf }
        if FileExtensions.image.contains(ext) { return .image }
        if FileExtensions.document.contains(ext) { return .document }
        if FileExtensions.audio.contains(ext) { return .audio }
        if FileExtensions.video.contains(ext) { return .video }
        if FileExtensions.archive.contains(ext) { return .archive }
        return .other
    }
}
