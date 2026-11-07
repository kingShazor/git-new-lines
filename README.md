# Neue Zeilen pro Tag

Ein kleines Zig-Programm, das für die letzten zehn UTC-Kalendertage pro Tag das Netto-Delta (`hinzugefügte Zeilen - entfernte Zeilen`) in Git-Commits ausgibt. Anschließend wird der durchschnittliche Netto-Zuwachs pro Tag über alle zehn Tage angezeigt; Tage ohne Änderungen zählen dabei als `0`. Gezählt werden nur Dateien mit bekannten Endungen für JavaScript (`.js`, `.jsx`, `.mjs`, `.cjs`), C++ (`.cc`, `.cpp`, `.cxx`, `.h`, `.hh`, `.hpp`, `.hxx`), Zig (`.zig`), Lua (`.lua`), fish (`.fish`) und Bash (`.sh`, `.bash`). Binärdateien werden ignoriert; Merge-Commits werden nicht doppelt gezählt.

Die Zählung verwendet den Committer-Zeitstempel und die Historie des aktuell ausgecheckten Branches. Git muss installiert sein. `cl` sucht das Repository vom aktuellen Verzeichnis aus (Git findet dabei auch ein übergeordnetes Repository).

```sh
zig build-exe main.zig -O ReleaseFast -femit-bin=cl
```

Das erstellt das Executable `cl`. Starte es mit dem gewünschten Git-Projekt als aktuellem Verzeichnis, zum Beispiel über seinen Pfad oder nachdem du es in deinen `PATH` gelegt hast:

```sh
cd /pfad/zum/projekt
/pfad/zu/cl
```

Für einen einmaligen Lauf ohne separates Executable:

```sh
zig run main.zig
```
