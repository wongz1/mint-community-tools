# Changelog

## 0.5.6 - 2026-10-04

- **Loot and vendor windows.** The window that opens when you loot something, and a vendor's
  window, wear the flat skin with the bag windows: a flat panel, flat buttons and tabs, and
  item slots with the border in the colour of the item's quality. Their switch is the bag
  windows' switch, on the **Bars** page.
- **Right-click the damage meter's box.** In `/mint edit`, a right-click on the **Damage
  meter** box opens the game's own box of settings for the meter (style, numbers, frame
  width and height, bar height, padding, transparency, text size, visibility), the one the
  game's Edit Mode shows, without going into the game's Edit Mode. What you change is saved
  into your game layout when you close the box. It does not open in combat, and it cannot
  save into the game's own Modern and Classic layouts: for those, make a layout of your own
  first. Shift-right-click puts the box back where it was, which a plain right-click still
  does on every other box.
- **Edit Mode's settings box.** In the game's own Edit Mode, the box of settings that opens
  when you click something (the damage meter's bar height and spacing, for one) is flat now,
  like the Edit Mode window itself, and so are Edit Mode's other dialogs.
- **`/mint uidump loot`** and **`/mint uidump vendor`** record the loot window and a vendor's
  window for a bug report. Type them while the window is open.
- **Fixed: thin lines near the bottom of the screen.** The game draws short capped lines
  between the buttons of its main action bar. It makes them when it lays that bar out, which
  can be long after login, and puts them where its own bar would be, so they showed up as a
  row of stray lines under the minimalist UI's bars. They are hidden now, whenever they
  appear.

## 0.5.5 - 2026-10-04

A flat skin for the game's damage meter, a quest list that shows every quest you pick up,
and the bag row put away by default. This version adds a file, so close the game completely
and start it again after updating: a /reload is not enough.

- **Damage meter.** The game has a damage meter of its own (turn it on in the game's Options,
  or type `/console damageMeterEnabled 1`). With the minimalist UI on it now wears the flat
  skin: no header art, plain bars, a flat backdrop. The new **Meter** page of the Settings
  tab has its switch, the backdrop (on or off, and how dark), every bar in your class colour
  or in the colours the game gives them, and the font and size of the names and numbers.
  The meter has its own **Damage meter** box in `/mint edit`, so it moves with the rest.
  It is still the game's meter: the bars' height and spacing, the window's size, and the
  icons stay in the game's own Edit Mode (Shift-click **Edit Mode** in the Escape menu, then
  click the meter), because only the game's own settings can change those safely.
- **Quest list: All and Tracked.** The quest list now has two tabs. **All** (the default)
  shows every quest in your quest log, so a quest shows up the moment you pick it up.
  **Tracked** shows only the ones you are tracking, as before. Shift-click a quest to track
  it or to stop tracking it. When the list is taller than it may be, the mouse wheel scrolls
  it.
- **Chat scroll bar.** The scroll bar that shows when you point at the chat window is flat
  now, like the ones in the game menu's windows.
- **The bag row is hidden by default.** The row of bag buttons (the backpack, the four bags,
  the keyring and the reagent slot) is now put away unless you ask for it: your bag key still
  opens your bags as one window. To get the row back, untick **Hide the bag row** on the
  **Bars** page of the Settings tab. It works at once.
- **Item exports: things that are not worn no longer claim a slot.** Food, reagents and the
  like were sent to the website with a slot the game invents for "not worn", which showed up
  for officers as a gap to fill. It is left out now, also for items already recorded.
- **`/mint uidump meter`** records the game's own damage meter for a bug report or a future
  skin. Have its window on screen, with a few bars in it, when you type it.

## 0.5.4 - 2026-10-04

A flat cast bar, a Mint Edit Mode button in the game menu, colour and size options for the
experience bar, and a fix for the chat window stretching out of place. This version adds a
file, so close the game completely and start it again after updating: a /reload is not enough.

- **Cast bars.** Your cast bar joins the minimalist UI: no ornate frame, the spell's name on
  the bar instead of in a box under it, and a plain fill in your class colour (green for a
  channel, red when interrupted). It has its own **Cast bar** box in `/mint edit`. The
  target's cast bar gets the same look. The new **Cast bar** page of the Settings tab has its
  switch, your cast bar's width and height, the size of the spell's name, and how far the
  name sits left or right, up or down from the middle of the bar.
