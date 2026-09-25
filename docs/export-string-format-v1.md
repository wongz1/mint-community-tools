# Guild Armory export string, format v1

This is the contract between the in-game addon (producer) and the website / Discord bot (consumers).
Anything that can decode this string can be a consumer. Nothing here depends on Blizzard's web API.

## String layout

```
GAE1:<base64>:<checksum>
```

| Part | Meaning |
|------|---------|
| `GAE1` | Format marker plus major version. A consumer must reject any prefix it does not know. |
| `<base64>` | Standard RFC 4648 base64 (alphabet `A-Za-z0-9+/`, `=` padding, no line breaks) of the UTF-8 JSON document below. |
| `<checksum>` | Adler-32 of the raw JSON bytes (the base64-decoded payload) as 8 lowercase hex characters. Same value as zlib's `adler32`. |

The three parts are separated by `:`; base64 never contains `:`, so splitting on `:` is safe.

### Decoding (any language)

1. Trim whitespace, split on `:`, require exactly 3 parts and prefix `GAE1`.
2. Base64-decode part 2 to bytes.
3. Compute Adler-32 of those bytes; compare with part 3. If it differs, the string was truncated or edited: reject it.
4. Decode the bytes as UTF-8 and parse as JSON.

JavaScript:

```js
function adler32(bytes) {
  let a = 1, b = 0;
  for (const x of bytes) { a = (a + x) % 65521; b = (b + a) % 65521; }
  return ((b << 16) | a) >>> 0;
}
function decodeGae(str) {
  const [prefix, body, sum] = str.trim().split(":");
  if (prefix !== "GAE1") throw new Error("unsupported version");
  const bytes = Uint8Array.from(atob(body), c => c.charCodeAt(0));
  if (adler32(bytes).toString(16).padStart(8, "0") !== sum.toLowerCase()) throw new Error("checksum mismatch");
  return JSON.parse(new TextDecoder().decode(bytes));
}
```

Python:

```python
import base64, json, zlib
def decode_gae(s):
    prefix, body, csum = s.strip().split(":")
    assert prefix == "GAE1"
    raw = base64.b64decode(body, validate=True)
    assert format(zlib.adler32(raw) & 0xffffffff, "08x") == csum.lower()
    return json.loads(raw.decode("utf-8"))
```

A second document type, a recorded raid, uses the same envelope and is told apart by `"kind": "raid"`; see [`raid-capture-format-v1.md`](raid-capture-format-v1.md). A character export has no `kind` key.

## JSON document

Keys are emitted in sorted order. A key whose value is unknown is **omitted**, never `null`. Consumers must ignore keys they do not recognise, so fields can be added within v1 without breaking anyone.

| Key | Type | Notes |
|-----|------|-------|
| `v` | number | Schema version. Always `1` for this document. |
| `src` | string | `"self"` (player exported their own character). Reserved for `"inspect"` in a later version. |
| `ts` | number | Unix time (seconds) when the export was made. |
| `addon` | object | `name`, `version` of the exporting addon. |
| `game` | object | `version` (e.g. `"1.15.9"`), `build`, `toc` (interface number) reported by the client. |
| `char` | object | See below. |
| `items` | array | Equipped items. Empty slots are simply absent. |
| `talents` | array | Optional. Classic-style talent trees. Absent when the client has no such API. |
| `talentsError` | string | Present only if reading talents raised an error. |

### `char`

`name` (the FIRST name), `lastName` (the last name — see below), `realm` (display name), `realmSlug` (normalised, when the client provides it), `region` (`US`/`KR`/`EU`/`TW`/`CN`), `class` (localised), `classFile` (stable English token like `WARRIOR`, use this for logic), `race`, `raceFile`, `sex` (2 = male, 3 = female), `level`, `faction`, `guild`, `guildRank`.

**WoW Forever characters have a first and a last name**, and it is the pair that is unique — first names repeat. In the real client `UnitName("player")` returns the first name, with the last name as its **second return value** (where other clients put the realm); the settings folder writes them as `First-Last` and chat lines as `First Last`. The addon puts the first name in `name` and the last name in `lastName` (a single word, no spaces or hyphens). A second value that equals the current realm name is the realm, not a last name (`GetNormalizedRealmName()` to compare). `lastName` is omitted only on a client that has no last names at all.

