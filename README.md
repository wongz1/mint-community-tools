# Mint Community Manager — in-game addon

The World of Warcraft addon side of [Minty's Community Manager](https://github.com/wongz1/mintys-community-manager), a community website and Discord bot for a WoW Forever (Classic+) guild. This repository is public because an addon ships as readable Lua; the website and bot live in the other repository.

**Status:** starting from scratch. Nothing here runs yet. What exists is the contract the addon has to meet — the two string formats the website already imports — so the addon can be built against something fixed.

## What the addon does

WoW addons have no network access, so everything moves by copy and paste, one way, from the game to the website:

- **Every member** exports their character (gear and talents) as a string and pastes it on the website's Roster page. That is how the roster and armory are filled.
- **Anyone** can export their class's talent trees, so the website's talent calculator shows WoW Forever's real trees rather than Classic Era's placeholders. Any level, any build; rank text the tooltip can't show is left out and filled in from other players' exports.
- **Officers** record a raid night — boss kills, who was there for each kill, what dropped and who received it — and paste the recording on the website's Raids page. If several officers recorded the same raid, the website merges their recordings, each filling in what the others missed.

The website imports both today; the addon's job is to produce them.

## The contracts

| Spec | What it describes |
|------|-------------------|
| [`docs/export-string-format-v1.md`](docs/export-string-format-v1.md) | The `GAE1:` character export string: layout, checksum, the JSON document with the character, equipped items and talents. |
| [`docs/raid-capture-format-v1.md`](docs/raid-capture-format-v1.md) | The raid recording: the session envelope, kills, attendees, loot, and the fingerprint the website uses to merge two officers' recordings of one raid. |
| [`docs/talent-tree-format-v1.md`](docs/talent-tree-format-v1.md) | A class's talent trees as the game shows them — every tree, each talent's place, ranks, prerequisite and text — which the website's talent calculator is built on. The talent ORDER is the contract: the character export's rank digits follow it. |

Both are versioned. Adding optional fields is fine within a version; changing the meaning of a field or the string layout means a new prefix, and the website's decoders are updated alongside. Keep the copies in both repositories the same.

## Things to know before writing it

- **Strings are self-reported.** The source is public and strings are plain text, so a string can be hand-edited. The checksum only catches accidental corruption; nothing on the website treats an import as tamper-proof.
- **WoW only writes an addon's saved variables on a clean logout or `/reload`, never on a crash.** A recording that has not been exported lives in memory until then. A second officer recording the same raid is the real safety net, and a `/reload` between pulls is a cheap habit.
- **The WoW Forever client is a beta.** Its interface number and which events it fires are not confirmed; feature-detect rather than assume.
- **Item data comes from the client.** Item names, quality and stats (`GetItemStats`) are read in game and carried in the strings, so the website never needs an item database to display what the addon sends.

## License

[MIT](LICENSE)
