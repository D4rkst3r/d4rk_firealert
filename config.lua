Config = {}
Config.Framework = "qbx"
Config.Job       = "firefighter"

Config.Debug   = true
Config.Version = "2.3.0"

Config.Maintenance = {
    DegradeChance = 5,
    CheckInterval = 30,
    RepairItem    = "electronics_kit"
}

Config.AutoSmoke = {
    Enabled       = true,
    CheckRadius   = 8.0,
    CheckInterval = 5,
}

Config.Dispatch = {
    Enabled = true,
    System  = "ps-dispatch",  -- "ps-dispatch" | "cd_dispatch" | "ox_lib" | "none"
    Code    = "10-70",
    Icon    = "fas fa-fire-extinguisher",
    Color   = "#e74c3c",
}

Config.Placement = {
    MaxDistance        = 4.0,   -- Maximale Platzierungsdistanz vom Spieler in Metern
    MinDistance        = 0.5,
    SystemSearchRadius = 50.0,  -- Radius in dem nach Panels gesucht wird (Option C)
}

Config.Interaction = {
    DistancePanel  = 2.0,  -- Interaktionsreichweite für Panels
    DistanceDevice = 1.5,  -- Interaktionsreichweite für Melder/Sirenen
}

-- Config.MDT entfernt — das Tablet läuft jetzt als eigenständige Resource d4rk_firemdt.
-- Den Computer-Prop für ox_target dort in d4rk_firemdt/config.lua konfigurieren.

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