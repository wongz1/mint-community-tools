# Changelog

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
