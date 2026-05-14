# Safari Equivalence Map

Research date: 2026-05-12

This note maps the Codex Chrome browser integration onto Savannah's current macOS app plus Safari extension shape.

## Current Savannah Shape

Savannah currently contains:

- a macOS SwiftUI app target named `Savannah`
- a Safari App Extension target named `SafariTourGuide`
- a Safari content script resource named `script.js`
- an `SFSafariExtensionHandler` subclass that receives Safari extension requests and script messages
- a Safari Web Extension target named `SpiderWeb`
- a Manifest V3 web extension resource set under `SpiderWeb/Resources`
- a `SafariWebExtensionHandler` native app-extension entry point for WebExtension native messaging

Savannah now has both Safari extension shapes in the same Xcode project. `SafariTourGuide` is a Safari App Extension that uses `SafariServices` classes such as `SFSafariExtensionHandler`, `SFSafariPage`, `SFSafariWindow`, and `SFSafariToolbarItem`. `SpiderWeb` is a Safari Web Extension target that uses a manifest-based WebExtensions runtime closer to Chrome and Firefox extension APIs.

Safari's extension families have different tradeoffs:

- Safariextz extensions are obsolete and not relevant for Savannah.
- Safari content blockers are too limited because they do not run arbitrary JavaScript or receive page content.
- Safari App Extensions are Mac-only, can provide native Mac UI in Safari, and use Safari's unique `SafariServices` API.
- Safari Web Extensions are the cross-platform path, closer to Chrome and Firefox WebExtensions, but Safari does not support every WebExtensions API and still requires a native app wrapper for distribution.

The current Savannah project is therefore a real hybrid baseline: native-Mac-control through `SafariTourGuide`, and WebExtensions parity experiments through `SpiderWeb`.

## API Boundary

The Safari App Extension target cannot be treated as a WebExtensions runtime. Its injected script gets the Safari app-extension `safari` object, and its native code gets `SafariServices` proxy objects. That is enough for script injection, page messaging, active window and tab access, opening new Safari windows and tabs, reloading pages, and native Mac app coordination.

The Safari App Extension target does not directly expose WebExtensions APIs such as:

```text
browser.tabs
browser.windows
browser.scripting
browser.devtools
browser.runtime.sendNativeMessage
browser.runtime.connectNative
```

Those APIs belong to Safari Web Extensions. In Savannah terms, that means WebExtension-style tab inventory, screenshot capture, dynamic script injection, and native messaging are not features we can simply call from `SafariTourGuide` as it exists today. We either implement the smaller Safari App Extension surface honestly, route WebExtension-shaped work through `SpiderWeb`, or use a separate native fallback such as Accessibility, Apple Events, AppleScript, or another user-approved macOS automation path.

## Design Goal

Savannah should preserve the Codex-facing JavaScript browser object surface from the Chrome plugin as closely as possible. This is the primary compatibility goal because Codex is likely to be better at using OpenAI's own trained and documented tool shapes than a new Savannah-specific command vocabulary.

The target surface is the object model that the Chrome skill exposes after bootstrap:

```text
agent.browsers.get(...)
browser.nameSession(...)
browser.user.openTabs()
browser.user.claimTab(...)
browser.user.history(...)
browser.tabs.selected()
browser.tabs.new()
browser.tabs.list()
browser.tabs.get(...)
browser.tabs.finalize(...)
tab.goto(...)
tab.close()
tab.title()
tab.url()
tab.playwright.*
tab.cua.*
tab.dom_cua.*
tab.dev.*
```

