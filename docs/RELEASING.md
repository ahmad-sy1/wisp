# Releasing

A release is a signed, notarized `wisp-<version>.zip` attached to a GitHub Release. [`scripts/release.sh`](../scripts/release.sh) does all of it in one go.

## One-time setup

1. **Developer ID certificate**: Xcode → Settings → Accounts → your team → *Manage Certificates…* → **+** → *Developer ID Application*.
2. **Notarization credentials**: create an app-specific password at <https://account.apple.com> (*Sign-In and Security → App-Specific Passwords*), then store it in the Keychain under the profile name the script expects:

   ```bash
   xcrun notarytool store-credentials wisp-notary --apple-id <your Apple ID> --team-id <your team ID>
   ```

   It asks for the password itself, so it never ends up in your shell history.

Check both:

```bash
security find-identity -v -p codesigning     # Developer ID Application: …
xcrun notarytool history --keychain-profile wisp-notary
```

## Cutting a release

1. Bump `MARKETING_VERSION` (and `CURRENT_PROJECT_VERSION`) in `project.yml` in a pull request, together with the `CHANGELOG.md` entry. Merge it.
2. On an up-to-date, clean `main`:

   ```bash
   ./scripts/release.sh
   ```

The script stops with a clear message unless you are on a clean `main` that matches `origin/main`, the tag doesn't exist yet, and the certificate and notary profile are both found. Then it:

1. builds Release, signed with the Developer ID (hardened runtime, secure timestamp);
2. verifies the signature, zips the app and submits it to Apple's notary service, waiting for the result;
3. staples the ticket to the app and checks it with `spctl`;
4. zips the stapled app, tags `v<version>`, pushes the tag and creates the GitHub Release with the zip.

## CI

[`.github/workflows/build.yml`](../.github/workflows/build.yml) builds every push and pull request to `main` on a clean macOS runner, without signing. A newer push to the same branch cancels the build that is still running, to save macOS minutes on the private repository.
