# Codex Chrome And Browser Runtime Integration Notes

Research date: 2026-05-12

This note captures public and local evidence about how Codex exposes Chrome and browser integration so Savannah can choose the right first implementation path.

## Current Conclusion

Savannah should mimic the Chrome plugin's JavaScript browser object surface first. The goal is not to depend on OpenAI's private Chrome bridge. The goal is to give Codex agents the same shape they already know how to use:

```js
const browser = await agent.browsers.get("extension");
await browser.nameSession("...");
const tabs = await browser.user.openTabs();
const tab = await browser.user.claimTab(tabs[0]);
await tab.goto("https://example.com");
await tab.playwright.getByText("Continue", { exact: false }).click();
await browser.tabs.finalize({ keep: [] });
```

The reason is model compatibility. OpenAI can train Codex on its own browser tools and bundled plugin surfaces. Savannah cannot assume that same training advantage, so the safest design is to preserve the browser-object vocabulary Codex already sees in Chrome's own skill:

```text
agent.browsers.get(...)
browser.user.openTabs()
browser.user.claimTab(...)
browser.user.history(...)
browser.tabs.selected()
browser.tabs.new()
browser.tabs.list()
browser.tabs.get(...)
browser.tabs.finalize(...)
browser.nameSession(...)
tab.goto(...)
tab.close()
tab.title()
tab.url()
tab.playwright.*
tab.cua.*
tab.dom_cua.*
tab.dev.*
```

That surface can be backed by Savannah-owned internals. The transport from Codex to the Savannah app can be a local socket, MCP server, XPC helper, native app endpoint, or another app-owned mechanism. What matters at the Codex-facing boundary is that the agent writes familiar Chrome-shaped JavaScript instead of learning a parallel `savannah_*` command vocabulary.

Using OpenAI's private native-pipe bridge would only be necessary if Savannah tries to become a first-class backend inside Codex's bundled `browser-client.mjs`. That may be unavailable or brittle for third-party plugins, and it is not required to copy the agent-facing object model.

Terminology matters here. In Codex Desktop, Browser Use is the built-in in-app browser path and selects the `iab` backend. Chrome appears under Computer Use alongside Any App, and the Chrome skill selects the `chrome` backend. Both paths use the local browser-object runtime shape, but they are different product surfaces and should not be collapsed in Savannah docs.

## Agent-Facing Chrome Surface

The Chrome plugin is not an MCP tool namespace in the usual sense. There is no direct model-visible tool call named `chrome.getUserTabs` or `browser_user_open_tabs`.

The model-visible call boundary is the generic Node REPL JavaScript tool. The Chrome skill instructs the agent to import the plugin's browser client, run setup, bind a browser object, and then use JavaScript methods on that object:

```js
const { setupAtlasRuntime } = await import("<chrome plugin root>/scripts/browser-client.mjs");
await setupAtlasRuntime({ globals: globalThis });
globalThis.browser = await agent.browsers.get("extension");
```

After that bootstrap, the skill tells the agent to use the bound `browser` object:

```js
const userTabs = await browser.user.openTabs();
const tab = await browser.user.claimTab(userTabs[0]);
await tab.playwright.getByText("Save", { exact: false }).click();
await browser.tabs.finalize({ keep: [] });
```

In the Chrome client internals, `browser.user.openTabs()` is translated to a lower-level backend request named `getUserTabs`. That backend request is not the normal agent-facing surface. It is one transport message inside the browser client.

The practical layers are:

1. Skill layer: tells the agent when to use Chrome and what JavaScript object methods are supported.
2. JavaScript client layer: installs `globalThis.agent`, `globalThis.display`, and the browser object API.
3. Transport layer: sends lower-level backend requests such as `getUserTabs`, `claimUserTab`, `createTab`, `executeCdp`, and `moveMouse`.
4. Backend layer: Chrome extension/native host code actually reads or controls the browser.

Savannah should copy layers 1 and 2 as closely as practical. Layers 3 and 4 should be Savannah-owned and Safari-native.

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

That lines up with the local Chrome plugin inspection: the plugin owns skill routing and setup checks, while `browser-client.mjs` builds the shared browser-object runtime and talks to the Chrome-native browser backend.

## Bridge Role

The special bridge in that client is `import.meta.__codexNativePipe`. It is a privileged Codex runtime hook that lets the bundled browser client discover and connect to native browser backend pipes. From the agent's perspective, it is not the API being used. It is a transport detail that makes the Chrome implementation work.

The bridge provides:

- native backend discovery
- session and turn metadata attachment
- browser security checks and user elicitation
- screenshot/display integration
- tab ownership and cleanup semantics
- a shared object facade over Chrome, in-app browser, and CDP-style backends

Those are useful behaviors, but they are not unique requirements for Savannah. Savannah can reproduce the same agent-facing object methods with its own transport if it provides comparable semantics and clear errors.

## Public Codex Repo Signals

The public `openai/codex` repository does not appear to publish the Chrome extension source in the searched paths, but it does expose useful integration seams:

