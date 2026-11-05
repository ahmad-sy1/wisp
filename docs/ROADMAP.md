# Roadmap

What is planned, roughly in order. Every item becomes its own branch and pull request; bigger ones get a GitHub issue first.

## Next

| Item | Notes | Tracking |
|---|---|---|
| **Files tab** | The drop zone, restyled. | |
| **Home tiles** | Pick the Home tiles as chips (board 10.1); GitHub is live, Notion and WHOOP don't exist yet. | [#24](https://github.com/ahmad-sy1/wisp/issues/24) |
| **Focus task rules: sites and defaults** | Adding app/project rules is done; browser sites as a source (needs Automation) and *Default* rules are left. Board 10.6. | [#27](https://github.com/ahmad-sy1/wisp/issues/27) |
| **Notion, WHOOP** | Sign in with OAuth (PKCE), tokens in the Keychain; fills the Home tiles. See [INTEGRATIONS.md](INTEGRATIONS.md#planned-notion-whoop). | |
| **Own app icon and sounds** | The wisp mark from board 0; short, quiet system-like sounds. | |
| **First signed release** | `./scripts/release.sh` once the main tabs are in. See [RELEASING.md](RELEASING.md). | |

## Later

- **Departure**: NDW open data for the road a jam is on; a choice of route for repeated trips; other countries' providers behind `TravelProvider`.

## Decided against

- **Song lyrics** (LRCLIB): built and removed again. The spectrum is enough, and no song data needs to leave the Mac.
- **"Up next" in the Music tab**: macOS doesn't expose the queue of Spotify or YouTube.
- **Tab bar next to the camera**: would save about 38 pt of height, but the space under the camera stays as it is.
