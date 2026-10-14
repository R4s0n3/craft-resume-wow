# Craft Resume

A standalone **WoW Retail crafting-session tracker**. Start a session, craft normally, and review what actually happened. No libraries, account, external database, or price addon required.

## Install

Extract `dist/CraftResume-0.5.0.zip` into your Retail AddOns directory, or copy the `CraftResume` folder there:

```text
World of Warcraft/_retail_/Interface/AddOns/CraftResume/CraftResume.toc
```

Restart WoW if it was already running when you installed the addon. Enable **Craft Resume** on the character-selection AddOns screen. Open it with **`/cr`**, `/tr`, or `/craftresume`. The old `/traderesume` command remains available.

The manifest targets Retail interface `120100`. Check your client's number with `/dump select(4, GetBuildInfo())` if it flags the addon as out of date. A matching manifest does not substitute for an in-game compatibility test.

## Use

1. Open your profession. Enter an optional session name in Craft Resume and click **Start**.
2. Craft using the normal profession window, including **Create All**.
3. **Mini** switches to the compact tracker; **Details** switches back. Only one view is visible at a time. Closing a view hides the addon while recording continues.
4. **Pause / Resume** controls recording. **Finish** ends the session and keeps it in history.
5. Open the **History** tab and select a session to review it. Click a recipe in Overview to filter the summary, items, reagents, and craft log. **All recipes** clears that filter.
6. **Export CSV** opens a copyable report. Press Ctrl+A, Ctrl+C and paste into a CSV file or spreadsheet.

Session controls always operate on the current character's active session, even while viewing an older session. The footer names that active session. Rename, Delete, and Export apply to the history entry being viewed. Deletion is available for finished sessions and asks for confirmation.

The full window is 600 × 460, using WoW's native frame borders, buttons, and gold labels. The mini tracker is 236 × 118 and includes Pause/Resume and Finish. Both remember their position, and the selected view is restored after a reload. Hover totals or stat rows for explanations and confidence intervals.

| Command | Action |
| --- | --- |
| `/cr` | Open / close the summary |
| `/cr start [name]` | Begin a session |
| `/cr pause` | Pause recording |
| `/cr resume` | Resume recording |
| `/cr stop` | Finish and save |
| `/cr mini` | Switch between compact and full views |
| `/cr export` | Export the selected session |
| `/cr resetui` | Center the windows |

The legacy `/tr` and `/traderesume` aliases remain available.

## What it records

- Completed crafting operations and produced item units, grouped by recipe, item, quality, and personal/order scope.
- Base output and actual extra units reported by multicraft. The result's total quantity **already includes** multicraft extras.
- Exact item and currency quantities reported as resourcefulness returns. Reagent item IDs keep different ranks separate.
- Selected reagent quantities committed to every completed craft, including enchants. Used and resourcefulness-returned reagents are shown separately with item icons and tooltips.
- Observed multicraft procs, crafts with reagent returns, and ingenuity procs.
- Concentration spent and ingenuity refunds.
- Item/currency rewards from first crafts, kept separate from ordinary crafted output and proc trials.
- Disenchant operations and every material quantity shown in their loot window. These are separated from crafted-item totals and use their item links, icons, and tooltips.
- The most recent 1,000 crafting operations per session, plus complete aggregate totals for the session.

The Items tab labels crafting-order output, enchants, recrafts, and first-craft/bonus rewards. **Items produced** includes newly produced order items; it does not claim these all entered your bags. Enchanted and recrafted items are listed but do not count as newly produced units. The Reagents tab shows selected inputs used by completed crafts and resourcefulness returns in separate sections. Prices, profit, and bag-difference estimates are outside this version's scope.

Disenchant tracking activates only around the player's Disenchant spell and reads the resulting loot slots, including autoloot. Regular loot is ignored. Retail's loot event exposes the resulting materials but not a dependable source-item link, so the history records the operation and its outputs rather than guessing which input item was destroyed.

## Comparing the crafting-menu percentages

The tracker snapshots operation stats using the actual crafting API arguments, refreshing at each cast where possible. It uses localized stat names and `ratingPct`, the percentage Blizzard displays; `bonusRatingPct` is not added a second time. It retains the unrounded percentage, so the UI's rounded integer can differ slightly.

