# Implementation Goal

## Goal title

Implement pop-out preview and in-app Aerial activation

## Goal scope

- [x] Implement the approved plan through the full local pre-push and manual Tahoe validation suite.
- [ ] Continue through draft PR creation, independent review, verified fixes, and CI verification. This is not authorized by the current request.

## Source of truth

- `./docs/requirements.md`
- `./docs/implementation-plan.md`
- `./docs/superpowers/specs/2026-08-09-popout-preview-wallpaper-activation-design.md`
- Repository conventions and applicable `AGENTS.md` files

## Goal prompt

Implement the approved pop-out preview editor and in-app native Aerial activation described in `./docs/requirements.md` by following `./docs/implementation-plan.md` as the execution source of truth.

Use the `codex-spec-to-pr` skill and load `references/execute-plan.md` before implementation. Work only on `agent/popout-preview-wallpaper-activation`. Execute approved steps in order, keep each tracked step in a separate focused commit, and run the required local checks before every commit. Preserve unrelated user changes and all encoding/manifest invariants. Stop and ask about every material ambiguity or plan deviation, with a recommended option and concise tradeoffs.

Step 1 is a hard compatibility and privacy gate: do not implement `WallpaperSelectionStore` until the current Tahoe system has a manually selected AerialDrop wallpaper whose native linked selection can be read and sanitized. At planning time the active provider was still `com.apple.NeptuneOneExtension`. Capture only the relevant linked selection, remove all personal identifiers, validate the fixture, and commit it before production selection-store code.

Implement only through local validation. Do not push, create or update a PR, merge, tag, version-bump, or release. After implementation, run the full validation ladder, perform the manual Tahoe matrix, update Code Review Graph, document the manual fallback for graph gaps, and report any external blocker honestly.

The goal is complete only when the local definition of done in `./docs/implementation-plan.md` is satisfied. Do not silently relax tests, skip manual private-schema verification, bypass the fixture gate, or change approved scope.

## `/goal` start instructions

1. Confirm an AerialDrop wallpaper is selected in System Settings and the provider is the native Aerial provider.
2. Invoke `/goal` in the Codex chat composer.
3. Use the Goal title and Goal prompt above.
4. Start the goal with the `codex-spec-to-pr` skill.
5. Keep the goal active through the selected local implementation scope.

## Checkpoints

1. Branch and repository safety verified.
2. Tahoe linked-Aerial fixture captured, sanitized, validated, and committed.
3. Safe selection store implemented, tested, and committed.
4. Preferences and output calculations implemented, tested, and committed.
5. Pop-out editor implemented, built, and manually checked.
6. Activation/model and Library UI implemented, tested, and committed.
7. Documentation updated and committed.
8. Full local suite, manual Tahoe validation, and final graph/manual review passed.

## Stop conditions

- The active provider is not the native Aerial provider when fixture capture begins.
- The ground-truth configuration cannot be sanitized without losing required schema.
- Material product, architecture, security, migration, compatibility, or scope ambiguity appears.
- Unrelated working-tree changes have unclear ownership.
- Approved plan materially conflicts with repository reality.
- Required local permissions or Tahoe facilities are unavailable.
- A test, manual validation, or graph-review finding requires a user decision.