- **Mint Edit Mode button.** The game menu (Escape) has a **Mint Edit Mode** button at its
  bottom while the minimalist UI is on. It opens the minimalist UI's edit mode, the same as
  `/mint edit`. A switch on the **General** page of the Settings tab removes it.
- **Switches work at once.** Every switch on the Settings tab now takes effect the moment you
  click it. That includes turning the minimalist UI or any piece of it **on**, which used to
  need a reload, and turning the quest tracker, the game menu, the bag windows or the cast
  bars **off**. "Class colours on players' health bars" and "Hide the micro menu", which
  silently waited for a reload, are fixed too.
- **What still needs a reload.** Turning **off** the action bars, chat, unit frames or minimap
  (or the whole minimalist UI while one of those is on). Those pieces take the game's own
  frames apart, and only the game can put them back together. Those switches are marked
  "(turning off needs a reload)" on the Settings tab, which also says so when you flip one,
  names which, and has the Reload button.
- **Settings pages renamed.** With a seventh page, two were shortened to fit: "Action bars" is
  now **Bars** and "Unit frames" is now **Units**.
- **Experience bar colour and size.** The experience bar is in your class colour, as before.
  The **Bars** page of the Settings tab has a new **Experience bar** section: a switch that
  turns the class colour off, for the game's own purple, and the bar's width and height.
- **Fixed: the chat window stretching and no longer following its box.** The game sometimes
  fastens the chat window to a place of its own without letting go of where the addon had it
  (seen after a level-up). The window then stretched between the two, and dragging its box in
  `/mint edit` no longer moved it. The addon now checks every point the window is held by,
  not the first one alone, and puts it right on the next frame. The bag window, the cast bar
  and the action bars' buttons get the same check.
- **The chat box stays on screen.** The Chat box in `/mint edit` now stops where the tabs
  above the window and the edit box under it are still on screen, so a chat window dragged
  to the bottom edge keeps the line you type on.
- **Updating while the game is running.** A file that comes with an update is only read when
  the game starts. Until then the Settings tab stopped working at the first page that needed
  the new file. It now opens as normal, the page says to restart the game, and so does a line
  in chat at login.
- **`/mint uidump chat`** records the chat windows for a bug report: every point the main
  window is held by, its size and place, and what the game had done to it each time the addon
  had to put it back.

## 0.5.3 - 2026-10-03

- **Names, not "You", in the loot tracker.** The **Looted by** column on the Loot tab and in
  the loot watcher shows the name of the character who received the item. Your own loot shows
  your character's name, in green, instead of "You".

## 0.5.2 - 2026-10-03

Flat bag windows, size and text controls for the chat window, and fixes for Edit Mode. This
version adds a file, so restart the game once after updating.

**New**

- **Bag windows.** The backpack and bag windows are flat dark panels like the rest of the UI.
  Each slot is a plain square with the item's picture in it, and its border is the colour of
  the item's quality; empty slots are plain squares. The search box, the coin box and the
  sort button are flat too, and the bag's menu is a small **v** button where the portrait
  was. The bag window has its own **Bag window** box in `/mint edit`, so you can put it where
  you like; a bag opened in combat moves to its box when combat ends. Its switch is on the
  **Action bars** page of the Settings tab.
- **Chat size and text.** The **Chat** page of the Settings tab now sets the chat window's
  width and height, the size of its text, and its font. The text stays as the game has it
  until you choose a size or a font there.
- **The Edit Mode button opens this UI's edit mode.** While the minimalist UI is on, clicking
  **Edit Mode** in the game menu shows the minimalist UI's frames as boxes to drag, the same
  as `/mint edit`. Hold **Shift** while clicking it for the game's own edit mode. To have the
  button always open the game's, untick it on the **General** page of the Settings tab.

**Fixed**

- **Errors when opening Edit Mode.** With the minimalist UI's action bars on, clicking
  **Edit Mode** in the game menu threw Lua errors and the game's edit mode came up broken.
  The game's edit mode opens cleanly again.
- **The chat box moved without the chat window.** In `/mint edit`, dragging the Chat box could
  leave the chat window behind, because the game had fastened the window somewhere else. The
  window now stays on its box. A chat window moved in the game's own edit mode, or dragged by
  its tab, goes back to its box afterwards: move it with `/mint edit`.
- **Settings text running off the window.** Long labels on the Settings pages ran past the
  window's side. They now wrap onto a second line, and text on buttons is cut short rather
  than spilling out.

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
