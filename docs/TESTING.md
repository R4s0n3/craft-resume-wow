# Validation

`make test` runs the model and event adapter under LuaJIT, using Retail-shaped payloads and a minimal API harness. It verifies successful-result accounting, quantities, multicraft, item/currency returns, recipe switching, batch snapshots, duplicates, zero operation IDs, first-craft rewards, paused/reloaded sessions, retention, and CSV escaping. The UI workflow harness exercises view switching, closing, saved view migration, mini controls, history navigation, and export. These tests cannot validate native frame rendering or the server's actual event sequence.

## In-game smoke test still required

1. Install the ZIP and enable script errors with `/console scriptErrors 1`. Log in and use `/tr`. Check the compact native layout, dragging, Escape, and `/tr resetui` at your normal UI scale. Mini must hide the full window; Details must hide Mini. Closing either view must keep both hidden after a craft. Reload in each mode and confirm only the selected view returns. Hover stat rows to inspect their explanatory tooltips.
2. Choose a modern recipe with multicraft and resourcefulness. Note its displayed chances and base yield. Start a named session and craft 10–20 times, including Create All. Confirm output and reagent rows show their actual icons and native item/currency tooltips.
3. Compare every output and returned reagent with Blizzard's crafting result panel. The craft count should be successful casts, including normal outcomes. Produced units should equal the sum of total result quantities, without adding multicraft twice.
4. Confirm a first-craft reward is labeled separately and does not add a craft or proc trial. Cancel a cast and check that it adds nothing.
5. Change recipes, change equipment or a crafting buff, and craft again. Verify recipe filters, per-item quality rows, and sampled displayed averages. A recipe without multicraft should not dilute multicraft trials.
6. Pause and craft once. Confirm recording is paused. Resume before starting a fresh batch. Finish after results arrive. Verify history selection and the active-session footer when browsing history during another session.
7. `/reload` during an idle active session. Check it restores paused with identical totals. Resume and verify that new crafts append once. Check another character can read the same history without recording into the first character's session.
8. Test concentration, ingenuity, enchanting, order crafting, recrafting, and salvage if you use them. For an enchant, verify every selected reagent and rank appears under Reagents → Used once per completed cast, while any resourcefulness return appears separately under Returned. Cancelled casts must add neither. Order and recraft labeling must be checked before relying on those breakdowns.
9. Disenchant several items with autoloot both on and off. Each cast should add one disenchant and the exact dust/shard/crystal quantities. Open unrelated loot during the same session and confirm it is ignored. Cancel one disenchant and confirm it adds nothing.
10. Rename a session, export CSV, open it in a spreadsheet, and compare totals. Delete a disposable finished test session after confirming the popup. Test a session with more than 50 crafts to check log paging.

If an error occurs, retain its stack trace, `/dump GetBuildInfo()` output, recipe ID, and the steps that caused it. Database location and limitations are documented in the README.
