# Mint Community Tools — the in-game addon

The World of Warcraft addon side of [Minty's Community Manager](https://github.com/wongz1/mintys-community-manager), a community website and Discord bot for a WoW Forever (Classic+) guild. This repository is public because an addon ships as readable Lua; the website and bot live in the other repository.

The addon is called **Mint Community Tools** in game (`/mint`).

**Status:** v0.1.0. The gear scanner works: every member can scan their equipped gear and talents in a window and export them as a string for the website's Roster page. Raid recording and talent tree export are specified (below) but not built yet.

## What the addon does

WoW addons have no network access, so everything moves by copy and paste, one way, from the game to the website:

- **Every member** exports their character (gear and talents) as a string and pastes it on the website's Roster page. That is how the roster and armory are filled. *(Built.)*
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

Type `/mint` or click the note icon on the minimap. The window shows your character, all nineteen equipment slots as the addon sees them (hover a row for the item's tooltip), the average item level, and your talent split.

1. Click **Export for website**. The export string appears in the box at the bottom, already selected.
2. Press **Ctrl+C** (**Cmd+C** on a Mac) to copy it.
3. On the website, open **Roster** and paste it under **Add or update a character**.

Do it again whenever your gear changes. The window refreshes on its own when you swap an item while it is open, and tells you if your gear changed since the last export.

| Command | What it does |
|---------|--------------|
| `/mint` | Open or close the window. |
| `/mint export` | Scan and put the export string in the window, ready to copy. |
| `/mint scan` | A one-line summary of your gear in chat. |
| `/mint region EU` | Set your region (US, EU, KR, TW, CN) when the client cannot tell the addon. Without an argument, says which region is being used and why. |
| `/mint json` | The export as raw JSON in the window, for debugging. |
| `/mint debug` | Client build, interface number and which APIs exist. Paste this in bug reports. |
| `/mint selftest` | Run the built-in encoder tests. |

`/mct` and `/gb` do the same as `/mint`.

### The WoW Forever beta client

- **Saved settings do not load.** The beta client writes addon settings at logout but never reads them back (every addon is affected). Mint Community Tools keeps only conveniences there — the minimap button's position and the last export — so nothing is lost; the minimap button just goes back to its default spot after a logout.
- **Names.** WoW Forever characters have a first and a last name. The addon reads them from `UnitName` (first name, with the last name as the second value) and exports both; the website identifies a character by region, realm, first name and last name together.
- **Region.** The website identifies a character by region, realm and name, but the beta client does not report its region the way other clients do. The addon tries `GetCurrentRegion`, `GetCurrentRegionName` and the `portal` cvar; a portal of `beta`, `test` or `ptr` means a Blizzard test client, which is US-hosted, so those export **US** (shown as "US, beta" in the window). Only when nothing answers at all does it assume US, and then it says so. The raw portal value is exported as `game.portal` so the website can tell a beta export from a live one. `/mint region EU` overrides it (kept for the session; also saved, for clients that load saved variables).
- **Interface number.** `16001` in the `.toc` is what other addons load with on the 1.60.1 beta client. `/mint debug` prints the number the client actually reports.

## The contracts

| Spec | What it describes |
|------|-------------------|
| [`docs/export-string-format-v1.md`](docs/export-string-format-v1.md) | The `GAE1:` character export string: layout, checksum, the JSON document with the character, equipped items (with the client's stat block for each) and talents. |
| [`docs/raid-capture-format-v1.md`](docs/raid-capture-format-v1.md) | The raid recording: the session envelope, kills, attendees, loot, and the fingerprint the website uses to merge two officers' recordings of one raid. |
| [`docs/talent-tree-format-v1.md`](docs/talent-tree-format-v1.md) | A class's talent trees as the game shows them — every tree, each talent's place, ranks, prerequisite and text — which the website's talent calculator is built on. The talent ORDER is the contract: the character export's rank digits follow it. |
| [`docs/class-data-format-v1.md`](docs/class-data-format-v1.md) | A class's spellbook (read at a trainer: every rank, the level it is learned at, cost, text) and a character's racials, exported per character and merged by the website — so the site's class reference comes from the game itself rather than a third party's datamining. |

All are versioned. Adding optional fields is fine within a version; changing the meaning of a field or the string layout means a new prefix, and the website's decoders are updated alongside. Keep the copies in both repositories the same.

## Layout

```
MintCommunityTools/
  MintCommunityTools.toc   addon manifest (interface number, load order)
  Encode.lua       JSON, base64, Adler-32, the GAE1 envelope; pure Lua 5.1, no bit ops
  Collect.lua      reads the character, equipped items and talents (every API feature-detected)
  UI.lua           the window: gear list, tooltips, export box, minimap button
  Core.lua         slash commands, events, debug and self test
tests/
  run.py           runs the addon under a mocked WoW API and decodes the result in Python
  fixtures/        export strings the harness produced, for the website's importer tests
```

## Tests

```
python3 tests/run.py            # -v prints the chat output, the window text and the decoded JSON
python3 tests/run.py --write-fixtures
```

Needs a Lua 5.1 interpreter — WoW's Lua — on `PATH` (`brew install luajit` on macOS, `apt install luajit` on Debian/Ubuntu) or in `$LUA`. The harness loads the addon files with `setfenv` into a mocked WoW API in three flavours (WoW Forever with last names, Classic Era, a Mainline-style client), opens the window, clicks its buttons, then decodes the export string independently with Python's `base64`, `zlib` and `json` and checks every field against the spec. `--write-fixtures` saves the strings under `tests/fixtures/`; the website's tests can import them so both ends of the paste flow are tested against each other.

## Things to know before changing it

- **Strings are self-reported.** The source is public and strings are plain text, so a string can be hand-edited. The checksum only catches accidental corruption; nothing on the website treats an import as tamper-proof.
- **Feature-detect, never assume.** The WoW Forever client is a beta; which functions and events it has is not confirmed. Every API call in `Collect.lua` is guarded, and a missing one leaves a field out rather than breaking the export. `/mint debug` reports what a client has.
- **Item data comes from the client.** Item names, quality, item level and stats (`GetItemStats`) are read in game and carried in the strings, so the website never needs an item database to display what the addon sends.
- **WoW only writes an addon's saved variables on a clean logout or `/reload`, never on a crash** — and the beta client does not read them back at all. Nothing that matters may live only there.

## License

[MIT](LICENSE)