Under that JavaScript object surface, Savannah should keep the lower-level command names and command shapes from the Chrome plugin as closely as possible:

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
playwright_* commands where a page automation backend can support them
cua_* and dom_cua_* commands where native or script-assisted pointer control can support them
```

The practical product goal is compatibility at the Codex plugin boundary. Safari-specific implementation details should stay behind that boundary. The transport does not need to be OpenAI's private native-pipe bridge. Savannah can use a Savannah-owned endpoint, MCP server, socket, XPC helper, or other native app route as long as the agent-facing browser object behaves like Chrome's where supported and fails explicitly where Safari cannot match it.

## Implementation Priority

Use this priority order before adding command behavior:

1. Prefer `SpiderWeb` and Safari WebExtension APIs for browser-wide behavior that maps to Chrome extension APIs.
2. Use `SafariTourGuide` and Safari App Extension APIs for `SafariServices` capabilities such as active window, active tab, active page, page properties, app-extension UI, and app-extension script messaging.
3. Use Accessibility, Apple Events, AppleScript, or event synthesis only when neither extension surface provides the capability and the command can explain its required macOS permission clearly.
4. Return an explicit unsupported-command error when the behavior cannot be implemented safely or truthfully.

Native automation is therefore a fallback capability source, not a hidden compatibility layer. Any command backed by native automation should report that source in diagnostics or `getInfo` capability metadata.

## Codex Integration Open Path

Savannah still needs an early proof of how it plugs into Codex:

- Preferred proof: make Savannah expose a Chrome-shaped JavaScript browser object so existing `browser.user.*`, `browser.tabs.*`, `tab.playwright.*`, `tab.cua.*`, `tab.dom_cua.*`, and `tab.dev.*` usage patterns stay intact.
- Compatibility proof: keep lower-level Chrome command names such as `getUserTabs`, `claimUserTab`, `createTab`, `finalizeTabs`, `executeCdp`, and `moveMouse` behind that object surface so the implementation remains easy to compare with Chrome.
- Fallback proof: use a regular Codex plugin transport if Chrome-like browser backend registration is not available or is too tightly coupled to OpenAI's bundled Chrome path, but keep the Chrome-shaped JavaScript object as the agent-facing API.
- Packaging proof: decide whether Savannah installs a local plugin copy from the app bundle, points Codex at a git/local plugin source, or offers both for development and release builds.

Codex Desktop's Browser Use product surface is the built-in in-app browser. Chrome is exposed separately under Computer Use alongside Any App, even though both paths use a shared browser-client API shape internally. Savannah should target Chrome parity, not the in-app-browser product role.

The Chrome-like object surface is more important than the exact bridge path. Reusing OpenAI's private bundled bridge would be useful only if it is available and stable for third-party plugins. The Savannah design should not require that bridge to achieve agent familiarity.

See [Codex Chrome And Browser Runtime Integration Notes](codex-chrome-browser-runtime-notes.md) for the local plugin, public Codex repo, and public issue-tracker evidence behind this distinction.

## Chrome Capability To Safari Option Matrix

| Chrome capability | Chrome mechanism | Safari-native candidate | Current confidence |
| --- | --- | --- | --- |
| Native bridge | `chrome.runtime.connectNative` to native messaging host | containing macOS app, app group storage, XPC, local socket, or app-owned helper | Medium |
| Extension background runtime | MV3 service worker | `SFSafariExtensionHandler` plus containing app process | Medium |
| Page content script | `chrome.scripting.executeScript`, runtime content script | `SFSafariContentScript` declared in extension Info.plist | High |
| Script-to-extension message | `chrome.runtime.sendMessage` | `safari.extension.dispatchMessage` to `SFSafariExtensionHandler.messageReceived` | High |
| Extension-to-script message | `chrome.tabs.sendMessage` | `SFSafariPage.dispatchMessageToScript` | High |
| Active tab and window model | `chrome.tabs`, `chrome.windows` | `SFSafariApplication.getActiveWindow`, `SFSafariWindow.getActiveTab`, `SFSafariTab.getActivePage`, `SFSafariPage.getPropertiesWithCompletionHandler` | High for active context |
| Existing tab inventory | `chrome.tabs.query` | Safari App Extension APIs proved active-window/active-tab access, but full all-window/all-tab enumeration is still unproven; may require native accessibility, AppleScript, Safari Web Extension APIs, or a user-observed-tab model | Low for App Extension, medium candidate for Web Extension |
| Tab creation/navigation | `chrome.tabs.create`, CDP navigation | `SFSafariApplication.openWindow(with:)`, `SFSafariWindow.openTab(with:makeActiveIfPossible:)`, active page messaging for script-side navigation only when safe | Medium |
| Tab groups/session grouping | `chrome.tabGroups` | no direct Safari App Extension equivalent identified yet; may need Savannah-side logical grouping | Low |
| Browser history | `chrome.history.search` | no direct Safari App Extension equivalent identified yet; likely unavailable without separate Safari/private data access | Low |
| Downloads | `chrome.downloads` events and download commands | no direct Safari App Extension equivalent identified yet; native app can manage its own downloads, but not necessarily Safari's download list | Low |
| Window close | `chrome.windows.remove` or tab/window commands | `SFSafariWindow.close()` | Medium |
| CDP page control | `chrome.debugger` + CDP | no direct Safari App Extension equivalent found; Safari Web Inspector extensions add developer UI, not a proven automation transport | Low |
| Cursor overlay | injected content script and image asset | Safari content script with DOM overlay and extension resource asset | High |
| File upload | Playwright file chooser path through browser backend | likely needs native UI automation or page-script plus user-mediated file input support | Low |

## Candidate Savannah Architecture

### Codex-Facing Plugin Surface

Savannah should expose a browser backend that speaks the same command family as the Chrome plugin. The first implementation can advertise only the commands it genuinely supports, but names should stay compatible:

- use `browser_id: "safari"` or a Savannah-specific backend ID only at selection time
- keep tab command names identical where behavior matches
- keep browser-user command names identical where behavior matches
- keep Playwright-style command names only when selector semantics and timeouts are close enough to be useful
- return explicit unsupported-command errors for gaps instead of silent fallbacks

### Native App Role

The macOS app can own process-level capabilities that the Safari extension cannot:

- Codex plugin connection endpoint at `~/Library/Containers/com.galewilliams.Savannah/Data/tmp/savannah-codex/codex.sock`
- session registry
- command routing
- app group shared state
- durable logs and diagnostics
- optional helper or local service
- permission prompts or operator-visible status UI

This is the closest Savannah equivalent to the Chrome plugin's bundled native host plus extension-host binary.

The first Codex-to-app transport is a user-local Unix domain socket carrying length-prefixed JSON-RPC. The app owns the socket and pairing token under a short runtime directory inside its sandbox container. The plugin reads the token, sends a `hello` handshake, then routes Chrome-shaped backend methods over the socket. This keeps the agent-facing JavaScript browser object independent from the internal transport while avoiding a localhost TCP service.

No additional app sandbox exception is expected for the socket proof. Safari extension installation is a separate operator step: build and run the containing app once, enable the extension in Safari Settings > Extensions, and enable unsigned extension development in Safari's Developer settings if the development build does not appear.

Shared browser state is a separate app-extension concern. `SpiderWeb` writes native-messaging tab snapshots into the App Group container `group.com.galewilliams.Savannah`, and the app reads that file when answering `getTabs` and `getUserTabs`. The first snapshot path is:

```text
~/Library/Group Containers/group.com.galewilliams.Savannah/savannah-codex/spiderweb-state.json
```

If the App Group is not available, Savannah reports that state explicitly in `webExtensionBridge`. In the current local proof, the App Group container is available, Safari reports both bundled extensions through `SFSafariExtensionManager`, and both extensions are enabled in Safari Settings.

### Safari Web Extension Option

`SpiderWeb` is Savannah's Safari Web Extension target. It is the candidate surface for closer Chrome tool parity than the Safari App Extension APIs expose. Apple's compatibility guidance says Safari Web Extensions use WebExtensions-style JavaScript APIs, can use native messaging through the containing app's native extension, and should be checked against Safari's supported API matrix.

The initial `SpiderWeb` implementation now includes a first native-messaging tab snapshot path:

- manifest version 3
- `background.js` as a module background script
- `content.js` matched only on `*://example.com/*`
- popup resources and toolbar icon assets
- `nativeMessaging` and `tabs` permissions
- native handler class `SafariWebExtensionHandler`
- `browser.tabs.query({})` snapshots from the background script
- `browser.runtime.sendNativeMessage(...)` delivery to the native handler
- App Group JSON snapshot writing for the containing app to read
- `browser.tabs.sendMessage(...)` page snapshot requests from the background script to `content.js`
- a read-only `tab.dom_cua.get_visible_dom()` facade backed by `getPageSnapshot`
- node-id and selector actions through `tab.dom_cua.click(...)`, `tab.dom_cua.type(...)`, and `tab.dom_cua.fill(...)`

