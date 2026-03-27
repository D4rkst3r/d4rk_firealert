Config = {}
Config.Framework = "qbx" -- "qbx" oder "qbcore"
Config.Job = "fire"      -- Jobname der Feuerwehr

Config.Debug = true      -- Zeigt Marker und Prints in der Konsole

Config.Maintenance = {
    DegradeChance = 5,             -- 5% Chance pro Check auf Defekt
    CheckInterval = 30,            -- Alle X Minuten wird auf Defekte geprüft
    RepairItem = "electronics_kit" -- Item für die Reparatur (optional)
}

Config.Devices = {
    ["panel"] = {
        label = "BMA Zentrale",
        model = `prop_ops_industrial_01`,
        price = 5000
    },
    ["smoke"] = {
        label = "Rauchmelder",
        model = `prop_fire_alarm_04`,
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
