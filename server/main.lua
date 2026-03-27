local ActiveSystems = {}

-- Initialisierung beim Serverstart
MySQL.ready(function()
    local results = MySQL.query.await('SELECT * FROM fire_systems')
    if results then
        for _, system in ipairs(results) do
            system.coords = json.decode(system.coords)
            ActiveSystems[system.id] = system
        end
    end
    print("^2[d4rk_firealert] System erfolgreich geladen.^7")
end)

-- Hilfsfunktion: Schickt einem Spieler (oder allen) alle aktuellen Geräte
local function SyncDevices(target)
    local devices = MySQL.query.await('SELECT * FROM fire_devices')
    TriggerClientEvent('d4rk_firealert:client:loadInitialDevices', target, devices)
end

-- Sync beim Joinen (QBX / QBCore)
RegisterNetEvent('QBCore:Server:PlayerLoaded', function(Player)
    SyncDevices(Player.PlayerData.source)
end)

-- Device registrieren
RegisterNetEvent('d4rk_firealert:server:registerDevice', function(type, coords, rot, zone, systemName)
    local src = source
    local systemId = nil

    if type == "panel" then
        systemId = MySQL.insert.await('INSERT INTO fire_systems (name, coords) VALUES (?, ?)', {
            systemName, json.encode(coords)
        })
        ActiveSystems[systemId] = { id = systemId, name = systemName, coords = coords, status = 'normal' }

        MySQL.insert.await('INSERT INTO fire_devices (system_id, type, coords, rotation, zone) VALUES (?, ?, ?, ?, ?)', {
            systemId, type, json.encode(coords), json.encode(rot), zone
        })
    else
        systemId = MySQL.scalar.await('SELECT id FROM fire_systems ORDER BY id DESC LIMIT 1')
        if systemId then
            MySQL.insert.await('INSERT INTO fire_devices (system_id, type, coords, rotation, zone) VALUES (?, ?, ?, ?, ?)', {
                systemId, type, json.encode(coords), json.encode(rot), zone
            })
        end
    end

    -- WICHTIG: Sofortiger Sync an alle, damit das Prop erscheint
    SyncDevices(-1)
end)

-- Alarm auslösen
RegisterNetEvent('d4rk_firealert:server:triggerAlarm', function(systemId, zone)
    if not ActiveSystems[systemId] then return end
    ActiveSystems[systemId].status = 'alarm'

    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'BMA ALARM: ' .. ActiveSystems[systemId].name,
        description = 'Auslöser: ' .. zone,
        type = 'error',
        duration = 10000
    })

    TriggerClientEvent('d4rk_firealert:client:playAlarmSound', -1, ActiveSystems[systemId].coords)
end)

-- Wartungs-Loop
CreateThread(function()
    while true do
        Wait(Config.Maintenance.CheckInterval * 60000)
        MySQL.update('UPDATE fire_devices SET health = health - 5 WHERE health > 0 ORDER BY RAND() LIMIT 2')
    end
end)