- `chrome@openai-bundled` and `computer-use@openai-bundled` are in the discoverable-plugin allowlist in `codex-rs/core-plugins/src/lib.rs`.
- Browser-origin approval tests model browser-origin approval as an MCP-style elicitation with connector id `browser-use` and tool name `access_browser_origin`.
- macOS sandbox tests explicitly allow a `/tmp/codex-browser-use` Unix socket path, matching issue reports that the shared browser runtime and Chrome extension host communication involve local socket discovery.
- `BrowserUseExternal` is a stable, default-enabled feature flag, but the public source only describes it as a requirements gate for external browser integration. It does not expose a third-party backend registration API.
- The TUI hides the `openai-bundled` marketplace from normal plugin listing, which explains why Chrome can be present locally without behaving like an ordinary repo marketplace entry.

These details support treating the shared browser-client runtime as a first-class Codex browser transport, not merely a skill. They do not prove that third-party plugins can register new Chrome-like external browser backends.

## Core Plugin Loader Signals

The public core-plugin source is useful for normal plugin mechanics:

- `marketplace.rs` discovers repo marketplaces at `.agents/plugins/marketplace.json` and `.claude-plugin/marketplace.json`.
- Local marketplace plugin paths must start with `./` and must stay inside the marketplace root.
- Local plugin paths resolve relative to the marketplace root, not relative to `.agents/plugins/`.
- Git plugin sources can point at repository roots or git subdirectories, with optional `ref` or `sha` selectors.
- Invalid or unsupported marketplace plugin entries are skipped with warnings instead of failing the whole marketplace.
- `store.rs` installs plugins into `plugins/cache/<marketplace>/<plugin>/<version>/` under Codex home.
- `store.rs` chooses the cache version from `plugin.json` when present, otherwise `local`.
- `loader.rs` refreshes non-curated configured plugin cache entries from discovered marketplaces; curated plugins use the curated marketplace SHA-derived cache version.
- `loader.rs` loads skills, MCP servers, apps, and hooks from the installed cache root, not directly from the source marketplace path.
- `manager.rs` installs a resolved marketplace plugin, writes its enabled state into user config, and uses the same installed cache as the later runtime loader.

For Savannah, this means the repo-local marketplace shape is correct for ordinary plugin testing. It also means editing the source plugin is not enough after installation; Codex may keep using the cached copy until the plugin cache refreshes or the plugin is reinstalled.

The public code did not show a way for a normal plugin manifest to declare a new `agent.browsers` backend. The visible manifest-loading path exposes skills, MCP servers, apps, and hooks. Browser backend registration still appears to live in the bundled browser-client/runtime side rather than the generic core-plugin loader.

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

The Savannah plugin now starts with:

