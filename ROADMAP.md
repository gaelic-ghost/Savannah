# Savannah Roadmap

Use this roadmap to track milestone-level delivery through checklist sections.

## Table of Contents

- [Vision](#vision)
- [Product Principles](#product-principles)
- [Milestone Progress](#milestone-progress)
- [Milestone 0: Foundation](#milestone-0-foundation)
- [Milestone 1: Product Shape](#milestone-1-product-shape)
- [Milestone 2: Codex Browser Integration](#milestone-2-codex-browser-integration)
- [Backlog Candidates](#backlog-candidates)
- [History](#history)

## Vision

- TBD

## Product Principles

- Keep the app and Safari extension behavior grounded in the native Apple platform surfaces already present in the project.
- Prefer Safari WebExtension APIs first for Chrome-equivalent browser control, use Safari App Extension APIs when `SafariServices` is the better fit, and use Accessibility, Apple Events, or AppleScript only to fill proven API gaps.
- Preserve Xcode as the source of truth for project structure, target membership, schemes, and build settings.
- Keep early milestones focused on proving the app shape before adding release or packaging complexity.

## Milestone Progress

Use this section as a concise rollup of milestone names and statuses, not as a second task list.

- Milestone 0: Foundation - In Progress
- Milestone 1: Product Shape - Planned
- Milestone 2: Codex Browser Integration - Planned

## Milestone 0: Foundation

### Status

In Progress

### Scope

- [ ] Establish the repository guidance, validation, README, and roadmap skeletons.
- [ ] Confirm the Xcode project, app target, test targets, and Safari extension target build cleanly.
- [ ] Replace placeholder app behavior with the first intentional Savannah-facing surface.

### Tickets

- [ ] Run the Xcode build workflow against `Savannah.xcodeproj`.
- [ ] Decide whether the app keeps Core Data in the first product slice.
- [ ] Replace template SwiftUI sample content with first-purpose UI.
- [ ] Review Safari extension target membership and extension metadata.

### Exit Criteria

- [ ] Local repo-maintenance validation passes.
- [ ] Debug build passes for the app and extension targets.
- [ ] README and roadmap describe the current project state without template placeholders outside intentionally user-owned prose.

## Milestone 1: Product Shape

### Status

Planned

### Scope

- [ ] Define the first complete Savannah workflow across the app and Safari extension.

### Tickets

- [ ] Capture the first user-facing workflow in a focused design note or issue.
- [ ] Identify the app-owned data model and extension-owned messaging boundary.
- [ ] Add targeted tests for the first non-template behavior.

### Exit Criteria

- [ ] The app has one coherent end-to-end workflow that can be built, run, and explained from the README.
- [ ] Safari extension responsibilities are explicit in code and docs.

## Milestone 2: Codex Browser Integration

### Status

Planned

### Scope

- [ ] Define Savannah's Codex-facing browser command contract using the Chrome plugin command names where behavior can match.
- [ ] Prove whether Savannah can register as a Chrome/Computer Use-style browser backend, or whether it needs a regular Codex plugin tool surface instead.
- [ ] Route browser capabilities through `SpiderWeb` first, then `SafariTourGuide`, then native macOS automation only for documented gaps.
- [ ] Decide how the Savannah app installs or exposes its Codex plugin bundle from a local checkout, git source, or app-shipped plugin copy.

### Tickets

- [x] Prototype a minimal Codex plugin bundle with `plugin.json`, a Savannah skill, and a `savannah-client.mjs` connection script.
- [ ] Test whether the plugin client can participate in the existing Chrome/Computer Use browser runtime shape or must expose regular plugin commands.
- [ ] Define a typed command protocol for `ping`, `getInfo`, tab creation, tab selection, navigation, session naming, and explicit unsupported-command errors.
- [x] Define typed snapshot validation and capability reporting for `getTabs` and `getUserTabs`.
- [x] Prove `createTab` through app-to-`SpiderWeb` WebExtension dispatch and refreshed tab snapshots.
- [x] Add request-id command acknowledgements so WebExtension-backed commands can report completion instead of dispatch-only acceptance.
- [x] Split Chrome-compatible tab creation from navigation so `tabs.new()` returns a tab facade and `tab.goto(url)` owns page loading.
- [x] Add WebExtension-backed tab info, reload, and close commands behind the Chrome-style tab facade.
- [x] Report stale SpiderWeb snapshots distinctly and make command acknowledgement timeouts point at Safari extension wake-up.
- [x] Prove a read-only `tab.dom_cua.get_visible_dom()` path through `SpiderWeb` content-script page snapshots.
- [x] Add first node-id/selector DOM CUA actions for click and text entry through `SpiderWeb`.
- [x] Enable only the `SpiderWeb` WebExtension permissions needed for the first command slice.
- [x] Implement `SpiderWeb` native messaging for tab snapshot liveness and capability reporting.
- [x] Prove `getTabs` can read enabled Safari tabs from the `SpiderWeb` App Group snapshot.
- [ ] Implement app-to-`SafariTourGuide` messaging only for active-page or `SafariServices` capabilities that WebExtension APIs do not cover cleanly.
- [ ] Inventory Accessibility, Apple Events, and AppleScript candidates for remaining gaps, including required permissions and operator-facing failure messages.

### Exit Criteria

- [ ] Savannah can answer a Codex-side `ping` and `getInfo` through the chosen plugin/backend path.
- [ ] The backend reports a capability list that distinguishes WebExtension, App Extension, native automation, unsupported, and unproven capabilities.
- [x] At least one tab-oriented command works end to end through the preferred API path.
- [ ] Unsupported commands fail with clear, human-readable messages and no silent native automation fallback.

## Backlog Candidates

- [ ] Add a contributor workflow document if external setup details grow beyond `AGENTS.md`.
- [ ] Add release notes once the first tag or public build exists.
- [ ] Add packaging or distribution guidance after the app has a validated release path.

## History

- Initial roadmap scaffold created.
