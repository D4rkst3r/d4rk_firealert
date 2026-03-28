-- d4rk_firealert: config.lua
Config = {}
Config.Framework = "qbx"
Config.Job       = "firefighter"

Config.Debug   = true
Config.Version = "2.4.0"

Config.Maintenance = {
    DegradeChance = 5,   -- % Chance pro Check dass ein Gerät Health verliert
    CheckInterval = 30,  -- Minuten zwischen automatischen Health-Checks
    RepairItem    = "repairkit"  -- "" = kein Item nötig
}

-- NEU: Wie viele Tage zwischen Pflichtinspektionen liegen.
-- Nach dieser Zeit wird das Gerät automatisch auf 'trouble' gesetzt.
-- Wird beim Einbau und nach jeder Reparatur neu gesetzt.
Config.ServiceInterval = 30  -- Tage

Config.AutoSmoke = {
    Enabled       = true,
    CheckRadius   = 8.0,   -- Meter um den Rauchmelder in denen nach Feuer gesucht wird
    CheckInterval = 5,     -- Sekunden zwischen Prüfungen
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

-- NEU: Sprinkleranlage
Config.Sprinkler = {
    -- GTA-Partikel-Dictionary und -Effektname für den Wasserstrahl.
    -- "ent_ray_fire_sprinkler" aus "core" ist der native GTA-Sprinkler-Effekt.
    ParticleDict   = "core",
    ParticleEffect = "ent_ray_fire_sprinkler",
    ParticleScale  = 1.5,    -- Größe des Partikel-Effekts

    -- Radius in dem Feuer gelöscht wird (RemoveAllFiresInRange)
    ExtinguishRadius   = 4.0,
    -- Millisekunden zwischen Lösch-Checks (zu niedrig = Performance-Hit)
    ExtinguishInterval = 2000,
}

-- NEU: Sabotage-Detection
Config.Sabotage = {
    -- Dauer der Sabotage-Aktion in Millisekunden (Progressbar)
    ActionDuration  = 8000,
    -- Health-Verlust durch eine Sabotage-Aktion
    HealthDamage    = 50,
    -- Maximale Distanz in Metern vom Gerät bei der Sabotage möglich ist
    MaxDistance     = 2.0,
    -- Cooldown in Sekunden zwischen Sabotage-Aktionen pro Spieler
    Cooldown        = 60,
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
    },
    -- NEU: Sprinkleranlage
    -- Prop-Modell: prop_water_pipe_dist ist ein Wasser-Rohr/Düsen-Prop.
    -- Bei Bedarf durch ein passendes MLO-spezifisches Prop ersetzen.
    ["sprinkler"] = {
        label = "Sprinkleranlage",
        model = `v_ret_gc_sprinkler`,
        price = 800
    },
}