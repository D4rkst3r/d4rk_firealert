# d4rk_firealert 🚒

Ein realistisches Brandmeldesystem für FiveM (Hardcore RP).

## Features

- **Ghost-Placement**: Visuelle Vorschau beim Platzieren von Meldern.
- **Zonensystem**: Räume können individuell benannt werden (z.B. "Küche EG").
- **Wartung**: Melder verlieren über Zeit an Haltbarkeit und müssen repariert werden.
- **Zentrale**: Steuerungseinheit für Alarmquittierung und Reset.

## Installation

1. `install.sql` in die Datenbank importieren.
2. `ensure d4rk_firealert` in die server.cfg schreiben.
3. In der `config.lua` den Job (z.B. 'fire') anpassen.

## Befehle

- `/install_bma [panel/smoke/pull/siren]` - Startet den Installationsmodus.
