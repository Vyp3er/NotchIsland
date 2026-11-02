# NotchIsland installieren

Eine Anleitung für alle, die NotchIsland einfach benutzen wollen, ohne Xcode und ohne Programmierkenntnisse. Dauer: etwa 5 Minuten.

## Was du brauchst

- Einen Mac mit **macOS 14 (Sonoma) oder neuer**, Apple Silicon oder Intel.
- Am schönsten ist es auf einem **MacBook mit Notch**. Auf anderen Macs erscheint die Island oben mittig am Bildschirmrand.

## 1. Herunterladen

1. Öffne **https://github.com/Vyp3er/NotchIsland/releases/latest**.
2. Klicke unter **Assets** auf **`NotchIsland-1.0.zip`**.
3. Die Datei landet in deinem Ordner **Downloads**. Safari entpackt sie meist automatisch. Sonst machst du einen Doppelklick auf die ZIP-Datei, dann erscheint daneben **NotchIsland.app**.

## 2. In den Programme-Ordner legen

Ziehe **NotchIsland.app** im Finder in den Ordner **Programme** (in der Seitenleiste links).

> **Wichtig:** Nur aus dem Ordner „Programme“ heraus richtet NotchIsland den automatischen Start beim Anmelden und den Neustart nach einem Absturz ein.

## 3. Der erste Start

NotchIsland ist nicht bei Apple **notarisiert**. Dafür braucht man ein kostenpflichtiges Apple-Entwicklerkonto. macOS blockiert deshalb den ersten Start einmalig. So erlaubst du ihn:

1. Öffne **Programme** und mach einen Doppelklick auf **NotchIsland**.
   Es erscheint die Meldung *„NotchIsland“ wurde nicht geöffnet*. Klicke auf **Fertig**, **nicht** auf „In den Papierkorb legen“.
2. Öffne **Systemeinstellungen → Datenschutz & Sicherheit** und scrolle ganz nach unten zum Abschnitt **Sicherheit**.
3. Dort steht *„NotchIsland“ wurde blockiert, um deinen Mac zu schützen.* Klicke daneben auf **Dennoch öffnen** und bestätige mit deinem Passwort oder Touch ID.
4. Im nächsten Fenster noch einmal **Dennoch öffnen** klicken.

Das musst du nur einmal machen. Danach startet NotchIsland ganz normal.

**Auf macOS 14 (Sonoma) geht es auch kürzer:** Rechtsklick auf NotchIsland → **Öffnen** → nochmals **Öffnen**.

**Alternative über das Terminal**, falls du es lieber so machst oder die Meldung *„NotchIsland“ ist beschädigt und kann nicht geöffnet werden* erscheint. Öffne die App **Terminal** und füge diese Zeile ein:

```bash
xattr -dr com.apple.quarantine /Applications/NotchIsland.app
```

Danach öffnest du NotchIsland ganz normal per Doppelklick. Der Befehl entfernt nur die Download-Markierung von dieser einen App.

## 4. Was nach dem Start passiert

- **Kein Fenster, kein Symbol im Dock.** Das ist Absicht. NotchIsland läuft im Hintergrund.
- In der **Menüleiste** erscheint ein kleines Symbol (ein Rechteck mit gefülltem oberen Streifen). Darüber erreichst du **Einstellungen** und **Beenden**.
- macOS meldet **„Anmeldeobjekt hinzugefügt“**. Ab jetzt startet NotchIsland bei jeder Anmeldung von selbst. Abschalten kannst du das in den Einstellungen unter „Beim Login starten“.
- **Fahre mit der Maus auf die Notch.** Die Island klappt auf. Fährst du weg, klappt sie wieder zu.

## 5. Berechtigungen

macOS fragt erst nach, wenn du einen Tab öffnest, der etwas braucht. Klicke dann auf **Erlauben**. Ändern kannst du das später unter **Systemeinstellungen → Datenschutz & Sicherheit**.

| macOS fragt nach … | wofür | wann |
|---|---|---|
| **Kamera** | Spiegel im Kamera-Tab (die Kamera läuft nur, solange der Tab offen ist) | Beim ersten Öffnen des Kamera-Tabs |
| **Kalender** | Termine von heute und morgen, Erinnerung 5 Minuten vorher | Beim ersten Öffnen des Kalender-Tabs |
| **Musik / Spotify steuern** | Nur, falls die normale Musikerkennung nicht funktioniert | Selten |
| **Dateien in Schreibtisch, Dokumente, Downloads** | Vorschaubilder für Dateien, die du in die Ablage gelegt hast | Eventuell nach einem Neustart |

