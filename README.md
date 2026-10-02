# Mint Community Tools — the in-game addon

The World of Warcraft addon side of [Minty's Community Manager](https://github.com/wongz1/mintys-community-manager), a community website and Discord bot for a WoW Forever (Classic+) guild. This repository is public because an addon ships as readable Lua; the website and bot live in the other repository.

The addon is called **Mint Community Tools** in game (`/mint`).

**Status:** v0.3.0. Two features, each a tab of the same window: the **gear scanner** (scan your equipped gear and talents and export them as a string for the website's Roster page) and the **loot tracker** (a log of what drops and who loots it, with tooltips and chat links, which also collects item data for the website's item database). Raid recording and talent tree export are specified (below) but not built yet.

## What the addon does

WoW addons have no network access, so everything moves by copy and paste, one way, from the game to the website:

- **Every member** exports their character (gear and talents) as a string and pastes it on the website's Roster page. That is how the roster and armory are filled. *(Built.)*
- **Every member** collects item data as they play: every item the addon sees drop is kept, and **Export new items** turns what is new into a string to paste on the website, where it waits for an officer's approval before it enters the item database. *(Built; see [Sending items to the website](#sending-items-to-the-website).)*
- **Anyone** can export their class's talent trees, so the website's talent calculator shows WoW Forever's real trees rather than Classic Era's placeholders. *(Not yet.)*
- **Officers** record a raid night — boss kills, who was there for each kill, what dropped and who received it — and paste the recording on the website's Raids page. *(Not yet.)*

## Install

Download `MintCommunityTools-v<version>.zip` from the [latest release](https://github.com/wongz1/mint-community-tools/releases/latest) and unzip it into your WoW Forever addons folder, `World of Warcraft/_classic_beta_/Interface/AddOns/`. The zip holds only the `MintCommunityTools` folder. From a checkout of this repository instead:

1. Copy (or symlink) the `MintCommunityTools` folder into your WoW Forever addons folder:
   `World of Warcraft/_classic_beta_/Interface/AddOns/MintCommunityTools`
   so that `MintCommunityTools.toc` ends up at `.../AddOns/MintCommunityTools/MintCommunityTools.toc`.
2. Start the game (or `/reload` if it is already running). Mint Community Tools prints a line in chat when it has loaded.
3. If the AddOns screen at character select marks it "out of date", tick **Load out of date AddOns**.

## Use

Type `/mint` or left-click the small square button on the minimap. The window has a tab per feature.

The look is flat and ElvUI-like, with none of the game's own frame art: dark panels with 1px black borders, a title strip across the top of each window with an `x` on the right, flat buttons and tabs that light their border in your class colour under the mouse (the selected tab keeps it), column headers on a strip above a striped list, dim grey labels and light grey text. Item names keep their quality colours. Each window sizes itself to what is in it.

### Gear

Your character, all nineteen equipment slots as the addon sees them (hover a row for the item's tooltip), the average item level, and your talent split.

1. Click **Export for website**. The export string appears in the box at the bottom, already selected.
2. Press **Ctrl+C** (**Cmd+C** on a Mac) to copy it.
3. On the website, open **Roster** and paste it under **Add or update a character**.

Do it again whenever your gear changes. The window refreshes on its own when you swap an item while it is open, and tells you if your gear changed since the last export.

### Loot

Everything that drops, newest first: what you loot, what your group loots (from the loot lines in chat), and what is left on a corpse (from the loot window). A drop that is seen and then handed out is one line.

- The item's name is in the colour of its quality, next to its icon, who looted it and when.
- **Hover** a line for the item's own tooltip, with its stats.
- **Shift-click** a line to link the item in chat, exactly as a shift-click on an item in your bags does. Ctrl-click tries it on.
- **Showing: ...** filters by quality; the mouse wheel and the arrows page back through the last 500 drops.
- **Show loot watcher** opens a small window of the latest drops to leave open while you play. `/mint watch` or a right-click on the minimap button does the same. The mouse wheel scrolls it back through the last 100 drops; the position shows in its title strip, and **Latest** there returns to the newest. While it is scrolled back, new loot does not move what you are looking at. Closing it with its `x` turns it off.

### The minimap button

A small flat square with the addon's note icon on the minimap's edge; its border lights up under the mouse. Left-click opens the window, right-click shows or hides the loot watcher, and dragging moves the button around the minimap's edge. `/mint minimap` hides or shows it; `/mint minimap reset` puts it back.

| Command | What it does |
|---------|--------------|
| `/mint` | Open or close the window. |
| `/mint export` | Scan and put the export string in the window, ready to copy. |
| `/mint scan` | A one-line summary of your gear in chat. |
| `/mint loot` | Open the window on the Loot tab. |
| `/mint watch` | Show or hide the loot watcher. |
| `/mint items` | Export the items seen since the last export, for the website's item database. `/mint items all` exports every item again. |
| `/mint minimap` | Show or hide the minimap button; `/mint minimap reset` puts it back in its default place. |
| `/mint region EU` | Set your region (US, EU, KR, TW, CN) when the client cannot tell the addon. Without an argument, says which region is being used and why. |
| `/mint json` | The export as raw JSON in the window, for debugging. |
| `/mint debug` | Client build, interface number and which APIs exist. Paste this in bug reports. |
| `/mint selftest` | Run the built-in encoder tests. |

`/mct` and `/gb` do the same as `/mint`.

### The WoW Forever beta client

- **Saved data does not load, until you link it.** The beta client writes addon data at logout but never reads it back (every addon is affected), so the loot log and the minimap button's place would start over each session. The one-time fix: log in with the addon once and `/exit`, then, with the game closed, run the script that is in the addon's folder — `link-saved-settings.sh` on macOS or Linux (`sh "<game folder>/_classic_beta_/Interface/AddOns/MintCommunityTools/link-saved-settings.sh"`), `LinkSavedSettings.cmd` on Windows (right-click, Run as administrator). It links your save file into the addon as `Saved.lua`, which the client does load; the login line then says the saved data was restored. If you use [ForeverSVFix](https://github.com/nobewayo/ForeverSVFix) or [SVShim](https://github.com/kylef000/wow-forever-svshim), which do this for every addon, you don't need it. Nothing depends on it: without the link every session starts empty and works. Export your new items before you log out in that case, since what was seen is forgotten with the session.
- **Names.** WoW Forever characters have a first and a last name. The addon reads them from `UnitName` (first name, with the last name as the second value) and exports both; the website identifies a character by region, realm, first name and last name together.
- **Region.** The website identifies a character by region, realm and name, but the beta client does not report its region the way other clients do. The addon tries `GetCurrentRegion`, `GetCurrentRegionName` and the `portal` cvar; a portal of `beta`, `test` or `ptr` means a Blizzard test client, which is US-hosted, so those export **US** (shown as "US, beta" in the window). Only when nothing answers at all does it assume US, and then it says so. The raw portal value is exported as `game.portal` so the website can tell a beta export from a live one. `/mint region EU` overrides it (kept for the session; also saved, for clients that load saved variables).
- **Interface number.** `16001` in the `.toc` is what other addons load with on the 1.60.1 beta client. `/mint debug` prints the number the client actually reports.

## Sending items to the website

The website has an item database that officers curate. WoW Forever's own items are in no dataset anywhere, so the game client is the only source for them, and every member's addon sees a different part of the game. The addon keeps every item it sees drop — its name, quality, item level, type, slot, icon and stats, all as the client reports them — and exports them the same way it exports your character: as a string you paste.

1. On the **Loot** tab, click **Export new items**. The line above the button says how many there are.
2. Press **Ctrl+C** (**Cmd+C** on a Mac), and paste the string on the website's **Items** page.
3. Back in game, click **Done**. That is what marks those items as exported.

- **Only what is new is exported**: items you have not exported before, and items whose details changed since. Export after a session and the string is that session's finds, not your lifetime's.
- **A long export comes in parts**, a hundred items to a string (about 40 KB; the game's text box gets slow with more). Paste a part, click **Next part**, paste the next one. Every part stands on its own, so the order does not matter and one that goes astray costs only itself.
- **Nothing is marked as exported until you click Next part or Done.** Close the window instead and the same items are offered again next time.
- **Export all** sends every item again, for a paste that went astray. The website takes the same item twice without complaint.
- What you paste reaches the officers' review queue, and the find is credited to the website account that pasted it.

Items with a random suffix ("of the Bear") are logged but not exported: every variant shares an item ID and differs in name and stats. The format is [`docs/item-export-format-v1.md`](docs/item-export-format-v1.md).

## The contracts

| Spec | What it describes |
|------|-------------------|
| [`docs/export-string-format-v1.md`](docs/export-string-format-v1.md) | The `GAE1:` character export string: layout, checksum, the JSON document with the character, equipped items (with the client's stat block for each) and talents. |
| [`docs/raid-capture-format-v1.md`](docs/raid-capture-format-v1.md) | The raid recording: the session envelope, kills, attendees, loot, and the fingerprint the website uses to merge two officers' recordings of one raid. |
| [`docs/item-export-format-v1.md`](docs/item-export-format-v1.md) | The item export (`kind: "items"`): the items a player has seen drop, as the client describes them, a hundred to a string, for the website's item review queue. |
| [`docs/talent-tree-format-v1.md`](docs/talent-tree-format-v1.md) | A class's talent trees as the game shows them — every tree, each talent's place, ranks, prerequisite and text — which the website's talent calculator is built on. The talent ORDER is the contract: the character export's rank digits follow it. |
| [`docs/class-data-format-v1.md`](docs/class-data-format-v1.md) | A class's spellbook (read at a trainer: every rank, the level it is learned at, cost, text) and a character's racials, exported per character and merged by the website — so the site's class reference comes from the game itself rather than a third party's datamining. |

All are versioned. Adding optional fields is fine within a version; changing the meaning of a field or the string layout means a new prefix, and the website's decoders are updated alongside. Keep the copies in both repositories the same.

## Layout

```
MintCommunityTools/
  MintCommunityTools.toc   addon manifest (interface number, load order)
  Encode.lua       JSON, base64, Adler-32, the GAE1 envelope; pure Lua 5.1, no bit ops
  Collect.lua      reads the character, equipped items and talents (every API feature-detected)
  Loot.lua         the loot tracker: loot lines, the loot window, the log, the items seen and their export
  UI.lua           the window and its tabs, the Gear tab, the flat skin and the shared widgets (ns.W)
  LootUI.lua       the Loot tab and the loot watcher
  Minimap.lua      the minimap button
  Core.lua         saved data, slash commands, events, debug and self test
  Saved.lua        not in the repository: a link to your save file (see the beta client notes)
  link-saved-settings.sh, LinkSavedSettings.cmd   make that link
tests/
  run.py           runs the addon under a mocked WoW API and checks the results in Python
  fixtures/        what the harness produced, for the website's importer tests
```

## Tests

```
python3 tests/run.py            # -v prints the chat output, the window text, the loot log and the decoded JSON
python3 tests/run.py --write-fixtures
```

Needs a Lua 5.1 interpreter — WoW's Lua — on `PATH` (`brew install luajit` on macOS, `apt install luajit` on Debian/Ubuntu) or in `$LUA`. The harness loads the addon files with `setfenv` into a mocked WoW API in three flavours (WoW Forever with last names, Classic Era, a Mainline-style client), opens the window, clicks its buttons, loots, links an item in chat and drags the minimap button, checks that no frame uses Blizzard's frame templates or border art, then decodes the export string independently with Python's `base64`, `zlib` and `json` and checks every field against the spec. The item export is decoded and checked the same way, including a 250-item export that must come out as three self-contained parts. `--write-fixtures` saves the strings under `tests/fixtures/`; the website's tests can import them so both ends of the paste flow are tested against each other.

## Things to know before changing it

- **Strings are self-reported.** The source is public and strings are plain text, so a string can be hand-edited. The checksum only catches accidental corruption; nothing on the website treats an import as tamper-proof.
- **Feature-detect, never assume.** The WoW Forever client is a beta; which functions and events it has is not confirmed. Every API call in `Collect.lua` is guarded, and a missing one leaves a field out rather than breaking the export. `/mint debug` reports what a client has.
- **Item data comes from the client.** Item names, quality, item level and stats (`GetItemStats`) are read in game and carried in the strings, so the website never needs an item database to display what the addon sends.
- **WoW only writes an addon's saved variables on a clean logout or `/reload`, never on a crash** — and the beta client does not read them back at all. Nothing that matters may live only there.

## License

[MIT](LICENSE)
