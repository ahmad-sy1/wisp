# Night notes

Log of the overnight work on **CI & PR Radar** and the **departure assistant** (5 Nov 2026). Newest state of this file is on the last branch of the stack.

## What I found

- **There was no GitHub integration yet.** The brief says to reuse the existing auth, but only a placeholder Home tile and a plan in `docs/INTEGRATIONS.md` existed. So the sign-in is built too. WHOOP doesn't exist either (not needed).
- **There were no tests.** Added a `wispTests` target that compiles the pure `Core` folders with no host app (a hosted test would start wisp, which claims the notch and the hook socket), and `scripts/test.sh`. `xcodebuild test` hung here for 15+ minutes; `xcrun xctest` runs them in milliseconds, so the script and CI use that.
- Six PRs of yours are still open (#32–#38). `feat/home-tiles` already contains four of them.

## Decisions

| Decision | Why |
|---|---|
| Stacked on `feat/home-tiles`, each PR targets the previous branch | The new tabs need its `HomeTile` and Preferences. This differs from "PR against main", but keeps every diff readable. Merge from the bottom up; GitHub retargets the next PR if you delete the merged branch. |
| Branch names `feature/...` | From your brief, over `feat/...` in `CONTRIBUTING.md`. |
| Sign-in: *Use GitHub CLI login* (after a click) or a pasted token | OAuth/device flow needs an OAuth app registered on your account, which I shouldn't do for you. A token sits in the Keychain only. |
| Polling while the notch is closed | A deliberate exception to "no timers when closed", because you asked for it: one pending wake-up, adaptive (25 s running, 60 s just active, 3 min quiet), nothing asleep/locked/disconnected. |
| REST with ETags for the radar, one GraphQL call for the graph | 304s don't count against the limit. GraphQL has no ETag, so it runs at most every 30 min and only with the tab open. |
| Failures win over running jobs; cancelled and skipped aren't failures | You want to know of a failure right away; a cancelled run is usually superseded by a new push. |
| Your own comments and `[bot]` comments aren't news | Otherwise CI bots would tick the notch all day. |
| First answer after connecting is silent | Existing state isn't an event. Failed runs do show their dot. |

## To do for you

- Connect GitHub in Settings → Integrations (one click if `gh` is logged in).
