# Local code signing

GitMenuBar stores the GitHub token and the AI provider keys in the macOS
keychain. macOS binds every keychain item to the signature of the app that
created it. A build with a different signature is a different app, so the
"Always allow" grant from the previous build does not apply and the password
prompt comes back. `make build` and `make install-app` therefore sign with one
stable identity.

## Identity

`scripts/config/release_signing.sh` resolves the identity in this order:

1. `GITMENUBAR_CODE_SIGN_IDENTITY` when it is set.
2. `GITMENUBAR_RELEASE_CODE_SIGN_IDENTITY`, which defaults to `Apple Development`.
3. `GitMenuBar Local Self-Signed`, created by `make setup-self-signed-cert`.
4. Ad-hoc, with a warning. Ad-hoc signatures change on every build, so the
   keychain prompt returns after each rebuild.

The first identity that the keychain reports as stably available wins. The build
prints the resolved certificate hash, for example:

```text
Signing with 'Apple Development' (B8350AE0A41F4F902BF18A1746234B64C48D3A11)
```

Check the result on a built app:

```bash
codesign -dv .xcode-build/Build/Products/Debug/GitMenuBar.app
codesign -d -r- .xcode-build/Build/Products/Debug/GitMenuBar.app
```

A stable signature reports a `TeamIdentifier` and a designated requirement based
on the certificate, not on the build:

```text
designated => identifier "com.mourato.GitMenuBar" and anchor apple generic and
certificate leaf[subject.CN] = "Apple Development: ..."
```

Ad-hoc signing instead reports `Signature=adhoc`, `TeamIdentifier=not set`, and a
requirement that pins the code hash (`cdhash`), so every rebuild invalidates the
keychain grant.

To use the repository self-signed certificate instead of a personal Apple
certificate:

```bash
make setup-self-signed-cert
GITMENUBAR_CODE_SIGN_IDENTITY="GitMenuBar Local Self-Signed" make build
```

## Keychain access group

Both credential stores send `kSecAttrAccessGroup` (`KeychainAccessGroup.identifier`
in `GitMenuBar/Services/Credentials/KeychainItemClient.swift`). The matching
entitlement is `keychain-access-groups` in
`GitMenuBar/GitMenuBar-KeychainAccessGroups.entitlements`.

That entitlement file is **not** used by default. `keychain-access-groups` is a
restricted entitlement: macOS kills the process at launch when the signature does
not carry a provisioning profile that authorizes the group. The default
`GitMenuBar.entitlements` signs without a Development Team, so embedding the group
there stops the app from starting. Verified on macOS 27.3 (build 26C5035r): an
ad-hoc signature, the repository self-signed certificate, and an Apple Development
certificate all terminated with `SIGKILL` when the entitlement was embedded
without an authorizing profile.

The group becomes active when a Development Team is available:

```bash
GITMENUBAR_DEVELOPMENT_TEAM=YOURTEAMID make build
```

`scripts/run-build.sh` then passes the team and the access-group entitlements to
Xcode, which signs with the provisioning profile of that team and skips the local
re-signing pass. This path needs an Xcode account with a profile for the team and
has not been exercised in this repository yet.

Without a Team ID the access group is inert, not wrong:

- On the legacy file keychain, `kSecAttrAccessGroup` is accepted and ignored. Item
  lookup, update, and delete keep working, so existing items are readable and no
  migration is needed.
- Once the app moves to the data protection keychain (which needs a Team ID), the
  same queries become filtered by the declared group.

## Cached credentials

`GitHubKeychainTokenStore` and `AIKeychainStore` read the keychain once per unlock
and keep the result in memory behind an `NSLock`. Writes and deletes update the
memory copy, so a save does not trigger a read.

The keychain is read again only when a credential is rejected:

- `GitHubAuthManager` invalidates the cached token when `/user` answers `401`, then
  retries once with a fresh read.
- `OpenRouterUsageProvider` and `OpenCodeGoUsageProvider` invalidate the cached AI
  keys on `401`/`403` before the next refresh.

There is no polling interval: without a rejection, the copy lives until the app
quits.
