# Savannah Roadmap

Use this roadmap to track milestone-level delivery through checklist sections.

## Table of Contents

- [Vision](#vision)
- [Product Principles](#product-principles)
- [Milestone Progress](#milestone-progress)
- [Milestone 0: Foundation](#milestone-0-foundation)
- [Milestone 1: Product Shape](#milestone-1-product-shape)
- [Backlog Candidates](#backlog-candidates)
- [History](#history)

## Vision

- TBD

## Product Principles

- Keep the app and Safari extension behavior grounded in the native Apple platform surfaces already present in the project.
- Preserve Xcode as the source of truth for project structure, target membership, schemes, and build settings.
- Keep early milestones focused on proving the app shape before adding release or packaging complexity.

## Milestone Progress

Use this section as a concise rollup of milestone names and statuses, not as a second task list.

- Milestone 0: Foundation - In Progress
- Milestone 1: Product Shape - Planned

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

## Backlog Candidates

- [ ] Add a contributor workflow document if external setup details grow beyond `AGENTS.md`.
- [ ] Add release notes once the first tag or public build exists.
- [ ] Add packaging or distribution guidance after the app has a validated release path.

## History

- Initial roadmap scaffold created.