That means `SpiderWeb` is now the first WebExtension-backed tab inventory path. With both Safari extensions enabled and all three targets carrying the `group.com.galewilliams.Savannah` App Group entitlement, `getTabs` returned a `web-extension-snapshot` inventory containing Safari's Start Page tab and an active `https://example.com/` tab.

This option could help with:

- `browser.tabs`-style tab commands
- `browser.windows`-style window commands on macOS
- `browser.scripting` and `browser.tabs` script/CSS injection commands
- `browser.tabs.captureVisibleTab`
- `browser.runtime.sendNativeMessage` between extension JavaScript and the containing app's native extension
- `browser.devtools` and a `devtools_page` for a Safari Web Inspector extension

This option does not erase the Safari gaps. Apple's compatibility guidance calls out unsupported or partial areas that matter to Chrome parity:

- `scripting.executeScript` does not support `injectImmediately`
- dynamic content script registration is Safari-version-dependent
- `tabs.move` is unsupported
- `tabs.highlighted` is unsupported
- `tabs.update` does not support `highlighted`
- some WebExtensions navigation events and request-blocking features are unsupported or partial
- content scripts cannot send native messages directly; native messaging comes from background scripts or extension pages

Treat `SpiderWeb` as a companion target, not an automatic replacement for `SafariTourGuide`.

