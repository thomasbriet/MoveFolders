# MoveFolders

MoveFolders is een macOS AppKit tool om projectmappen tussen volumes/netwerkschijven over te zetten met rsync, post-verify, mismatch-afhandeling en optionele bronverwijdering.

De releasebuild is voor Apple silicon en vereist macOS 11 of nieuwer. Automatisch starten via de systeemlogin-iteminstelling vereist macOS 13 of nieuwer.

De app onthoudt de 5 laatst gebruikte bron- en doelpaden, ondersteunt favorieten voor bron/doel/opties, kan mislukte of geannuleerde overdrachten hervatten, en ondersteunt meerdere eenrichtings-syncprofielen zolang de app draait. Het syncvoortgangsscherm volgt automatisch een actief profiel wanneer het geselecteerde profiel niet draait, terwijl de profielvelden op de handmatige selectie blijven staan. De getoonde actieve sync kan afzonderlijk worden gestopt zonder andere profielen te onderbreken. Tijdens sync wordt de wijzigingsdatum direct na ieder volledig overgezet bestand expliciet hersteld en gecontroleerd. Daardoor slaat een volgende run reeds afgeronde bestanden over, ook wanneer de vorige sync tussentijds op bijvoorbeeld 80% is gestopt. Na een volledig afgeronde overdracht worden ook de wijzigingsdatums van alle geraakte mappen van de diepste map naar boven hersteld. Sync-profielen proberen ontbrekende netwerkschijven stil opnieuw te verbinden met oplopende wachttijden van 1, 5, 15, 30 en 60 minuten en gaan automatisch verder zodra de mappen weer beschikbaar zijn. Zowel sync- als koppelfoutentellers worden bij een herstart van de app gereset; een succesvolle sync of koppeling reset de betreffende teller eveneens. De stille koppeling toont geen Finder- of inlogvenster en gebruikt reeds beschikbare macOS-Sleutelhangergegevens. Bestandsnamen met accenten worden bij sync naar netwerkschijven genormaliseerd. SFM-naamvarianten die verschillende SMB-servers anders tonen, zoals `` en `>`, worden apart herkend en beschermd zodat hetzelfde bestand niet telkens wordt verwijderd en opnieuw overgezet. Via `Instellingen…` kan MoveFolders bij het inloggen starten en verborgen in de menubalk blijven draaien. Het menubalkmenu biedt status, handmatige sync, pauzeren/hervatten en toegang tot het log. Lege geselecteerde bronmappen kunnen standaard automatisch worden overgeslagen. Een persistent overdrachtslog registreert per bestand of het wel of niet is overgezet en is via de knop `Log` te openen.

Zie [CHANGELOG.md](CHANGELOG.md) voor alle releasewijzigingen.

## Build

```bash
./scripts/build_release.sh 0.9.15
```

Dit maakt lokaal:

- `MoveFolders.app`
- `MoveFolders_v0.9.15_share.zip`
- `MoveFolders_v0.9.15_installer.pkg`

## Updates

De app controleert bij iedere start automatisch op een nieuwere GitHub Release en toont alleen een melding wanneer een update beschikbaar is. De knop `Updates` kan dezelfde controle handmatig uitvoeren en de `.pkg` installer openen. Installeren wordt geblokkeerd zolang een overdracht of sync actief is, zodat een actieve rsync-run en het bijbehorende datumherstel niet halverwege worden afgebroken.

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
