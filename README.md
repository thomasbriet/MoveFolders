# MoveFolders

MoveFolders is een macOS AppKit tool om projectmappen tussen volumes/netwerkschijven over te zetten met rsync, post-verify, mismatch-afhandeling en optionele bronverwijdering.

De releasebuild is voor Apple silicon en vereist macOS 11 of nieuwer. Automatisch starten via de systeemlogin-iteminstelling vereist macOS 13 of nieuwer.

De app onthoudt de 5 laatst gebruikte bron- en doelpaden, ondersteunt favorieten voor bron/doel/opties, kan mislukte of geannuleerde overdrachten hervatten, en ondersteunt meerdere eenrichtings-syncprofielen zolang de app draait. Sync-profielen kunnen ontbrekende netwerkschijven iedere vijf minuten opnieuw laten verbinden en gaan automatisch verder zodra de mappen weer beschikbaar zijn. Via `Instellingen…` kan MoveFolders bij het inloggen starten en verborgen in de menubalk blijven draaien. Het menubalkmenu biedt status, handmatige sync, pauzeren/hervatten en toegang tot het log. Lege geselecteerde bronmappen kunnen standaard automatisch worden overgeslagen. Een persistent overdrachtslog registreert per bestand of het wel of niet is overgezet en is via de knop `Log` te openen.

Zie [CHANGELOG.md](CHANGELOG.md) voor alle releasewijzigingen.

## Build

```bash
./scripts/build_release.sh 0.9
```

Dit maakt lokaal:

- `MoveFolders.app`
- `MoveFolders_v0.9_share.zip`
- `MoveFolders_v0.9_installer.pkg`

## Updates

De app heeft een knop `Updates` die de nieuwste GitHub Release kan controleren en de `.pkg` installer kan openen.

Voor gebruik moet in `MoveFolders_v0.3.swift` deze constante worden ingesteld:

```swift
let updateGitHubOwner = "thomasbriet"
let updateGitHubRepo = "MoveFolders"
```

Publiceer nieuwe installers als GitHub Release assets, bijvoorbeeld met tag `v0.8.3`, `v0.8.4`, enzovoort.

Vanaf versie `0.6` installeert de package altijd naar `/Applications/MoveFolders.app`. Oudere appbundles zoals `/Applications/MoveFolders_v0.5.app` worden tijdens installatie opgeruimd.

## Automatisch starten en menubalk

Open `MoveFolders → Instellingen…`:

- `Start MoveFolders bij inloggen` gebruikt op macOS 13 en nieuwer de door macOS beheerde login-iteminstelling. Plaats de app daarvoor in `/Applications` (Programma’s).
- `Start zonder hoofdvenster in de menubalk` opent bij een volgende start alleen het menubalkicoon.
- `Automatische syncs pauzeren` stopt nieuwe geplande syncs en reconnectpogingen. Een lopende sync wordt eerst afgerond; `Sync nu` blijft bruikbaar.

## Automatische release

GitHub Actions bouwt en uploadt release-assets automatisch:

- Push een tag zoals `v0.5`, of
- Start in GitHub `Actions` -> `Build release` -> `Run workflow` en vul bijvoorbeeld `0.4` in.

De workflow maakt of update de GitHub Release en uploadt:

- `MoveFolders_v<versie>_installer.pkg`
- `MoveFolders_v<versie>_share.zip`

## Release checklist

1. Werk versie aan met `./scripts/build_release.sh <versie>`.
2. Commit bronwijzigingen.
3. Push naar GitHub.
4. Tag en push de release, bijvoorbeeld `git tag -a v0.5 -m "MoveFolders v0.5"` en `git push --tags`.
