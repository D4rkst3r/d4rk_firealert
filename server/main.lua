-- d4rk_firealert: server/main.lua
local ActiveSystems  = {}
local AlarmCooldowns = {}  -- FIX #2: { [src] = os.time() } für Spam-Schutz
local dbReady        = false
local pendingSyncs   = {}  -- FIX #9: Clients die requestSync vor MySQL.ready schickten

---------------------------------------------------------
-- Initialisierung
---------------------------------------------------------

MySQL.ready(function()
    -- FIX #8: Status aus DB laden — vorher wurde immer 'normal' gesetzt
    -- und ein laufender Alarm vor einem Restart ging verloren
    local results = db.getAllSystems()
    if results then
        for _, system in ipairs(results) do
            if type(system.coords) == "string" then
                system.coords = json.decode(system.coords)
            end
            ActiveSystems[system.id] = system
            -- system.status kommt direkt aus der DB (normal / alarm / trouble)
        end
        print(("^2[d4rk_firealert] %s Brandschutzsysteme geladen.^7"):format(#results))
    end

    dbReady = true

    -- FIX #9: Alle Clients die während MySQL.ready gewartet haben jetzt syncen
    for _, src in ipairs(pendingSyncs) do
        SyncDevices(src)
    end
    pendingSyncs = {}
end)

---------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------

function SyncDevices(target)
    local devices = db.getAllDevices()
    if devices then
        TriggerClientEvent('d4rk_firealert:client:loadInitialDevices', target, devices)
    end
end

---------------------------------------------------------
-- Spieler-Sync
---------------------------------------------------------

-- FIX #9: requestSync ohne Wait(1000) auf Client-Seite
-- Server entscheidet ob sofort oder nach DB-Init gesynct wird
RegisterNetEvent('d4rk_firealert:server:requestSync', function()
    local src = source
    if dbReady then
        SyncDevices(src)
    else
        -- DB noch nicht bereit — in Queue packen
        table.insert(pendingSyncs, src)
    end
end)

RegisterNetEvent('QBCore:Server:PlayerLoaded', function(Player)
    SyncDevices(Player.PlayerData.source)
end)

AddEventHandler('qbx_core:clientLoaded', function()
    SyncDevices(source)
end)

---------------------------------------------------------
-- Device registrieren
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:registerDevice', function(deviceType, coords, rot, zone, systemName, manualId)
    local src      = source
    local systemId = manualId

    if deviceType == "panel" then
        systemId = db.createSystem(systemName or 'Gebäude BMA', coords)
        ActiveSystems[systemId] = {
            id     = systemId,
            name   = systemName or 'Gebäude BMA',
            coords = coords,
            status = 'normal'
        }
    end

    if not systemId then
        return TriggerClientEvent('ox_lib:notify', src, {
            title       = 'BMA Fehler',
            description = 'Kein aktives System ausgewählt! Starte erst die Wartung am Panel.',
            type        = 'error'
        })
    end

    -- FIX #6: Delta-Sync — nur das neue Gerät an alle senden statt komplette Liste
    local newId = db.addDevice(systemId, deviceType, coords, rot, zone)
    if newId then
        local newDevice = {
            id        = newId,
            system_id = systemId,
            type      = deviceType,
            coords    = json.encode(coords),
            rotation  = json.encode(rot),
            zone      = zone,
            health    = 100
        }
        TriggerClientEvent('d4rk_firealert:client:addDevice', -1, newDevice)
    end
end)

---------------------------------------------------------
-- Alarm auslösen
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:triggerAlarm', function(systemId, zone, deviceCoords)
    local src = source
    local id  = tonumber(systemId)

    if not ActiveSystems[id] then return end

    -- FIX #2: Cooldown-Check — verhindert Alarm-Spam
    local now = os.time()
    if AlarmCooldowns[src] and (now - AlarmCooldowns[src]) < 30 then
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'BMA',
            description = 'Bitte warte kurz vor dem nächsten Alarm.',
            type        = 'error'
        })
        return
    end

    -- FIX #1: Proximity-Check — Spieler muss nah am Gerät sein
    -- Verhindert dass Cheater/Exploits Alarme aus der Ferne auslösen
    if deviceCoords then
        local playerPed    = GetPlayerPed(src)
        local playerCoords = GetEntityCoords(playerPed)
        local dist = #(playerCoords - vector3(deviceCoords.x, deviceCoords.y, deviceCoords.z))
        if dist > 5.0 then
            Utils.Log(("Spieler %s hat versucht Alarm aus %.1fm Entfernung auszulösen!"):format(src, dist))
            return
        end
    end

    AlarmCooldowns[src]  = now
    ActiveSystems[id].status = 'alarm'
    db.updateSystemStatus(id, 'alarm')

    TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, id, 'alarm')

    TriggerClientEvent('ox_lib:notify', -1, {
        title       = 'BMA ALARM: ' .. ActiveSystems[id].name,
        description = 'Auslöser: ' .. zone,
        type        = 'error',
        duration    = 10000
    })

    TriggerClientEvent('d4rk_firealert:client:playAlarmSound', -1, ActiveSystems[id].coords)
