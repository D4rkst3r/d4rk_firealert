local ActiveSystems = {}

-- Initialisierung beim Serverstart
MySQL.ready(function()
    local results = MySQL.query.await('SELECT * FROM fire_systems')
    if results then
        for _, system in ipairs(results) do
            if type(system.coords) == "string" then
                system.coords = json.decode(system.coords)
            end
            ActiveSystems[system.id] = system
        end
        print(("^2[d4rk_firealert] %s Brandschutzsysteme geladen.^7"):format(#results))
    end
end)

-- Hilfsfunktion: Schickt einem Spieler (oder allen) alle aktuellen Geräte
local function SyncDevices(target)
    local devices = MySQL.query.await('SELECT * FROM fire_devices')
    if devices then
        TriggerClientEvent('d4rk_firealert:client:loadInitialDevices', target, devices)
    end
end

-- Sync beim Joinen (QBX / QBCore / Standalone)
RegisterNetEvent('QBCore:Server:PlayerLoaded', function(Player)
    SyncDevices(Player.PlayerData.source)
end)

-- Falls du QBX nutzt:
AddEventHandler('qbx_core:clientLoaded', function()
    SyncDevices(source)
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

    SyncDevices(-1) -- Sofortiger Sync an alle
end)

-- Alarm auslösen
RegisterNetEvent('d4rk_firealert:server:triggerAlarm', function(systemId, zone)
    local id = tonumber(systemId)
    if not ActiveSystems[id] then return end
    
    ActiveSystems[id].status = 'alarm'

    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'BMA ALARM: ' .. ActiveSystems[id].name,
        description = 'Auslöser: ' .. zone,
        type = 'error',
        duration = 10000
    })

    TriggerClientEvent('d4rk_firealert:client:playAlarmSound', -1, ActiveSystems[id].coords)
end)

-- Gerät entfernen
RegisterNetEvent('d4rk_firealert:server:removeDevice', function(coords)
    local src = source
    if not Utils.HasJob(Config.Job) then return end

    local x = math.floor(coords.x)
    local y = math.floor(coords.y)
    
    -- Wir löschen basierend auf den ungefähren Koordinaten im JSON String
    local affectedRows = MySQL.update.await('DELETE FROM fire_devices WHERE coords LIKE ? AND coords LIKE ?', { 
        '%' .. x .. '%', 
        '%' .. y .. '%' 
    })

    if affectedRows and affectedRows > 0 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'BMA Demontage', 
            description = 'Gerät wurde erfolgreich entfernt.', 
            type = 'success'
        })
        SyncDevices(-1) -- Liste für alle aktualisieren
    else
        print("^1[d4rk_firealert] Fehler: Gerät beim Löschen nicht gefunden.^7")
    end
end)

-- Wartungs-Loop
CreateThread(function()
    while true do
        Wait(Config.Maintenance.CheckInterval * 60000)
        MySQL.update('UPDATE fire_devices SET health = health - 5 WHERE health > 0 ORDER BY RAND() LIMIT 2')
    end
end)

-- Test Command
RegisterCommand('test_bma', function(source, args)
    local src = source
    if not Utils.HasJob(Config.Job) then return end

    local systemId = tonumber(args[1])
    if not systemId or not ActiveSystems[systemId] then 
        TriggerClientEvent('ox_lib:notify', src, {title = 'Fehler', description = 'Ungültige System-ID', type = 'error'})
        return 
    end

    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'BMA PROBEALARM: ' .. ActiveSystems[systemId].name,
        description = 'Dies ist eine geplante Wartung / Test.',
        type = 'inform',
        duration = 5000
    })

    TriggerClientEvent('d4rk_firealert:client:playAlarmSound', -1, ActiveSystems[systemId].coords)
end)