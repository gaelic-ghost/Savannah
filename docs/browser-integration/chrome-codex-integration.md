# Codex Chrome Browser Integration

Research date: 2026-05-12

This note records how the installed Codex Chrome integration is shaped so Savannah can preserve the same Codex-facing tool vocabulary where Safari allows it.

## Summary

The Codex Chrome integration is a three-part system:

- a Codex plugin bundle that exposes skill guidance, setup checks, and a bundled browser client
- a native messaging host named `com.openai.codexextension`
- a Manifest V3 Chrome extension named `Codex`

The extension is not just a page content script. Its background service worker connects to the native host, exposes browser/session commands over a JSON-RPC-style protocol, uses Chrome extension APIs for tabs, groups, history, downloads, and storage, and uses `chrome.debugger` as the Chrome DevTools Protocol transport for page control.

## Local Evidence Snapshot

The installed local snapshot inspected for this report had these identifiers:

- Codex Chrome plugin version: `0.1.7`
- Chrome extension ID: `hehggadaopoacecdllhhajmbjkdcmajg`
- Chrome extension version: `1.1.4`
- Native host name: `com.openai.codexextension`
- Native host type: `stdio`
- Extension manifest version: `3`

The native host manifest allows only this origin:

```text
chrome-extension://hehggadaopoacecdllhhajmbjkdcmajg/
```

## Components

### Codex Plugin Bundle

The plugin manifest describes Chrome as a productivity plugin that lets Codex control Chrome with existing browser state, including logged-in sites, open tabs, and page content.

The plugin bundle includes:

- `skills/chrome/SKILL.md`
- `scripts/browser-client.mjs`
- Chrome setup and health-check scripts
- `scripts/extension-id.json`
- a bundled platform-specific `extension-host` binary

The skill guidance treats the extension as the required backend. If communication fails, the supported recovery path is checking Chrome, the extension, and the native host manifest, then asking the user to repair or reinstall through the Codex plugin UI when the install surface is broken.

### Native Host

The native host manifest is created under Chrome's native messaging host location and points at the bundled `extension-host` binary. The manifest shape follows Chrome native messaging:

```json
{
  "name": "com.openai.codexextension",
  "description": "Codex chrome native messaging host",
  "type": "stdio",
  "path": ".../extension-host",
  "allowed_origins": [
    "chrome-extension://hehggadaopoacecdllhhajmbjkdcmajg/"
  ]
}
```

The Codex-side browser client also uses a privileged native pipe bridge inside the Codex runtime. It frames JSON messages with a 32-bit length prefix before sending them through that native pipe.

### Chrome Extension

The installed extension has:

- a Manifest V3 background service worker: `background.js`
- a popup page: `popup.html`
- a runtime-injected content script: `content-scripts/codex.js`
- a cursor image exposed as a web-accessible resource

The extension declares broad host access and these permissions:

```text
alarms
bookmarks
debugger
downloads
downloads.ui
favicon
history
nativeMessaging
notifications
readingList
scripting
sessions
storage
tabGroups
tabs
topSites
```

## Connection Flow

The control path is:

```text
Codex runtime
-> browser-client.mjs
-> privileged native pipe bridge
-> extension-host binary
-> Chrome native messaging
-> Chrome extension service worker
-> Chrome extension APIs and Chrome DevTools Protocol
```

The extension service worker calls `chrome.runtime.connectNative` with the native host name. It reconnects with alarms/timeouts when disconnected and stores connection status in `chrome.storage.local` as `NATIVE_HOST_STATUS`.

The popup reads that storage key and can request current status with `GET_NATIVE_HOST_STATUS`.

## Request Protocol

Both sides use JSON-RPC-style messages with:

- `jsonrpc: "2.0"`
- `method`
- `params`
- optional `id` for request/response
- `result` or `error`

Visible request methods between the Codex browser client and extension backend include:

```text
ping
getInfo
getTabs
getUserTabs
getUserHistory
claimUserTab
createTab
finalizeTabs
nameSession
attach
detach
executeCdp
executeUnhandledCommand
moveMouse
```

The extension can also send events back to Codex, including CDP events and download-change events.

## Browser Control Model

### Tabs and Sessions

The extension tracks Codex browser sessions and maps tabs to sessions. It can:

- query Chrome tabs
- create tabs
- remove tabs
- claim existing user tabs
- group tabs into Codex-owned tab groups
- move deliverable tabs into a separate deliverable group
- name a Codex session group
- finalize which tabs stay open after a session

Chrome tab groups are part of the user-visible operating model, not just internal metadata. The extension stores group metadata in `chrome.storage.local`.

### CDP Bridge

The extension uses `chrome.debugger` as its Chrome DevTools Protocol transport:

- `chrome.debugger.attach`
- `chrome.debugger.sendCommand`
- `chrome.debugger.detach`
- `chrome.debugger.onEvent`
- `chrome.debugger.onDetach`
- `chrome.debugger.getTargets`

The Codex-side client wraps that as a CDP helper and then builds Playwright-style locator actions, screenshots, DOM reads, clicks, typing, downloads, file chooser handling, and cursor motion on top.

### Content Script Overlay

The content script is mostly a user-visible overlay and liveness handshake:

- it injects a closed shadow root with a fixed-position Codex cursor overlay
- it responds to `CONTENT_PING`
- it receives `AGENT_CURSOR_STATE`
- it sends `AGENT_CURSOR_ARRIVED`
- it uses `chrome.runtime.getURL("images/cursor-chat.png")` for the cursor asset

The content script is injected with `chrome.scripting.executeScript` when a tab becomes part of a Codex browser session.

### Safety Gates

The Codex-side client performs URL and file-transfer checks before commands that navigate, inspect, upload, or download. Some commands are treated as safe without an origin prompt, including listing tabs, creating tabs, claiming tabs, selecting tabs, closing tabs, naming a session, and waiting.

The client checks remote URL policy through ChatGPT backend site-status endpoints for ordinary web origins. It also uses Codex elicitation before sensitive browser-origin or file-transfer operations.

## Codex-Facing Tool Families

The plugin does not statically list all tools in its plugin manifest. `browser-client.mjs` builds a browser-use runtime and exposes a dynamic tool surface. The visible command families are:

```text
browser_user_open_tabs
browser_user_claim_tab
browser_user_history
list_tabs
create_tab
close_tab
selected_tab
name_session
navigate_tab_url
playwright_* locator, screenshot, file chooser, wait, and download commands
cua_* and dom_cua_* pointer, screenshot, and download commands
```

Savannah should treat these names as the compatibility target unless a Safari limitation forces a narrower shape.

## External References

- [Chrome native messaging](https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging)
- [chrome.debugger](https://developer.chrome.com/docs/extensions/reference/api/debugger)
- [chrome.scripting](https://developer.chrome.com/docs/extensions/reference/api/scripting)
- [chrome.tabs](https://developer.chrome.com/docs/extensions/reference/api/tabs)
- [chrome.tabGroups](https://developer.chrome.com/docs/extensions/reference/api/tabGroups)
- [chrome.downloads](https://developer.chrome.com/docs/extensions/reference/api/downloads)
- [Chrome extension manifest V3](https://developer.chrome.com/docs/extensions/develop/migrate/what-is-mv3)
- [Codex Chrome extension user docs](https://developers.openai.com/codex/app/chrome-extension)

