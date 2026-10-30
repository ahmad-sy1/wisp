# Launch checklist

Everything to sort out before wisp is offered as a public download, outside the Mac App Store. The App Store isn't an option as wisp is now: it requires the App Sandbox, and Now Playing (private MediaRemote through `/usr/bin/perl`), the hooks installer and several helper processes don't work inside it.

Tick items off in the pull request that does them.

## Apple

- [x] Apple Developer Program membership (€99 a year). Needed to notarize new versions; versions already out keep working if it lapses.
- [x] Developer ID Application certificate and the `wisp-notary` profile in the Keychain (see [RELEASING.md](RELEASING.md)).
- [x] Hardened runtime on.
- [x] Usage descriptions for Calendar, Location and System Audio in `Info.plist`, translated in `InfoPlist.xcstrings`.
- [ ] A first real notarization: confirms that `wisp-hook` and `libNowPlayingBridge.dylib` are signed correctly too.
- [ ] Apple trademarks: no Apple logos, no SF Symbols in the app icon or logo, "for Mac" rather than names that suggest Apple made it.
- [ ] Say on the website that Now Playing relies on a private macOS interface that an update can break.

## Other companies

- [ ] Anthropic: "works with Claude Code" is fine; no Claude logo, nothing that suggests an official app.
- [ ] Google: no Gmail logo. Stay with IMAP and app passwords; Gmail over OAuth needs Google's paid security assessment (CASA).
- [ ] Open-Meteo: visible attribution ("Weather data by Open-Meteo.com", CC BY 4.0) in Settings and on the website; it is only shown in a tooltip now. Commercial use needs a paid plan.
- [ ] GitHub, Notion, WHOOP (when built): register wisp as an OAuth app with each; all ask for a privacy policy URL, WHOOP approves developers first.
- [x] Nothing from `~/coucou` (code, icons, sounds) in wisp.

## Legal (Netherlands / EU)

- [ ] Licence: the repository is public, but `LICENSE` calls the source private. Pick one: make the repository private and publish releases from a separate public repository; keep it public as "all rights reserved" with matching wording; or open source (e.g. MIT).
- [ ] Terms of use for the app: free to use, at your own risk, no warranty.
- [ ] Privacy policy: what goes where (Gmail directly with Google; the place name to Open-Meteo; the update check to GitHub; nothing else, no telemetry).
- [ ] Name: search "wisp" at BOIP / EUIPO and among existing Mac apps before buying a domain.
- [ ] Free or paid. Free as a hobby: a contact address on the website is enough. Paid (also donations with something in return): KvK registration and VAT, easiest through a merchant of record such as Paddle or Lemon Squeezy; the EU Cyber Resilience Act then applies too.

## Domain and website

- [ ] Domain (about €10–20 a year), e.g. `getwisp.app` or `wispnotch.com`. `.app` requires HTTPS.
- [ ] Hosting: GitHub Pages with the custom domain; the download button points to the latest GitHub Release.
- [ ] Content: what wisp does with screenshots; requirements (MacBook with a notch, macOS 15 or later, Claude Code optional); download; changelog; privacy policy; terms; contact.
- [ ] No analytics, so no cookie banner.
- [ ] Support e-mail on the domain (forwarding from the registrar).

## The app, before 1.0

- [ ] Own app icon and sounds (roadmap).
- [ ] Update check: built in-house (no Sparkle, no dependencies), can be switched off in Settings, asks only GitHub.
- [ ] *Remove hooks* in Settings and an uninstall guide: after deleting wisp, the hooks in `~/.claude/settings.json` point to a missing `wisp-hook` and Claude Code reports errors.
- [ ] First launch: a short explanation of the permissions and the hooks.
- [ ] *Report a problem*: a link to GitHub Issues (there are no crash reports).
- [ ] Test on a clean Mac or a second user account, and on a Mac without a notch.
- [ ] Version 1.0.0 with release notes in `CHANGELOG.md`.

## Distribution

- [ ] GitHub Releases (`./scripts/release.sh`).
- [ ] The website's download button.
- [ ] A Homebrew tap (`brew install --cask ahmad-sy1/tap/wisp`); the official Homebrew cask list comes once wisp is known enough.

## Costs

Apple Developer Program €99 a year and a domain at about €10–20 a year. Everything else is free while wisp is free.
