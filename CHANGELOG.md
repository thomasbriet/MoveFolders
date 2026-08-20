# Changelog

Alle relevante wijzigingen aan MoveFolders worden hier bijgehouden.

## [0.9.21] - 2026-08-20

### Opgelost

- Tijdelijke InDesign-vergrendelbestanden met de extensie `.idlk` worden niet meer gekopieerd door een sync en worden op Folder B beschermd tegen `--delete`.
- Een geopend InDesign-document op Folder B kan daardoor niet meer de volledige sync laten mislukken met rsync-code 23 en `Resource busy (16)`.

### Getest

- De fout is herleid tot een `.idlk`-bestand dat niet meer in Folder A stond, maar op Folder B nog in gebruik was.
- Met `--delete` blijft het uitgesloten `.idlk`-bestand behouden, terwijl een gewoon extra testbestand wel voor verwijdering wordt geselecteerd.

## [0.9.20] - 2026-08-20

### Opgelost

- De opgeslagen SMB/SFM-compatibiliteitsindex groeit niet langer alleen maar door. Vóór iedere sync worden de onthouden speciale paden opnieuw tegen Folder A gecontroleerd.
- Een speciaal SMB-bestand dat is verwijderd of naar een gewone bestandsnaam is hernoemd, verdwijnt automatisch uit de index en wordt niet meer als `SMB-naam 3/3` in de status verwerkt.
- Voor speciale SMB-mappen wordt de actuele inhoud opnieuw opgebouwd, zodat ook verdwenen onderliggende bestanden uit de index worden verwijderd.

### Verbeterd

- Een opgeschoonde index wordt één keer als `SYNC SMB-INDEX OPGESCHOOND` in het overdrachtslog vermeld, inclusief het aantal verdwenen of hernoemde paden.

### Getest

- De bestaande Games-index met drie vermeldingen is vergeleken met Folder A. De hernoemde tweede `Blechmann`-vermelding wordt als verouderd gevonden; de twee werkelijk nog bestaande speciale paden blijven behouden.

## [0.9.19] - 2026-08-20

### Opgelost

- Verweesde rsync-tempbestanden bij speciaal vertaalde SMB-namen worden nu samen met het echte doelbestand beschermd. Een onbereikbaar SMB-spookbestand zoals `.FuturTDem..cHLuIO` veroorzaakt daardoor niet meer bij iedere Games-sync rsync-code 23 of 24.
- De totale syncvoortgang loopt niet meer terug op Macs die de ingebouwde oudere rsync gebruiken. Daar wordt de opdrachtvoortgang nu berekend uit `to-check`/`to-chk`/`ir-chk`, in plaats van het percentage van ieder afzonderlijk bestand als totaalpercentage te tonen.
- Ook bij incremental recursion kan een reeds getoond opdrachtpercentage niet meer lager worden.

### Verbeterd

- Bij een mislukte sync worden maximaal twaalf concrete rsync-foutregels met bestandsnaam en foutreden als `SYNC RSYNC FOUT` in het overdrachtslog geschreven.
- De samenvattingsregel bij een rsync-fout toont voortaan ook de eerste concrete foutmelding naast de exitcode.

### Getest

- De problematische `FuturTDem`-map is gericht getest met en zonder tempbescherming. Met de nieuwe filter eindigt de echte rsync-run met code 0 en blijven beide geldige doelvarianten behouden.
- Een volledige read-only Games-sync met alle SFM-filters eindigt met code 0.
- Progressieregels van zowel rsync `--info=progress2` als de oudere macOS `--progress`-uitvoer zijn getest, inclusief een teruglopende incremental-recursion-teller.

## [0.9.18] - 2026-08-13

### Toegevoegd

- Vóór het verwijderen scant MoveFolders iedere bronmap volledig op macOS-vergrendelingen zoals de Finder-optie `Vergrendeld` en de bestandsvlag `uchg`.
- Als vergrendelde bronitems worden gevonden, vraagt de app expliciet om toestemming met de keuzes `Ontgrendel en verwijder` en `Behoud bronmap`. De kopie op het doel wordt daarbij niet aangepast.
- Ontgrendelde en bewust behouden bronmappen worden herkenbaar vastgelegd in het overdrachtslog.

