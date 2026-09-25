# Talent tree export, format v1

The contract between the in-game addon (producer) and the website (consumer) for a class's talent trees: what the game itself shows in the talent window — every tree, every talent's place, ranks, prerequisite and text. The website's talent calculator (`/talents`) is built on this; until an export arrives it shows Classic Era's trees as placeholders. The companion specs are [`export-string-format-v1.md`](export-string-format-v1.md) (a character) and [`raid-capture-format-v1.md`](raid-capture-format-v1.md) (a raid).

Produced by the addon in this repository; consumed by the website's talent importer in [wongz1/mintys-community-manager](https://github.com/wongz1/mintys-community-manager), which replaces the placeholder trees of that class (`talent_trees`, `source = 'addon'`). A change to this format is made in both repositories.

## Why this exists

WoW Forever is Classic+: its trees may have new or changed talents, and there is no data source for them outside the game — Blizzard's API has no WoW Forever namespace and no spell endpoint for Classic, and community datasets describe Classic Era. The client is the only truthful source, and an addon can read all of it (`GetTalentTabInfo`, `GetTalentInfo`, `GetTalentPrereqs`, the talent tooltip). Any player of the class can export their class's trees; it does not need a level-60 character or any points spent (see *Rank text* below for what points do add).

## Envelope

Identical to a character export: `GAE1:<base64 JSON>:<adler32>`. See the character spec for the layout and decoding. A consumer tells the documents apart by the `kind` key: `"talents"` here, `"raid"` for a raid recording, absent on a character export. Each importer rejects the other kinds with a message saying where they belong.

One class (three trees, roughly 50 talents with all their rank text) is about 15–25 KB of JSON. The website accepts up to 256 KB.

## JSON document

Keys are emitted in sorted order. An unknown value is **omitted**, never `null` — except a rank's text, where `null` has a meaning (below). Consumers ignore keys they don't recognise.

| Key | Type | Notes |
|-----|------|-------|
| `v` | number | `1`. |
| `kind` | string | `"talents"`. |
| `ts` | number | Unix time (seconds) when the export was made. |
| `addon`, `game` | object | As in the character export. `game.version`/`build` matter here: a tree export is only as current as the client it came from. |
| `class` | object | `classFile` (stable token, e.g. `WARRIOR` — this is the key the website files the trees under) and `class` (localized display name). |
| `locale` | string | The client's locale (`GetLocale()`, e.g. `enUS`). Names and rank text are in this language. |
| `trees` | array | In the client's **tab order**, which is the order the character export's `talents[]` uses. Exactly the trees the client reports (three in Classic); the website replaces the class's trees as a set, so a partial export is rejected. |

### `trees[]`

| Key | Type | Notes |
|-----|------|-------|
| `index` | number | 1-based tab index. |
| `name` | string | Localized tree name (`GetTalentTabInfo`). |
| `icon` | number or string | The tree's icon, **exactly what the client returned**: a FileDataID number on modern clients, a texture path string on older ones. Best-effort; consumers fall back to text. |
| `background` | string | The tree's background texture name (`fileName` from `GetTalentTabInfo`), when the client gives one. |
| `talents` | array | **In the client's talent index order** (`GetTalentInfo(tab, i)` for `i = 1..GetNumTalents(tab)`). This order is the contract: the character export's `ranks` string for this tree has one digit per entry here, in this order, and the calculator's build links use the same order. Never sort these. |

### `talents[]`

| Key | Type | Notes |
|-----|------|-------|
| `name` | string | Localized. |
| `icon` | number or string | As above. |
| `tier` | number | Row, 1-based from the top (`tier` from `GetTalentInfo`). |
| `column` | number | Column, 1-based from the left. |
| `maxRank` | number | |
| `ranks` | array | One entry per rank, rank 1 first: the rank's description **as text**, or `null` when the exporting client could not show it (see *Rank text*). Length is always `maxRank`. |
| `requires` | object | Present when the talent has a prerequisite (`GetTalentPrereqs`): `tier`, `column` of the prerequisite talent in this tree. Classic requires the prerequisite at full rank; if the client reports a required rank, add `rank`. |
| `spellIds` | number[] | The spell ID of each rank, when the client exposes them (some clients do through the talent link). Optional; useful for matching against other data, never required. |

Talent positions are unique within a tree; two talents on one cell is a malformed export.

## Rank text

The talent tooltip shows the **current** rank's text and the **next** rank's. So one character can supply, for each talent, the text of the rank they have and the one after it — for an unspent talent, rank 1 only. The addon fills what it can see and writes `null` for the rest; it must not guess, extrapolate or copy rank 1's text into later ranks.

The website **merges** across exports: layout, names, ranks and prerequisites are taken whole from the newest export for that class (the client is authoritative), and each rank's text is kept from whichever export had it. Three or four raiders of a class with different builds between them cover every rank of every talent the guild cares about, without anyone respeccing.

Text is plain: the addon strips colour codes (`|cAARRGGBB` … `|r`) and texture escapes (`|T…|t`) and joins tooltip lines with a newline. Numbers are left exactly as shown — a rank's text is what a player would read in game, not a template.

## Trust

As with every export: the addon's source is public and the string is plain text, so it can be hand-edited. The website treats a talent export as a proposal — an officer reviews and applies it, the same way item observations wait in a queue — not as something to apply on sight.

## Versioning

- Adding optional keys: no version change.
- Changing the meaning of a key, the talent order rule, or the envelope: `kind: "talents"` with `v: 2`, and the website's importer learns both.

## Example (decoded JSON, abbreviated)

```json
{
  "addon": { "name": "MintCommunityTools", "version": "0.1.0" },
  "class": { "class": "Warrior", "classFile": "WARRIOR" },
  "game": { "build": "60101", "toc": 16001, "version": "1.60.1" },
  "kind": "talents",
  "locale": "enUS",
  "trees": [
    {
      "index": 1,
      "name": "Arms",
      "icon": 132355,
      "background": "WarriorArms",
      "talents": [
        { "name": "Improved Heroic Strike", "icon": 132282, "tier": 1, "column": 1, "maxRank": 3,
          "ranks": ["Reduces the cost of your Heroic Strike ability by 1 rage point.", "Reduces the cost of your Heroic Strike ability by 2 rage points.", null] },
        { "name": "Deflection", "icon": 132269, "tier": 1, "column": 2, "maxRank": 5,
          "ranks": ["Increases your Parry chance by 1%.", null, null, null, null] },
        { "name": "Deep Wounds", "icon": 132090, "tier": 3, "column": 3, "maxRank": 3, "requires": { "tier": 1, "column": 3 },
          "ranks": ["Your critical strikes cause the opponent to bleed, dealing 20% of your melee weapon's average damage over 12 sec.", null, null] }
      ]
    },
    { "index": 2, "name": "Fury", "talents": [ "…" ] },
    { "index": 3, "name": "Protection", "talents": [ "…" ] }
  ],
  "ts": 1790000000,
  "v": 1
}
```
