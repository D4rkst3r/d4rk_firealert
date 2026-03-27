Config = {}
Config.Framework = "qbx"    -- "qbx" oder "qbcore"
Config.Job       = "firefighter"

Config.Debug = true

Config.Maintenance = {
    DegradeChance = 5,              -- % Chance pro Check dass ein Gerät degradiert
    CheckInterval = 30,             -- Alle X Minuten
    RepairItem    = "electronics_kit"
}

-- FIX #7: Version angepasst
Config.Version = "2.0.0"

-- Automatische Rauchmelder-Auslösung (#1)
Config.AutoSmoke = {
    Enabled      = true,   -- Rauchmelder reagieren auf GTA-Feuer in der Nähe
    CheckRadius  = 8.0,    -- Radius in Metern um den Rauchmelder
    CheckInterval = 5,     -- Sekunden zwischen Checks (pro Melder)
}

-- Dispatch-Integration (#3)
Config.Dispatch = {
    Enabled = true,
    -- Unterstützte Systeme: "ps-dispatch", "cd_dispatch", "ox_lib" (nur Notify), "none"
    System  = "ps-dispatch",
    Code    = "10-70",     -- Einsatz-Code der in der Dispatch-Meldung erscheint
    Icon    = "fas fa-fire-extinguisher",
    Color   = "#e74c3c",   -- Farbe des Dispatch-Markers
}

Config.Devices = {
    ["panel"] = {
        label = "Fire Alarm Panel",
        model = `m23_1_prop_m31_controlpanel_02a`,
        price = 5000
    },
    ["smoke"] = {
        label = "Rauchmelder",
        model = `prop_fire_alarm_03`,
        price = 450
    },
    ["pull"] = {
        label = "Handfeuermelder",
        model = `prop_fire_alarm_01`,
        price = 200
    },
    ["siren"] = {
        label = "Alarmsirene",
        model = `prop_fire_alarm_02`,
        price = 600
    }
}