### Opgelost

- Een vergrendeld bestand kan niet meer pas halverwege een recursieve verwijdering worden ontdekt. Als toestemming wordt geweigerd of ontgrendelen mislukt, blijft de volledige nog aanwezige bronmap behouden.
- Na toestemming controleert MoveFolders of iedere vergrendeling daadwerkelijk is verwijderd. Systeemvergrendelingen of andere mislukte ontgrendelingen worden gemeld zonder vervolgens een gedeeltelijke verwijdering te starten.

## [0.9.17] - 2026-08-13

### Opgelost

- Terugkerende `SYNC NIET OVERGEZET`-meldingen met rsync-code `.f.....g....` zijn opgelost. Deze bestanden hadden al exact dezelfde inhoud, grootte en wijzigingsdatum; alleen de Unix-groep verschilde tussen de lokale bron en het SMB-doel.
- De rsync-capaciteitsdetectie test `--no-owner` en `--no-group` nu rechtstreeks. Rsync ondersteunt de algemene vorm `--no-OPTION`, maar Homebrew-rsync en de ingebouwde macOS-openrsync tonen deze varianten niet betrouwbaar in `--help`.
- SMB-syncs proberen daardoor geen gebruikers- of groepsmetadata meer te bewaren wanneer bestandsrechten zijn uitgeschakeld. Een server die bron-groep `admin` als doel-groep `staff` presenteert veroorzaakt niet langer bij iedere sync dezelfde metadatamelding.

### Getest

- Alle 14 gemelde 30Seconds-, TinyTins-, template- en Erikding-fontbestanden zijn byte voor byte en op grootte en wijzigingsdatum gecontroleerd. Met `--no-group --no-owner` geeft geen van deze bestanden nog een rsync-wijziging.
- Zowel rsync 3.4.1 van Homebrew als de ingebouwde macOS-rsync accepteert de gebruikte opties.

## [0.9.16] - 2026-08-12

### Opgelost

- Een racecondition tussen de live stdout/stderr-lezer en de afsluitcallback van `Process` is opgelost. Beide konden precies bij het stoppen van rsync tegelijk dezelfde `Data`-buffer lezen en wijzigen, wat een `EXC_BREAKPOINT` in `Data._Representation.subscript.getter` veroorzaakte.
- De streamingbuffer is ondergebracht in één vergrendelde toestand. Live lezen, de resterende uitvoer ophalen, records splitsen en een snapshot maken kunnen daardoor niet meer gelijktijdig dezelfde gegevens benaderen.
- Dezelfde beveiliging geldt nu ook voor gewone Move-folders-overdrachten, waar de lees- en afsluitcallback een vergelijkbaar risico hadden.
- Regels die door een leesgrens midden in een UTF-8-teken of bestandsnaam werden gesplitst, worden eerst als bytes samengevoegd en pas daarna verwerkt.

### Geoptimaliseerd

- MoveFolders bewaart per lopend commando maximaal de laatste 4 MB uitvoer in het geheugen. Langdurige syncs kunnen daardoor niet meer honderden MB aan reeds verwerkt rsync-log vasthouden.
- Het debugvenster verwerkt regels voortaan gebundeld per kwart seconde en houdt een begrensde recente geschiedenis bij. Een verborgen debugvenster wordt niet meer voor iedere rsync-regel opnieuw opgemaakt en naar beneden gescrold.

### Getest

- De nieuwe streamingafhandeling heeft een ThreadSanitizer-stresstest met 3.600.000 records doorstaan zonder datarace of ontbrekende records. Daarbij bleef een uitvoerstroom van 6 MB correct begrensd op exact 4 MB.

## [0.9.15] - 2026-08-12

### Opgelost

