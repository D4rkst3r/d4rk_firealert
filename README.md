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

1. `/install_bma panel` → Panel platzieren, Gebäudenamen eingeben → System-ID merken.
2. Am Panel: **Wartungsmodus aktivieren** → System-ID wird gespeichert.
3. `/install_bma smoke` / `/install_bma pull` → Melder platzieren, Zonenname eingeben.
4. Weiterer Melder → automatisch mit aktivem System verknüpft.
5. Am Panel: **Wartungsmodus beenden**.

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
    MaxDistance = 4.0,  -- Maximale Platzierungsdistanz in Metern
    MinDistance = 0.5,
}
```

---

## Changelog

### v2.1.0
- **FIX**: Automatischer Alarm-Trigger (`triggerAutoAlarm`) ist jetzt ein separates Server-Event — Cheater können `'automatic'` als triggerType nicht mehr injecten um Proximity/Cooldown zu umgehen.
- **FIX**: `pendingSyncs` ist jetzt ein Set statt Array — kein doppelter Sync bei mehrfachem `requestSync` vor DB-Init.
- **FIX**: Placement-Distanz wird jetzt auf `Config.Placement.MaxDistance` geclampt — kein Fernplatzieren per Mausrad-Spam mehr.
- **FIX**: Feedback-Notify wenn `requestSync` zu früh angefragt wird (Server noch nicht bereit).
- **FIX**: `OpenDeviceList` nutzt jetzt `devicesBySystem[sId]`-Map statt alle spawnedObjects zu iterieren.
- **FIX**: `math.randomseed(os.time())` im Wartungs-Loop für echte Zufälligkeit nach Restart.
- **FIX**: `getAllDevicesWithCoords()` entfernt (Dead Code seit v2.0.0).
- **NEU**: ACE-Permissions für `/install_bma` und `/test_bma` via `lib.addCommand`.
- **NEU**: README vollständig aktualisiert.

### v2.0.0
- Automatische Rauchmelder-Auslösung via `GetNumberOfFiresInRange`.
- Alarm-Log (`fire_alarm_log` Tabelle) mit Quittierungs-Protokoll.
- Dispatch-Integration (ps-dispatch, cd_dispatch, Fallback).
- Reparatur-System mit Item-Check (ox_inventory / qb-inventory).
- Sirene hat jetzt Target-Optionen (Reparieren, Abmontieren).
- Delta-Sync: nur neue/entfernte Geräte werden übertragen.
- Blink-Thread nutzt Maps statt O(n) Iteration.
- Alarmstatus überlebt Server-Restart (Status aus DB).
- Job-Check auf `registerDevice` und `quittieren`.
- Proximity-Check + Cooldown beim Pull-Alarm.

### v1.0.0
- Grundsystem: Ghost-Placement, Zonensystem, Panel, Rauch-/Handfeuermelder, Sirene.
- Wartungs-Loop mit Health-Degradierung.
- QBCore/QBX Kompatibilität.