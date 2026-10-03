# Changelog

## 0.5.1 - 2026-10-03

Mint Community Tools is now on CurseForge. Nothing has changed in game: if you already have
0.5.0, you do not need to do anything.

- **On CurseForge.** The addon's page is
  https://www.curseforge.com/wow/addons/mint-community-tools and it is listed for WoW Forever.
  CurseForge checks every file before listing it, so a new version appears there a little
  while after it is released.
- **Every release goes to both places.** From this version on, each new version is published
  to GitHub and uploaded to CurseForge automatically, and announced in Discord.
- **GitHub still works.** The latest version is always at
  https://github.com/wongz1/mint-community-tools/releases/latest on GitHub.

## 0.5.0 - 2026-10-03

More of the game's interface joins the minimalist UI, and the pieces already there get more
choices. As before, all of it is optional: open `/mint`, go to the **Settings** tab, switch on
what you want, and `/reload`. If you are updating, restart the game once so the new files load.

**New pieces**

- **Quest tracker.** A plain list of the quests you are tracking, in place of the game's
  tracker: each title in the colour of its difficulty with its level in front, its objectives
  under it (finished ones dimmed), and "Ready to turn in" once a quest is done. Click the
  **Quests** header to fold the list away, click a quest to open it in the quest log, and
  shift-click a quest to stop tracking it. It has its own box in edit mode. The game's own
  tracker is hidden while this is on; turn it off on the **Quests** page to have that back.
- **Game menu.** The Escape menu, the windows it opens (Options, AddOns, Edit Mode, Macros,
  Help) and the game's confirmation boxes are flat dark panels: no ornate borders or header
  art. Their buttons, tabs, check boxes, drop-downs, search boxes, sliders and scroll bars are
  flat too. Its switch is on the **General** page.

**Unit frames**

- **Whole names.** Both of a character's names are shown, not just the first.
- **Animated 3D portraits.** A new option under Portraits shows the unit's own model in
  place of the flat picture.
- **Text and sizes.** On the **Unit frames** page you can now pick the font and font size,
  the width and height of the player and target frames (and of the two small frames), a size
  each for buff icons and debuff icons, how many icons go in a row, and whether countdown
  numbers show on buffs and on debuffs. A size changed in combat applies when combat ends.

**Minimap**

- **Coordinates beside the zone's name.** Your coordinates sit at the right end of the strip
  above the minimap instead of taking a row under it. A long zone name is cut short before it
  reaches them; hover the strip to read all of it. The two clocks share one row under the map.
- **The addon's minimap button works with a round or a square minimap.** It follows the
  minimap by default. To choose yourself: `/mint minimap round`, `/mint minimap square` or
  `/mint minimap auto`, or the **Button shape** button on the **General** page, which also
  has a box to hide the button. Rude Boy's, Cat Facts' and Rat Facts' buttons follow this
  addon's square minimap as well, from their own latest versions.

**Smaller things**

- **Keyring and reagent bag.** In the bag row, the keyring shows a key and an empty reagent
  bag slot shows a dimmed herb, instead of two blank squares. The **Action bars** page can
  leave both out of the row.
- **Chat backdrop.** It stays behind the chat window wherever the window is, and now takes in
  the tabs above the text and the edit box below.
- **Settings pages.** The Settings tab is split into pages (General, Action bars, Chat, Unit
  frames, Minimap, Quests), picked with the row of buttons across its top. Edit mode, Reset
  positions and Reload UI are under every page.

Still drawn by the game: the lists that open from a drop-down, and the keybinding buttons in
Options.

## 0.4.0 - 2026-10-02

The minimalist UI: the game's own interface in the addon's flat skin. Each piece is optional
and all of it is off until you turn it on: open `/mint`, go to the **Settings** tab (or type
`/mint ui on`), then `/reload`.

- **Action bars.** The bar art is gone; every button is a flat square with its keybind top
  right. Bars 1 to 3 stack at the bottom, bars 4 and 5 stand on the right, the pet and
  stance bars sit above, the bags bottom right, the micro menu beside them (or hidden). The
  experience bar is a thin strip along the bottom.
- **Chat.** No frame, tab or edit box art; the edit box is a flat strip under the window;
  the side buttons are gone (the mouse wheel scrolls). An optional backdrop behind it.
- **Unit frames.** The addon's own player, target, target-of-target and pet frames: health in
  class or reaction colour with the name and numbers, power under it with the level,
  portraits you can turn off. Buffs and debuffs sit above, below, left or right of each
  frame as you choose, or not at all; the target's debuffs can be limited to your own.
  Click to target, right-click for the menu, in combat too.
