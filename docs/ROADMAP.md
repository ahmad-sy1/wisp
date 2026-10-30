# Roadmap

What is planned, roughly in order. Every item becomes its own branch and pull request; bigger ones get a GitHub issue first.

## Next

| Item | Notes | Tracking |
|---|---|---|
| **Files tab** | The drop zone, restyled. | |
| **Home tiles** | Pick the Home tiles as chips (board 10.1), once GitHub, Notion and WHOOP exist. | [#24](https://github.com/ahmad-sy1/wisp/issues/24) |
| **Keyboard shortcut** | Open the notch with ⌥Space (changeable). Board 10.2. | [#25](https://github.com/ahmad-sy1/wisp/issues/25) |
| **Music settings** | Mini spectrum on/off, battery saver, which sources show. Board 10.5. | [#26](https://github.com/ahmad-sy1/wisp/issues/26) |
| **Focus task rules** | See, add and remove app/project/site → task rules. Board 10.6. | [#27](https://github.com/ahmad-sy1/wisp/issues/27) |
| **GitHub, Notion, WHOOP** | Sign in with OAuth (PKCE), tokens in the Keychain; fills the Home tiles. See [INTEGRATIONS.md](INTEGRATIONS.md#planned-github-notion-whoop). | |
| **Own app icon and sounds** | The wisp mark from board 0; short, quiet system-like sounds. | |
| **First signed release** | `./scripts/release.sh` once the main tabs are in. See [RELEASING.md](RELEASING.md). | |

## Decided against

- **Song lyrics** (LRCLIB): built and removed again. The spectrum is enough, and no song data needs to leave the Mac.
- **"Up next" in the Music tab**: macOS doesn't expose the queue of Spotify or YouTube.
- **Tab bar next to the camera**: would save about 38 pt of height, but the space under the camera stays as it is.
