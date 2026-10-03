import Foundation
import UIKit
import UniformTypeIdentifiers

/// 「ファイル」で選んだフォルダ（教材 book・記録 rec）を覚え、ページからの読み書きを受ける。
/// ⭕ 許可はブックマークで覚える（次に開いたときも選び直さなくてよい）。
/// ⭕ iCloud のファイルは手元に無いことがあるので、読むときは NSFileCoordinator を通す（落としてから読む）。
final class Folders: NSObject, UIDocumentPickerDelegate {
    static let shared = Folders()
    private var picking: CheckedContinuation<URL?, Never>?

    private func key(_ kind: String) -> String { "folder.\(kind)" }

    func root(_ kind: String) -> URL? {
        #if DEBUG
        // 試すとき：-folder.book /path で、選ばずにフォルダを渡せる（シミュレーターだけ）
        if let p = UserDefaults.standard.string(forKey: "folder.\(kind).debug") { return URL(fileURLWithPath: p) }
        #endif
        guard let data = UserDefaults.standard.data(forKey: key(kind)) else { return nil }
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if stale, let fresh = try? url.bookmarkData() { UserDefaults.standard.set(fresh, forKey: key(kind)) }
        return url
    }

    @MainActor
    func pick(_ kind: String, from vc: UIViewController) async -> String? {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder])
        picker.delegate = self
        picker.allowsMultipleSelection = false
        let url: URL? = await withCheckedContinuation { c in
            picking = c
            vc.present(picker, animated: true)
        }
        guard let url else { return nil }
        _ = url.startAccessingSecurityScopedResource()
        if let data = try? url.bookmarkData() { UserDefaults.standard.set(data, forKey: key(kind)) }
        return url.lastPathComponent
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        picking?.resume(returning: urls.first); picking = nil
    }
    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        picking?.resume(returning: nil); picking = nil
    }

    // ---- ページからの操作。path はフォルダの中の相対パス（"" はフォルダそのもの）
    func url(_ kind: String, _ path: String) throws -> URL {
        guard let r = root(kind) else { throw err("フォルダがまだ選ばれていません") }
        if path.isEmpty { return r }
        guard !path.split(separator: "/").contains("..") else { throw err("パスが不正です") }
        return r.appendingPathComponent(path)
    }

    /// 一覧：iCloud にだけあるファイル（.名前.icloud）も、元の名前で返す
    func list(_ kind: String, _ path: String) throws -> [[String: Any]] {
        let dir = try url(kind, path)
        let items = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [])
        var out: [[String: Any]] = []
        for u in items {
            var name = u.lastPathComponent
            if name.hasPrefix(".") && name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
            } else if name.hasPrefix(".") { continue }
            let v = try? u.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            out.append(["name": name, "kind": (v?.isDirectory ?? false) ? "directory" : "file", "size": v?.fileSize ?? 0])
        }
        return out
    }

    func stat(_ kind: String, _ path: String) -> [String: Any]? {
        guard let u = try? url(kind, path) else { return nil }
        let fm = FileManager.default
        var isDir: ObjCBool = false
        if fm.fileExists(atPath: u.path, isDirectory: &isDir) {
            let attrs = try? fm.attributesOfItem(atPath: u.path)
            let size = (attrs?[.size] as? Int) ?? 0
            return ["kind": isDir.boolValue ? "directory" : "file", "size": size]
        }
        let cloud = u.deletingLastPathComponent().appendingPathComponent("." + u.lastPathComponent + ".icloud")
        if fm.fileExists(atPath: cloud.path) { return ["kind": "file", "size": 0] }
        return nil
    }

    func readData(_ kind: String, _ path: String) throws -> Data {
        let u = try url(kind, path)
        var result: Result<Data, Error> = .failure(err("読めませんでした"))
        var cerr: NSError?
        NSFileCoordinator().coordinate(readingItemAt: u, options: [], error: &cerr) { real in
            result = Result { try Data(contentsOf: real, options: .mappedIfSafe) }
        }
        if let cerr { throw cerr }
        return try result.get()
    }

    func write(_ kind: String, _ path: String, _ text: String, append: Bool) throws {
        let u = try url(kind, path)
        var cerr: NSError?
        var inner: Error?
        NSFileCoordinator().coordinate(writingItemAt: u, options: append ? [] : .forReplacing, error: &cerr) { real in
            do {
                try FileManager.default.createDirectory(at: real.deletingLastPathComponent(), withIntermediateDirectories: true)
                let data = Data(text.utf8)
                if append, FileManager.default.fileExists(atPath: real.path) {
                    let h = try FileHandle(forWritingTo: real)
                    try h.seekToEnd(); try h.write(contentsOf: data); try h.close()
                } else {
                    try data.write(to: real, options: .atomic)
                }
            } catch { inner = error }
        }
        if let cerr { throw cerr }
        if let inner { throw inner }
    }

    func mkdir(_ kind: String, _ path: String) throws {
        try FileManager.default.createDirectory(at: try url(kind, path), withIntermediateDirectories: true)
    }

    func remove(_ kind: String, _ path: String) throws {
        let u = try url(kind, path)
        if FileManager.default.fileExists(atPath: u.path) { try FileManager.default.removeItem(at: u) }
    }

    private func err(_ m: String) -> NSError { NSError(domain: "oto", code: 1, userInfo: [NSLocalizedDescriptionKey: m]) }
}
