# NotchIsland

Verwandelt die Notch deines MacBooks in eine Dynamic Island wie beim iPhone. Fährst du mit der Maus auf die Notch oder ziehst eine Datei darüber, klappt sie mit einer Spring-Animation auf. Verlässt du sie, klappt sie nach kurzer Verzögerung wieder zu.

| Tab | Was er kann |
|---|---|
| **Ablage** | Dateien, Ordner, Bilder, Links und Text hineinziehen und wieder herausziehen (auch mehrere). Vorschaubilder per QuickLook, fehlende Dateien werden markiert, die Ablage bleibt nach einem Neustart erhalten. |
| **Musik** | Cover, Titel, Fortschritt (zum Spulen ziehen), Play/Pause, Vor/Zurück für Musik, Spotify, Browser und andere Apps. Zugeklappt: Mini-Cover links, Equalizer rechts. |
| **Kamera** | Gespiegelte Live-Vorschau der FaceTime-Kamera. Sie läuft nur, solange der Tab offen ist. |
| **Kalender** | Termine von heute und morgen mit Farbe, Countdown und „Beitreten“ für Zoom, Teams, Meet und Webex. 5 Minuten vor Beginn erscheint ein Hinweis neben der Notch. |
| **Zwischenablage** | Die letzten ~30 Texte, Links, Bilder und Dateien. Klick kopiert, Ziehen fügt ein, Einträge lassen sich anheften. Passwörter werden ignoriert. |
| **MacBuddy** | Status, Ergebnisse und Bestätigungen des KI-Assistenten [MacBuddy](https://github.com/Vyp3er/MacBuddy), mit Not-Aus direkt neben der Notch (siehe [MacBuddy-Anbindung](#macbuddy-anbindung)). |
| **Timer** | Dauer oder Uhrzeit eintippen („5min“, „15 Minuten“, „@5pm“, „Pizza 12 min“), Enter startet. Mehrere Timer gleichzeitig, Restzeit neben der Notch, Alarm mit Ton (siehe [Timer](#timer)). |

## Download und Installation

**Ohne Xcode:** Die fertige App gibt es unter **[Releases](https://github.com/Vyp3er/NotchIsland/releases/latest)**. Die Schritt-für-Schritt-Anleitung steht in **[INSTALLATION.md](INSTALLATION.md)**. Sie erklärt auch den ersten Start, den macOS bei nicht notarisierten Apps blockiert.

## Voraussetzungen

- macOS 14 oder neuer, Apple Silicon oder Intel
- Am besten ein MacBook mit Notch. Ohne Notch erscheint die Island oben mittig auf dem Hauptbildschirm.
- Nur zum Selbstbauen: Xcode 16 oder neuer (entwickelt und getestet mit Xcode 27 auf macOS 27.0.1)

## Selbst bauen

### Empfohlen: Installationsskript

```bash
./scripts/install.sh
```

Das Skript baut eine Release-Version, kopiert sie nach `/Applications/NotchIsland.app` und startet sie. Beim ersten Start aus dem Programme-Ordner trägt sich die App selbst als Anmeldeobjekt ein (`SMAppService`), danach startet sie bei jedem Login automatisch. Abschalten kannst du das in den Einstellungen.

### In Xcode

`NotchIsland.xcodeproj` öffnen, Scheme **NotchIsland** wählen, ⌘R.

### Mit `xcodebuild`

```bash
xcodebuild -project NotchIsland.xcodeproj -scheme NotchIsland -configuration Release -derivedDataPath build/DerivedData build
```

Die App liegt danach in `build/DerivedData/Build/Products/Release/NotchIsland.app`.

> **Hinweis:** Zeigt `xcode-select` auf die Command Line Tools (zum Beispiel nach `xcode-select --install`), bricht `xcodebuild` mit „requires Xcode“ ab. Entweder einmalig umstellen …
>
> ```bash
> sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
> ```
>
> … oder `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` vor den Befehl setzen. Das Installationsskript macht das automatisch.

Ein Build aus Xcode/DerivedData registriert sich **nicht** automatisch als Anmeldeobjekt. So zeigt der Autostart nie auf einen Zwischenstand. Dafür ist die Kopie in `/Applications` da.

## Neustart nach einem Absturz

Die installierte App startet sich nach einem Absturz selbst neu, nach etwa 2 Sekunden.

- **So funktioniert es:** Beim Start legt NotchIsland einen kleinen Wächter-Prozess (`/usr/bin/perl`) an, der über eine Pipe mit der App verbunden ist. Beim normalen Beenden meldet sich die App beim Wächter ab. Reißt die Verbindung ohne Abmeldung ab, öffnet der Wächter die App erneut.
- **Normales Beenden bleibt beendet:** über das Menüleisten-Icon, die Einstellungen, beim Abmelden/Ausschalten und bei `pkill`/SIGTERM.
- **„Sofort beenden“** (Aktivitätsanzeige, ⌥⌘⎋) zählt wie ein Absturz, die App kommt also wieder. Zum dauerhaften Beenden das Menü nutzen.
- **Schutz vor Absturzschleifen:** Höchstens 3 automatische Neustarts innerhalb von 10 Minuten, danach bleibt die App nach dem nächsten Absturz aus.
- Gilt nur für die Kopie in `/Applications`, damit z. B. Xcodes Stopp-Button beim Entwickeln nicht zu Neustarts führt. Abschaltbar in den Einstellungen.

## Berechtigungen

Alles unter **Systemeinstellungen → Datenschutz & Sicherheit**. macOS fragt jeweils erst, wenn ein Tab die Berechtigung wirklich braucht.

| Berechtigung | Wofür | Wann wird gefragt? |
|---|---|---|
| **Kamera** | Kamera-Tab | Beim ersten Öffnen des Kamera-Tabs |
| **Kalender** → „Vollzugriff“ | Kalender-Tab und 5-Minuten-Hinweis | Beim ersten Öffnen des Kalender-Tabs |
| **Automation** → Musik / Spotify | Nur für den AppleScript-Fallback (siehe unten) | Nur wenn der Fallback aktiv wird |
| **Dateien und Ordner** (Schreibtisch, Dokumente, Downloads) | Vorschauen und Gültigkeitsprüfung für abgelegte Dateien aus diesen Ordnern | Ggf. nach einem Neustart beim ersten Zugriff |
| **Allgemein → Anmeldeobjekte** | Autostart | „NotchIsland“ muss dort erlaubt sein |

**Nicht** nötig: Bedienungshilfen, Bildschirmaufnahme, Festplattenvollzugriff, Eingabeüberwachung.

**Berechtigungen nach einem Neu-Build:** Standardmäßig wird ad-hoc signiert („Sign to Run Locally“). macOS verknüpft Freigaben mit der Signatur, deshalb fragt es nach jedem Neu-Build erneut. Mit einem eigenen Zertifikat bleiben die Freigaben erhalten. Lege `Config/Signing.local.xcconfig` an:

```
CODE_SIGN_IDENTITY = Apple Development: Dein Name (XXXXXXXXXX)
DEVELOPMENT_TEAM = DEINETEAMID
```

Verfügbare Zertifikate zeigt `security find-identity -v -p codesigning`.

## Musik: welcher Weg?

Seit macOS 15.4 dürfen Drittanbieter-Apps das private **MediaRemote**-Framework nicht mehr nutzen. NotchIsland verwendet deshalb das Open-Source-Projekt **[mediaremote-adapter](https://github.com/ungive/mediaremote-adapter)** (BSD-3-Clause, eingebunden unter `Vendor/mediaremote-adapter`, Stand Commit `0e82bf1`, 17.10.2026):

- Das Xcode-Projekt baut daraus das Target `MediaRemoteAdapter.framework` und bettet es zusammen mit `mediaremote-adapter.pl` in die App ein.
- Die App startet `/usr/bin/perl mediaremote-adapter.pl … stream`. Perl ist ein Apple-Binary und darf MediaRemote weiterhin nutzen. Das Framework läuft in diesem Prozess und streamt Titel, Cover, Position und Status als JSON-Zeilen. Befehle (Play/Pause, Vor/Zurück, Spulen) gehen über `… send`/`… seek`.
- Ein kleiner Perl-Wächter beendet den Adapter, sobald NotchIsland nicht mehr läuft, auch nach einem Absturz.
- Getestet mit macOS 27.0.1: Der Selbsttest des Adapters besteht, und der Stream liefert Daten aus Musik-Apps und Browsern.

**Fallback:** Startet der Adapter wiederholt nicht, oder liefert er nach einem macOS-Update keine Daten, fragt NotchIsland Musik und Spotify per AppleScript ab. Dabei werden nur laufende Apps abgefragt, und es wird nichts gestartet. In den Einstellungen kannst du unter *Musik → Quelle* auch fest „Nur Musik & Spotify (AppleScript)“ wählen.

## Timer

Klick auf das Timer-Symbol in der Tab-Leiste, eintippen, **Enter**. Rechts im Feld steht schon beim Tippen, was erkannt wurde („bis 17:30 · 47 Min“), sonst „Nicht erkannt“.

| Eingabe | Ergebnis |
|---|---|
| `5min`, `5 min`, `15 Minuten`, `90s`, `45 Sekunden`, `2h` | Dauer |
| `1h30`, `1 Stunde 20`, `2 min 30`, `5 Minuten und 30 Sekunden` | zusammengesetzte Dauer (Zahl ohne Einheit = nächstkleinere Einheit) |
| `1,5 Std`, `anderthalb Stunden`, `halbe Stunde`, `Viertelstunde`, `zehn Minuten`, `half an hour` | Kommazahlen und Zahlwörter |
| `25:00`, `1:30:00`, `10` | Minuten:Sekunden, Stunden:Minuten:Sekunden, nackte Zahl = Minuten |
| `@5pm`, `@5:30pm`, `@17:30`, `um 17 Uhr`, `bis 18.30`, `5pm`, `at 6 pm` | Uhrzeit (liegt sie schon hinter dir, gilt morgen; `@5` am Nachmittag heißt 17:00) |
| `Pizza 12 min`, `Tee in 3 Minuten`, `Anruf um 15 Uhr` | übrige Wörter werden zum Namen |

- **Uhrzeit nur mit Kennzeichen:** `@`, `um`, `bis`, `at` oder `Uhr`/`am`/`pm`. So bleibt `25:00` eindeutig eine Dauer von 25 Minuten. `@25:00` ist ungültig und startet nichts.
- **Schnellwahl** (1, 3, 5, 10, 15, 25 Min, 1 Std), solange kein Timer läuft.
- **Karten:** Restzeit, Fortschritt, Pausieren/Fortsetzen, Entfernen.
- **Ablauf:** Die Island klappt im Timer-Tab auf und bleibt offen, solange es klingelt (höchstens 30 s, Ton „Glass“). „Stopp“ beendet, „+5 Min“ verlängert. Die Glocke oben rechts stellt alle klingelnden Timer ab.
- **Neben der Notch:** Restzeit des nächsten Timers. Klingeln hat Vorrang vor Terminen, ein laufender Timer vor der Musik.
- **Tastatur:** Die Island wird nur für das Eingabefeld zum Key-Window, ohne NotchIsland zu aktivieren. Beim Zuklappen geht der Fokus an deine App zurück. Esc leert das Feld bzw. klappt zu. ⌘V, ⌘C, ⌘A und ⌘Z funktionieren. Solange du tippst, klappt die Island nicht zu.
- **Neustart:** Timer werden in `~/Library/Application Support/NotchIsland/timers.json` gespeichert und laufen nach einem Neustart weiter. Was in der Zwischenzeit abgelaufen ist, klingelt noch, wenn es weniger als 2 Minuten her ist.
- **Einstellungen › Timer:** Ton, automatisch aufklappen, Restzeit neben der Notch.

## MacBuddy-Anbindung

*Optional:* Nur relevant, wenn du auch den KI-Assistenten **[MacBuddy](https://github.com/Vyp3er/MacBuddy)** nutzt (eigene App, Apple Silicon, macOS 26 oder neuer). Ohne MacBuddy zeigt der Tab „MacBuddy läuft nicht“; ausblenden lässt er sich unter *Einstellungen › Tabs*.

NotchIsland zeigt, was MacBuddy gerade tut, und kann es steuern. Grundlage ist der Abschnitt „NotchIsland-Protokoll“ in der MacBuddy-README und der Code aus dessen Ordner `NotchIslandIntegration/`.

| Wo | Was |
|---|---|
| **Neben der Notch** | Links Symbol und Status („Öffnet Safari“), rechts ein roter **Stopp**. Der Stopp ist im zugeklappten Zustand direkt klickbar; darüber klappt die Island bewusst nicht auf. Nach dem Ende kurz ✓ oder ✗. |
| **Tab „MacBuddy“** | Laufender Status mit Fortschritt und großem Stopp, Bestätigungen riskanter Aktionen („Ablehnen“ / z. B. „In den Papierkorb“), Ergebnistext mit „In MacBuddy öffnen“ und „OK“. Ohne laufende Aufgabe: „MacBuddy öffnen“ bzw. „MacBuddy starten“. |
| **Bestätigungen** | Die Island klappt automatisch im MacBuddy-Tab auf und bleibt offen, bis die Anfrage beantwortet ist (hier oder im MacBuddy-Panel). |

- **Transport:** `DistributedNotificationCenter` mit JSON im `object`, Protokollversion 1. `Modules/MacBuddy/MacBuddyIslandProtocol.swift` ist eine **unveränderte Kopie** der Protokolldatei aus MacBuddy. Ändert MacBuddy das Protokoll, muss diese Datei neu kopiert werden.
- **Sicherheit:** „Ausführen“ erscheint nur, wenn MacBuddy es erlaubt (`allowsApproval`). MacBuddy nimmt eine Bestätigung zudem nur an, wenn die ID zu einer offenen Anfrage passt. Stopp und Ablehnen sind immer möglich.
- **Gegenüber dem Beispiel-Client geändert:** Status und Ergebnis haben getrennte Timer. Im Original setzte das auf das Ergebnis folgende `status(done)` den gemeinsamen Timer zurück, das Ergebnis verschwand dadurch schon nach 2,5 statt nach 6 Sekunden. Solange der MacBuddy-Tab offen ist, bleibt das Ergebnis stehen. Beendet sich MacBuddy, wird die Anzeige zurückgesetzt.
- **Einstellungen › MacBuddy:** Anbindung an/aus, automatisch aufklappen, Anzeige neben der Notch, Status von MacBuddy (läuft / beendet / nicht installiert). In MacBuddy zeigt *Einstellungen › NotchIsland › Verbindung prüfen*, ob NotchIsland antwortet.
- **Vorrang neben der Notch:** MacBuddy › klingelnder Timer › Termin-Hinweis › laufender Timer › Musik.

## Bedienung

- **Öffnen:** Maus auf die Notch (Verzögerung einstellbar) oder auf die Notch klicken. Ein Klick auf eine Live-Aktivität öffnet direkt deren Tab.
- **Drag-Hover:** Eine Datei über die Notch ziehen öffnet die Island im Ablage-Tab.
- **Ablage:** Klick wählt aus, ⌘-Klick und ⇧-Klick wählen mehrere. Ziehen nimmt die ganze Auswahl mit. Herausziehen **kopiert**, mit gedrückter **⌘-Taste** wird verschoben. Doppelklick öffnet. Rechtsklick: Öffnen, Im Finder zeigen, QuickLook, Teilen, Entfernen.
- **Zwischenablage:** Klick kopiert zurück. Die Pinnadel heftet an, angeheftete Einträge bleiben beim Leeren erhalten.
- **Einstellungen:** Menüleisten-Icon oder Zahnrad in der Island.

## Einstellungen

Beim Login starten · Neustart nach Absturz · haptisches Feedback · Island-Größe (Kompakt/Standard/Groß) · Verzögerung beim Öffnen und Schließen · Live-Aktivitäten für Musik und Kalender · Tabs ein-/ausblenden und umsortieren · Ablage: nach dem Herausziehen entfernen · Musikquelle · Länge des Zwischenablage-Verlaufs.

## Daten

- Ablage-Index, Zwischenablage-Verlauf und von NotchIsland angelegte Dateien (Bilder, Texte, Links ohne eigene Datei): `~/Library/Application Support/NotchIsland/`
- Einstellungen: `defaults read de.vincentschmitt.NotchIsland`

Nichts davon verlässt den Mac.

## Projektstruktur

```
NotchIsland/
├── App/            Start, AppDelegate, Menüleiste, Autostart, Debug-Snapshots
├── Core/           Einstellungen, Pfade, Tabs, Logging, Thumbnail-Cache
├── Island/         Notch-Geometrie, Panels, Fenster-Controller (Hover/Drag), SwiftUI-Island
├── Modules/
│   ├── Shelf/      Ablage (Drop-Reader, Drag-Quelle, QuickLook, Kacheln)
│   ├── Music/      MediaRemote-Adapter-Client, AppleScript-Fallback, Ansichten
│   ├── Camera/     AVFoundation-Vorschau
│   ├── Calendar/   EventKit, Meeting-Link-Erkennung, Live-Aktivität
│   ├── Clipboard/  Verlauf, Karten
│   ├── MacBuddy/   Protokoll (Kopie aus MacBuddy), Client, Ansichten
│   └── Timer/      Eingabe-Parser, Timer-Store mit Alarm, Ansichten
├── Settings/       Einstellungsfenster
└── Resources/      App-Icon
Config/             Info.plist, Entitlements (kein Sandbox), Signing.xcconfig
Vendor/             mediaremote-adapter (Framework-Target im Projekt)
scripts/            install.sh, make-icon.swift
```

## Deinstallieren

1. In den Einstellungen „Beim Login starten“ ausschalten, dann NotchIsland über das Menü beenden (nicht „Sofort beenden“, sonst startet sie neu).
2. `/Applications/NotchIsland.app` und `~/Library/Application Support/NotchIsland` löschen.

## Bekannte Grenzen

- Der Equalizer ist animiert, zeigt aber keine echten Pegel (macOS stellt sie nicht bereit).
- Solange eine Live-Aktivität sichtbar ist, verdecken die schwarzen „Ohren“ neben der Notch Menüleisten-Einträge, die direkt daneben liegen.
- Der mediaremote-adapter nutzt private Schnittstellen. Ein künftiges macOS-Update kann ihn brechen, dann greift der AppleScript-Fallback für Musik und Spotify.
- Mit einem Mausrad ohne horizontales Scrollen blätterst du in der Ablage mit ⇧ + Rad.
