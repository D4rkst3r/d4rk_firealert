-- d4rk_firealert: server/main.lua
local ActiveSystems  = {}
local AlarmCooldowns = {}  -- { [src] = os.time() }
local dbReady        = false
local pendingSyncs   = {}  -- Clients die requestSync vor MySQL.ready schickten

---------------------------------------------------------
-- Initialisierung
---------------------------------------------------------

MySQL.ready(function()
    local results = db.getAllSystems()
    if results then
        for _, system in ipairs(results) do
            if type(system.coords) == "string" then
                system.coords = json.decode(system.coords)
            end
            ActiveSystems[system.id] = system
            -- Status kommt direkt aus der DB (normal / alarm / trouble)
        end
        print(("^2[d4rk_firealert] %s Brandschutzsysteme geladen.^7"):format(#results))
    end

    dbReady = true

    -- Alle Clients syncen die während MySQL.ready gewartet haben
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

-- FIX #3: Dispatch-Benachrichtigung je nach konfiguriertem System
local function SendDispatch(systemId, zone, coords)
    if not Config.Dispatch.Enabled then return end

    local system = ActiveSystems[systemId]
    if not system then return end

    local title = Config.Dispatch.Code .. ' - Brandmeldung: ' .. system.name
    local desc  = 'Auslöser: ' .. zone

    local dispatchSystem = Config.Dispatch.System

    if dispatchSystem == "ps-dispatch" and GetResourceState('ps-dispatch') == 'started' then
        exports['ps-dispatch']:sendPoliceAlert({
            message       = title,
            detailMessage = desc,
            code          = Config.Dispatch.Code,
            icon          = Config.Dispatch.Icon,
            coords        = coords,
            jobs          = { Config.Job },
        })

    elseif dispatchSystem == "cd_dispatch" and GetResourceState('cd_dispatch') == 'started' then
        exports['cd_dispatch']:SendAlert({
            job_table  = { Config.Job },
            coords     = coords,
            message    = title .. ' | ' .. desc,
            code       = Config.Dispatch.Code,
            icon       = Config.Dispatch.Icon,
        })

    else
        -- Fallback: ox_lib Notify nur an Feuerwehr-Spieler
        local players = GetPlayers()
        for _, playerId in ipairs(players) do
            if Utils.HasJobServer(tonumber(playerId), Config.Job) then
                TriggerClientEvent('ox_lib:notify', tonumber(playerId), {
                    title       = title,
                    description = desc,
                    type        = 'error',
                    duration    = 15000
                })
            end
        end
    end
end

-- Trouble-Status für ein System prüfen und ggf. aufheben
local function CheckAndClearTrouble(systemId)
    local troubled = db.getTroubledDevices()
    local stillTroubled = false
    if troubled then
        for _, row in ipairs(troubled) do
            if row.system_id == systemId then
                stillTroubled = true
                break
            end
        end
    end
    if not stillTroubled and ActiveSystems[systemId] and ActiveSystems[systemId].status == 'trouble' then
        ActiveSystems[systemId].status = 'normal'
        db.updateSystemStatus(systemId, 'normal')
        TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, systemId, 'normal')
        Utils.Log(("System #%s: Trouble aufgehoben, alle Geräte repariert."):format(systemId))
    end
end

---------------------------------------------------------
-- Spieler-Sync
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:requestSync', function()
    local src = source
    if dbReady then
        SyncDevices(src)
    else
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
    local src = source

    -- FIX #8: Job-Check fehlte komplett — jeder konnte Geräte spawnen
    if not Utils.HasJobServer(src, Config.Job) then
        Utils.Log(("Spieler %s hat versucht ein Gerät ohne Job zu installieren!"):format(src))
        return TriggerClientEvent('ox_lib:notify', src, {
            title       = 'BMA Fehler',
            description = 'Du hast keine Berechtigung für diese Aktion.',
            type        = 'error'
        })
    end

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

    local newId = db.addDevice(systemId, deviceType, coords, rot, zone)
    if newId then
        TriggerClientEvent('d4rk_firealert:client:addDevice', -1, {
            id        = newId,
            system_id = systemId,
            type      = deviceType,
            coords    = json.encode(coords),
            rotation  = json.encode(rot),
            zone      = zone,
            health    = 100
        })
    end
end)

---------------------------------------------------------
-- Alarm auslösen
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:triggerAlarm', function(systemId, zone, deviceCoords, triggerType)
    local src = source
    local id  = tonumber(systemId)

    if not ActiveSystems[id] then return end
    if ActiveSystems[id].status == 'alarm' then return end -- Bereits im Alarm

    -- Proximity-Check (nur bei manuellen Alarmen, nicht bei automatischen)
    local isTriggerAutomatic = (triggerType == 'automatic')
    if not isTriggerAutomatic and deviceCoords then
        local playerCoords = GetEntityCoords(GetPlayerPed(src))
        local dist = #(playerCoords - vector3(deviceCoords.x, deviceCoords.y, deviceCoords.z))
        if dist > 5.0 then
            Utils.Log(("Spieler %s hat Alarm aus %.1fm versucht (max. 5m) — blockiert."):format(src, dist))
            return
        end
    end

    -- Cooldown-Check (nur manuelle Alarme)
    if not isTriggerAutomatic then
        local now = os.time()
        if AlarmCooldowns[src] and (now - AlarmCooldowns[src]) < 30 then
            TriggerClientEvent('ox_lib:notify', src, {
                title       = 'BMA',
                description = 'Bitte warte kurz vor dem nächsten Alarm.',
                type        = 'error'
            })
            return
        end
        AlarmCooldowns[src] = now
    end

    ActiveSystems[id].status = 'alarm'
    db.updateSystemStatus(id, 'alarm')

    -- FIX #2: Alarm loggen
    db.logAlarm(id, ActiveSystems[id].name, zone, isTriggerAutomatic and 'automatic' or 'manual')

    TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, id, 'alarm')

    TriggerClientEvent('ox_lib:notify', -1, {
        title       = '🚨 BMA ALARM: ' .. ActiveSystems[id].name,
        description = 'Auslöser: ' .. zone,
        type        = 'error',
        duration    = 10000
    })

    TriggerClientEvent('d4rk_firealert:client:playAlarmSound', -1, ActiveSystems[id].coords)

    -- FIX #3: Dispatch-Meldung an Feuerwehr senden
    SendDispatch(id, zone, ActiveSystems[id].coords)
