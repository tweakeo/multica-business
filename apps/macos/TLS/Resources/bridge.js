// Native bridge shim for the WKWebView host.
//
// Recreates the `window.desktopAPI`, `window.daemonAPI` and `window.updater`
// shapes that apps/desktop/src/preload/index.ts exposes under Electron, so the
// desktop renderer runs unchanged. Synchronous values come from
// `window.__TLS_BOOT__`, injected by the host before this script. Calls go to
// the single `tls` message handler, which only answers the main frame of the
// bundled `tls-app://app` origin.
(() => {
  "use strict";

  const boot = window.__TLS_BOOT__;
  if (!boot || window.desktopAPI) return;

  const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.tls;
  const call = (name, payload) =>
    handler ? handler.postMessage({ name, payload: payload === undefined ? null : payload }) : Promise.reject(new Error("native bridge unavailable"));
  const send = (name, payload) => {
    call(name, payload).catch((err) => console.warn(`[tls-bridge] ${name} failed`, err));
  };

  // Channels whose events must not be lost if they fire before the renderer
  // subscribes (deep links, notification clicks, shortcuts). Mirrors the
  // readiness queue Electron's main process keeps for the same channels.
  const BUFFERED = new Set(["auth:token", "invite:open", "inbox:open", "settings:open", "tab:select-by-shortcut"]);
  const listeners = new Map();
  const pending = new Map();

  const subscribe = (channel) => (callback) => {
    let set = listeners.get(channel);
    if (!set) listeners.set(channel, (set = new Set()));
    set.add(callback);
    const queued = pending.get(channel);
    if (queued) {
      pending.delete(channel);
      queued.forEach((payload) => callback(payload));
    }
    return () => set.delete(callback);
  };

  Object.defineProperty(window, "__tlsEmit", {
    value: (channel, payload) => {
      const set = listeners.get(channel);
      if (set && set.size > 0) {
        set.forEach((cb) => {
          try {
            cb(payload);
          } catch (err) {
            console.error(`[tls-bridge] listener for ${channel} threw`, err);
          }
        });
      } else if (BUFFERED.has(channel)) {
        const queued = pending.get(channel) || [];
        queued.push(payload);
        pending.set(channel, queued);
      }
    },
  });

  const desktopAPI = {
    appInfo: boot.appInfo,
    systemLocale: boot.systemLocale,
    runtimeConfig: boot.runtimeConfig,
    windowContext: boot.windowContext,
    onSystemLocaleChanged: subscribe("locale:system-changed"),
    getLastFreeze: () => null,
    ackFreeze: () => {},
    reportAuthSession: (userId) => send("auth.session", { userId }),
    onAuthToken: subscribe("auth:token"),
    onInviteOpen: subscribe("invite:open"),
    openExternal: (url) => call("shell.openExternal", { url }).then(() => undefined),
    downloadURL: (url) => call("file.download", { url }).then(() => undefined),
    setImmersiveMode: (immersive) => call("window.setImmersive", { immersive: !!immersive }).then(() => undefined),
    showNotification: (payload) => send("notification.show", payload),
    setUnreadBadge: (count) => send("badge.set", { count }),
    onInboxOpen: subscribe("inbox:open"),
    onNavigationGesture: subscribe("navigation:gesture"),
    setRendererRouteContext: () => {},
    pickDirectory: (defaultPath) => call("directory.pick", { defaultPath: defaultPath || null }),
    validateLocalDirectory: (path) => call("directory.validate", { path }),
    onCloseActiveTab: subscribe("tab:close-active"),
    onOpenSettings: subscribe("settings:open"),
    onSelectTabShortcut: subscribe("tab:select-by-shortcut"),
    closeWindow: () => send("window.close"),
    openIssueWindow: (request) => call("window.openIssue", request),
  };

  const daemonAPI = {
    start: () => call("daemon.start"),
    stop: () => call("daemon.stop"),
    restart: () => call("daemon.restart"),
    getStatus: () => call("daemon.status"),
    probeRuntimes: () => call("daemon.probeRuntimes"),
    getHostName: () => call("daemon.hostName"),
    onStatusChange: subscribe("daemon:status"),
    setTargetApiUrl: (url) => call("daemon.setTargetApiUrl", { url }).then(() => undefined),
    syncToken: (token, userId) => call("daemon.syncToken", { token, userId }).then(() => undefined),
    clearToken: () => call("daemon.clearToken").then(() => undefined),
    reauthenticate: (token, userId) => call("daemon.reauthenticate", { token, userId }),
    isCliInstalled: () => call("daemon.isCliInstalled"),
    getPrefs: () => call("daemon.getPrefs"),
    setPrefs: (prefs) => call("daemon.setPrefs", prefs),
    autoStart: () => call("daemon.autoStart").then(() => undefined),
    retryInstall: () => call("daemon.autoStart").then(() => undefined),
    startLogStream: () => send("daemon.startLogStream"),
    stopLogStream: () => send("daemon.stopLogStream"),
    onLogLine: subscribe("daemon:log-line"),
    openLogFile: () => call("daemon.openLogFile"),
  };

  // Updates are not wired yet (no Sparkle feed); report a stable "none".
  const noop = () => () => {};
  const updater = {
    onUpdateAvailable: noop,
    onDownloadProgress: noop,
    onUpdateDownloaded: noop,
    downloadUpdate: () => Promise.resolve(),
    installUpdate: () => Promise.resolve(),
    getPreferences: () => Promise.resolve({ automaticUpdates: false }),
    setAutomaticUpdates: () => Promise.resolve({ automaticUpdates: false }),
    checkForUpdates: () => Promise.resolve({ ok: false, error: "Updates are not configured for this build" }),
  };

  Object.defineProperty(window, "desktopAPI", { value: Object.freeze(desktopAPI) });
  Object.defineProperty(window, "daemonAPI", { value: Object.freeze(daemonAPI) });
  Object.defineProperty(window, "updater", { value: Object.freeze(updater) });

  // WebKit ignores `-webkit-app-region`. Treat the top strip (where the
  // renderer draws its drag regions) as draggable unless the press lands on
  // an interactive control, matching the repo rule that controls in the top
  // 48px opt out with `no-drag`.
  const DRAG_STRIP_PX = 48;
  const INTERACTIVE =
    "button, a, input, textarea, select, label, summary, [role=button], [role=tab], [role=menuitem], [role=combobox], [role=textbox], [contenteditable=''], [contenteditable=true], [data-no-drag]";
  const inDragStrip = (event) =>
    event.button === 0 && event.clientY <= DRAG_STRIP_PX && !(event.target instanceof Element && event.target.closest(INTERACTIVE));

  window.addEventListener(
    "mousedown",
    (event) => {
      if (inDragStrip(event) && event.detail === 1) send("window.drag");
    },
    true,
  );
  window.addEventListener(
    "dblclick",
    (event) => {
      if (inDragStrip(event)) send("window.titlebarDoubleClick");
    },
    true,
  );
  // Mouse back/forward buttons (3/4) are surfaced as navigation gestures by
  // the host's NSEvent monitor; nothing else to do here.
})();