- SMB-servers die SFM-tekens verschillend tonen, bijvoorbeeld `` op Folder A en `>` op Folder B, veroorzaken niet langer bij iedere sync een verwijdering en nieuwe overdracht van hetzelfde bestand.
- MoveFolders maakt per syncprofiel eenmalig een index van SFM-namen en behandelt deze paden apart. De gewone rsync-run verbergt de bronvariant en beschermt de equivalente doelvariant tegen `--delete`.
- De volledige macOS SFM-tabel wordt ondersteund, inclusief `` als afsluitende punt en de privétekens voor ongeldige Windows-/SMB-naamtekens.
- SFM-bestanden worden op grootte en wijzigingsdatum vergeleken, alleen indien nodig naar de equivalente doelnaam gekopieerd en direct van de juiste bronwijzigingsdatum voorzien.
- SFM-mappen behouden eveneens hun wijzigingsdatum. Verwijderde SFM-bronpaden worden alleen op het doel verwijderd wanneer `Extra bestanden op doel verwijderen` voor het profiel aanstaat.
- Een app-update kan niet meer worden gestart zolang een sync actief is. Dit voorkomt dat een update of herstart rsync beëindigt voordat de wijzigingsdatum van het laatst afgeronde bestand is hersteld.
- Bij het afsluiten van MoveFolders worden actieve rsync-procesbomen expliciet gestopt en wordt het overdrachtslog eerst weggeschreven; er blijven daardoor geen verweesde syncprocessen achter.

### Getest

- Op de gebruikte SMB-doelschijf zijn zowel `` ↔ `>` als `` ↔ afsluitende punt getest. Na de gerichte verwerking meldde een rsync-dry-run met `--delete` geen verwijdering of nieuwe overdracht en waren grootte en wijzigingsdatum exact gelijk.

## [0.9.14] - 2026-08-11

### Opgelost

- Het voortgangsscherm in `Sync folders` volgt nu automatisch een actieve sync wanneer het geselecteerde profiel zelf niet draait. Daardoor blijft het hoofdscherm niet meer ten onrechte `wacht` tonen terwijl een ander profiel bestanden synchroniseert.
- De profielvelden en dropdown blijven op het handmatig geselecteerde profiel staan, zodat een automatisch gestarte sync geen invoer of profielkeuze overschrijft.
- De onderste statusregel vermeldt actieve profielen apart van het geselecteerde profiel en wordt bij starten, voortgang, wachten en afronden direct bijgewerkt.
- `Stop sync` stopt het profiel waarvan de actieve voortgang wordt getoond wanneer het geselecteerde profiel niet draait.
- De verouderde tekst `Netwerkschijven elke 5 minuten verbinden` is vervangen door `Netwerkschijven automatisch verbinden`, passend bij het oplopende retrieschema.

## [0.9.13] - 2026-08-11

### Opgelost

- Opgeslagen foutentellers van syncprofielen worden bij iedere herstart van MoveFolders gereset. Een nieuwe sessie begint daardoor opnieuw bij de eerste retryfase en neemt geen oude foutreeks uit een vorige sessie over.
- Een volledig geslaagde sync blijft de foutenteller direct op nul zetten.
- Het stil opnieuw koppelen van ontbrekende netwerkschijven gebruikt nu hetzelfde oplopende schema als syncfouten: fouten 1 t/m 5 na 1 minuut, 6 t/m 10 na 5 minuten, 11 t/m 14 na 15 minuten, 15 en 16 na 30 minuten en daarna na 60 minuten.
- Netwerkschijfkoppelingen hebben een eigen foutenteller per share. Deze teller wordt bij een geslaagde koppeling en automatisch bij iedere appstart gereset.
- De syncstatus en het log tonen het nummer van de mislukte koppelpoging en de actuele wachttijd.

## [0.9.12] - 2026-08-10

### Opgelost

- MoveFolders behoudt nu naast bestandsdatums ook de wijzigingsdatums van overgezette mappen, zowel bij `Move folders` als bij `Sync folders`.
- Mapdatums worden na een volledig geslaagde overdracht van de diepste map naar de bovenliggende mappen hersteld. Hierdoor kan het schrijven van onderliggende bestanden de zojuist herstelde datum niet opnieuw veranderen.
- Een sync herstelt alleen de datums van mappen die door toegevoegde, gewijzigde of verwijderde inhoud geraakt zijn, inclusief de syncroot.
- Een gewone verplaatsopdracht herstelt alle geselecteerde bronmappen vóór de optionele bronverwijdering. Als een mapdatum niet veilig kan worden hersteld, blijft de bron behouden en wordt de fout expliciet gemeld.
- De voortgang en het overdrachtslog tonen de aparte fase voor mapdatumherstel en eventuele fouten per map.