The displayed average weights each sampled completed craft equally. Observed rate is sampled crafts with a reported proc divided by sampled crafts. A missing or unsupported stat is **unknown**, not a zero-percent sample. A known 0% stat is a valid sample. Ingenuity only samples crafts that spent concentration.

Resourcefulness is labeled as **visible returns**: the result API reports returned reagents, but does not provide a separate resourcefulness-roll boolean. It cannot expose an internal roll that saved nothing. A low observed return rate alone does not prove that Blizzard's advertised chance is wrong. Likewise, a multicraft proc chance is not the percentage of extra item units produced.

The 95% Wilson interval describes uncertainty in the observed binary rate. It is a rough descriptive guide, particularly when combining different recipes or changing chances; it is not a formal test of the game's RNG. Filter to a single recipe and collect a substantial sample for useful comparisons.

## Saved history

WoW persists the account-wide `CraftResumeDB` SavedVariable during a normal logout, exit, or `/reload`. Existing `TradeResumeDB` history is imported automatically. It is normally stored at:

```text
_retail_/WTF/Account/<account>/SavedVariables/CraftResume.lua
```

An active session is restored **paused** after login or reload. Resume it explicitly. Offline and paused time are excluded from active duration. Different characters have separate active sessions and share the history browser. The latest **200 finished sessions** are retained automatically, plus unfinished sessions. Each session retains 1,000 recent craft records; older records roll out of the log without changing aggregate totals. Back up the SavedVariables file with WoW closed, or export important sessions before they age out.

## Scope and verification

This initial version targets current Retail item crafting. It uses `TRADE_SKILL_ITEM_CRAFTED_RESULT` and `TRADE_SKILL_CURRENCY_REWARD_RESULT`, not localized chat parsing or bag differences. It observes crafting APIs through secure post-hooks and does not automate casts or replace Blizzard functions.

Results carry an operation ID but no recipe ID. The tracker associates them with pending craft contexts and groups related packets into one operation. First-craft rewards do not inflate craft counts. Duplicate packets with the same operation and result identity are ignored. Zero operation IDs cannot reliably associate multiple reward packets; those packets are treated separately rather than merging unrelated identical crafts.

Results received while recording count toward the session. Start before the batch and finish after it completes. If you resume during a batch, use a third-party crafting flow, or receive a result without a matching context, output still records but recipe attribution or chance comparisons may be unavailable. Random salvage results are retained; when identified as salvage, stat comparison is disabled. Crafts with no item-result event cannot be inferred reliably and are not counted. Crafting orders and recrafts have adapter support but still need in-game validation.

**Local tests pass; live WoW execution has not been verified in this workspace.** See [the in-game checklist](docs/TESTING.md) for the remaining smoke test.

## Development

```sh
make test       # LuaJIT (Lua 5.1 compatible) regression tests
make package    # reproducible installable ZIP in dist/
```

Implementation: `Model.lua` owns totals and retention; `Tracker.lua` adapts Retail events; `Core.lua` owns sessions and persistence; `UI.lua` provides native WoW frames; `Export.lua` creates CSV reports.

### Publishing releases

GitHub Actions packages and publishes version tags to GitHub and CurseForge.
Configure the repository variable `CURSEFORGE_PROJECT_ID` and secret
`CF_API_TOKEN` before creating a release tag. The token is available from the
[CurseForge API Tokens page](https://authors.curseforge.com/#/settings/api-tokens).

For each release, update `## Version` in `CraftResume/CraftResume.toc`, commit
the change, and push a matching tag such as `v0.6.0`. The workflow verifies that
the tag and TOC versions match, creates the installable ZIP and GitHub release,
and uploads the same release to CurseForge.

The integration was checked against Blizzard's generated API definitions and UI source, as mirrored by Gethe:

- [TradeSkillUI events and functions](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUIDocumentation.lua)
- [Crafting result and operation structures](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_APIDocumentationGenerated/TradeSkillUITypesDocumentation.lua)
- [Blizzard's crafting output log](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_Professions/Blizzard_ProfessionsCraftingOutputLog.lua)
- [Blizzard's crafting stat display](https://github.com/Gethe/wow-ui-source/blob/live/Interface/AddOns/Blizzard_ProfessionsTemplates/Blizzard_ProfessionsRecipeCrafterDetails.lua)
