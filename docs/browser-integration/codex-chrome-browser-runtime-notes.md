# Codex Chrome And Browser Runtime Integration Notes

Research date: 2026-05-12

This note captures public and local evidence about how Codex exposes Chrome and browser integration so Savannah can choose the right first implementation path.

## Current Conclusion

Savannah should prototype a Chrome-compatible browser client first, then fall back to a regular Codex plugin command surface only if the Chrome/Computer Use browser backend shape is not available to third-party plugins.

The reason is tool compatibility. The Chrome integration does not just expose a standalone skill. Its plugin client registers a browser backend that Codex presents through the familiar browser tool families:

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
playwright_*
cua_*
dom_cua_*
```

If Savannah can participate in that backend shape, Codex users get the Safari equivalent without learning a parallel command vocabulary. If it cannot, Savannah should still ship a normal plugin, but that path is likely less Chrome-compatible.

Terminology matters here. In Codex Desktop, Browser Use is the built-in in-app browser path and selects the `iab` backend. Chrome appears under Computer Use alongside Any App, and the Chrome skill selects the `chrome` backend. Both paths use the local `browser-client.mjs` runtime shape, but they are different product surfaces and should not be collapsed in Savannah docs.

## Official OpenAI Signals

OpenAI's Codex Chrome extension docs describe Chrome as a plugin-installed browser surface for tasks that need signed-in browser state. They explicitly steer local development servers, file-backed previews, and public pages toward the in-app browser first, and steer signed-in sites such as business tools toward Chrome.

The same docs describe these user-facing behaviors:

- install from Codex's Plugins surface
- confirm the Chrome extension shows Connected
- invoke `@Chrome` directly or let Codex suggest it
- keep thread work grouped in Chrome tab groups
- ask before interacting with each new website host
- gate browser history separately, without an always-allow option
- rely on Chrome extension permissions for debugger access, broad website access, browsing history, notifications, bookmarks, downloads, native app communication, and tab groups

That lines up with the local Chrome plugin inspection: the plugin owns skill routing and setup checks, while `browser-client.mjs` builds the shared browser-client runtime and talks to the Chrome-native browser backend.

## Public Codex Repo Signals

The public `openai/codex` repository does not appear to publish the Chrome extension source in the searched paths, but it does expose useful integration seams:

- `chrome@openai-bundled` and `computer-use@openai-bundled` are in the discoverable-plugin allowlist in `codex-rs/core-plugins/src/lib.rs`.
- Browser-origin approval tests model browser-origin approval as an MCP-style elicitation with connector id `browser-use` and tool name `access_browser_origin`.
- macOS sandbox tests explicitly allow a `/tmp/codex-browser-use` Unix socket path, matching issue reports that the shared browser runtime and Chrome extension host communication involve local socket discovery.

These details support treating the shared browser-client runtime as a first-class Codex browser transport, not merely a skill. They do not prove that third-party plugins can register new Chrome-like external browser backends.

## Public Issue Tracker Signals

Open issues in `openai/codex` provide useful failure-mode evidence:

- External/detachable browser requests mention existing backend names such as `iab`, `chrome`, and `cdp`, and a possible `BrowserUseExternal` feature flag.
- Some reports show Chrome extension and native-host checks passing while `agent.browsers.list()` or backend acquisition still times out.
- Some reports show `@Chrome` falling back to isolated Chrome DevTools or MCP-style controlled profiles instead of the user's signed-in Chrome profile.
- Some reports show plugin discovery, marketplace availability, and runtime-advertised browser backends diverging.

For Savannah, the lesson is to test each layer separately:

1. Is the Savannah plugin installed and enabled?
2. Does Codex expose the Savannah browser backend to the current turn as a Chrome/Computer Use-style browser surface?
3. Can the plugin client discover and connect to the Savannah app?
4. Can the Savannah app reach `SpiderWeb` through Safari Web Extension native messaging?
5. Can `SpiderWeb` operate the requested Safari tab through WebExtension APIs?
6. If a fallback route is used, does the command report that it is using `SafariTourGuide` or native automation instead of silently changing capability source?

## Plugin Shape

The Savannah plugin should start with:

```text
plugins/savannah/
  .codex-plugin/plugin.json
  skills/savannah/SKILL.md
  scripts/savannah-client.mjs
  scripts/check-app-connection.mjs
  scripts/check-safari-extension-state.mjs
  assets/
```

Add `.mcp.json` only if a normal MCP server becomes necessary. The official plugin docs say plugins can bundle skills, apps, MCP servers, hooks, and assets. They do not require MCP for every plugin.

The first client should copy the Chrome plugin's tested shape as far as possible:

- bootstrap from a skill
- expose a browser object or backend client
- provide connection diagnostics before doing browser work
- keep command names and response fields close to Chrome
- return clear unsupported-command errors for gaps

## Savannah App Shape

The app should expose one local command endpoint to the Codex-side plugin client. The endpoint can be a local socket, XPC service, or another app-owned local transport, but it should be versioned and inspectable.

The app owns:

- backend liveness
- command routing
- session registry
- capability reporting
- durable diagnostics
- operator-facing permission state
- dispatch to `SpiderWeb`, `SafariTourGuide`, or native automation

`SpiderWeb` should be the first browser-control implementation target. `SafariTourGuide` should fill `SafariServices` gaps. Native automation should fill only proven extension-API gaps and should report its permission requirements in `getInfo`.

## First Proof Target

The smallest proof should answer:

```text
ping -> pong
getInfo -> backend id, app version, extension state, capability sources
getTabs -> at least one truthful tab/page inventory shape, even if partial
```

Success means Codex can call Savannah through the chosen plugin/backend path and Savannah can report a capability list that distinguishes:

- WebExtension-backed
- AppExtension-backed
- native automation-backed
- unsupported
- unproven

Failure should still be useful. If Chrome-like browser backend registration is not open to third-party plugins, the prototype should prove that quickly and keep the regular plugin/MCP fallback path clean.

## References

- [Codex Chrome extension](https://developers.openai.com/codex/app/chrome-extension)
- [Codex plugins](https://developers.openai.com/codex/plugins)
- [Build plugins](https://developers.openai.com/codex/plugins/build)
- [openai/codex core plugin allowlist](https://github.com/openai/codex/blob/main/codex-rs/core-plugins/src/lib.rs)
- [openai/codex issue 20642: external or detachable Browser Use](https://github.com/openai/codex/issues/20642)
- [openai/codex issue 22057: Browser Use and Chrome backend timeouts](https://github.com/openai/codex/issues/22057)
- [openai/codex issue 21868: Chrome connected but fallback routing on Windows](https://github.com/openai/codex/issues/21868)
- [openai/codex issue 21598: plugin discovery and backend availability mismatch](https://github.com/openai/codex/issues/21598)
