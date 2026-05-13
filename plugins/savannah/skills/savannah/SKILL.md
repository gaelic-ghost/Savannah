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

## Runtime Shape

The first proof client intentionally mirrors the Chrome browser-client method names where practical:

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

Unsupported commands must return explicit unsupported-command errors with a capability source of `unsupported` or `unproven`.

## Capability Priority

Use capability sources in this order:

1. `web-extension` for Safari WebExtension APIs exposed by `SpiderWeb`.
2. `app-extension` for Safari App Extension APIs exposed by `SafariTourGuide`.
3. `native-automation` for Accessibility, Apple Events, AppleScript, or event synthesis after the gap is proven and permissions are clear.
4. `unsupported` when Savannah cannot safely or truthfully provide the command.