- **Minimap.** Square, in a thin border, with the zone's name above it and your coordinates
  and the time (your computer's and the game world's) with it. The mouse wheel zooms.
- **Edit mode.** `/mint edit` (or the Settings tab) shows every frame as a box to drag;
  right-click a box to put it back; where you leave them is saved.
- **Settings tab.** A switch for the whole thing and one per piece, with the choices inside
  each. Turning a piece on or off applies after a reload; the tab says so.

## 0.3.0 - 2026-10-02

A new look: the flat, ElvUI-like skin. Nothing changed in what the addon does, saves or
exports; the window's controls, slash commands and the export strings are as in 0.2.0.

- **Windows.** No more Blizzard dialog art. The main window and the loot watcher are flat
  dark panels with a 1px black border (one screen pixel at any UI scale), a 20px title strip
  with the title on the left (and the version, dimmed, after it) and a flat `x` on the right.
  Each window is laid out top to bottom and sized to its content, so nothing is drawn outside
  its backdrop.
- **Tabs and buttons.** Flat buttons, 20px tall, that take the accent colour on their border
  when hovered. The accent is your class colour (a muted cyan if the client does not say).
  The selected tab keeps the accent border and a lighter background.
- **Lists.** Column headers sit on an 18px strip; rows sit on a list panel, every other row a
  touch lighter. Slot names, times, hints, summaries and status lines are in dim grey; item
  names keep their quality colour; failed status lines are still red.
- **Copy boxes.** The export boxes are flat panels with the text in light grey and a plain
  scroll frame: the mouse wheel scrolls them, and there is no scroll bar art. The box's
  border takes the accent colour while it has focus.
- **Loot watcher.** The same title strip, with the scroll position dimmed after the title and
  the flat **Latest** button on the strip. Closing it with its `x` still turns it off.
- **Minimap button.** A 20px flat square in the panel colour with a 1px border and the icon
  inset 2px; the border takes the accent colour under the mouse. It still sits on the
  minimap's edge, drags, and answers left and right clicks as before.
- **Tests.** The harness's stub frames now record the template each frame was created with
  and the backdrop it was given, and the run fails if any frame uses `UIPanelButtonTemplate`,
  `UIPanelCloseButton`, `UICheckButtonTemplate`, `InputBoxTemplate`, `BasicFrameTemplate`,
  `UIPanelScrollFrameTemplate` or a Blizzard border texture.

Releasing this version needs a tag: `git tag v0.3.0 && git push origin v0.3.0` after the
commit is on `main` (see RELEASING.md); the Release workflow builds the zip from the tag.

## 0.2.0

The loot tracker, and a window with tabs.

- **Loot tab.** Everything that drops is logged: what you loot, what your group loots, and what
  is left on the corpse. Item names are in the colour of their quality; hover a row for the
  item's own tooltip with its stats; **Shift-click** links the item in chat as if it were in
  your bags. Filter by quality, page back through the last 500 drops.
- **Loot watcher.** A small window of the latest drops to leave open while you play:
  `/mint watch`, or right-click the minimap button. The mouse wheel scrolls it back through
  the last 100 drops; **Latest** returns to the newest.
- **Items for the website.** Every item seen is kept, and **Export new items** on the Loot tab
  (or `/mint items`) turns what is new since your last export into a string to paste on the
  website's Items page, where it waits for an officer's approval. A long export comes in parts
  of a hundred items; **Next part** and **Done** mark each as exported once you have pasted it.
- **Tabs.** The window now has a tab per feature: Gear and Loot.
- **Minimap button.** It now sits on the minimap's edge with its icon inside the ring, stays
  where you drag it, and can be hidden: `/mint minimap`, `/mint minimap reset`.
- **The beta client and saved data.** The beta does not load addon data back. Run
  `link-saved-settings.sh` (Mac) or `LinkSavedSettings.cmd` (Windows) once from the addon's
  folder and the loot log survives a logout.

## 0.1.0

First release: the gear scanner.

- `/mint` (or the minimap button) opens a window with your character, every equipment slot
  (hover for the item's tooltip), your average item level and talent split.
- **Export for website** puts the export string in a copy box, already selected: press Ctrl+C
  (Cmd+C on a Mac) and paste it on the website's Roster page. The list refreshes when you
  change gear with the window open, and tells you when the last export is out of date.
- The export carries each item's stat block from the client, so the website needs no item
  database.
- WoW Forever's first and last names are exported as the website expects them.
- The beta client does not say which region it is on, so a beta client exports US.
  `/mint region EU` overrides it; `/mint debug` shows what the client answered.