### Hybrid Target Baseline

The project now includes both a Safari App Extension and a Safari Web Extension. Apple documents both extension kinds as app-extension targets embedded in a containing app. A Safari App Extension is added to an existing macOS app as a Safari Extension target whose type is Safari App Extension. A Safari Web Extension is also packaged as an app extension inside a containing app, and Xcode can create or package one as a Safari Extension App.

Apple also documents migration from a Safari App Extension to a Safari Web Extension as an explicit replacement behavior controlled by the `SFSafariAppExtensionBundleIdentifiersToReplace` key. That replacement key is important because it implies replacement is opt-in. `SpiderWeb` should not declare replacement of `SafariTourGuide` unless Savannah intentionally migrates away from the App Extension.

The open proof point is user experience and Safari settings behavior:

- both extensions may appear as separate enablement rows in Safari Settings
- each extension may need its own website/profile/private-browsing permissions
- app-to-extension routing must address the correct extension bundle identifier
- the containing app must present this as one product, even if Safari exposes two extension entries

For now, the hybrid design should be treated as a conscious product split: keep `SafariTourGuide` for native Mac UI and `SafariServices` active-page messaging, and use `SpiderWeb` only where it proves materially better for tab inventory, script injection parity, screenshots, native messaging, or Web Inspector experiments.

### Safari Web Inspector Extension Option

A custom Safari Web Inspector tool can be added later through `SpiderWeb` if Savannah needs one. It is not a general replacement for Chrome's `chrome.debugger` CDP bridge. It is a WebExtension-hosted developer tool that appears as a tab inside Safari Web Inspector. Safari requires the extension to create the inspector tab with `browser.devtools.panel.create()`, and the user views it through Develop > Show Web Inspector.

That has two consequences for Savannah:

- It may be useful for diagnostics, visibility, and experimental page inspection.
- It is probably not UX-friendly as the primary Codex automation backend unless we prove Savannah can reliably open or attach the inspector for a target page without making the user babysit Safari's developer UI.

