# Mint Community Tools — the in-game addon

The World of Warcraft addon side of [Minty's Community Manager](https://github.com/wongz1/mintys-community-manager), a community website and Discord bot for a WoW Forever (Classic+) guild. This repository is public because an addon ships as readable Lua; the website and bot live in the other repository.

The addon is called **Mint Community Tools** in game (`/mint`).

**Status:** v0.5.2. Three features, each a tab of the same window: the **minimalist UI** (the game's own interface in the addon's flat skin: action bars, chat, unit frames, a square minimap, a quest tracker and the game menu's windows, each optional and off by default), the **gear scanner** (scan your equipped gear and talents and export them as a string for the website's Roster page) and the **loot tracker** (a log of what drops and who loots it, with tooltips and chat links, which also collects item data for the website's item database). Raid recording and talent tree export are specified (below) but not built yet.

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

The button can sit around a round minimap or a square one: `/mint minimap round`, `/mint minimap square` or `/mint minimap auto`, or the **Button shape** button under **Minimap button** on the Settings tab, which also has a checkbox to show or hide it. Round puts it on the circle just outside the map; square puts it on the square just outside the map, in the same direction from the centre and clear of the strips above and below. Auto, the default, follows the minimap: square with this addon's square minimap, or with another addon's that says so through the global function `GetMinimapShape()`, and round otherwise. The button moves within a second when the map changes. If your minimap is square and auto does not notice, choose square.

With its own minimap on, the addon tells other addons' minimap buttons what the map looks like: it answers `GetMinimapShape()` (`"SQUARE"` or `"ROUND"`, a long-standing convention) and `GetMinimapEdgeInsets()` (the room the zone strip and the strips below the map take: above, below, left, right). Rude Boy, Cat Facts and Rat Facts read both, so their buttons sit on the square's edge and clear of the strips. Neither function is replaced if another addon already provides it.

| Command | What it does |
|---------|--------------|
| `/mint` | Open or close the window. |
| `/mint export` | Scan and put the export string in the window, ready to copy. |
| `/mint scan` | A one-line summary of your gear in chat. |
| `/mint loot` | Open the window on the Loot tab. |
| `/mint watch` | Show or hide the loot watcher. |
| `/mint items` | Export the items seen since the last export, for the website's item database. `/mint items all` exports every item again. |
| `/mint minimap` | Show or hide the minimap button; `/mint minimap reset` puts it back in its default place. |
| `/mint minimap round` | The shape of the minimap the button sits around: `round`, `square`, or `auto` (the default) to follow the minimap. |
| `/mint ui on` | Turn the minimalist UI on (`off` turns it off; alone, says what is on). Applies after `/reload`. `/mint ui reset` puts every frame back. |
| `/mint edit` | Edit mode: drag the overhaul's frames where you want them. |
| `/mint uidump menus` | The same record for the game menu and the windows it opens. Open the menu and each window once first, so that they exist. `/mint uidump bags` records the bag windows; have your bags open. |
| `/mint uidump` | Also records what the bag row's buttons are and what clicks on the keyring and reagent slot did. Record what this client's own interface is made of (frame names, the art on them, which functions exist) into the save file, for fixing the overhaul on a client it has not seen. Written to disk at the next `/reload`. |
| `/mint region EU` | Set your region (US, EU, KR, TW, CN) when the client cannot tell the addon. Without an argument, says which region is being used and why. |
| `/mint json` | The export as raw JSON in the window, for debugging. |
| `/mint debug` | Client build, interface number and which APIs exist. Paste this in bug reports. |
| `/mint selftest` | Run the built-in encoder tests. |

`/mct` and `/gb` do the same as `/mint`.

### The minimalist UI

The **Settings** tab turns the overhaul on, piece by piece. It is **off by default**: turn it on, `/reload`, then `/mint edit` to arrange it. Everything is the addon's flat skin: dark panels, 1px black borders, one accent colour.

- **Action bars.** The game's own buttons, so keybinds, paging and cooldowns are untouched, drawn flat: the icon in a 1px border, the keybind top right, no round button art, no gryphons. Bars 1 to 3 stack at the bottom, bars 4 and 5 stand on the right, the pet and stance bars sit above, the bags bottom right (the keyring, drawn with a key, and the reagent bag slot, drawn with a dimmed herb while it is empty, can be left out of the row), the micro menu beside them (it can be hidden; Escape and the keybinds still open everything). The experience bar is the addon's own: a thin flat bar under bar 1 with rested experience behind it (hover for the numbers), which shows your watched reputation once there is no experience left to gain. The gryphons and the rest of the bar art are removed by sweeping every texture off the bar's art frames, not by name, since the names differ between clients.
- **Chat.** The game's chat frames with the art gone: plain-text tabs, a flat edit box under the window, no side buttons (the mouse wheel scrolls). The Chat page of the Settings tab sets the window's **width and height** and the **size and font of its text** (left as the game has them until you choose). The window sits on its box in edit mode and is kept there: moved in the game's own edit mode or dragged by its tab, it goes back. An optional backdrop behind the main window: it is fastened to the chat window itself, so it stays behind it wherever the window goes, and takes in the tabs above the text and the edit box below.
- **Unit frames.** The addon's own player, target, target-of-target and pet frames. The health bar is in class colour for players and reaction colour for everything else, with the name and the numbers on it; the power bar under it carries the level. Names are whole: a WoW Forever character's first and last name both show, cut short with dots only when the bar runs out of room. **Portraits** can be turned off, or be **animated 3D portraits**: the unit's own model in place of the flat picture (the flat picture stands in for a unit too far away to be drawn). The Unit frames page of the Settings tab also sets the **font** of the text on the frames (the game's own fonts, plus LibSharedMedia's when another addon has brought that library) and its **size**, the **width and height** of the player and target frames and of the two small frames, the **size of buff icons and of debuff icons**, how many icons go in a row, and whether the **countdown numbers** show on buffs and on debuffs. A size changed in combat applies when combat ends. **Buffs and debuffs** are rows of icons on the side of the frame you pick for each (above, below, left, right, or off), debuffs nearest the frame; hover one for its tooltip; the target's debuffs can be limited to your own. Click to target, right-click for the unit's menu, in combat too. The pet frame, combo points and the target's cast bar are the game's, re-anchored.
- **Minimap.** Square, in a 1px border, on a mover; the mouse wheel zooms. The zone's name sits in a strip above it in the colour of its PvP standing, with your coordinates at the strip's right end; a name too long for the room that leaves is cut short with dots rather than running into the coordinates, and hovering the strip shows the whole name. Below the map sit your computer's time and the game world's time, whichever you switch on, on one row. With the zone strip off, the coordinates go below the map as well. The zoom buttons, the round border, the calendar and the game's own clock are gone; tracking, mail and the battleground icon stay.
- **Quest tracker.** The addon's own list of the quests you are tracking, in place of the game's tracker: a flat header strip with the count, then each quest's title in the colour of its difficulty (with its level in front, unless you turn that off) and its objectives under it, what is done dimmed, "Ready to turn in" once the quest is complete. Click the header to fold the list away, a quest to open it in the quest log, shift-click a quest to stop tracking it. An optional backdrop sits behind the list, and it stops growing at a set height and says how many more there are. The game's own tracker is hidden while this is on (the game puts it back some time after login; the addon looks once a second and hides it again), which also hides anything else it shows (and its quest item buttons); turn the piece off on the Quests page of the Settings tab to have it back.
- **Game menu.** The Escape menu, the windows it opens (Options, AddOns, Edit Mode, Macros, Help) and the game's confirmation boxes lose their ornate border, header art and textured background for a flat dark panel with a 1px border. Inside them: push buttons are flat squares whose border lights up under the mouse; a close button is a flat square with an x; tabs are flat with the open one's border lit; check boxes are flat squares that fill with the accent colour; drop-downs and search boxes are flat panels; sliders are a thin bar with a flat thumb; scroll bars a thin dark track with a flat thumb; framed areas get a 1px border; the options window's category headings lose their banners. Still the game's own: the lists that drop down from a drop-down, keybinding buttons, and the scroll bars' arrows. Its switch is on the General page.
- **Bag windows.** The backpack (as one window or a window per bag) is a flat dark panel with a 1px border, no portrait or frame art, and a flat close button. Each slot is a plain dark square with the item's picture trimmed to it; its border takes the colour of the item's quality, where the game drew a coloured frame; an empty slot is the plain square. The search box and the coin box are flat, the sort button is a flat square that says Sort, and the bag's menu (which was behind the portrait) is a small flat square with a v. The slots are not moved or resized. The window sits on its own **Bag window** box in edit mode, by its bottom right corner; the game places its bag windows every time one opens, so the addon puts the window back on its box after, and a bag opened in combat (when the game does not let it be moved) goes to its box when combat ends. Its switch is on the Action bars page.
- **Edit mode.** `/mint edit`, or the button on the Settings tab, shows every frame as a labelled box: drag it, right-click it to put it back, **Done** when finished. Positions are saved. **Reset positions** puts everything back. While the minimalist UI is on, the game menu's own **Edit Mode** button opens this edit mode too; hold Shift while clicking it for the game's edit mode (a switch on the General page turns this off). The game's button is not changed: a transparent button of the addon's lies over it and steps aside while Shift is held.

Turning the whole overhaul or one piece on or off changes the game's own frames, which only happens at a reload; the Settings tab says "Reload to apply" and has the button. Portraits, aura rows, the minimap strips and the quest list change at once. The Settings tab is split into pages (General, Action bars, Chat, Unit frames, Minimap, Quests) picked with the row of buttons across its top; Edit mode, Reset positions and Reload UI sit under whichever page is showing.

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
  Overhaul.lua     the minimalist UI: settings, movers, edit mode, applying it at login
  ActionBars.lua   the action bars, pet and stance bars, bags and micro menu, flat and on movers
  Chat.lua         the chat window with the art gone, on a mover
  UnitFrames.lua   the addon's own player, target and target-of-target frames, with aura rows
  Map.lua          the square minimap, the zone above it, coordinates and the time below it
  Quests.lua       the quest tracker: tracked quests and their objectives as a plain list
  Menus.lua        the game menu and the windows it opens, flat
  Bags.lua         the bag windows, flat, with quality-coloured slot borders
  SettingsUI.lua   the Settings tab
  Dump.lua         /mint uidump: a record of this client's own frames
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
- **Secret values.** The WoW Forever client is built on the newest engine, which hands addons some unit numbers (current health and power, an aura's stacks and timing, chat text during an encounter) as *secret values*: they may be stored, passed to a status bar, font string or cooldown, and run through `string.format`, but comparing one, doing arithmetic on it, indexing it or using it as a table key is an error. Check `issecretvalue(v)` before doing any of those to something a unit API returned; `UnitFrames.lua` shows the pattern. The test harness's "mainline" client hands out secret values that fail the same way, so a slip is caught there.
- **The overhaul changes the game's own frames once per session.** It hides and re-anchors Blizzard's frames at login and cannot put them back without a reload, so every switch that touches them says so. It is off by default until it has been proven on the real client; `Overhaul.DEFAULTS.enabled` is the one place to flip that.
- **WoW only writes an addon's saved variables on a clean logout or `/reload`, never on a crash** — and the beta client does not read them back at all. Nothing that matters may live only there.

## License

[MIT](LICENSE)
