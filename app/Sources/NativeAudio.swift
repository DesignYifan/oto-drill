import AVFoundation
import WebKit

/// Mac（Catalyst）だけ：音はアプリ本体の AVPlayer で鳴らす。ページの new Audio() は MAC_AUDIO_JS がこれにつなぎ替える。
/// × アプリの中のブラウザ（WKWebView）は Mac Catalyst では音声を開けない（2026-10-04 に確かめた。
///   ファイル・blob・data・ネットの mp3・Web Audio のどれも読み込みが始まらない。ブラウザの部品が音声の処理を止められている）
/// ○ ページは変えない。iPhone は今まで通りページの中で鳴らす
@MainActor
final class NativeAudio {
    static let shared = NativeAudio()
    weak var web: WKWebView?

    private final class One {
        let player = AVPlayer()
        var rate: Float = 1
        var wantPlay = false
        var pendingSeek: Double?
        var ready = false
        var timeObs: Any?
        var endObs: NSObjectProtocol?
        var statusObs: NSKeyValueObservation?
        var playingObs: NSKeyValueObservation?
        var tmp: URL?
    }
    private var all: [Int: One] = [:]

    func handle(_ b: [String: Any]) async throws -> Any? {
        let id = b["id"] as? Int ?? 0
        let o = all[id] ?? { let n = One(); all[id] = n; return n }()
        switch b["a"] as? String ?? "" {
        case "load":
            try await load(id, o, b)
        case "play":
            o.wantPlay = true
            if o.ready { o.player.playImmediately(atRate: o.rate) }
        case "pause":
            o.wantPlay = false
            o.player.pause()
        case "seek":
            let t = b["t"] as? Double ?? 0
            if o.ready { seek(o, t) } else { o.pendingSeek = t }
        case "rate":
            o.rate = Float(b["r"] as? Double ?? 1)
            if o.player.rate != 0 { o.player.rate = o.rate }
        case "vol":
            o.player.isMuted = b["muted"] as? Bool ?? false
            o.player.volume = Float(b["vol"] as? Double ?? 1)
        case "drop":
            clear(o); all[id] = nil
        default:
            throw NSError(domain: "oto", code: 3, userInfo: [NSLocalizedDescriptionKey: "知らない音の操作"])
        }
        return true
    }

