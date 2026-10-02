# Item export, format v1

The contract between the in-game addon (producer) and the website (consumer) for item data: what the game client says about the items a player has seen drop. The website's item database is curated by officers; this export is how members feed it without an API token. The companion specs are [`export-string-format-v1.md`](export-string-format-v1.md) (a character), [`raid-capture-format-v1.md`](raid-capture-format-v1.md) (a raid) and [`talent-tree-format-v1.md`](talent-tree-format-v1.md) (a class's talents).

Produced by the addon's loot tracker (Loot tab, **Export new items**); consumed by the website's item importer, which files every item in the officers' review queue — the same buffer the item API (`POST /api/items/submit`) writes to. Nothing in an export reaches the item database until an officer approves it. A change to this format is made in both repositories.

## Envelope

Identical to a character export: `GAE1:<base64 JSON>:<adler32>`. See the character spec for the layout and decoding. A consumer tells the documents apart by the `kind` key: `"items"` here, `"raid"` for a raid recording, `"talents"` for talent trees, absent on a character export. Each importer rejects the other kinds with a message saying where they belong.

## Size, and parts

One item with its stats is about 300 bytes of JSON, 400 in the string. The game's text box becomes slow to select and copy well before the website would mind the size, so **the addon puts at most 100 items in one string** (about 40 KB) and splits a larger export into parts. The website accepts up to 256 KB and 500 items per string.

**Every part is a complete document that stands on its own.** Parts can be pasted in any order, some can be left out, and any part can be pasted twice: the importer treats each as it would a small export. `part` is there so the website can say "part 2 of 3" back to the person pasting, nothing more.

The addon exports **only what is new**: items it has not exported before, and items whose details changed since (the client describes an item it has not loaded yet by its link alone, and fills in the rest later). "Export all" sends everything again, for a paste that went astray. So the same item arriving twice, identical, is normal and must be harmless.

## JSON document

Keys are emitted in sorted order. An unknown value is **omitted**, never `null`. Consumers ignore keys they don't recognise.

| Key | Type | Notes |
|-----|------|-------|
| `v` | number | `1`. |
| `kind` | string | `"items"`. |
| `ts` | number | Unix time (seconds) when the export was made. |
| `addon`, `game` | object | As in the character export (`game.portal` included, so a beta client's items can be told apart). |
| `by` | object | The character that was being played when the export was made: `name`, `lastName`, `realm`, `region`, as in the character export's `char`. Informational. **Credit for a find goes to the website account that pastes the string**, not to this. |
| `part` | object | `index` (from 1) and `of`. `{ "index": 1, "of": 1 }` when the export is a single string. |
| `items` | array | At least one item, at most 100 from this addon. |

### `items[]`

The same shape the item API takes, so one importer serves both.

| Key | Type | Notes |
|-----|------|-------|
| `id` | number | Item id. Required. |
| `name` | string | Item name as shown in the client. Required. |
| `quality` | number | 0 Poor, 1 Common, 2 Uncommon, 3 Rare, 4 Epic, 5 Legendary. |
| `itemLevel` | number | |
| `itemClass` | string | The client's item type, localized ("Armor", "Weapon", "Trade Goods"). |
| `itemSubclass` | string | The client's subtype, localized ("Cloth", "One-Handed Swords"). |
| `equipLoc` | string | The equip location token (`INVTYPE_FEET`); absent for things that are not worn. |
| `icon` | number or string | **Exactly what the client returned**: a FileDataID number on modern clients, a texture path string on older ones. |
| `stats` | object | The item's stat block exactly as the client's `GetItemStats` reports it, keyed by the client's stat token. Zero-valued stats are left out; the key is omitted when there is nothing to report. |

An item appears once per string. **Items with a random suffix ("of the Bear") are never exported**: every variant shares the item id and differs in name and stats, so there is no single item to file them under.

## Trust

As with every export: the addon's source is public and the string is plain text, so it can be hand-edited. That is why it only reaches the review queue. The checksum only detects accidental truncation or corruption.

## Versioning

- Adding optional keys: no version change.
- Changing the meaning of a key or the envelope: `kind: "items"` with `v: 2`, and the website's importer learns both.

## Example (decoded JSON, abbreviated)

```json
{
  "addon": { "name": "MintCommunityTools", "version": "0.2.0" },
  "by": { "lastName": "Stormwind", "name": "Theoden", "realm": "Classic Beta PvP", "region": "US" },
  "game": { "build": "70009", "portal": "test", "toc": 16001, "version": "1.60.1" },
  "items": [
    { "equipLoc": "INVTYPE_FEET", "icon": 132541, "id": 16800, "itemClass": "Armor", "itemLevel": 66,
      "itemSubclass": "Cloth", "name": "Arcanist Boots", "quality": 4,
      "stats": { "ITEM_MOD_INTELLECT_SHORT": 14, "ITEM_MOD_STAMINA_SHORT": 13 } },
    { "icon": 134104, "id": 20725, "itemClass": "Gem", "itemLevel": 60, "itemSubclass": "Simple",
      "name": "Nexus Crystal", "quality": 3 }
  ],
  "kind": "items",
  "part": { "index": 1, "of": 1 },
  "ts": 1790000000,
  "v": 1
}
```