end)

---------------------------------------------------------
-- Alarm quittieren
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:quittieren', function(systemId)
    local src = source
    local id  = tonumber(systemId)

    if ActiveSystems[id] then
        ActiveSystems[id].status = 'normal'
        db.updateSystemStatus(id, 'normal')

        TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, id, 'normal')

        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'BMA',
            description = 'System wurde erfolgreich quittiert.',
            type        = 'success'
        })
    end
end)

---------------------------------------------------------
-- Gerät entfernen
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:removeDevice', function(coords)
    local src = source

    if not Utils.HasJobServer(src, Config.Job) then
        Utils.Log(("Spieler %s hat keine Berechtigung zum Entfernen!"):format(src))
        return
    end

    local devices    = db.getAllDevicesWithCoords()
    local idToDelete = nil

    if devices then
        for _, dev in ipairs(devices) do
            local devCoords = type(dev.coords) == "string" and json.decode(dev.coords) or dev.coords
            if devCoords then
                local dist = #(vector3(coords.x, coords.y, coords.z) - vector3(devCoords.x, devCoords.y, devCoords.z))
                if dist < 1.5 then
                    idToDelete = dev.id
                    break
                end
            end
        end
    end

    if idToDelete then
        local affectedRows = db.removeDevice(idToDelete)
        if affectedRows > 0 then
            -- FIX #6: Delta-Sync — nur die deviceId senden, Client löscht gezielt
            TriggerClientEvent('d4rk_firealert:client:removeDevice', -1, idToDelete)

            TriggerClientEvent('ox_lib:notify', src, {
                title       = 'BMA Demontage',
                description = 'Gerät erfolgreich entfernt.',
                type        = 'success'
            })
        end
    else
        Utils.Log(("Lösch-Fehler: Kein Gerät bei Coords %s gefunden."):format(json.encode(coords)))
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'Fehler',
            description = 'Gerät konnte in der Datenbank nicht identifiziert werden.',
            type        = 'error'
        })
    end
end)

