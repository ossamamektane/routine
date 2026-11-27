// Routine apps (Mac, iPhone, iPad): runs before the page, every time it loads.
// The app puts two values in front of this file:
//   ROUTINE_SAVED = { key: value }   the saved data (the app keeps it in storage.json)
//   ROUTINE_APP   = { platform: "mac" | "ios", shell: number }
// localStorage is replaced by a copy that lives in the app, so the data never depends on
// the browser engine keeping it. Every change is sent to the app right away.
(function () {
  var saved = ROUTINE_SAVED || {}, data = {};
  // The newest data, straight from the app (prompt waits for its answer), in case ROUTINE_SAVED is older.
  try { var raw = window.prompt("routine:storage"); if (raw) saved = JSON.parse(raw); } catch (e) {}
  for (var k in saved) if (Object.prototype.hasOwnProperty.call(saved, k)) data[k] = String(saved[k]);
  window.ROUTINE_APP = ROUTINE_APP;
  function send(m) { try { window.webkit.messageHandlers.routine.postMessage(m); } catch (e) {} }
  var store = {
    getItem: function (k) { k = String(k); return Object.prototype.hasOwnProperty.call(data, k) ? data[k] : null; },
    setItem: function (k, v) { k = String(k); v = String(v); data[k] = v; send({ type: "store", key: k, value: v }); },
    removeItem: function (k) { k = String(k); if (Object.prototype.hasOwnProperty.call(data, k)) { delete data[k]; send({ type: "unstore", key: k }); } },
    clear: function () { for (var k in data) { delete data[k]; send({ type: "unstore", key: k }); } },
    key: function (i) { var ks = Object.keys(data); return i >= 0 && i < ks.length ? ks[i] : null; }
  };
  Object.defineProperty(store, "length", { get: function () { return Object.keys(data).length; } });
  try {
    Object.defineProperty(window, "localStorage", { configurable: true, get: function () { return store; } });
    if (window.localStorage !== store) throw new Error("not replaced");
  } catch (e) {
    // Fallback: the engine's own localStorage, filled from the app's copy and mirrored back to it.
    try {
      var ls = window.localStorage, set = Storage.prototype.setItem, remove = Storage.prototype.removeItem;
      for (var k2 in data) set.call(ls, k2, data[k2]);
      Storage.prototype.setItem = function (k, v) { set.call(this, k, v); if (this === ls) send({ type: "store", key: String(k), value: String(v) }); };
      Storage.prototype.removeItem = function (k) { remove.call(this, k); if (this === ls) send({ type: "unstore", key: String(k) }); };
    } catch (e2) {}
  }
})();
