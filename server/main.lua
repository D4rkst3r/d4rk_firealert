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
            ActiveSystems[system.id].status = 'normal' -- Standardstatus
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

-- Sync beim Joinen
RegisterNetEvent('QBCore:Server:PlayerLoaded', function(Player)
    SyncDevices(Player.PlayerData.source)
end)

AddEventHandler('qbx_core:clientLoaded', function()
    SyncDevices(source)
end)

-- Device registrieren (Update mit manualId für Wartungsmodus)
RegisterNetEvent('d4rk_firealert:server:registerDevice', function(type, coords, rot, zone, systemName, manualId)
    local src = source
    local systemId = manualId -- Die ID, die der Techniker am Panel ausgewählt hat

    -- Wenn ein Panel gesetzt wird, neues System in fire_systems erstellen
    if type == "panel" then
        systemId = MySQL.insert.await('INSERT INTO fire_systems (name, coords) VALUES (?, ?)', {
            systemName, json.encode(coords)
        })
        ActiveSystems[systemId] = { id = systemId, name = systemName, coords = coords, status = 'normal' }
    end

    -- Sicherheitscheck: Wenn kein Panel im Wartungsmodus ist und kein neues Panel gebaut wird
    if not systemId then
        return TriggerClientEvent('ox_lib:notify', src, {
            title = 'BMA Fehler', 
            description = 'Kein aktives System ausgewählt! Starte erst die Wartung am Panel.', 
            type = 'error'
        })
    end

    -- Gerät speichern und fest mit der systemId verknüpfen
    MySQL.insert.await('INSERT INTO fire_devices (system_id, type, coords, rotation, zone) VALUES (?, ?, ?, ?, ?)', {
        systemId, type, json.encode(coords), json.encode(rot), zone
    })

    SyncDevices(-1) -- Sofortiger Sync an alle
end)

-- Alarm auslösen
RegisterNetEvent('d4rk_firealert:server:triggerAlarm', function(systemId, zone)
    local id = tonumber(systemId)
    if not ActiveSystems[id] then return end
    
    ActiveSystems[id].status = 'alarm'

    -- Visuelles Update an alle (Panel blinken lassen)
    TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, id, 'alarm')

    TriggerClientEvent('ox_lib:notify', -1, {
        title = 'BMA ALARM: ' .. ActiveSystems[id].name,
        description = 'Auslöser: ' .. zone,
        type = 'error',
        duration = 10000
    })

    TriggerClientEvent('d4rk_firealert:client:playAlarmSound', -1, ActiveSystems[id].coords)
end)

-- Alarm quittieren (Reset)
RegisterNetEvent('d4rk_firealert:server:quittieren', function(systemId)
    local src = source
    local id = tonumber(systemId)
    
    if ActiveSystems[id] then
        ActiveSystems[id].status = 'normal'
        -- Visuelles Update an alle (Blinken stoppen)
        TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, id, 'normal')
        
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'BMA', 
            description = 'System wurde erfolgreich quittiert.', 
            type = 'success'
        })
    end
end)

-- Gerät entfernen
RegisterNetEvent('d4rk_firealert:server:removeDevice', function(coords)
    local src = source
    if not Utils.HasJob(Config.Job) then return end

    -- Wir nutzen einen "Range"-Check statt math.floor, um ungenaue Floats abzufangen
    -- Wir suchen nach Einträgen, die in der Nähe der Klicks sind
    local xMin, xMax = coords.x - 0.5, coords.x + 0.5
    local yMin, yMax = coords.y - 0.5, coords.y + 0.5

    -- Wir holen erst alle Geräte und filtern in Lua (sicherer als LIKE bei JSON)
    local devices = MySQL.query.await('SELECT id, coords FROM fire_devices')
    local idToDelete = nil

    if devices then
        for _, dev in ipairs(devices) do
            local devCoords = type(dev.coords) == "string" and json.decode(dev.coords) or dev.coords
            if devCoords then
                -- Check ob die Koordinate nah genug dran ist (Distanz-Check)
                local dist = #(vector3(coords.x, coords.y, coords.z) - vector3(devCoords.x, devCoords.y, devCoords.z))
                if dist < 1.5 then
                    idToDelete = dev.id
                    break
                end
            end
        end
    end

    if idToDelete then
        local affectedRows = MySQL.update.await('DELETE FROM fire_devices WHERE id = ?', { idToDelete })
        if affectedRows > 0 then
            TriggerClientEvent('ox_lib:notify', src, {
                title = 'BMA Demontage', 
                description = 'Gerät erfolgreich entfernt.', 
                type = 'success'
            })
            SyncDevices(-1)
        end
    else
        print(("^1[d4rk_firealert] Lösch-Fehler: Kein Gerät bei Coords %s gefunden.^7"):format(coords))
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Fehler', 
            description = 'Gerät konnte in der Datenbank nicht identifiziert werden.', 
            type = 'error'
        })
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