```text
plugins/savannah/
  .codex-plugin/plugin.json
  skills/savannah/SKILL.md
  scripts/savannah-client.mjs
  scripts/check-codex-install-surfaces.mjs
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

The repo-local marketplace lives at `.agents/plugins/marketplace.json` and points at `./plugins/savannah`. That matches the official local-plugin path for repo-scoped testing. If Savannah later needs a personal install for day-to-day use, the personal marketplace at `~/.agents/plugins/marketplace.json` can point at an absolute or home-rooted Savannah plugin source, and Codex will install a cached copy under `~/.codex/plugins/cache/<marketplace>/<plugin>/<version>/`.

Chrome itself is not installed from this repo-local marketplace shape. On this machine it is an OpenAI-bundled plugin under `~/.codex/plugins/cache/openai-bundled/chrome/0.1.7/`, with a `latest` sibling. Browser Use and Computer Use have sibling bundled cache entries. The Savannah proof should therefore try the ordinary marketplace path first, then only consider a bundled-cache-style copy if Codex cannot expose the browser backend shape through a normal local plugin.

## Savannah App Shape

The app should expose one local command endpoint to the Codex-side plugin client. The selected first transport is a user-local Unix domain socket with length-prefixed JSON-RPC messages.

The first socket location is a short path inside Savannah's sandbox container:

```text
~/Library/Containers/com.galewilliams.Savannah/Data/tmp/savannah-codex/codex.sock
```

The first pairing token location is:

```text
~/Library/Containers/com.galewilliams.Savannah/Data/tmp/savannah-codex/codex-token
```

The app creates the runtime directory with `0700` permissions, creates the token file with `0600` permissions, and creates the socket with `0600` permissions. The plugin reads the token and sends a `hello` JSON-RPC request before any browser command.

The runtime directory intentionally uses the sandbox container's short `Data/tmp` path instead of Application Support. A sandboxed macOS app sees Application Support through its container path, which can exceed the Unix domain socket path length limit. A top-level `/tmp` path would keep the socket short but requires an app sandbox exception. The container `Data/tmp` path is short enough for Unix sockets, writable by the app without extra sandbox exceptions, and still readable by the separate Codex plugin script through the user's Library path.

The frame format is intentionally tiny:

```text
4-byte big-endian payload length
UTF-8 JSON payload
```

The initial handshake request is:

```json
{
  "jsonrpc": "2.0",
  "id": "req_1",
  "method": "hello",
  "params": {
    "protocolVersion": "0.1.0",
    "client": "savannah-codex-plugin",
    "token": "<pairing token>"
  }
}
```

After the handshake, the plugin can send raw Chrome-compatible backend methods such as `ping`, `getInfo`, `getUserTabs`, `nameSession`, and `finalizeTabs`. The JavaScript browser object surface remains the preferred agent-facing layer above those raw methods.

Unix socket plus JSON-RPC is the first implementation choice because it is:

- directly usable from Node through `net.createConnection(path)`
- directly usable from the macOS app through POSIX sockets or Network-framework-compatible Unix endpoints
- bidirectional without exposing a localhost TCP port
- easier for a Codex plugin script than `NSXPCConnection`
- explicit enough to inspect, log, and version

XPC remains a later hardening option if Savannah needs signed native peer identity or a helper process boundary. Localhost HTTP or WebSocket remains a fallback only if browser-debugger-style tooling makes it materially useful.

This socket proof does not require extra app sandbox exceptions. If Savannah later moves the socket outside its container, it will need either a sandbox temporary file exception, an App Group container, or a non-sandboxed helper. Safari extension installation and enablement are separate:

- Build and run the containing Savannah app at least once so Safari can discover the bundled extensions.
- In Safari, enable the extension under Safari Settings > Extensions.
- During unsigned development, enable Safari's developer setting for unsigned extensions if Safari does not show the extension.
- In Safari 17 or later, also check profile-specific extension enablement when testing with Safari profiles.

`SpiderWeb` native messaging uses the App Group container `group.com.galewilliams.Savannah` for extension-to-app tab snapshots:

```text
~/Library/Group Containers/group.com.galewilliams.Savannah/savannah-codex/spiderweb-state.json
```

That App Group is separate from the Codex socket sandbox decision. The socket can stay inside the Savannah app container, but browser state shared by the Safari Web Extension and containing app needs a shared container. If the App Group entitlement is missing from either the Savannah app target or the `SpiderWeb` target, `getInfo` reports the missing shared state instead of pretending tab inventory is available.

The first live proof succeeded with the App Group entitlement present on the Savannah app, `SpiderWeb`, and `SafariTourGuide` targets. After Safari enabled both extensions, `SpiderWeb` wrote `spiderweb-state.json` and the Codex-side `getTabs` call returned `inventory: "web-extension-snapshot"` with the active `https://example.com/` tab.

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

The smallest proof should expose the Chrome-shaped object surface from `scripts/savannah-client.mjs`:

```js
const { setupSavannahRuntime } = await import("<plugin root>/scripts/savannah-client.mjs");
await setupSavannahRuntime({ globals: globalThis });
const browser = await savannah.browsers.get("safari");
await browser.nameSession("short task name");
const tabs = await browser.user.openTabs();
await browser.tabs.finalize({ keep: [] });
```

Behind that object surface, the proof currently answers these raw commands:

```text
ping -> pong
getInfo -> backend id, app version, extension state, capability sources
getTabs -> at least one truthful tab/page inventory shape, even if partial
```

`ping` and `getInfo` first try the Savannah app over the Unix socket. When the app is not running, the plugin returns explicit plugin-local fallback responses unless `SAVANNAH_REQUIRE_APP=1` is set. `getTabs` and `getUserTabs` read the latest `SpiderWeb` tab snapshot when the WebExtension has written one; otherwise they return an explicit `unproven` empty inventory with the bridge-state reason.

Success for the next slice means Codex can call Savannah through the chosen plugin/backend path and Savannah can report a capability list that distinguishes:

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
- [openai/codex marketplace loader](https://github.com/openai/codex/blob/main/codex-rs/core-plugins/src/marketplace.rs)
- [openai/codex plugin loader](https://github.com/openai/codex/blob/main/codex-rs/core-plugins/src/loader.rs)
- [openai/codex plugin manager](https://github.com/openai/codex/blob/main/codex-rs/core-plugins/src/manager.rs)
- [openai/codex plugin store](https://github.com/openai/codex/blob/main/codex-rs/core-plugins/src/store.rs)
- [openai/codex feature flags](https://github.com/openai/codex/blob/main/codex-rs/features/src/lib.rs)
- [openai/codex TUI plugin list filtering](https://github.com/openai/codex/blob/main/codex-rs/tui/src/app/background_requests.rs)
- [openai/codex issue 20642: external or detachable Browser Use](https://github.com/openai/codex/issues/20642)
- [openai/codex issue 22057: Browser Use and Chrome backend timeouts](https://github.com/openai/codex/issues/22057)
- [openai/codex issue 21868: Chrome connected but fallback routing on Windows](https://github.com/openai/codex/issues/21868)
- [openai/codex issue 21598: plugin discovery and backend availability mismatch](https://github.com/openai/codex/issues/21598)