end)

---------------------------------------------------------
-- Alarm quittieren
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:quittieren', function(systemId)
    local src = source
    local id  = tonumber(systemId)

    -- FIX #9: Job-Check fehlte — jeder Spieler konnte Alarme quittieren
    if not Utils.HasJobServer(src, Config.Job) then
        Utils.Log(("Spieler %s hat versucht Alarm ohne Job zu quittieren!"):format(src))
        return TriggerClientEvent('ox_lib:notify', src, {
            title       = 'BMA Fehler',
            description = 'Nur Feuerwehr kann Alarme quittieren.',
            type        = 'error'
        })
    end

    if not ActiveSystems[id] then return end

    ActiveSystems[id].status = 'normal'
    db.updateSystemStatus(id, 'normal')

    -- FIX #2: Quittierung im Log vermerken
    local playerName = GetPlayerName(src) or tostring(src)
    db.logAcknowledge(id, playerName)

    TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, id, 'normal')

    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'BMA',
        description = 'System wurde erfolgreich quittiert.',
        type        = 'success'
    })
end)

---------------------------------------------------------
-- Gerät entfernen
---------------------------------------------------------

-- FIX #6: Empfängt jetzt deviceId statt Coords — kein teurer Koordinaten-Scan mehr
RegisterNetEvent('d4rk_firealert:server:removeDevice', function(deviceId)
    local src = source

    if not Utils.HasJobServer(src, Config.Job) then
        Utils.Log(("Spieler %s hat keine Berechtigung zum Entfernen!"):format(src))
        return
    end

    if not deviceId then return end

    local affectedRows = db.removeDevice(deviceId)
    if affectedRows > 0 then
        TriggerClientEvent('d4rk_firealert:client:removeDevice', -1, deviceId)
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'BMA Demontage',
            description = 'Gerät erfolgreich entfernt.',
            type        = 'success'
        })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'Fehler',
            description = 'Gerät konnte nicht entfernt werden.',
            type        = 'error'
        })
    end
