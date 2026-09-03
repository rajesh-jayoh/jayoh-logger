# Packaging JayOh Logger as an Unlocked Package

This can't be run from the environment that built this zip — it requires an
authenticated `sf` CLI session against your JayOh Dev Hub, which isn't
reachable from here. Run these from your Mac (VS Code terminal is fine — same
`sf` CLI either way).

## One-time setup (per Dev Hub)

1. Make sure your Dev Hub is authorized and set as default:
   ```bash
   sf org login web --alias JayOhDevHub --set-default-dev-hub
   ```

2. From inside this unzipped `jayoh-logger/` folder, create the package:
   ```bash
   sf package create \
     --name "JayOh Logger" \
     --description "Org-local error logging framework with platform-event-backed persistence" \
     --package-type Unlocked \
     --path force-app \
     --target-dev-hub JayOhDevHub
   ```
   This prints a `0Ho...` package ID and also writes a `packageAliases` entry
   into `sfdx-project.json` automatically — commit that change.

## Cut a version

```bash
sf package version create \
  --package "JayOh Logger" \
  --installation-key-bypass \
  --wait 15 \
  --target-dev-hub JayOhDevHub
```
This validates the metadata against a scratch org behind the scenes (takes a
few minutes) and returns a `04t...` package version ID.

Promote it once you're happy with it (required before installing in
production, not required for sandboxes):
```bash
sf package version promote \
  --package "JayOh Logger@0.1.0-1" \
  --target-dev-hub JayOhDevHub
```

## Install into a client org

```bash
sf package install \
  --package "JayOh Logger@0.1.0-1" \
  --target-org BMUAT \
  --wait 10
```
Repeat with `--target-org <leveldata-alias>` for Level Data, etc. — same
version, same behavior, no copy-pasted metadata to keep in sync by hand.

## After the first version exists

Every subsequent change to this package:
```bash
sf package version create --package "JayOh Logger" --installation-key-bypass --wait 15 --target-dev-hub JayOhDevHub
sf package install --package "JayOh Logger@<new-version>" --target-org <client-org-alias> --wait 10
```

## Why this matters for you specifically
You're already running this in more than one org (BMG, Level Data, and
whoever's next). Without packaging, a bug fix made in one org's metadata has
to be manually re-applied everywhere else — and it's easy to lose track of
which org has which version. An unlocked package gives you one source of
truth and a real upgrade path.
