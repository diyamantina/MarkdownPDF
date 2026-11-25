import Foundation

/// The folder every temporary file of the tests lives under: the folder `TMPDIR` names when it is an absolute path,
/// otherwise the system's temporary folder. On macOS `FileManager.temporaryDirectory` ignores `TMPDIR` (MEASURED: a
/// run with `TMPDIR` set to an external folder still wrote under `/var/folders` on the system disk), so the tests
/// ask the environment first, here and nowhere else.
enum TestTemporaryRoot {
    /// The root for temporary files. A missing, empty, blank or relative `TMPDIR` is not trusted (a relative one would
    /// mean the current folder) and gives `fallback`.
    static func root(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fallback: URL = FileManager.default.temporaryDirectory,
    ) -> URL {
        guard let value = environment["TMPDIR"]?.trimmingCharacters(in: .whitespaces), value.hasPrefix("/") else {
            return fallback
        }
        return URL(fileURLWithPath: value, isDirectory: true).standardizedFileURL
    }

    /// The root of this process.
    static var url: URL {
        root()
    }
}
