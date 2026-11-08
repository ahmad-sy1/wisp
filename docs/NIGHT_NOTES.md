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

| New tabs land at the end of your own tab order | That is what `Preferences` does for a saved order. Drag GitHub and Departure next to Calendar in Settings → Notch to match the design. |
| Wing order: focus, urgent status, music, calm status, mail | A failure beats music; a run that merely goes doesn't take the spectrum away. |
| Own pull request glyph | SF Symbols has nothing like the design's icon; `arrow.triangle.pull` read as a fork. |
| First look skips old comments | With 21 open PRs a first round was 130 requests. Now about 65, and the list shows right after the search. |

### Departure engine

| Decision | Why |
|---|---|
| wisp doesn't know where you are | It never reads your location (a promise in the README). The trip starts at the event you're at or just left, otherwise at home. |
| Three hours ahead it starts asking, 45 minutes before leaving it shows | Asking earlier wastes requests; the 45 is the point where it is useful to see. |
| "Routine" means an event without a location gets it from the same title elsewhere | From three different days at one place, or at once for a repeating event. Any event with a location already counts as a trip, as the brief says. |
| The way home ends 45 minutes after your last event | wisp can't see that you've left. |
| Same building is no trip | Two lessons in a row at the same place, by name or within about 150 m. |
| Red from a delay or jam of 10 min, orange from 3 min (or within 5 min of leaving) | My choice; constants at the top of `DepartureEngine`. |
| Waiting is only advised from 10 min saved, and never if it makes you late | Below that the advice is noise. |
| Rain check default off | As on design page 4. |
| A bike route is a walking route's length at 16 km/h | The SDK's MapKit has no cycling directions (`automobile`, `walking`, `transit` only). |

### Providers

| Decision | Why |
|---|---|
| **No fake data in a real build.** Without an NS key wisp uses Apple Maps' total transit time, not the mock | Your brief says to use the mock, but made-up train times could make you miss a real train. The mock is there for tests and Debug (`-departureDemo`). |
| NS for the route, OVapi only for how late a bus is | NS's advice includes buses with line numbers. OVapi has no route planner. |
| OVapi over plain HTTP | It has no HTTPS (tested). A single exception in `Info.plist`; only stop codes go there. |
| Buienradar first, then Open-Meteo | Radar is better for "rain in 10 minutes", but only covers NL/BE; this has to work for any user. |
| Not NDW for the road number | Stretch goal; left out. The route name from MapKit gives *A15* when it can. |

Tested live: place lookup, car (33 min, 23 without traffic), bike, transit ETA, Buienradar, Open-Meteo, OVapi's stop list. **Not tested: NS**, I have no key. Its parser is tested on a response I wrote by hand from public examples of the v3 API; `originLat`-style parameters come from memory of the docs. Check it first.

The search also turned up a public repository with an NS key in its source. I didn't use it.

### Departure UI

| Decision | Why |
|---|---|
| A trip goes before a GitHub status on the notch | It is on the clock, and only there during its window. |
| *Reistijd naar je dienst* moved to Settings → Departure, *Op de fiets/auto* became *Standaard vervoer* | The merge you asked for. Your saved mode (car) carried over; *on foot* isn't on the design, so it becomes bike. Recognising shifts stays under Calendar & weather. |
| The Agenda's departure card uses the real trip once the assistant is on that shift | Otherwise two places give two different times. |
| Car and bike's right cards built without a board | The PDF only draws public transport; described in `docs/DESIGN.md`. |
| Tab bar extras give way to the tabs | Eleven tabs left less room: the Agenda date and clipboard search pushed the tabs aside. Date now shrinks, search shrinks, *Ongelezen* no longer cuts off. |
| Tab icon `tram` | Closest SF Symbol to the design's train. |

## Checked and not checked

- Live against your account with `gh` login: 21 PRs, checks, the graph. Screenshots in the PR use `-githubDemo`.
- Departure tab, closed notch and Settings in Dutch and English with `-departureDemo`: drawn and compared to the PDF.
- **Not checked, needs you:** the tick and flash (they move, and snapshots are still), all clicks (mode switch, sign-in, address sheet, repository sheet), the Keychain path, a real trip end to end with your calendar, and the CPU of the spinner in Release (it needs a real run going).
- The Mac kept sleeping at night: my keep-awake request was refused and I didn't work around it, so timings measured tonight mean little.

## To do for you

- Connect GitHub in Settings → GitHub (one click if `gh` is logged in).
- Enter your home address in Settings → Departure; until then the whole feature is asleep. Rain check is off by default, as in the design.
- Drag *Departure* and *GitHub* next to *Calendar* in Settings → Notch: your saved order puts new tabs at the end.
- Merge from the bottom: #37 and the PRs under it, then #39, #40, #41, #42, then the last one. CI only runs on PRs into `main`, so it runs once each is retargeted.
- Get an NS key: <https://apiportal.ns.nl>, subscribe to *Ns-App*/*Reisinformatie*, add it under Settings → Integrations.
