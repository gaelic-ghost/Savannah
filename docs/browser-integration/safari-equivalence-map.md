# Safari Equivalence Map

Research date: 2026-05-12

This note maps the Codex Chrome browser integration onto Savannah's current macOS app plus Safari App Extension shape.

## Current Savannah Shape

Savannah currently contains:

- a macOS SwiftUI app target named `Savannah`
- a Safari App Extension target named `SafariTourGuide`
- a Safari content script resource named `script.js`
- an `SFSafariExtensionHandler` subclass that receives Safari extension requests and script messages

The current extension is a Safari App Extension, not a Safari Web Extension manifest-based target. That matters because Safari App Extensions use `SafariServices` classes such as `SFSafariExtensionHandler`, `SFSafariPage`, `SFSafariWindow`, and `SFSafariToolbarItem`, while Safari Web Extensions aim closer to the cross-browser WebExtensions API surface.

Safari's extension families have different tradeoffs:

- Safariextz extensions are obsolete and not relevant for Savannah.
- Safari content blockers are too limited because they do not run arbitrary JavaScript or receive page content.
- Safari App Extensions are Mac-only, can provide native Mac UI in Safari, and use Safari's unique `SafariServices` API.
- Safari Web Extensions are the cross-platform path, closer to Chrome and Firefox WebExtensions, but Safari does not support every WebExtensions API and still requires a native app wrapper for distribution.

The current Savannah target is therefore on the native-Mac-control side of the Safari design space, not the maximum cross-browser-code-sharing side.

## Design Goal

Savannah should preserve the Codex-facing browser tool names and command shapes from the Chrome plugin as closely as possible:

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

The practical product goal is compatibility at the Codex plugin boundary. Safari-specific implementation details should stay behind that boundary.

## Chrome Capability To Safari Option Matrix

| Chrome capability | Chrome mechanism | Safari-native candidate | Current confidence |
| --- | --- | --- | --- |
| Native bridge | `chrome.runtime.connectNative` to native messaging host | containing macOS app, app group storage, XPC, local socket, or app-owned helper | Medium |
| Extension background runtime | MV3 service worker | `SFSafariExtensionHandler` plus containing app process | Medium |
| Page content script | `chrome.scripting.executeScript`, runtime content script | `SFSafariContentScript` declared in extension Info.plist | High |
| Script-to-extension message | `chrome.runtime.sendMessage` | `safari.extension.dispatchMessage` to `SFSafariExtensionHandler.messageReceived` | High |
| Extension-to-script message | `chrome.tabs.sendMessage` | `SFSafariPage.dispatchMessageToScript` | High |
| Active tab and window model | `chrome.tabs`, `chrome.windows` | `SFSafariApplication.getActiveWindow`, `SFSafariWindow.getActiveTab`, `SFSafariPage.getPropertiesWithCompletionHandler` | Medium |
| Existing tab inventory | `chrome.tabs.query` | Safari App Extension APIs appear narrower; may require native accessibility, AppleScript, or WebKit/Safari automation research | Low |
| Tab creation/navigation | `chrome.tabs.create`, CDP navigation | Safari App Extension APIs may not expose full creation/navigation; investigate containing app URL open, AppleScript, accessibility, and Safari Web Extension alternatives | Low |
| Tab groups/session grouping | `chrome.tabGroups` | no direct Safari App Extension equivalent identified yet; may need Savannah-side logical grouping | Low |
| Browser history | `chrome.history.search` | no direct Safari App Extension equivalent identified yet; likely unavailable without separate Safari/private data access | Low |
| Downloads | `chrome.downloads` events and download commands | no direct Safari App Extension equivalent identified yet; native app can manage its own downloads, but not necessarily Safari's download list | Low |
| CDP page control | `chrome.debugger` + CDP | no direct Safari App Extension equivalent; investigate Safari Web Inspector automation, WebKit, accessibility, and script-evaluated DOM actions | Low |
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

- Codex plugin connection endpoint
- session registry
- command routing
- app group shared state
- durable logs and diagnostics
- optional helper or local service
- permission prompts or operator-visible status UI

This is the closest Savannah equivalent to the Chrome plugin's bundled native host plus extension-host binary.

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
| `getTabs` | report only tabs/pages Savannah can observe, with explicit partial-inventory metadata |
| `getUserTabs` | same as `getTabs` until broader Safari tab inventory is proven |
| `claimUserTab` | claim only an observed page; otherwise return unsupported/not-observable |
| `createTab` | unsupported until a Safari-safe creation path is proven |
| `getUserHistory` | unsupported unless a supported Safari or user-approved native source is proven |
| `attach` / `detach` | start/stop session tracking for an observable page |
| `executeCdp` | unsupported; keep name for compatibility but report that Safari has no CDP bridge |
| `executeUnhandledCommand` | dispatch future Safari-specific implementations with clear unsupported errors |

## Key Open Questions

- Can a Safari App Extension enumerate all windows and tabs, or only the active context Safari exposes to the extension?
- Can Savannah safely open or navigate Safari tabs through first-party APIs, or does this require an AppleScript/accessibility fallback?
- Is a Safari Web Extension target a better fit for cross-browser tool parity than a Safari App Extension target?
- Would a hybrid design make sense: keep a Safari App Extension for native Mac UI/control, and add a Safari Web Extension target only if the WebExtensions/native-messaging surface gives materially better Codex parity?
- Can Safari Web Extension native messaging provide a closer analogue to Chrome native messaging while still using the containing app?
- What level of DOM action can a Safari content script safely support without a CDP equivalent?
- How should Savannah represent partial tab inventory so Codex tools do not overclaim control?

## Recommended Next Investigation Slices

1. Inspect official Safari App Extension APIs for page/window/tab capabilities and document what is directly exposed.
2. Add a small Savannah protocol sketch for Chrome-compatible command names and unsupported-command errors.
3. Prototype content-script overlay ping/state messaging through the existing `script.js` and `SafariExtensionHandler`.
4. Evaluate Safari Web Extension native messaging as an alternate or companion extension shape.
5. Use the Chrome plugin live against Chrome to capture exact command responses for `getInfo`, `openTabs`, `claimTab`, and basic tab actions.

## External References

- [Safari app extensions](https://developer.apple.com/documentation/safariservices/safari_app_extensions)
- [SFSafariExtensionHandler](https://developer.apple.com/documentation/safariservices/sfsafariextensionhandler)
- [SFSafariPage](https://developer.apple.com/documentation/safariservices/sfsafaripage)
- [SFSafariWindow](https://developer.apple.com/documentation/safariservices/sfsafariwindow)
- [Safari web extensions](https://developer.apple.com/documentation/safariservices/safari_web_extensions)
- [Messaging between the app and JavaScript in a Safari web extension](https://developer.apple.com/documentation/safariservices/messaging_between_the_app_and_javascript_in_a_safari_web_extension)
- [MDN WebExtensions API compatibility](https://developer.mozilla.org/en-US/docs/Mozilla/Add-ons/WebExtensions/Browser_support_for_JavaScript_APIs)
- [The four types of Safari extension](https://underpassapp.com/news/2023-4-24.html)