---------------------------------------------------------
-- FIX #3: Gerät reparieren
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:repairDevice', function(deviceId)
    local src = source

    if not Utils.HasJobServer(src, Config.Job) then return end

    -- Item-Check falls konfiguriert
    if Config.Maintenance.RepairItem and Config.Maintenance.RepairItem ~= "" then
        local hasItem = false

        if GetResourceState('ox_inventory') == 'started' then
            hasItem = exports.ox_inventory:GetItem(src, Config.Maintenance.RepairItem, nil, true) ~= nil
            if hasItem then
                exports.ox_inventory:RemoveItem(src, Config.Maintenance.RepairItem, 1)
            end
        elseif GetResourceState('qb-inventory') == 'started' then
            local QBCore = exports['qb-core']:GetCoreObject()
            local Player = QBCore.Functions.GetPlayer(src)
            if Player then
                hasItem = Player.Functions.GetItemByName(Config.Maintenance.RepairItem) ~= nil
                if hasItem then
                    Player.Functions.RemoveItem(Config.Maintenance.RepairItem, 1)
                end
            end
        else
            -- Kein Inventory-System: Reparatur ohne Item erlauben
            hasItem = true
        end

        if not hasItem then
            TriggerClientEvent('ox_lib:notify', src, {
                title       = 'BMA Reparatur',
                description = 'Benötigt: ' .. Config.Maintenance.RepairItem,
                type        = 'error'
            })
            return
        end
    end

    db.updateDeviceHealth(deviceId, 100)

    -- FIX #3: Delta-Update — Health ohne vollen Resync aktualisieren
    TriggerClientEvent('d4rk_firealert:client:updateDeviceHealth', -1, deviceId, 100)

    -- Trouble-Status zurücksetzen falls alle Geräte des Systems repariert sind
    local device = db.getDeviceById(deviceId)
    if device then
        local troubled = db.getTroubledDevices()
        local stillTroubled = false
        if troubled then
            for _, row in ipairs(troubled) do
                if row.system_id == device.system_id then
                    stillTroubled = true
                    break
                end
            end
        end
        if not stillTroubled and ActiveSystems[device.system_id] and ActiveSystems[device.system_id].status == 'trouble' then
            ActiveSystems[device.system_id].status = 'normal'
            db.updateSystemStatus(device.system_id, 'normal')
            TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, device.system_id, 'normal')
        end
    end

    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'BMA Reparatur',
        description = 'Gerät erfolgreich auf 100% repariert.',
        type        = 'success'
    })
end)

---------------------------------------------------------
-- FIX #4: Wartungs-Loop mit DegradeChance und vollständiger Trouble-Logik
---------------------------------------------------------

CreateThread(function()
    while true do
        Wait(Config.Maintenance.CheckInterval * 60000)

        -- FIX #4: Config.Maintenance.DegradeChance wird jetzt tatsächlich genutzt
        -- Vorher: immer 2 Geräte degradiert, DegradeChance wurde komplett ignoriert
        local allDevices = db.getAllDevices()
        if allDevices then
            for _, dev in ipairs(allDevices) do
                if dev.health > 0 and math.random(1, 100) <= Config.Maintenance.DegradeChance then
                    local newHealth = math.max(0, dev.health - 10)
                    db.updateDeviceHealth(dev.id, newHealth)
                    -- Client über Health-Änderung informieren (Delta-Update)
                    TriggerClientEvent('d4rk_firealert:client:updateDeviceHealth', -1, dev.id, newHealth)
                end
            end
        end

        -- FIX #4: Trouble-Status für Systeme mit kritischen Geräten setzen
        local troubledSystems = db.getTroubledDevices()
        if troubledSystems then
            for _, row in ipairs(troubledSystems) do
                local sId = row.system_id
                if ActiveSystems[sId] and ActiveSystems[sId].status == 'normal' then
                    ActiveSystems[sId].status = 'trouble'
                    db.updateSystemStatus(sId, 'trouble')
                    TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, sId, 'trouble')
                    Utils.Log(("System %s → 'trouble' (Gerät unter 20%% Health)"):format(sId))
                end
            end
        end
    end
end)

---------------------------------------------------------
-- Test Command
---------------------------------------------------------

RegisterCommand('test_bma', function(source, args)
    local src = source
    if not Utils.HasJobServer(src, Config.Job) then return end

    local systemId = tonumber(args[1])
    if not systemId or not ActiveSystems[systemId] then
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'Fehler',
            description = 'Ungültige System-ID',
            type        = 'error'
        })
        return
    end

    TriggerClientEvent('ox_lib:notify', -1, {
        title       = 'BMA PROBEALARM: ' .. ActiveSystems[systemId].name,
        description = 'Dies ist eine geplante Wartung / Test.',
        type        = 'inform',
        duration    = 5000
    })

    TriggerClientEvent('d4rk_firealert:client:playAlarmSound', -1, ActiveSystems[systemId].coords)
end)