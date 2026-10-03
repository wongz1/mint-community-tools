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
publishes it to GitHub Releases, and to CurseForge once that is set up (below). Watch it
under the repo's Actions tab.

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

## CurseForge

The CurseForge project's ID is `1724233` (also in the `.toc` as `## X-Curse-Project-ID`).
Every tagged release is uploaded to it as a beta file for WoW Forever 1.60.1, with that
version's section of `CHANGELOG.md` as its notes.

One-time setup: create an API token at https://authors.curseforge.com/account/api-tokens and
save it as the repository secret `CF_API_KEY` (GitHub: Settings > Secrets and variables >
Actions). Until that secret exists the upload step is skipped and releases go to GitHub only.

- The upload is done by `tools/cf_upload.py`, which trims the token: a secret pasted with a
  trailing newline made the packager's own upload fail with "Missing field metadata".
- To upload a release that already exists (one made before the secret was set, or one whose
  upload failed), run the "CurseForge upload" workflow from the Actions tab with the tag, or:

  ```bash
  gh workflow run cf-upload.yml -f tag=v0.5.0
  ```

- The upload looks up CurseForge's own id for WoW Forever 1.60.1. When the game moves to a
  new version, change `1.60.1` in both workflow files.

