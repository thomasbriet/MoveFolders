# Changelog

Alle relevante wijzigingen aan MoveFolders worden hier bijgehouden.

## [0.8] - 2026-08-03

### Toegevoegd

- Eerste versie van eenrichtings-syncprofielen: Folder A blijft leidend en wordt periodiek naar Folder B gesynct.
- Sync-profielen bewaren bron, doel, interval, aan/uit-status, xattr-keuze en optioneel verwijderen van extra doelbestanden.
- Sync-profielen draaien automatisch op de achtergrond zolang de app actief is.
- Knoppen toegevoegd voor `Bewaar sync`, `Sync aan/uit` en `Sync nu`.
- Sync-statusregel toont laatste run, volgende run en laatste status/fout.
- Scheduler voorkomt overlappende sync-runs per profiel.
- Bij onbereikbare servers of rsync-fouten wordt de fout opgeslagen en later opnieuw geprobeerd met oplopende retry-wachttijd.

## [0.7.3] - 2026-07-15

### Opgelost

- Hervatbare overdrachten worden nu direct bij de start opgeslagen.
- De hervatbare opdracht wordt na elk afgerond, overgeslagen, mislukt of geannuleerd item bijgewerkt.
- Na crash, force quit of herstart blijft `Hervat` daardoor staan met de laatst bekende resterende items.
- Eerder mislukte items blijven behouden in de hervat-lijst wanneer later in dezelfde opdracht wordt geannuleerd.

## [0.7.2] - 2026-07-15

### Opgelost

- App opent nu eerst het hoofdvenster voordat bron- en doelvolumes worden geladen.
- Debugvenster opent niet meer automatisch bij het starten van de app.
- Naam-sortering start geen onnodige metadata-scan meer op netwerkvolumes.
- Bron- en doellijsten tonen na 8 seconden een melding wanneer een volume traag reageert, zodat de app niet vast lijkt te lopen.

## [0.7.1] - 2026-07-15

### Gewijzigd

- Overdrachtscherm toont nu aparte ETA's voor het huidige bestand, de huidige map en de totale opdracht.
- De snelheidsregel is gescheiden van de ETA-regel zodat lange voortgangsteksten minder snel door elkaar lopen.
- Standaard buildversie in `scripts/build_release.sh` verhoogd naar `0.7.1`.

## [0.7] - 2026-07-15

### Toegevoegd

- Knop `Hervat` om mislukte of geannuleerde overdrachten opnieuw te proberen.
- Mislukte, met waarschuwing gekopieerde en geannuleerde items worden opgeslagen als hervatbare opdracht.
- Bij annuleren worden het huidige item en de resterende items klaargezet voor hervatten.
- Dropdown `Laatste doelen` voor de 5 laatst gebruikte doelpaden.
- Dropdown `Favorieten` voor opgeslagen combinaties van bron, doel en opties.
- Knop `Bewaar` om de huidige bron, doel en opties als favoriet op te slaan.
- Actiegerichte samenvatting met knoppen voor `Hervat`, `Open doelmap` en `Toon log`.

### Gewijzigd

- Normale start en hervatten gebruiken dezelfde overdrachtslogica.
- Doelpaden worden onthouden bij kiezen, toepassen, favoriet gebruiken en starten van een overdracht.
- De `Hervat`-knop is alleen actief wanneer er een hervatbare overdracht bestaat.
- Standaard buildversie in `scripts/build_release.sh` verhoogd naar `0.7`.

## [0.6.3] - 2026-07-15

### Gewijzigd

- Overdrachtscherm opent smaller, ongeveer 70% van de eerdere breedte.
- Overdrachtscherm is nu resizable.
- Snelheid staat bovenaan het overdrachtscherm en wordt genormaliseerd naar `MB/s`.
- Bovenste progressregel toont nu de progressie van het huidige bestand in plaats van de totale bestandstelling.
- De rsync-copy gebruikt per-bestandprogress zodat de huidige bestandsbalk nauwkeuriger is.
- ETA staat voortaan alleen op de bovenste snelheidsregel.

## [0.6.2] - 2026-07-01

### Opgelost

- Hoofdvenster-layout blijft stabiel bij vergroten en verkleinen.
- Linker- en rechterkolom worden opnieuw berekend op basis van de actuele venstergrootte.
- Bron- en doelvelden, dropdowns, optie-checkboxes, padknoppen en tabellen overlappen niet meer bij resize.
- Tabellen behouden bruikbare minimale afmetingen.

### Gewijzigd

- Minimale venster- en contentgrootte ingesteld voor het hoofdvenster.
- AppKit autoresizing masks voor het hoofdvenster vervangen door centrale layoutlogica.
- Standaard buildversie in `scripts/build_release.sh` verhoogd naar `0.6.2`.

## [0.6.1] - 2026-07-01

### Toegevoegd

- Optie `Lege mappen overslaan` in het hoofdscherm.
- De optie staat standaard aan.
- Geselecteerde bronmappen zonder bestanden worden vóór de doelcontrole en vóór rsync automatisch overgeslagen.
- Overgeslagen lege mappen verschijnen als waarschuwing in de overdrachtssamenvatting.

### Gewijzigd

