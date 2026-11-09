# Neue Zeilen pro Tag

Ein kleines Zig-Programm, das für die letzten konfigurierten UTC-Kalendertage pro Tag das Netto-Delta (`hinzugefügte Zeilen - entfernte Zeilen`) in Git-Commits ausgibt. Standardmäßig sind das zehn Tage. Am Ende zeigt es die Netto-Summe und den durchschnittlichen Netto-Zuwachs pro Tag über den gesamten Zeitraum an; Tage ohne Änderungen zählen dabei als `0`. Gezählt werden nur Dateien mit bekannten Endungen für JavaScript (`.js`, `.jsx`, `.mjs`, `.cjs`), C++ (`.cc`, `.cpp`, `.cxx`, `.h`, `.hh`, `.hpp`, `.hxx`), Zig (`.zig`), Lua (`.lua`), fish (`.fish`) und Bash (`.sh`, `.bash`). Binärdateien werden ignoriert; Merge-Commits werden nicht doppelt gezählt.

Standardmäßig werden zehn Tage ausgewertet. Mit `--days` oder `-n` lässt sich die Anzahl ändern; der Durchschnitt wird auf zwei Nachkommastellen gerundet.

Die Zählung verwendet den Committer-Zeitstempel und die Historie des aktuell ausgecheckten Branches. Git muss installiert sein. `cl` sucht das Repository vom aktuellen Verzeichnis aus (Git findet dabei auch ein übergeordnetes Repository).

```sh
zig build-exe main.zig -O ReleaseFast -femit-bin=cl
```

Das erstellt das Executable `cl`. Starte es mit dem gewünschten Git-Projekt als aktuellem Verzeichnis, zum Beispiel über seinen Pfad oder nachdem du es in deinen `PATH` gelegt hast:

```sh
cd /pfad/zum/projekt
/pfad/zu/cl
```

Zum Beispiel für 30 Tage:

```sh
/pfad/zu/cl --days 30
```

Für einen einmaligen Lauf ohne separates Executable:

```sh
zig run main.zig
```
