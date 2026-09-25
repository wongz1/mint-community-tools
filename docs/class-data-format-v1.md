# Class data export, format v1: spellbooks and racials

The contract between the in-game addon (producer) and the website (consumer) for the class reference data shown under each class's talent calculator: the **spellbook by level** (every trainer spell, every rank, the level it is learned at, its cost and text) and the **racials** (what each race brings). The companion specs are [`talent-tree-format-v1.md`](talent-tree-format-v1.md) (a class's trees), [`export-string-format-v1.md`](export-string-format-v1.md) (a character) and [`raid-capture-format-v1.md`](raid-capture-format-v1.md) (a raid).

Produced by the addon in this repository; consumed by the website in [wongz1/mintys-community-manager](https://github.com/wongz1/mintys-community-manager), which stores the result in `forever_data` and shows it on `/talents/<class>`. Until an export arrives, that data comes from Talents Forever's CC BY 4.0 read of the beta client; an export replaces the matching slice and is never overwritten by that import again. A change to this format is made in both repositories.

## Why this exists

The maintainer wants the site to depend on the game itself, not on a third party's datamining. Everything Talents Forever publishes here is visible in the running client — at a class trainer, and in a character's spellbook — and an addon can read all of it. What an addon can't do is see everything from one character: a trainer teaches one class, a spellbook belongs to one race. So these exports are **per character, merged by the website**: nine visits to a trainer cover the spellbooks, and a few characters of different races cover the racials.

## Envelope

Identical to a character export: `GAE1:<base64 JSON>:<adler32>`. See the character spec for the layout and decoding. A consumer tells the documents apart by `kind`: `"spellbook"` and `"racials"` here, `"talents"` for trees, `"raid"` for a recording, absent on a character export. Each importer rejects the other kinds with a message saying where they belong.

A class's full spellbook is 30–60 KB of JSON; a racials export a few KB. The website accepts up to 512 KB.

## Common keys

Keys are emitted in sorted order. An unknown value is **omitted**, never `null`, except where a `null` is given a meaning below. Consumers ignore keys they don't recognise.

| Key | Type | Notes |
|-----|------|-------|
| `v` | number | `1`. |
| `kind` | string | `"spellbook"` or `"racials"`. |
| `ts` | number | Unix time (seconds) when the export was made. |
| `addon`, `game` | object | As in the character export. `game.version`/`build` say which client this describes. |
| `locale` | string | The client's locale (`GetLocale()`). Names and text are in this language. |
| `character` | object | Who exported: `classFile` (e.g. `WARRIOR`), `class` (localized), `raceFile` (e.g. `Dwarf` → `Dwarf`; the client's race token), `race` (localized), `faction` (`Alliance`/`Horde`), `level`. The website groups spellbooks by `classFile` and racials by `raceFile`; the rest is context. |

### A spell, wherever it appears

| Key | Type | Notes |
|-----|------|-------|
| `name` | string | Localized. |
| `rank` | string | The rank label as the game shows it (`"Rank 3"`, `"Passive"`, or `""` for a spell with one rank). |
| `spellId` | number | When the client exposes it (`GetSpellBookItemInfo`, or the spell link). Optional; it is how the website matches the same spell across exports and locales, so include it whenever it exists. |
| `icon` | number or string | **Exactly what the client returned**: a FileDataID number or a texture path. The website draws icons by name and falls back to nothing for a number. |
| `lines` | array | The tooltip's header lines as `[left, right]` pairs, in order: cost and range, cast time and cooldown, stance or weapon requirements — `[["15 Rage", "Melee Range"], ["Instant", "20 sec cooldown"]]`. Empty pairs are omitted. |
| `text` | string | The description, plain: colour codes (`|cAARRGGBB`…`|r`) and texture escapes (`|T…|t`) stripped, lines joined with `\n`. Numbers are what the tooltip showed **for the exporting character** — a level-30 character's Fireball does less than a level-60's — so `character.level` travels with it (below). |

## `kind: "spellbook"`

What a class learns, read at a **class trainer** with the "unavailable" filter on so every rank is listed, not only the ones this character can buy now (`SetTrainerServiceTypeFilter("unavailable", 1)`, then `GetNumTrainerServices()` / `GetTrainerServiceInfo(i)` / `GetTrainerServiceLevelReq(i)` / `GetTrainerServiceCost(i)` / `GetTrainerServiceIcon(i)`, and `GameTooltip:SetTrainerService(i)` for the text), plus what the character already knows from its own spellbook (`GetNumSpellTabs()` / `GetSpellTabInfo(t)` / `GetSpellBookItemName(i, "spell")`, `GameTooltip:SetSpellBookItem`). The spellbook part is what covers the spells no trainer sells: the ones every character starts with, and what talents grant.

| Key | Type | Notes |
|-----|------|-------|
| `trainer` | object | Present when the export was made with a trainer window open: `name` (the NPC), `zone`. Without it the export holds only known spells, and the website says so (it can't fill the level column from it). |
| `tabs` | array | The character's spellbook tabs in the client's order: `{ name, spells: [<spell>…] }`. `General` first. Each spell carries `known: true` and the common keys above. |
| `trainable` | array | Everything the trainer listed, known or not: a spell (common keys) plus `level` (the level requirement — the point of this export), `cost` (copper), `known` (already learned), and `skillLine`/`skillLevel` when the client reports a profession-style requirement. Ranks the character can't buy yet are exactly the ones worth having, so they are never filtered out. |

The website merges spellbook exports for a class by `spellId`, else by `name` + `rank`: `level` and `cost` from any trainer export that has them (they don't vary by character); `text` and `lines` from the **highest-level** exporting character, since the numbers scale; a spell's tab from any export that knew it. A spell present in one race's export and absent from another's of the same class (a Human Priest's *Desperate Prayer*) is marked as that race's, which is how per-race class spells are found without a special export.

## `kind: "racials"`

A character's racials, read from the **General** tab of its own spellbook. In Classic-style clients a racial's tooltip carries the words `Racial` or `Racial Passive` on its type line; the addon includes every General-tab spell and sets `racial: true` on the ones whose tooltip says so, so the website can tell *Blood Fury* from *Attack* without a list. (If this client's tooltips lack that line, the addon sets `racial` on nothing and the website falls back to "General-tab spells that no other race of this class has" across several exports; either way, send the whole tab.)

| Key | Type | Notes |
|-----|------|-------|
| `general` | array | Every spell in the General tab: the common keys plus `racial` (boolean, as above). |

The website keeps, per `raceFile`, the spells flagged racial, merged by `spellId`/name across exports, text from the highest-level exporter, and derives "which classes can be this race" from the classes that have exported for it (until a race's export exists, it keeps what it has from Talents Forever).

## Legacy perks

Not part of v1. They live in a panel of their own in the client; once someone has that panel open with the addon loaded and confirms what its API or frames expose, they get their own `kind` (or join the talent export as extra trees, which is how the website already models them: per-perk point gates, placeholder slots).

## Trust

As with every export: plain text a person could edit. The website treats these as proposals an officer reviews and applies, the same as talent trees and item observations — never applied on sight.

## Versioning

- Adding optional keys: no version change.
- Changing the meaning of a key or the envelope: the same `kind` with `v: 2`, and the website's importer learns both.

## Examples (decoded JSON, abbreviated)

```json
{
  "v": 1, "kind": "spellbook", "ts": 1790000000, "locale": "enUS",
  "addon": { "name": "MintCommunityTools", "version": "0.2.0" },
  "game": { "build": "69876", "toc": 16001, "version": "1.60.1" },
  "character": { "classFile": "WARRIOR", "class": "Warrior", "raceFile": "Dwarf", "race": "Dwarf", "faction": "Alliance", "level": 34 },
  "trainer": { "name": "Bilban Tosslespanner", "zone": "Ironforge" },
  "tabs": [
    { "name": "General", "spells": [ { "name": "Attack", "rank": "", "spellId": 6603, "icon": "Interface\\Icons\\Ability_MeleeDamage", "known": true, "lines": [], "text": "Basic melee attack." } ] },
    { "name": "Arms", "spells": [ { "name": "Charge", "rank": "Rank 2", "spellId": 6178, "icon": "Interface\\Icons\\Ability_Warrior_Charge", "known": true,
        "lines": [["", "8-25 yd range"], ["Instant", "15 sec cooldown"], ["Requires Battle Stance", ""]],
        "text": "Charge an enemy, generate 12 Rage, and Stun it for 1 sec. Cannot be used in combat." } ] }
  ],
  "trainable": [
    { "name": "Charge", "rank": "Rank 3", "spellId": 11578, "level": 46, "cost": 180000, "known": false, "icon": "Interface\\Icons\\Ability_Warrior_Charge",
      "lines": [["", "8-25 yd range"], ["Instant", "15 sec cooldown"]], "text": "Charge an enemy, generate 15 Rage, and Stun it for 1 sec. Cannot be used in combat." }
  ]
}
```

```json
{
  "v": 1, "kind": "racials", "ts": 1790000500, "locale": "enUS",
  "character": { "classFile": "WARRIOR", "class": "Warrior", "raceFile": "Orc", "race": "Orc", "faction": "Horde", "level": 60 },
  "general": [
    { "name": "Blood Fury", "rank": "", "spellId": 20572, "racial": true, "icon": "Interface\\Icons\\Racial_Orc_BerserkerStrength",
      "lines": [["Instant", "2 min cooldown"]], "text": "Increases Attack Power and Spell Power by 10% for 15 sec." },
    { "name": "Attack", "rank": "", "spellId": 6603, "racial": false, "icon": "Interface\\Icons\\Ability_MeleeDamage", "lines": [], "text": "Basic melee attack." }
  ]
}
```