### Getest

- Op de gebruikte SMB-doelschijf zijn de wijzigingsdatums van meerdere geneste mappen en de synchronisatieroot na een proefkopie succesvol diep-naar-boven hersteld en opnieuw gecontroleerd.

## [0.9.11] - 2026-08-10

### Toegevoegd

- MoveFolders controleert twee seconden na iedere start automatisch en op de achtergrond de nieuwste GitHub-release.
- Alleen wanneer een nieuwere versie beschikbaar is verschijnt de bestaande updatekeuze met `Download en open installer`, `Open release` en `Later`.

### Gewijzigd

- Een mislukte automatische updatecontrole onderbreekt het openen van de app niet en wordt alleen in Debug gelogd. De handmatige knop `Updates` blijft fouten en de melding dat de nieuwste versie al wordt gebruikt wel tonen.
- Gelijktijdige automatische en handmatige updatecontroles worden voorkomen en GitHub-responses worden ook op HTTP-status gecontroleerd.

## [0.9.10] - 2026-08-10

### Gewijzigd

- Het automatische retrieschema na syncfouten is verfijnd: pogingen 1 t/m 5 volgen na 1 minuut, 6 t/m 10 na 5 minuten, 11 t/m 14 na 15 minuten, 15 en 16 na 30 minuten en alle volgende pogingen na 60 minuten.
- Een tijdelijke netwerk- of rsyncfout leidt daardoor niet meer al na enkele mislukte runs tot een wachttijd van een uur.
- Na een geslaagde sync wordt de foutenteller zoals voorheen teruggezet en geldt weer het normale profielinterval.

## [0.9.9] - 2026-08-07

### Opgelost

- Het syncvoortgangsscherm toont tijdens de overdracht weer de actuele relatieve bestandsnaam en het pad.
- Een rsync-voortgangsregel zoals `311.47M 8% 1.11MB/s` wordt niet langer ten onrechte achter `Bestand:` weergegeven.
- De live bestandsmarker wordt nu vóór de overdracht weergegeven. Zodra rsync met het volgende item begint, wordt het voorgaande bestand als afgerond verwerkt en krijgt het veilig zijn bronwijzigingsdatum terug.
- Het hervatgedrag uit 0.9.8 blijft behouden: bij annuleren wordt het actieve, mogelijk onvoltooide bestand niet als afgerond gemarkeerd.

### Getest

- In een SMB-proef verschenen drie opeenvolgende bestandsnamen live. Na annuleren bij het derde bestand werden de twee afgeronde bestanden bij een nieuwe dry-run overgeslagen en bleef uitsluitend het derde bestand over.

## [0.9.8] - 2026-08-07

### Opgelost

- Sync herstelt de wijzigingsdatum nu direct nadat ieder afzonderlijk bestand door rsync is afgerond, in plaats van pas na de volledige opdracht.
- MoveFolders wacht daarbij tot het tijdelijke rsync-bestand op het SMB-doel werkelijk is hernoemd. Hierdoor wordt nooit voortijdig de datum van een nog oud doelbestand aangepast.
- Als een sync wordt gestopt, blijven alle eerder volledig overgezette bestanden daardoor correct herkenbaar. Een volgende sync bouwt zijn bestandslijst opnieuw op, slaat die bestanden over en gaat verder met het nog onvoltooide deel.
- Het bestand dat precies tijdens het stoppen werd geschreven blijft via `--partial` bewaard, maar kan bij de volgende sync nog gedeeltelijk of volledig opnieuw moeten worden verwerkt.
- Een datumreparatie die niet veilig vóór het einde van rsync kon worden uitgevoerd, wordt na een normaal afgeronde opdracht opnieuw geprobeerd. Bij annuleren blijft deze bewust ongemarkeerd, zodat een mogelijk onvolledig bestand nooit ten onrechte als gelijk wordt gezien.
- Oudere rsync-versies zonder `--out-format` behouden de bestaande veilige datumherstelronde na een volledig afgeronde sync.

