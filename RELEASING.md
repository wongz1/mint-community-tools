# Releasing Mint Community Tools

1. Test in game: `/mint` opens the window with your gear, **Export for website** produces a
   string, and the website's Roster page accepts it; the minimap button sits on the minimap's
   edge; looting something puts it on the Loot tab, and shift-clicking it links it in chat;
   with the minimalist UI on, the bars, chat, unit frames, minimap and quest list come up,
   `/mint edit` moves them, and the Escape menu and its windows open flat.
2. Set the new version in both places, e.g. `0.2.0`:
   - `MintCommunityTools/MintCommunityTools.toc`: `## Version: 0.2.0`
   - `MintCommunityTools/Core.lua`: `ns.VERSION = "0.2.0"`

   (`python3 tests/run.py` fails if they differ.)
3. Add a `## 0.2.0` section at the top of `CHANGELOG.md`. It becomes the release notes, on
   GitHub and in Discord (step 5), exactly as written. Members read it, so write it for
   players: what changed for them and how to use it, no internals.
4. Commit and push, then tag:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

The Release workflow then runs the tests, checks the tag matches the `.toc` version, builds
`MintCommunityTools-v0.2.0.zip` (only the `MintCommunityTools` folder, see `.pkgmeta`) and
publishes it to GitHub Releases. Watch it under the repo's Actions tab.

5. Publish the notes to Discord. This is the last step of every release, once the tag is
   pushed (so the post can link to the GitHub release). Look first, then post:

   ```bash
   python3 ~/Documents/wow-guild-management/WoW-Forever-Guild-Website-and-Management/scripts/addon-publish.py ~/Documents/MintCommunityTools --dry-run
   python3 ~/Documents/wow-guild-management/WoW-Forever-Guild-Website-and-Management/scripts/addon-publish.py ~/Documents/MintCommunityTools
   ```

   The script reads the top `## <version>` section of `CHANGELOG.md` and the `.toc` Title,
   and says where the post is going: Mint Community Tools goes to `#mct-addon-dev`. Long
   notes are fine; what does not fit in the post continues in the thread under it.

   - Only as part of a release, never for work in progress: it posts in the community's
     Discord.
   - Publishing a version a second time replaces the stored notes and does not post again.
     `--repost` posts it again; use it only when asked to.
   - It uses an officer's API token already set up on this Mac
     (`~/.config/mintys-community-manager/token`). Leave that file alone.
   - If the script says the website refused it, stop and report the message.

   How it works: `docs/addon-updates.md` in the website repository.

The link to give testers is always the same:
https://github.com/wongz1/mint-community-tools/releases/latest
