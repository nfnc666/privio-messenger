// A copy of Flutter's default bootstrap with one change: the renderer is
// loaded from the CanvasKit copy that ships with this build instead of from
// Google's CDN. A messenger should not announce every page load to a third
// party, and the renderer is one of the few things on a Flutter web page that
// reaches off-origin by default.
{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: {
    canvasKitBaseUrl: "canvaskit/",
    // Where the engine looks for a glyph no bundled font can draw — emoji,
    // most of CJK, anything outside Latin. Left at its default it is
    // fonts.gstatic.com, so opening a chat containing an emoji would tell
    // Google the reader's address at that moment. Pointed at this origin it
    // finds nothing, logs that it is giving up, and stops asking: a missing
    // glyph is a cosmetic problem, and a request to a third party naming the
    // person reading is not. iOS and Android are unaffected — the system
    // supplies those glyphs there, which is why the bundled emoji font this
    // would otherwise need (~10 MB) is not worth carrying.
    fontFallbackBaseUrl: "fallback-fonts/",
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