**Character identity is `region` + `realm` + `name` + `lastName`.** A website row that has no last name yet (from before the addon sent one) is matched by first name and completed by the next export that names the character.

### `items[]`

| Key | Type | Notes |
|-----|------|-------|
| `slot` | number | Inventory slot id, see table. |
| `id` | number | Item id. |
| `name` | string | Item name as shown in the client, so the site does not need an item database to display it. |
| `quality` | number | 0 Poor, 1 Common, 2 Uncommon, 3 Rare, 4 Epic, 5 Legendary. |
| `ilvl` | number | Item level when the client reported one. |
| `enchant` | number | Enchant id from the item link (omitted when none). |
| `gems` | number[] | Non-zero gem item ids in socket order (omitted when none). |
| `suffix` | number | Random suffix id, e.g. negative for "of the Bear" style items (omitted when none). |
| `icon` | number or string | **Exactly what the client returned.** A FileDataID number on modern clients, or a texture path string like `Interface\Icons\INV_Jewelry_Necklace_07` on older ones. A number needs a FileDataID-to-image lookup on the website. Treat the icon as best-effort and fall back to a placeholder. |
| `stats` | object | Optional. The item's stat block exactly as the client's `GetItemStats` reports it, keyed by the client's stat token, e.g. `{ "ITEM_MOD_STAMINA_SHORT": 13, "ITEM_MOD_CRIT_RATING_SHORT": 2 }`. Numbers as given (a weapon's DPS can be fractional). Zero-valued stats are left out, and the key is omitted when the client has no such API or reports nothing for the item. This is what lets the website compare items without an item database. |

Slot ids: 1 Head, 2 Neck, 3 Shoulder, 4 Shirt, 5 Chest, 6 Waist, 7 Legs, 8 Feet, 9 Wrist, 10 Hands, 11 Ring 1, 12 Ring 2, 13 Trinket 1, 14 Trinket 2, 15 Back, 16 Main hand, 17 Off hand, 18 Ranged, 19 Tabard.

### `talents[]`

One entry per talent tree: `name`, `points` (points spent), `ranks` (a string with one digit per talent in the client's own talent order, rank capped at 9). Rendering a talent grid needs a per-tree layout table on the website; totals (`points`) are enough for a simple "31/20/0" display.

## Versioning rules

- Adding optional keys to the JSON: no version change.
- Changing the meaning of an existing key, or the string layout (for example adding compression): new prefix (`GAE2`). Producers and consumers can then support both side by side.

## Trust

The addon's source is public and strings are plain text, so a string can be hand-edited. Treat every import as **self-reported**. Do not use it for anything that needs to be tamper-proof. The checksum only detects accidental truncation or corruption.

## Example (decoded JSON, abbreviated)

```json
{
  "addon": { "name": "MintBridge", "version": "0.1.0" },
  "char": { "class": "Warrior", "classFile": "WARRIOR", "faction": "Alliance", "guild": "My Guild",
            "lastName": "Stormwind", "level": 60, "name": "Theoden", "race": "Human", "realm": "Mock Realm", "region": "US" },
  "game": { "build": "60101", "toc": 16001, "version": "1.60.1" },
  "items": [
    { "icon": 135001, "id": 12640, "ilvl": 66, "name": "Lionheart Helm", "quality": 4, "slot": 1,
      "stats": { "ITEM_MOD_AGILITY_SHORT": 18, "ITEM_MOD_CRIT_RATING_SHORT": 2, "ITEM_MOD_STRENGTH_SHORT": 18 } },
    { "enchant": 2564, "gems": [2345], "id": 18404, "name": "Onyxia Tooth Pendant", "quality": 4, "slot": 2 }
  ],
  "src": "self",
  "talents": [ { "name": "Arms", "points": 31, "ranks": "1234" } ],
  "ts": 1790000000,
  "v": 1
}
```