### Getest

- Een sync met drie bestanden is na het eerste bestand met rsync-code 20 onderbroken. Het eerste bestand had daarna aantoonbaar dezelfde inhoud, grootte en wijzigingsdatum als de bron; een aansluitende dry-run sloeg dit bestand over en meldde uitsluitend de twee resterende bestanden.
- Dezelfde proef is uitgevoerd met een reeds bestaand doelbestand met gelijke grootte maar andere inhoud. MoveFolders wachtte op de definitieve rsync-rename en markeerde niet per ongeluk de oude inhoud als actueel.

## [0.9.7] - 2026-08-07

### Opgelost

- Sommige SMB-doelen namen na rsync wel de juiste aanmaakdatum over, maar lieten `Laatst gewijzigd` op het overdrachtsmoment staan. Hierdoor verschenen dezelfde bestanden bij iedere sync opnieuw als `>f..t.......` en werden ze opnieuw verstuurd.
- Na rsync herstelt MoveFolders nu de wijzigingsdatum van ieder werkelijk overgezet regulier bestand expliciet vanuit de bron en leest de doelmetadata opnieuw ter controle.
- Een bestand wordt alleen aangepast wanneer bron en doel dezelfde grootte hebben. Een afwijkende grootte of geweigerde datum wordt niet verborgen maar als `SYNC DATUMHERSTEL MISLUKT` per bestand gelogd en maakt de syncstatus fout.
- Datumherstel kan met `Stop sync` worden geannuleerd en toont tijdens de nabehandeling `Datums herstellen: x/y` in de voortgang.

### Getest

- Op dezelfde SMB-share bleef zowel wijzigingsdatum als aanmaakdatum na de reparatie correct staan; een aansluitende rsync-dry-run meldde geen tijdsafwijking en geen overdracht meer.

## [0.9.6] - 2026-08-07

### Toegevoegd

- Het tabblad `Sync folders` heeft nu een knop `Stop sync` voor het geselecteerde actieve syncprofiel.
- Stoppen beëindigt de volledige rsync-procesboom van dat profiel. Andere gelijktijdige syncprofielen blijven doorlopen.

### Gewijzigd

- Een handmatig gestopte sync krijgt de status `Geannuleerd door gebruiker` en wordt apart als `SYNC GEANNULEERD` gelogd.
- Annuleren telt niet als nieuwe verbindings- of syncfout. Een ingeschakeld profiel mag pas bij zijn volgende geplande moment opnieuw starten.

## [0.9.5] - 2026-08-07

### Opgelost

- Het zichtbare overdrachtslog springt bij snel binnenkomende regels niet meer afwisselend omhoog en terug naar de nieuwste regel.
- Nieuwe logregels worden voor de schermweergave per kwart seconde gebundeld; het volledige logbestand wordt nog steeds direct en per regel bijgewerkt.
- Automatisch naar de nieuwste regel volgen gebeurt alleen wanneer de logweergave al onderaan stond. Na handmatig omhoog scrollen blijft de gekozen positie stabiel totdat je zelf weer naar beneden gaat.

## [0.9.4] - 2026-08-07

### Gewijzigd

- Automatische koppelpogingen voor ontbrekende netwerkschijven gebruiken nu macOS NetFS in `NoUI`-modus. Finder wordt niet meer geopend en er verschijnt geen inlogvenster.
- De stille koppeling gebruikt bestaande macOS-Sleutelhangergegevens. Als authenticatie niet zonder invoer lukt, blijft het sync-profiel wachten, wordt de fout alleen in status en log gezet en volgt na maximaal vijf minuten een nieuwe poging.
- Ook `Sync nu` toont geen bevestigingsalert wanneer eerst stil een ontbrekende netwerkschijf moet worden gekoppeld; de actuele toestand blijft zichtbaar in het syncscherm en log.
- Een geslaagde achtergrondkoppeling laat een ingeschakeld profiel automatisch opnieuw beoordelen, zodat de sync kort daarna kan starten zonder op de volgende schedulerronde te wachten.

