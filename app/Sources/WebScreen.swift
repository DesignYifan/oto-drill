import SwiftUI
import WebKit

/// 公開ページを開く。ページの直しはアプリを入れ直さずに届く。
/// 試すときの記録（アプリのフォルダの oto.log）。Mac から simctl get_app_container で読める
func dlog(_ m: String) {
    #if !DEBUG
    if !UserDefaults.standard.bool(forKey: "log") { return }   // 入れたままの版では書かない（調べるときだけ log を立てる）
    #endif
    let u = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("oto.log")
    let line = "\(Date()) \(m)\n"
    if let h = try? FileHandle(forWritingTo: u) { h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close() }
    else { try? line.data(using: .utf8)?.write(to: u) }
}

let PAGE: URL = {
    #if DEBUG
    // 試すとき：xcrun simctl launch … -page http://localhost:8790/?app=1 で、手元のページを開ける
    if let s = UserDefaults.standard.string(forKey: "page"), let u = URL(string: s) { return u }
    #endif
    return URL(string: "https://designyifan.github.io/oto-drill/?app=1")!
}()

struct WebScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> WebVC { WebVC() }
    func updateUIViewController(_ vc: WebVC, context: Context) {}
}

final class WebVC: UIViewController, WKScriptMessageHandlerWithReply, WKNavigationDelegate {
    var web: WKWebView!

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
        let cfg = WKWebViewConfiguration()
        cfg.allowsInlineMediaPlayback = true
        cfg.mediaTypesRequiringUserActionForPlayback = []
        cfg.setURLSchemeHandler(OtoFS(), forURLScheme: "otofs")
        let ucc = cfg.userContentController
        ucc.addScriptMessageHandler(self, contentWorld: .page, name: "oto")
        ucc.addUserScript(WKUserScript(source: BRIDGE_JS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        #if targetEnvironment(macCatalyst)
        ucc.addUserScript(WKUserScript(source: MAC_FETCH_JS, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        #endif
        web = WKWebView(frame: view.bounds, configuration: cfg)
        web.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        web.navigationDelegate = self
        web.scrollView.contentInsetAdjustmentBehavior = .never   // 余白はページが env(safe-area-inset-*) で取る
        web.isOpaque = false; web.backgroundColor = .clear
        web.isInspectable = true          // Mac の Safari から中を見て直せるように
        web.allowsBackForwardNavigationGestures = false
        view.addSubview(web)
        dlog("開く \(PAGE.absoluteString)")
        web.load(URLRequest(url: PAGE, cachePolicy: .reloadRevalidatingCacheData))
    }

    // ページからの頼みごと（window.oto.*）。答えは Promise としてページへ返る
    func userContentController(_ ucc: WKUserContentController, didReceive message: WKScriptMessage,
                               replyHandler: @escaping (Any?, String?) -> Void) {
        guard let b = message.body as? [String: Any], let op = b["op"] as? String else { replyHandler(nil, "形が違います"); return }
        let kind = b["kind"] as? String ?? "", path = b["path"] as? String ?? ""
        let F = Folders.shared
        Task { @MainActor in
            do {
                switch op {
                case "log":
                    dlog("ページ：\(b["text"] as? String ?? "")"); replyHandler(true, nil)
                case "ask":
                    let t = try await Groq.ask(system: b["system"] as? String ?? "", user: b["user"] as? String ?? "")
                    replyHandler(t, nil)
                case "pick":
                    let name = await F.pick(kind, from: self)
                    replyHandler(name.map { ["name": $0] }, nil)
                case "info":
                    replyHandler(F.root(kind).map { ["name": $0.lastPathComponent] }, nil)
                case "list":
                    let r = try await Task.detached { try F.list(kind, path) }.value
                    replyHandler(r, nil)
                case "stat":
                    replyHandler(F.stat(kind, path), nil)
                case "read":
                    let d = try await Task.detached { try F.readData(kind, path) }.value
                    replyHandler(String(decoding: d, as: UTF8.self), nil)
                case "bytes":   // Mac：ページの fetch は otofs:// に届かない（https のページから止められる）。中身をここから渡す
                    let d = try await Task.detached { try F.readData(kind, path) }.value
                    replyHandler(d.base64EncodedString(), nil)
                case "write", "append":
                    let text = b["text"] as? String ?? ""
                    try await Task.detached { try F.write(kind, path, text, append: op == "append") }.value
                    replyHandler(true, nil)
                case "mkdir":
                    try F.mkdir(kind, path); replyHandler(true, nil)
                case "remove":
                    try F.remove(kind, path); replyHandler(true, nil)
                default:
                    replyHandler(nil, "知らない操作：\(op)")
                }
            } catch {
                replyHandler(nil, error.localizedDescription)
            }
        }
    }

    // 読めなかったときは、その理由を画面に出す（白いままにしない）
    func webView(_ webView: WKWebView, didFailProvisionalNavigation nav: WKNavigation!, withError error: Error) { showError(error) }
    func webView(_ webView: WKWebView, didFail nav: WKNavigation!, withError error: Error) { showError(error) }
    func webView(_ webView: WKWebView, didFinish nav: WKNavigation!) {
        dlog("読み込み完了 \(webView.url?.absoluteString ?? "")")
        #if DEBUG
        // 試すとき：-selftest 1 で、ページの中から口を全部呼んで結果を記録に書く
        if UserDefaults.standard.bool(forKey: "selftest") {
            let js = """
            const r = {};
            try { r.ask = await oto.ask('日本語で1行で答える', 'xin chào の意味は？'); } catch(e) { r.ask = 'エラー ' + e; }
            try { r.list = (await oto.fs.list('book', '')).length; } catch(e) { r.list = 'エラー ' + e; }
            try { r.stat = JSON.stringify(await oto.fs.stat('book', 'book.json')); } catch(e) { r.stat = 'エラー ' + e; }
            try { await oto.fs.append('rec', '記録/selftest.jsonl', '{"x":1}\\n'); await oto.fs.append('rec', '記録/selftest.jsonl', '{"x":2}\\n'); r.read = await oto.fs.read('rec', '記録/selftest.jsonl'); } catch(e) { r.read = 'エラー ' + e; }
            try { const res = await fetch(oto.fs.url('book', 'images.json')); r.fetch = res.status + ' ' + (await res.text()).length; } catch(e) { r.fetch = 'エラー ' + e; }
            try { const res = await fetch(oto.fs.url('book', '001.mp3'), {headers: {Range: 'bytes=0-99'}}); r.range = res.status + ' ' + (await res.arrayBuffer()).byteLength; } catch(e) { r.range = 'エラー ' + e; }
            const a = window.__oto && window.__oto.audio;
            if(a){ a.muted = true; a.volume = 0; }
            if(window.__oto){ window.__oto.clip.muted = true; }
            const t0 = Date.now(); document.querySelector('#play').click();
            await new Promise(res => setTimeout(res, 4000));
            r.audio = { paused: a && a.paused, t: a && Math.round(a.currentTime * 10) / 10, src: a && a.src.slice(0, 12), ms: Date.now() - t0, err: a && a.error && a.error.code, rs: a && a.readyState, ns: a && a.networkState, d: a && a.duration };
            return JSON.stringify(r);
            """
            webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page) { res in
                switch res { case .success(let v): dlog("自己試験 \(v ?? "")"); case .failure(let e): dlog("自己試験 失敗 \(e)") }
            }
        }
        #endif
    }
    private func showError(_ error: Error) {
        dlog("読み込み失敗 \(error.localizedDescription)")
        web.loadHTMLString("<meta name=viewport content='width=device-width'><body style='font:16px -apple-system;padding:40px 24px;color:#1b1d22;background:#f5f6f8'><h3>ページを開けませんでした</h3><p>\(error.localizedDescription)</p><p>ネットにつながっているか確かめて、アプリを開き直してください。</p></body>", baseURL: nil)
    }

    // 外へのリンクは Safari で開く
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if let u = action.request.url, action.navigationType == .linkActivated, u.host != PAGE.host {
            UIApplication.shared.open(u); decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }
}

/// otofs://<kind>/<パス> を、選んだフォルダの中のファイルとして返す。音声は途中から読めるよう Range に答える
final class OtoFS: NSObject, WKURLSchemeHandler {
    private var stopped = Set<ObjectIdentifier>()
    private let lock = NSLock()

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        let id = ObjectIdentifier(task)
        let req = task.request
        DispatchQueue.global(qos: .userInitiated).async {
            guard let url = req.url, let kind = url.host else { dlog("otofs 住所が読めない \(req.url?.absoluteString ?? "")"); return }
            let path = String(url.path.dropFirst()).removingPercentEncoding ?? ""
            do {
                let data = try Folders.shared.readData(kind, path)
                var status = 200, body = data
                var headers = ["Content-Type": OtoFS.mime(path), "Accept-Ranges": "bytes", "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store"]
                if let r = req.value(forHTTPHeaderField: "Range"), let (a, b) = OtoFS.range(r, data.count) {
                    status = 206; body = data.subdata(in: a..<(b + 1))
                    headers["Content-Range"] = "bytes \(a)-\(b)/\(data.count)"
                }
                headers["Content-Length"] = String(body.count)
                let resp = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
                self.send(id, task) { task.didReceive(resp); task.didReceive(body); task.didFinish() }
            } catch {
                dlog("otofs 読めない \(kind)/\(path) \(error.localizedDescription)")
                self.send(id, task) { task.didFailWithError(error) }
            }
        }
    }
    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {
        lock.lock(); stopped.insert(ObjectIdentifier(task)); lock.unlock()
    }
    private func send(_ id: ObjectIdentifier, _ task: WKURLSchemeTask, _ f: @escaping () -> Void) {
        DispatchQueue.main.async {
            self.lock.lock(); let gone = self.stopped.contains(id); self.lock.unlock()
            if !gone { f() }
        }
    }
    static func range(_ h: String, _ n: Int) -> (Int, Int)? {
        guard h.hasPrefix("bytes="), n > 0 else { return nil }
        let p = h.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 2 else { return nil }
        let a = Int(p[0]) ?? max(0, n - (Int(p[1]) ?? n))
        let b = p[0].isEmpty ? n - 1 : min(n - 1, Int(p[1]) ?? n - 1)
        return a <= b ? (a, b) : nil
    }
    static func mime(_ p: String) -> String {
        switch (p as NSString).pathExtension.lowercased() {
        case "mp3": return "audio/mpeg"
        case "m4a", "mp4": return "audio/mp4"
        case "wav": return "audio/wav"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "json": return "application/json"
        case "jsonl", "txt", "md": return "text/plain; charset=utf-8"
        default: return "application/octet-stream"
        }
    }
}

/// ページに足す window.oto。フォルダの口は Chrome の FileSystemDirectoryHandle と同じ形にページ側で包む（index.html の NDir）
let BRIDGE_JS = """
(function(){
  const call = (op, o) => window.webkit.messageHandlers.oto.postMessage(Object.assign({op}, o || {}));
  const log = t => { try{ window.webkit.messageHandlers.oto.postMessage({op: 'log', text: String(t)}); }catch(e){} };
  window.addEventListener('error', e => log('エラー ' + e.message + ' @' + (e.filename || '') + ':' + (e.lineno || '')));
  window.addEventListener('unhandledrejection', e => log('未処理 ' + (e.reason && (e.reason.message || e.reason))));
  window.oto = {
    native: 'ios',
    ask: (system, user) => call('ask', {system, user}),
    fs: {
      pick: kind => call('pick', {kind}),
      info: kind => call('info', {kind}),
      list: (kind, path) => call('list', {kind, path}),
      stat: (kind, path) => call('stat', {kind, path}),
      read: (kind, path) => call('read', {kind, path}),
      write: (kind, path, text) => call('write', {kind, path, text}),
      append: (kind, path, text) => call('append', {kind, path, text}),
      mkdir: (kind, path) => call('mkdir', {kind, path}),
      remove: (kind, path) => call('remove', {kind, path}),
      url: (kind, path) => 'otofs://' + kind + '/' + path.split('/').map(encodeURIComponent).join('/')
    }
  };
})();
"""

/// Mac（Catalyst）だけ：https のページからの fetch('otofs://…') は WebKit が止めて、アプリまで届かない（2026-10-04 に確かめた）。
/// ○ fetch を包み、otofs:// だけはアプリから中身を受け取って Response にする。<img>・<audio> の otofs:// はそのまま届くので触らない。
/// × iPhone には入れない（iPhone は fetch が届いていて、そのままで動いている）
let MAC_FETCH_JS = """
(function(){
  window.oto.native = 'mac';
  const orig = window.fetch.bind(window);
  window.fetch = async (input, init) => {
    const url = typeof input === 'string' ? input : (input && input.url) || '';
    if(!url.startsWith('otofs://')) return orig(input, init);
    const u = new URL(url), kind = u.host, path = u.pathname.slice(1).split('/').map(decodeURIComponent).join('/');
    const b64 = await window.webkit.messageHandlers.oto.postMessage({op: 'bytes', kind, path});
    const bin = atob(b64), buf = new Uint8Array(bin.length);
    for(let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
    return new Response(new Blob([buf]), {status: 200});
  };
})();
"""