- Pre-scan tellingen worden hergebruikt voor de lege-mapcontrole wanneer pre-scan aan staat.
- De hoofdschermindeling is aangepast zodat de opties en padknoppen niet overlappen.
- Standaard buildversie in `scripts/build_release.sh` verhoogd naar `0.6.1`.

## [0.6] - 2026-07-01

### Toegevoegd

- Update-installers gebruiken vanaf deze versie een vaste appnaam: `MoveFolders.app`.
- Update-installers gebruiken een vaste bundle-id en package-id, zodat macOS nieuwe versies als dezelfde app ziet.
- Package-installatie ruimt oude versie-genummerde apps op, zoals `MoveFolders_v0.5.app`.
- De updateknop downloadt de `.pkg` naar Downloads, opent de installer automatisch en sluit MoveFolders voor installatie.

### Gewijzigd

- Release-artifacts blijven versie-genummerd, maar de appbundle in de zip/pkg heet voortaan `MoveFolders.app`.
- Standaard buildversie in `scripts/build_release.sh` verhoogd naar `0.6`.

## [0.5] - 2026-07-01

### Toegevoegd

- Dropdown `Laatste bronnen` in het hoofdscherm.
- Opslag van maximaal 5 laatst gebruikte bronpaden via `UserDefaults`.
- Recente bronnen worden bijgewerkt bij map kiezen, `Gebruik bronpad` en het starten van een overdracht.
- Submapnavigatie via dubbelklik vult de recente-bronnenlijst niet onnodig.
- GitHub Actions release-workflow bouwt automatisch de `.app`, `.zip` en `.pkg` bij nieuwe tags.
- Release-workflow kan ook handmatig vanuit GitHub Actions worden gestart.

### Gewijzigd

- Standaard buildversie in `scripts/build_release.sh` verhoogd naar `0.5`.
- GitHub Actions workflow expliciet op Node.js 24 gezet.

## [0.4] - 2026-06-10

### Toegevoegd

- GitHub-koppeling voor `thomasbriet/MoveFolders`.
- Knop `Updates` in de app voor controle op de nieuwste GitHub Release.
- Buildscript voor lokale release-builds met `.app`, deelbare `.zip` en `.pkg` installer.
- Versie `0.4` installer en deelpakket.
- Optie `Bron verwijderen na overdracht`.
- Knop `Annuleer overdracht` in het statusscherm.
- Statusscherm met huidig bestand, doelpad en overdrachtsvoortgang.
- Post-verify statusregels met scanrichting, aantallen en geschatte voortgang.
- Busy/indeterminate indicator tijdens post-verify.
- Mismatch-venster met selectieknoppen: `Alles`, `Niets`, `Inverteer` en `Alleen bron nieuwer`.
- Optie voor het kopiëren van bestandsattributen/xattrs.
- Prompt bij xattr-permissiefouten om xattrs voor de map of opdracht uit te schakelen.
- Debuglogging voor rsync-commando's, rsync-status en verwijderfouten.
- Pending-delete cleanup voor bronmappen die tijdelijk `Resource busy` zijn.

### Gewijzigd

- Netwerkschijven laden sneller door eerst een snelle lijst zonder metadata te tonen.
- Metadata wordt alleen opgehaald wanneer dat nodig is, bijvoorbeeld bij sorteren op datum.
- Rsync-timeout kijkt naar inactiviteit in plaats van totale looptijd.
- Rsync-pad en flags worden dynamisch gekozen op basis van beschikbare rsync-versie.
- Xattrs staan standaard uit om `com.apple.provenance` permissiefouten te vermijden.
- Timestamps worden na kopie en mismatch-overwrite expliciet hersteld met FileManager en `touch -mt`.
- Post-verify corrigeert tijdverschillen wanneer grootte gelijk is.
- Extra bestanden op de doellocatie worden standaard genegeerd in plaats van als fout gemeld.
- Statusscherm toont alleen het relevante doelpad en niet opnieuw de volledige bron/doel-prefix.
- Lange bestands- en padnamen staan onder elkaar, zodat ze elkaar niet overlappen.
- Interne rsync-markers voor huidig bestand worden verborgen in de gewone statusweergave.
- Code 23 van rsync wordt specifieker beoordeeld en waar mogelijk als waarschuwing behandeld.

### Opgelost

- Overdrachten stoppen niet meer direct bij behandelbare rsync-waarschuwingen.
- Bronverwijdering geeft betere diagnostiek bij `Resource busy`.
- Verwijderen wordt opnieuw geprobeerd voordat de bron als niet verwijderd wordt gemeld.
- Mismatch-overwrite gebruikt robuustere kopie en timestamp-herstel.
- Dupcheck krijgt minder valse meldingen door ontbrekende of verkeerde datestamps.
- Xattr `Permission denied` telt niet meer als inhoudelijke bestandsmismatch.
- UI-spacing rond opties en statusregels is verbeterd.
- Het statusscherm toont het bestand waarmee rsync op dat moment bezig is.

## [0.3.x en eerder] - voor 2026-06-10

### Basisfunctionaliteit

- Eerste macOS AppKit-versie van MoveFolders.
- Bron- en doeltabellen met mapnavigatie.
- Sorteren op naam en datum.
- Overdracht via rsync.
- Post-verify tussen bron en doel.
- Mismatch-afhandeling voor bestaande of afwijkende bestanden.
- Debugvenster met logregels.
- App-icoon en basis packaging-bestanden.
