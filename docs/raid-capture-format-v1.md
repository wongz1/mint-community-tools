# Raid recording, format v1

The contract between the in-game addon (producer) and the website (consumer) for a recorded raid: boss kills, who was present at each, and the loot. The companion to [`export-string-format-v1.md`](export-string-format-v1.md), which covers a single character.

Produced by the addon in this repository; consumed by the website's `web/src/lib/raid-capture.ts` (validation) and `web/src/lib/raid-ingest.ts` (writing and merging) in [wongz1/mintys-community-manager](https://github.com/wongz1/mintys-community-manager). The website keeps reference recordings in `web/src/lib/__fixtures__/` that its importer tests run against; an addon that produces strings matching those is one the website can import. A change to this format is made in both repositories.

## Envelope

Identical to a character export: `GAE1:<base64 JSON>:<adler32>`. See the character spec for the layout and decoding. A consumer tells the two apart by the `kind` key: `"raid"` here, absent on a character export. Each importer rejects the other's document with a message saying where it belongs.

A full night (40 players, 10 bosses, 30 drops with stats) is roughly 10 KB of JSON. The website accepts up to 512 KB.

## JSON document

Keys are emitted in sorted order. An unknown value is **omitted**, never `null`. Consumers ignore keys they don't recognise.

| Key | Type | Notes |
|-----|------|-------|
| `v` | number | `1`. |
| `kind` | string | `"raid"`. |
| `ts` | number | Unix time (seconds) when the export was made. |
| `addon`, `game` | object | As in the character export. |
| `capturedBy` | object | `name`, `realm`, `region` of the player who recorded. `region` is the only source of region for every player in the recording. |
| `session` | object | `id` (unique per recording, not per raid), `instance` (instance name as the client reports it), `startedAt`, `endedAt` (absent while still recording; exporting mid-raid is fine). |
| `players` | array | Everyone seen, once each. Kills and loot refer to players by **0-based index** into this array. |
| `kills` | array | Boss kills in the order they happened. |
| `preLoot` | array | Loot recorded before the first kill (a trash drop). Same shape as a kill's `loot`. The website files it under the first kill. |

### `players[]`

`name`, `realm` (the recorder's realm when the client gave a bare name; the realm suffix from a cross-realm `Name-Realm` otherwise), `classFile` (stable token, e.g. `PRIEST`), `class` (localized). `classFile`/`class` are absent for a player seen only in a loot message and never in the raid roster.

### `kills[]`

| Key | Type | Notes |
|-----|------|-------|
| `seq` | number | Order within this recording, from 1. The website renumbers by time after merging. |
| `boss` | string | Encounter name from the client. |
| `encounterId` | number | When the client provided one. |
| `ts` | number | **Server time** of the kill (`GetServerTime`). Every client in the raid agrees on this to within a second or two, which is what lets two officers' kills be matched. |
| `attendees` | number[] | Player indexes. Everyone **in the group and online** at the moment of the kill. Zone is deliberately not checked: a raider running back from the graveyard is outside the instance when the boss dies. |
| `loot` | array | See below. |

Wipes are not recorded. A kill is `ENCOUNTER_END` with success, or `BOSS_KILL`; both firing for one kill is merged.

### `loot[]`

| Key | Type | Notes |
|-----|------|-------|
| `id`, `name` | number, string | From the item link. |
| `quality` | number | 0–5. Only items at or above the recorder's threshold (Epic by default) are recorded. |
| `ilvl`, `enchant`, `suffix` | number | When present. |
| `icon` | number or string | Exactly what the client returned, as in the character export. |
| `itemType`, `itemSubType` | string | **Localized** display strings. Show them; don't branch on them. |
| `equipLoc` | string | `INVTYPE_*` token; locale-independent. Absent for items that can't be equipped. |
| `classId`, `subclassId` | number | Item class (2 weapon, 4 armor, 12 quest, …) when the client returns them; locale-independent. |
| `stats` | object | The full `GetItemStats` block. Absent (not `{}`) when the item has none. |
| `to` | number | Player index of whoever received it. **Absent** when nobody did, or not yet. |
| `ts`, `toTs` | number | When it was first seen, and when it was received. |

Two loot entries are the same item when `id` and `suffix` match. One entry is one physical drop: two copies of an item are two entries.

How the addon knows what it knows:

- **What dropped** comes from the loot window. A corpse can be opened many times, showing fewer items each time, so per item the addon keeps the largest count seen in any single opening.
- **Who got it** comes from the raid's loot messages, matched using the client's own localized format strings. An award is attached to an un-awarded drop of that item, newest kill first (loot is often handed out after the raid has moved on). A loot message for an item never seen in a window still records the drop.

Item details in a recording come only from the client. (The website now also keeps an item database; what a recording says about an item is offered to it through the officers' review buffer, never written straight in.)

## Merging (consumer rules)

More than one officer records the same raid, because WoW writes an addon's saved data only on logout or `/reload` and a crash loses everything since. The website merges their recordings; nobody coordinates a session code.

- **Same raid** = same `instance` and the same raid date in the guild's home time zone (a night belongs to the date it started on, rolling over at 06:00), with at least half the smaller attendee set in common. Less overlap than that is a split run and becomes its own raid (`…#2`).
- **Same kill** = same `boss`, kill times within 5 minutes. New kills are added and the whole raid is renumbered by time.
- **Attendance** is the union.
- **Drops** per kill and item are the *larger* of the two counts, never the sum: both recorders saw the same copies.
- **Awards** fill drops that are still pending, skipping a recipient who already has that item from that kill. A disposition an officer set on the website is never overwritten by a paste.
- Pasting the same recording twice changes nothing. Merging A then B gives the same result as B then A. Every raw paste is kept for audit.

Raiders not on the roster are created under an "Unclaimed" system member so attendance and loot have something to point at; when the player later imports that character themselves, it becomes theirs along with its history.

## Trust

As with character exports: plain text, hand-editable, checksum only catches accidents. Importing is officer-only, and a recording is trusted exactly as far as "an officer submitted it".
