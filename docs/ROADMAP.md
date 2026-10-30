# Roadmap

What is planned, roughly in order. Every item becomes its own branch and pull request; bigger ones get a GitHub issue first.

## Next

| Item | Notes | Tracking |
|---|---|---|
| **Clipboard tab** | Last ~20 items, local only, never passwords (`ConcealedType` / `TransientType` are skipped). Board 5. | |
| **Notes tab** | Quick notes stored as JSON in Application Support. Board 6. | |
| **System tab** | Battery, CPU, storage, Wi-Fi name; AirPods only if it can be read reliably. Board 7. | |
| **Files tab** | The drop zone, restyled. | |
| **Mail notifications in the notch** | A short peek with *Openen / Verwijderen / Later*, and the unread count on the closed notch. Board 8. | |
| **GitHub, Notion, WHOOP** | Sign in with OAuth (PKCE), tokens in the Keychain; fills the Home tiles. See [INTEGRATIONS.md](INTEGRATIONS.md#planned-github-notion-whoop). | |
| **Own app icon and sounds** | The wisp mark from board 0; short, quiet system-like sounds. | |
| **First signed release** | `./scripts/release.sh` once the main tabs are in. See [RELEASING.md](RELEASING.md). | |

## Decided against

- **Song lyrics** (LRCLIB): built and removed again. The spectrum is enough, and no song data needs to leave the Mac.
- **"Up next" in the Music tab**: macOS doesn't expose the queue of Spotify or YouTube.
- **Tab bar next to the camera**: would save about 38 pt of height, but the space under the camera stays as it is.