    private func load(_ id: Int, _ o: One, _ b: [String: Any]) async throws {
        clear(o)
        o.ready = false; o.pendingSeek = nil; o.wantPlay = false
        o.rate = Float(b["rate"] as? Double ?? Double(o.rate))
        o.player.isMuted = b["muted"] as? Bool ?? false
        o.player.volume = Float(b["vol"] as? Double ?? 1)
        let url: URL
        if let kind = b["kind"] as? String, let path = b["path"] as? String {
            // 選んだフォルダの中のファイルをそのまま渡す（iCloud にしか無いときは、読む合図で手元に落としてから）
            url = try await Task.detached { () throws -> URL in
                let u = try Folders.shared.url(kind, path)
                var real = u, cerr: NSError?
                NSFileCoordinator().coordinate(readingItemAt: u, options: [], error: &cerr) { real = $0 }
                if let cerr { throw cerr }
                return real
            }.value
        } else if let b64 = b["b64"] as? String, let data = Data(base64Encoded: b64) {
            // blob: の音声（ページが手元に読み込んだもの）は、一時ファイルにして鳴らす
            let t = FileManager.default.temporaryDirectory.appendingPathComponent("oto-\(id)-\(UUID().uuidString).\(b["ext"] as? String ?? "mp3")")
            try data.write(to: t)
            o.tmp = t; url = t
        } else if let s = b["url"] as? String, let u = URL(string: s) {
            url = u
        } else {
            throw NSError(domain: "oto", code: 4, userInfo: [NSLocalizedDescriptionKey: "音声の場所が分かりません"])
        }
        let item = AVPlayerItem(url: url)
        item.audioTimePitchAlgorithm = .spectral   // 速度を変えても音程を変えない（ページの preservesPitch と同じ）
        o.statusObs = item.observe(\.status) { [weak self] it, _ in
            Task { @MainActor in
                guard let self else { return }
                if it.status == .readyToPlay, !o.ready {
                    o.ready = true
                    if let t = o.pendingSeek { self.seek(o, t); o.pendingSeek = nil }
                    self.emit(id, "loadedmetadata", o)
                    self.emit(id, "canplay", o)
                    if o.wantPlay { o.player.playImmediately(atRate: o.rate) }
                } else if it.status == .failed {
                    dlog("音 読めない \(it.error?.localizedDescription ?? "")")
                    self.emit(id, "error", o)
                }
            }
        }
        o.playingObs = o.player.observe(\.timeControlStatus) { [weak self] p, _ in
            Task { @MainActor in if p.timeControlStatus == .playing { self?.emit(id, "playing", o) } }
        }
        o.endObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in o.wantPlay = false; self?.emit(id, "ended", o) }
        }
        o.timeObs = o.player.addPeriodicTimeObserver(forInterval: CMTime(value: 1, timescale: 4), queue: .main) { [weak self] _ in
            Task { @MainActor in if o.player.rate != 0 { self?.emit(id, "timeupdate", o) } }
        }
        o.player.replaceCurrentItem(with: item)
    }

    private func seek(_ o: One, _ t: Double) {
        o.player.seek(to: CMTime(seconds: max(0, t), preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private func clear(_ o: One) {
        o.player.pause()
        if let t = o.timeObs { o.player.removeTimeObserver(t); o.timeObs = nil }
        if let e = o.endObs { NotificationCenter.default.removeObserver(e); o.endObs = nil }
        o.statusObs = nil; o.playingObs = nil
        o.player.replaceCurrentItem(with: nil)
        if let t = o.tmp { try? FileManager.default.removeItem(at: t); o.tmp = nil }
    }

    /// ページへ知らせる：window.__na(id, 種類, 今の位置, 長さ, 止まっているか)
    private func emit(_ id: Int, _ type: String, _ o: One) {
        let t = o.player.currentTime().seconds
        let d = o.player.currentItem?.duration.seconds ?? .nan
        let js = "window.__na && window.__na(\(id),'\(type)',\(t.isFinite ? t : 0),\(d.isFinite ? d : -1),\(o.player.rate == 0))"
        web?.evaluateJavaScript(js, completionHandler: nil)
    }
}

/// ページの new Audio() を、アプリ本体で鳴らす偽物に差し替える（Mac だけ）。ページが使っている分だけ同じ形にしてある：
/// src・currentTime・duration・paused・playbackRate・muted・volume・play()・pause()・dataset・preload と、
/// loadedmetadata・canplay・play・pause・playing・timeupdate・ended・error の知らせ
let MAC_AUDIO_JS = """
(function(){
  const N = window.webkit.messageHandlers.oto;
  const blobs = new Map(), oc = URL.createObjectURL.bind(URL), orv = URL.revokeObjectURL.bind(URL);
  URL.createObjectURL = o => { const u = oc(o); if(o instanceof Blob) blobs.set(u, o); return u; };
  URL.revokeObjectURL = u => { blobs.delete(u); orv(u); };
  const toB64 = blob => new Promise((res, rej) => { const fr = new FileReader(); fr.onload = () => res(String(fr.result).split(',')[1] || ''); fr.onerror = () => rej(fr.error); fr.readAsDataURL(blob); });
  const all = new Map(); let seq = 0;
  class NAudio extends EventTarget {
    constructor(src){
      super(); this.id = ++seq; all.set(this.id, this);
      this._src = ''; this._t = 0; this._stamp = 0; this._d = NaN; this.paused = true; this.ended = false;
      this._rate = 1; this._muted = false; this._vol = 1; this.preload = 'auto'; this.dataset = {}; this.error = null; this.readyState = 0;
      this._q = Promise.resolve(); this._gen = 0;
      if(src) this.src = src;
    }
    _send(a, o){ const m = Object.assign({op: 'audio', a, id: this.id}, o || {}); this._q = this._q.then(() => N.postMessage(m)).catch(e => { this.error = {code: 4, message: String(e)}; this.dispatchEvent(new Event('error')); }); return this._q; }
    get src(){ return this._src; }
    set src(u){
      u = String(u || ''); this._src = u; this._t = 0; this._d = NaN; this.paused = true; this.ended = false; this.readyState = 0; this.error = null;
      const gen = ++this._gen;
      this._q = this._q.then(async () => {
        if(gen !== this._gen || !u) return;
        let o;
        if(u.startsWith('otofs://')){ const x = new URL(u); o = {kind: x.host, path: x.pathname.slice(1).split('/').map(decodeURIComponent).join('/')}; }
        else if(u.startsWith('blob:') && blobs.has(u)){ const b = blobs.get(u); o = {b64: await toB64(b), ext: /mp4|m4a/.test(b.type) ? 'm4a' : /wav/.test(b.type) ? 'wav' : 'mp3'}; }
        else o = {url: new URL(u, location.href).href};
        if(gen !== this._gen) return;
        await N.postMessage(Object.assign({op: 'audio', a: 'load', id: this.id, rate: this._rate, muted: this._muted, vol: this._vol}, o));
      }).catch(e => { this.error = {code: 4, message: String(e)}; this.dispatchEvent(new Event('error')); });
    }
    get currentTime(){ return this.paused ? this._t : this._t + (performance.now() - this._stamp) / 1000 * this._rate; }
    set currentTime(t){ this._t = Number(t) || 0; this._stamp = performance.now(); this.ended = false; this._send('seek', {t: this._t}); }
    get duration(){ return this._d; }
    get playbackRate(){ return this._rate; }
    set playbackRate(r){ this._t = this.currentTime; this._stamp = performance.now(); this._rate = Number(r) || 1; this._send('rate', {r: this._rate}); }
    get defaultPlaybackRate(){ return 1; } set defaultPlaybackRate(r){}
    get muted(){ return this._muted; } set muted(m){ this._muted = !!m; this._send('vol', {muted: this._muted, vol: this._vol}); }
    get volume(){ return this._vol; } set volume(v){ this._vol = Number(v); this._send('vol', {muted: this._muted, vol: this._vol}); }
    play(){
      if(this.paused){ this.paused = false; this._stamp = performance.now(); this.dispatchEvent(new Event('play')); }
      if(this.ended){ this.ended = false; this._t = 0; this._send('seek', {t: 0}); }
      this._send('play'); return Promise.resolve();
    }
    pause(){
      if(!this.paused){ this._t = this.currentTime; this.paused = true; this.dispatchEvent(new Event('pause')); }
      this._send('pause');
    }
    load(){} canPlayType(){ return 'maybe'; }
    removeAttribute(k){ if(k === 'src'){ this._gen++; this._src = ''; this._send('pause'); } }
    setAttribute(k, v){ if(k === 'src') this.src = v; }
  }
  window.__na = (id, type, t, d, stopped) => {
    const a = all.get(id); if(!a) return;
    a._t = t; a._stamp = performance.now(); if(d > 0) a._d = d;
    if(type === 'loadedmetadata') a.readyState = 4;
    if(type === 'ended'){ a.paused = true; a.ended = true; a._t = a._d > 0 ? a._d : t; a.dispatchEvent(new Event('pause')); }
    if(type === 'error') a.error = {code: 4, message: 'アプリで読めませんでした'};
    a.dispatchEvent(new Event(type));
  };
  window.Audio = NAudio;
})();
"""