The automatic-start question is still open. The Apple docs describe user-facing Web Inspector activation and target-page permission prompts, not a Codex-style background debugging transport. Until proven otherwise, Web Inspector extension work should be treated as a developer diagnostic add-on, not the first implementation path for ordinary browser tools.

### Native Automation Gap Fillers

Safari App Extension and Safari Web Extension APIs should stay first because they are user-visible, permissioned browser extension surfaces. If those APIs cannot provide a Chrome-equivalent capability, Savannah can evaluate native macOS automation paths case by case:

- Accessibility for reading or driving visible Safari UI when extension APIs do not expose a browser-wide control.
- Apple Events or AppleScript for Safari operations that Safari exposes through its scripting dictionary.
- AppKit or Core Graphics event synthesis only for explicitly user-approved interaction paths where ordinary extension APIs cannot express the action.

These should be fallback tools, not hidden compatibility shims. Any Codex-facing command backed by native automation should report its capability source and fail clearly when the required macOS permission is missing.

### Safari Extension Role

The Safari App Extension should own browser-injected behavior:

- toolbar entry point
- content script injection as configured by Info.plist
- page-to-extension messaging
- extension-to-page messaging
- per-page overlay state
- page URL/title metadata available from `SFSafariPage`

It should not pretend to own browser-wide primitives if Safari does not expose them.

### Page Script Role

The content script can carry behavior similar to Chrome's overlay script:

- inject the Codex cursor overlay
- respond to a ping message
- accept cursor state updates
- report cursor arrival
- provide page-observable metadata that Safari allows
- eventually support limited DOM-side commands if the extension/app can safely route them

DOM-side commands should be treated as local implementation details unless they can faithfully support the Chrome plugin's Playwright-style behavior.

## First Compatibility Contract