NotchIsland braucht **keine** Bedienungshilfen, keine Bildschirmaufnahme und keinen Festplattenvollzugriff. Ablage, Zwischenablage-Verlauf und Timer werden nur lokal auf deinem Mac gespeichert.

## 6. Kurz erklärt

Oben links in der aufgeklappten Island wechselst du zwischen den Tabs:

- **Ablage:** Zieh Dateien, Bilder oder Text auf die Notch. Die Island öffnet sich und nimmt sie auf. Später ziehst du sie wieder heraus, z. B. in Mail, einen Ordner oder ein Upload-Feld. Rechtsklick: Öffnen, Im Finder zeigen, QuickLook, Teilen.
- **Musik:** Cover, Titel und Steuerung für Musik, Spotify und Videos im Browser. Solange etwas läuft, siehst du neben der Notch das Cover und einen kleinen Equalizer.
- **Kamera:** Schneller Blick in den Spiegel vor einem Videocall.
- **Kalender:** Deine nächsten Termine. Bei Zoom, Teams oder Meet gibt es einen „Beitreten“-Knopf.
- **Zwischenablage:** Die letzten Dinge, die du kopiert hast. Klick kopiert sie wieder, mit der Pinnadel heftest du sie an. Passwörter aus Passwortmanagern werden nicht gespeichert.
- **Timer:** Klick auf das Timer-Symbol, tippe z. B. `5min`, `15 Minuten`, `Pizza 12 min` oder `@17:30` und drück **Enter**. Die Restzeit siehst du neben der Notch. Wenn er abläuft, klingelt es.
- **MacBuddy:** Nur interessant, wenn du den Assistenten MacBuddy installiert hast. Sonst kannst du den Tab in den Einstellungen unter „Tabs“ ausblenden.

Alles Weitere stellst du in den **Einstellungen** ein: Größe der Island, Verzögerungen, welche Tabs sichtbar sind und in welcher Reihenfolge.

## Neue Version installieren

1. Neue ZIP-Datei unter **Releases** herunterladen und entpacken.
2. NotchIsland über das Menüleisten-Symbol → **NotchIsland beenden** schließen.
3. Die neue **NotchIsland.app** in **Programme** ziehen und **Ersetzen** wählen.
4. Schritt 3 („Der erste Start“) wiederholen. Kamera- und Kalenderzugriff musst du eventuell noch einmal erlauben.

Deine Ablage, Timer und Einstellungen bleiben erhalten.

## Deinstallieren

1. Einstellungen → **Beim Login starten** ausschalten.
2. Menüleisten-Symbol → **NotchIsland beenden**. Bitte nicht „Sofort beenden“, sonst startet sich die App wieder neu.
3. **NotchIsland** aus „Programme“ in den Papierkorb ziehen.
4. Optional die gespeicherten Daten löschen: Im Finder **Gehe zu → Gehe zum Ordner …** (⇧⌘G), `~/Library/Application Support/NotchIsland` eingeben und den Ordner löschen.

## Hilfe bei Problemen

| Problem | Lösung |
|---|---|
| „NotchIsland ist beschädigt“ | Terminal-Befehl aus Schritt 3 ausführen, dann neu öffnen. |
| Die Island erscheint nicht | Ist das Menüleisten-Symbol da? Wenn nicht, NotchIsland in „Programme“ erneut öffnen. Mit externem Monitor erscheint die Island auf dem Bildschirm mit Notch, sonst auf dem Hauptbildschirm. |
| Musik wird nicht angezeigt | Einstellungen → **Musik → Quelle** auf „Nur Musik & Spotify (AppleScript)“ stellen und die Nachfrage „… steuern“ erlauben. |
| Kamera oder Kalender: „Kein Zugriff“ | Systemeinstellungen → Datenschutz & Sicherheit → **Kamera** bzw. **Kalender** → NotchIsland einschalten. |
| Die App kommt nach dem Beenden zurück | Sie wurde wohl „sofort beendet“, das zählt als Absturz. Über das Menüleisten-Symbol beenden. |
| Startet nicht automatisch beim Anmelden | Systemeinstellungen → Allgemein → **Anmeldeobjekte** → NotchIsland erlauben. Die App muss in „Programme“ liegen. |

NotchIsland ist Open Source. Den Quellcode findest du in diesem Repository; die technische Beschreibung steht in der [README](README.md).
