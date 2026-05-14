---
name: savannah
description: "Prototype Safari browser integration for Codex through the Savannah macOS app and Safari extensions. Use when the user asks to check Savannah browser capability, app connection, Safari extension state, or Codex plugin install surfaces."
---

# Savannah

Use this skill when the user mentions `@savannah` or asks about the Savannah Safari browser integration.

Savannah is experimental. Prefer proof commands before browser work:

1. Run `scripts/savannah-client.mjs ping` to confirm the plugin script can execute.
2. Run `scripts/savannah-client.mjs getInfo` to report current backend assumptions and capability sources.
3. Run `scripts/check-codex-install-surfaces.mjs` when install location, marketplace, or cache behavior matters.

Do not claim Safari tab control is available until the app and extension report it through `getInfo`.

The plugin connects to the running Savannah app through a user-local Unix domain socket at `~/Library/Containers/com.galewilliams.Savannah/Data/tmp/savannah-codex/codex.sock`. The app writes the pairing token next to it as `codex-token`. If the app is not running, proof commands may return explicit plugin-local fallback responses. Set `SAVANNAH_REQUIRE_APP=1` when a command must fail instead of falling back.

The socket proof should not require extra app sandbox exceptions. `SpiderWeb` tab snapshots use the App Group container `group.com.galewilliams.Savannah`; if the App Group entitlement or container is missing, `getInfo` reports that in `webExtensionBridge`. Safari extension enablement is separate: build and run the containing app once, then enable `SpiderWeb` or `SafariTourGuide` in Safari Settings > Extensions. If a development extension is not visible, enable unsigned extensions in Safari's Developer settings.

## Runtime Shape

The first proof client should mimic the Chrome plugin's JavaScript browser object surface. Prefer this shape for agent-facing examples and usage:

```js
if (!globalThis.savannah) {
  const { setupSavannahRuntime } = await import("<plugin root>/scripts/savannah-client.mjs");
  await setupSavannahRuntime({ globals: globalThis });
}

const browser = await savannah.browsers.get("safari");
await browser.nameSession("short task name");
const userTabs = await browser.user.openTabs();
```

The goal is to make Savannah familiar to agents that already know Chrome's `agent.browsers`, `browser.user`, `browser.tabs`, `tab.playwright`, `tab.cua`, `tab.dom_cua`, and `tab.dev` surface. The transport underneath can be Savannah-owned.

Behind that object surface, mirror the Chrome browser-client method names where practical:

```text
ping
getInfo
getTabs
getUserTabs
getUserHistory
claimUserTab
createTab
navigateTabUrl
getTabInfo
reloadTab
closeTab
getPageSnapshot
finalizeTabs
nameSession
attach
detach
executeCdp
executeUnhandledCommand
moveMouse
```

The tab facade also exposes the first DOM-side Chrome-shaped read path:

```js
const tab = await browser.tabs.selected();
const snapshot = await tab.dom_cua.get_visible_dom();
```

That path is backed by `SpiderWeb` content-script messaging and returns a page snapshot with URL, title, viewport, visible text, and visible interactive elements. Treat it as a read-only proof, not full Chrome DOM CUA parity yet.

Unsupported commands must return explicit unsupported-command errors with a capability source of `unsupported` or `unproven`.

## Capability Priority

Use capability sources in this order:

1. `web-extension` for Safari WebExtension APIs exposed by `SpiderWeb`.
2. `app-extension` for Safari App Extension APIs exposed by `SafariTourGuide`.
3. `native-automation` for Accessibility, Apple Events, AppleScript, or event synthesis after the gap is proven and permissions are clear.
4. `unsupported` when Savannah cannot safely or truthfully provide the command.