Savannah should start with a typed command protocol that mirrors the Chrome method names:

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
domCuaAction
finalizeTabs
nameSession
attach
detach
executeCdp
executeUnhandledCommand
moveMouse
```

Initial support can be narrower:

| Method | First Savannah behavior |
| --- | --- |
| `ping` | app or extension liveness check |
| `getInfo` | report backend type, supported capabilities, app version, extension version |
| `nameSession` | store Savannah-side session title |
| `moveMouse` | update script overlay cursor state for the active Safari page when available |
| `getTabs` | report the active window/tab/page plus any Savannah-created or observed tabs; include explicit partial-inventory metadata |
| `getUserTabs` | same as `getTabs` until full Safari tab enumeration is proven |
| `claimUserTab` | claim only an observed page; otherwise return unsupported/not-observable |
| `createTab` | create an active Safari tab through `SpiderWeb` and return the created tab id without treating URL loading as part of creation |
| `navigateTabUrl` | navigate an existing Safari tab through `SpiderWeb` and wait for the tab's WebExtension update event to report a completed load |
| `getTabInfo` | read a single Safari tab through `SpiderWeb` and return a Chrome-style tab facade from `browser.tabs.get(id)` |
| `reloadTab` | reload an existing Safari tab through `SpiderWeb` and wait for a completed tab update |
| `closeTab` | close an existing Safari tab through `SpiderWeb` and refresh the tab snapshot |
| `getPageSnapshot` | ask `SpiderWeb` to message the page content script and return a read-only snapshot for `tab.dom_cua.get_visible_dom()` |
| `domCuaAction` | ask `SpiderWeb` to click or type into a visible page element selected by snapshot node id or CSS selector |
| `getUserHistory` | unsupported unless a supported Safari or user-approved native source is proven |
| `attach` / `detach` | start/stop session tracking for an observable page |
| `executeCdp` | unsupported; keep name for compatibility but report that Safari has no CDP bridge |
| `executeUnhandledCommand` | dispatch future Safari-specific implementations with clear unsupported errors |

## Key Open Questions

- Can a Safari App Extension enumerate all windows and tabs, or only the active context Safari exposes to the extension?
- Can Savannah safely support all Chrome `Tab.goto` wait semantics, redirects, and failure modes through Safari WebExtension tab update events alone?
- How much of Chrome's `tab.dom_cua` surface can be matched with WebExtension content scripts before Savannah needs native automation or Web Inspector support?
- Is a Safari Web Extension target a better fit for cross-browser tool parity than a Safari App Extension target for tab inventory, tab updates, screenshots, and native messaging?
- Would a hybrid design make sense: keep a Safari App Extension for native Mac UI/control, and add a Safari Web Extension target only if the WebExtensions/native-messaging surface gives materially better Codex parity?
- Can Savannah bundle both a Safari App Extension and a Safari Web Extension without confusing Safari Settings, permissions, or user onboarding?
- Can Safari Web Extension native messaging provide a closer analogue to Chrome native messaging while still using the containing app?
- Can a Safari Web Inspector extension be opened or attached automatically enough to support Codex, or is it only a developer-facing diagnostic tool?
- Which Chrome-equivalent gaps are better filled by Accessibility, Apple Events, or AppleScript instead of WebExtension APIs?
- What level of DOM action can a Safari content script safely support without a CDP equivalent?
- How should Savannah represent partial tab inventory so Codex tools do not overclaim control?

## Recommended Next Investigation Slices

1. Inspect official Safari App Extension APIs for page/window/tab capabilities and document what is directly exposed.
2. Add a small Savannah protocol sketch for Chrome-compatible command names and unsupported-command errors.
3. Prototype content-script overlay ping/state messaging through the existing `script.js` and `SafariExtensionHandler`.
4. Evaluate `SpiderWeb` native messaging as the WebExtension bridge to the containing app.
5. Verify how Safari Settings presents `SafariTourGuide` and `SpiderWeb` together, including website access, profile, and Private Browsing permissions.
6. Evaluate whether a Safari Web Inspector extension is worth adding to `SpiderWeb`, especially whether it can be opened and attached without a user-driven Develop menu flow.
7. Inventory Safari's AppleScript and Accessibility surfaces for the Chrome-equivalent gaps that neither extension target can cover cleanly.
8. Use the Chrome plugin live against Chrome to capture exact command responses for `getInfo`, `openTabs`, `claimTab`, and basic tab actions.

## External References

- [Safari app extensions](https://developer.apple.com/documentation/safariservices/safari_app_extensions)
- [SFSafariApplication](https://developer.apple.com/documentation/safariservices/sfsafariapplication)
- [SFSafariExtensionHandler](https://developer.apple.com/documentation/safariservices/sfsafariextensionhandler)
- [SFSafariPage](https://developer.apple.com/documentation/safariservices/sfsafaripage)
- [SFSafariTab](https://developer.apple.com/documentation/safariservices/sfsafaritab)
- [SFSafariWindow](https://developer.apple.com/documentation/safariservices/sfsafariwindow)
- [Safari web extensions](https://developer.apple.com/documentation/safariservices/safari_web_extensions)
- [Assessing your Safari web extension's browser compatibility](https://developer.apple.com/documentation/safariservices/assessing-your-safari-web-extension-s-browser-compatibility)
- [Messaging between the app and JavaScript in a Safari web extension](https://developer.apple.com/documentation/safariservices/messaging_between_the_app_and_javascript_in_a_safari_web_extension)
- [Adding a web development tool to Safari Web Inspector](https://developer.apple.com/documentation/safariservices/adding-a-web-development-tool-to-safari-web-inspector)
- [Converting a Safari app extension to a Safari web extension](https://developer.apple.com/documentation/safariservices/converting-a-safari-app-extension-to-a-safari-web-extension)
- [MDN devtools.panels.create](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/API/devtools/panels/create)
- [MDN WebExtensions API compatibility](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Browser_support_for_JavaScript_APIs)
- [The four types of Safari extension](https://underpassapp.com/news/2023-4-24.html)
