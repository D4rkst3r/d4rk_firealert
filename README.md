# d4rk_firealert 🚒

Ein realistisches Brandmeldesystem für FiveM (Hardcore RP).

## Features

- **Ghost-Placement**: Visuelle Vorschau beim Platzieren von Meldern (begrenzte Reichweite, konfigurierbar).
- **Zonensystem**: Räume können individuell benannt werden (z.B. "Küche EG").
- **Automatische Rauchmelder**: Reagieren auf GTA-native Feuer in der Nähe (`GetNumberOfFiresInRange`).
- **Wartung**: Melder verlieren über Zeit an Haltbarkeit und müssen repariert werden (Item-basiert).
- **Zentrale (Panel)**: Steuerungseinheit für Alarmquittierung, Geräteliste und Alarm-Protokoll.
- **Alarm-Log**: Jeder Alarm und jede Quittierung wird in der Datenbank protokolliert.
- **Dispatch-Integration**: Unterstützt `ps-dispatch`, `cd_dispatch`, oder Fallback auf ox_lib-Notify.
- **Delta-Sync**: Geräte werden einzeln gespawnt/despawnt — kein kompletter Reload bei jeder Änderung.
- **Sirenen-Audio**: Positions-basierter Loop-Sound mit konfigurierbarer Reichweite.
- **Sicherheit**: Job-Checks auf allen Server-Events, Proximity-Check und Cooldown beim Alarm.

## Abhängigkeiten

- [ox_lib](https://github.com/overextended/ox_lib)
- [ox_target](https://github.com/overextended/ox_target)
- [oxmysql](https://github.com/overextended/oxmysql)
- QBCore oder QBX Core

## Installation

1. `install.sql` in die Datenbank importieren.
2. `ensure d4rk_firealert` in die `server.cfg` schreiben.
3. `config.lua` anpassen (Job, Dispatch-System, AutoSmoke, etc.).
4. ACE-Permissions in der `server.cfg` eintragen (siehe unten).

## ACE-Permissions (server.cfg)

```
# Feuerwehr darf Geräte installieren
add_ace group.firefighter command.install_bma allow

# Admins dürfen Probealarm auslösen
add_ace group.admin command.test_bma allow
```

## Befehle

| Befehl | Beschreibung | Berechtigung |
|--------|-------------|--------------|
| `/install_bma [panel\|smoke\|pull\|siren]` | Startet den Installationsmodus | Job: firefighter |
| `/test_bma [systemId]` | Löst einen Probealarm aus | group.admin |

## Workflow: Neues Gebäude einrichten

1. `/install_bma panel` → Panel platzieren, Gebäudenamen + optionalen Zonenname eingeben.
2. `/install_bma smoke` / `/install_bma pull` / `/install_bma siren` → Gerät platzieren, Zonenname eingeben.
3. System wird **automatisch** anhand des nächsten Panels in der Nähe erkannt.
4. Bei mehreren Panels in Reichweite erscheint ein Auswahlmenü mit Systemname + Distanz.
5. Während der Platzierung zeigt eine blaue Linie das nächste Panel an.

> **Hinweis**: Kein manueller Wartungsmodus mehr nötig — die Systemzuweisung passiert vollautomatisch per Nähe.

## Konfiguration

```lua
Config.Job = "firefighter"  -- FiveM Job-Name

Config.Maintenance = {
    DegradeChance = 5,              -- % Chance pro Check
    CheckInterval = 30,             -- Minuten zwischen Checks
    RepairItem    = "electronics_kit"  -- "" = kein Item nötig
}

Config.AutoSmoke = {
    Enabled       = true,
    CheckRadius   = 8.0,   -- Meter
    CheckInterval = 5,     -- Sekunden
}

Config.Dispatch = {
    Enabled = true,
    System  = "ps-dispatch",  -- "ps-dispatch" | "cd_dispatch" | "ox_lib" | "none"
    Code    = "10-70",
}

Config.Placement = {
    MaxDistance        = 4.0,   -- Maximale Platzierungsdistanz in Metern
    MinDistance        = 0.5,
    SystemSearchRadius = 50.0,  -- Radius für automatische Systemerkennung
}

Config.Interaction = {
    DistancePanel  = 2.0,  -- Interaktionsreichweite für Panels
    DistanceDevice = 1.5,  -- Interaktionsreichweite für Melder/Sirenen
}
```

---

## Changelog

### v2.2.0
- **FIX**: `DistanceDevice` wird jetzt korrekt für Melder und Sirenen genutzt (war Dead Code).
- **FIX**: `currentSystemId` und Wartungsmodus-Menüeintrag entfernt — waren Dead Code seit Option C.
- **FIX**: README Workflow aktualisiert — beschreibt jetzt den korrekten Option C Flow.
- **FIX**: `lib.addCommand` mit leerem Callback ersetzt durch `RegisterCommand`.
- **NEU**: `playAlarmSound` klar als Eingangs-Beep dokumentiert.
- **NEU**: Version auf 2.2.0 angehoben.

### v2.1.0
- Sirenen-Audio-Thread mit `RequestScriptAudioBank` und manuellem Distanz-Check.
- Option C: Automatische Systemzuweisung per Nähe beim Platzieren.
- Blaue Linie zum nächsten Panel während Placement-Modus.
- Interaction-Range via `Config.Interaction` konfigurierbar.
- `DistancePanel` / `DistanceDevice` Parameter für alle ox_target Einträge.
- ACE-Permissions für `/install_bma` und `/test_bma`.
- `math.randomseed(os.time())` für echte Zufälligkeit im Wartungs-Loop.

### v2.0.0
- Automatische Rauchmelder-Auslösung via `GetNumberOfFiresInRange`.
- Alarm-Log (`fire_alarm_log` Tabelle) mit Quittierungs-Protokoll.
- Dispatch-Integration (ps-dispatch, cd_dispatch, Fallback).
- Reparatur-System mit Item-Check (ox_inventory / qb-inventory).
- Sirene hat Target-Optionen (Reparieren, Abmontieren).
- Delta-Sync: nur neue/entfernte Geräte werden übertragen.
- Alarmstatus überlebt Server-Restart (Status aus DB).
- Job-Check auf `registerDevice` und `quittieren`.
- Proximity-Check + Cooldown beim Pull-Alarm.

### v1.0.0
- Grundsystem: Ghost-Placement, Zonensystem, Panel, Rauch-/Handfeuermelder, Sirene.
- Wartungs-Loop mit Health-Degradierung.
- QBCore/QBX Kompatibilität.