## [0.9.3] - 2026-08-07

### Opgelost

- De syncvoortgang verwerkt nu ook de carriage-return-updates waarmee rsync een lopende voortgangsregel vernieuwt. Hierdoor worden percentage, snelheid en ETA tijdens grote bestanden ongeveer iedere seconde bijgewerkt in plaats van pas bij de volgende volledige tekstregel.
- UTF-8-tekens in bestandsnamen blijven intact wanneer een leesblok toevallig midden in een teken eindigt.

## [0.9.2] - 2026-08-07

### Opgelost

- Sync naar netwerkschijven behandelt NFC- en NFD-spellingen van dezelfde bestandsnaam voortaan als gelijk. Namen zoals `Räuber` en `Räuber` worden daardoor niet meer bij iedere sync verwijderd en opnieuw overgezet.
- Wanneer de geselecteerde rsync-versie dit ondersteunt, gebruikt netwerksync `UTF-8 → UTF-8-MAC`-normalisatie. Bij een oudere rsync zonder deze ondersteuning blijft de bestaande werkwijze intact en wordt dit in het log vermeld.

## [0.9.1] - 2026-08-07

### Toegevoegd

- Het tabblad `Sync folders` heeft nu een eigen knop `Log` naast `Sync nu`.
- De knop opent hetzelfde doorlopende overdrachtslog als de bestaande logknop in `Move folders` en het menubalkmenu.

## [0.9] - 2026-08-07

### Toegevoegd

- Nieuwe instellingenpagina via `MoveFolders → Instellingen…` (`Cmd+,`).
- Optie `Start MoveFolders bij inloggen` registreert de hoofdapp via Apples `SMAppService` op macOS 13 en nieuwer en toont wanneer nog goedkeuring in Systeeminstellingen nodig is.
- Optie `Start zonder hoofdvenster in de menubalk` laat MoveFolders na het inloggen als achtergrondapp draaien.
- Een permanent MoveFolders-menubalkmenu toont de algemene status en de status van alle syncprofielen.
- Vanuit de menubalk kunnen afzonderlijke profielen direct worden gesynchroniseerd, automatische syncs worden gepauzeerd of hervat, het log en hoofdvenster worden geopend en de app worden afgesloten.
- De pauzestand blijft tussen app-sessies bewaard; lopende syncs worden veilig afgerond en handmatige syncs blijven beschikbaar.

### Gewijzigd

- Bij verborgen starten worden de mappenlijsten van `Move folders` pas geladen wanneer het hoofdvenster wordt geopend, zodat een trage of ontbrekende netwerkschijf de achtergrondstart niet ophoudt.
- De GitHub-releaseworkflow gebruikt `actions/checkout@v7`, zodat de eerdere Node.js 20-waarschuwing vervalt.

### Compatibiliteit

- De Apple-silicon-releasebinary krijgt nu daadwerkelijk minimum macOS 11 mee in plaats van onbedoeld minimum macOS 26; alleen de systeemschakelaar voor automatisch starten vereist macOS 13 of nieuwer.

## [0.8.9] - 2026-08-07

### Toegevoegd

- Sync-profielen hebben standaard de optie `Netwerkschijven elke 5 minuten verbinden` ingeschakeld.
- MoveFolders bewaart per bereikbare netwerkbron en -doel de veilige macOS-remountinformatie en vraagt macOS bij uitval iedere vijf minuten opnieuw te verbinden.
- Het syncschema gaat automatisch verder zodra Folder A en Folder B weer beschikbaar zijn, zonder een tijdelijk ontbrekende share als mislukte sync te tellen.
- Het syncscherm en het doorlopende log tonen voortaan dat een profiel op een netwerkschijf wacht en wanneer een koppelpoging is aangevraagd.

### Opgelost

- Opnieuw gekoppelde shares met een door macOS toegevoegde suffix zoals `-1` of `-2` worden herkend; het opgeslagen pad wordt naar de werkelijk gekoppelde volumenaam bijgewerkt.

