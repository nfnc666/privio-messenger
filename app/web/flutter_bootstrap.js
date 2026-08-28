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
  },
  serviceWorkerSettings: {
    serviceWorkerVersion: {{flutter_service_worker_version}},
  },
});
