# Releasing Mint Community Tools

1. Test in game: `/mint` opens the window with your gear, **Export for website** produces a
   string, and the website's Roster page accepts it.
2. Set the new version in both places, e.g. `0.2.0`:
   - `MintCommunityTools/MintCommunityTools.toc`: `## Version: 0.2.0`
   - `MintCommunityTools/Core.lua`: `ns.VERSION = "0.2.0"`

   (`python3 tests/run.py` fails if they differ.)
3. Add a `## 0.2.0` section at the top of `CHANGELOG.md`. It becomes the release notes.
4. Commit and push, then tag:

   ```bash
   git tag v0.2.0
   git push origin v0.2.0
   ```

The Release workflow then runs the tests, checks the tag matches the `.toc` version, builds
`MintCommunityTools-v0.2.0.zip` (only the `MintCommunityTools` folder, see `.pkgmeta`) and
publishes it to GitHub Releases. Watch it under the repo's Actions tab.

The link to give testers is always the same:
https://github.com/wongz1/mint-community-tools/releases/latest