### Beveiliging

- MoveFolders bewaart geen netwerkwachtwoorden. De app gebruikt de remount-URL zonder wachtwoord en laat authenticatie aan macOS Sleutelhanger over.

## [0.8.8] - 2026-08-05

### Opgelost

- Het hoofdvenster komt na minimaliseren weer terug via een klik op het Dock-icoon of via Cmd+Tab.
- Een gesloten hoofdvenster kan opnieuw worden geopend zolang MoveFolders nog draait.

### Toegevoegd

- Standaard macOS-app- en venstermenu's met `Toon MoveFolders` (`Cmd+0`), `Minimaliseer` en `Breng alles naar voren`.

## [0.8.7] - 2026-08-05

### Opgelost

- Sync telt bestanden met uitsluitend metadata-, permissie- of xattrverschillen niet meer als overgezette bestanden.
- Het overdrachtslog gebruikt voor zulke bestanden `SYNC NIET OVERGEZET` en vermeldt de rsync-itemcode.
- De eindstatus maakt nu onderscheid tussen werkelijk overgezette bestanden, verwijderde bestanden en bestanden waarvan alleen metadata afweek.

### Gewijzigd

- Sync-profielen proberen geen POSIX-bestandspermissies meer naar SMB-doelen te kopiëren; inhoud, timestamps en de gekozen xattrs blijven wel volgens het profiel gesynchroniseerd.

## [0.8.6] - 2026-08-05

### Gewijzigd

- Sync-profielen maken Folder B niet meer automatisch aan; Folder A en Folder B moeten beide bestaande mappen zijn.
- Alleen de inhoud van Folder A wordt met de inhoud van Folder B gesynchroniseerd.
- Ontbrekende, niet gekoppelde of niet beschrijfbare doelmappen geven nu een gerichte foutmelding.

## [0.8.5] - 2026-08-04

### Toegevoegd

- Nieuwe knop `Log` opent een apart, doorlopend overdrachtslog zonder automatisch een venster te tonen.
- Per bestand wordt vastgelegd of het is overgezet of niet is overgezet, inclusief bronpad, doelpad en reden.
- Handmatige mismatchkeuzes en bestandswijzigingen uit sync-profielen worden eveneens gelogd.
- Het volledige log blijft tussen app-sessies bewaard in `~/Library/Logs/MoveFolders/overdrachten.log`.

### Gewijzigd

- Het logvenster is doorzoekbaar en toont bij zeer grote logs de meest recente 5 MB; het volledige bestand blijft onverkort op schijf staan.

## [0.8.4] - 2026-08-03

### Toegevoegd

- Met `Nieuw profiel` kunnen meerdere afzonderlijke sync-profielen worden aangemaakt.
- De profielkeuzelijst toont per profiel of het aan, uit of bezig is.
- De voortgang wordt per sync-profiel bijgehouden; door een ander profiel te selecteren wisselt ook de zichtbare voortgang.

### Gewijzigd

- Sync-profielen kunnen tijdens andere actieve syncs geselecteerd en aangepast worden. Opgeslagen wijzigingen gelden vanaf de volgende run van het aangepaste profiel.

## [0.8.3] - 2026-08-03

### Opgelost

- De voortgangstekst in `Sync folders` overlapt niet meer met de optie `Bestandsattributen (xattrs) kopiëren`.

## [0.8.2] - 2026-08-03

### Toegevoegd

- `Sync folders` toont nu een voortgangssectie met actief profiel, progressbalk, huidig bestand/pad, snelheid en ETA.
- Handmatige en automatische sync-runs werken dezelfde voortgang bij tijdens het kopiëren.

## [0.8.1] - 2026-08-03

### Gewijzigd

- Hoofdvenster heeft nu aparte tabbladen voor `Move folders` en `Sync folders`.
- Bestaande overdrachtbediening staat in `Move folders`.
- Sync-profielen hebben een eigen `Sync folders` formulier met profielnaam, Folder A, Folder B, interval en sync-opties.
- De move-tabellen gebruiken de vrijgekomen ruimte onderaan nu volledig.

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
