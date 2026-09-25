# Changelog

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