end)

---------------------------------------------------------
-- Gerät reparieren
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:repairDevice', function(deviceId)
    local src = source

    if not Utils.HasJobServer(src, Config.Job) then return end

    -- Item-Check
    local repairItem = Config.Maintenance.RepairItem
    if repairItem and repairItem ~= "" then
        local hasItem = false

        if GetResourceState('ox_inventory') == 'started' then
            hasItem = exports.ox_inventory:GetItem(src, repairItem, nil, true) ~= nil
            if hasItem then exports.ox_inventory:RemoveItem(src, repairItem, 1) end

        elseif GetResourceState('qb-inventory') == 'started' then
            local Player = exports['qb-core']:GetCoreObject().Functions.GetPlayer(src)
            if Player then
                hasItem = Player.Functions.GetItemByName(repairItem) ~= nil
                if hasItem then Player.Functions.RemoveItem(repairItem, 1) end
            end

        else
            hasItem = true -- Kein Inventory-System → Item-Check überspringen
        end

        if not hasItem then
            return TriggerClientEvent('ox_lib:notify', src, {
                title       = 'BMA Reparatur',
                description = 'Benötigt: ' .. repairItem,
                type        = 'error'
            })
        end
    end

    db.updateDeviceHealth(deviceId, 100)
    TriggerClientEvent('d4rk_firealert:client:updateDeviceHealth', -1, deviceId, 100)

    -- Trouble-Status prüfen
    local device = db.getDeviceById(deviceId)
    if device then
        CheckAndClearTrouble(device.system_id)
    end

    TriggerClientEvent('ox_lib:notify', src, {
        title       = 'BMA Reparatur',
        description = 'Gerät erfolgreich auf 100% repariert.',
        type        = 'success'
    })
end)

---------------------------------------------------------
-- Alarm-Log abrufen (für Panel-Menü)
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:getAlarmLog', function(systemId)
    local src = source
    if not Utils.HasJobServer(src, Config.Job) then return end

    local log = db.getAlarmLog(systemId, 10)
    TriggerClientEvent('d4rk_firealert:client:receiveAlarmLog', src, log)
end)

---------------------------------------------------------
-- Wartungs-Loop
---------------------------------------------------------

CreateThread(function()
    while true do
        Wait(Config.Maintenance.CheckInterval * 60000)

        local allDevices = db.getAllDevices()
        if allDevices then
            for _, dev in ipairs(allDevices) do
                if dev.health > 0 and math.random(1, 100) <= Config.Maintenance.DegradeChance then
                    local newHealth = math.max(0, dev.health - 10)
                    db.updateDeviceHealth(dev.id, newHealth)
                    TriggerClientEvent('d4rk_firealert:client:updateDeviceHealth', -1, dev.id, newHealth)
                    Utils.Log(("Gerät #%s degradiert → %s%%"):format(dev.id, newHealth))
                end
            end
        end

        local troubledSystems = db.getTroubledDevices()
        if troubledSystems then
            for _, row in ipairs(troubledSystems) do
                local sId = row.system_id
                if ActiveSystems[sId] and ActiveSystems[sId].status == 'normal' then
                    ActiveSystems[sId].status = 'trouble'
                    db.updateSystemStatus(sId, 'trouble')
                    TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, sId, 'trouble')
                    Utils.Log(("System #%s → 'trouble'"):format(sId))
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
        return TriggerClientEvent('ox_lib:notify', src, {
            title = 'Fehler', description = 'Ungültige System-ID', type = 'error'
        })
    end

    -- Test als eigenen Trigger-Typ loggen
    db.logAlarm(systemId, ActiveSystems[systemId].name, 'Probealarm', 'test')

    TriggerClientEvent('ox_lib:notify', -1, {
        title       = 'BMA PROBEALARM: ' .. ActiveSystems[systemId].name,
        description = 'Dies ist eine geplante Wartung / Test.',
        type        = 'inform',
        duration    = 5000
    })

    TriggerClientEvent('d4rk_firealert:client:playAlarmSound', -1, ActiveSystems[systemId].coords)
end)