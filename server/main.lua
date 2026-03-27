-- d4rk_firealert: server/main.lua
local ActiveSystems  = {}
local AlarmCooldowns = {}  -- { [src] = os.time() }
local dbReady        = false
local pendingSyncs   = {}  -- { [src] = true } — FIX #2: Set statt Array (kein Duplikat möglich)

-- FIX #8: Echter Zufalls-Seed damit Degradierung nach Restart nicht deterministisch ist
math.randomseed(os.time())

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
        end
        print(("^2[d4rk_firealert] %s Brandschutzsysteme geladen (v%s).^7"):format(#results, Config.Version))
    end

    dbReady = true

    -- FIX #2: pendingSyncs ist jetzt ein Set { [src] = true } — kein Duplikat möglich
    for src in pairs(pendingSyncs) do
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

-- Dispatch-Benachrichtigung je nach konfiguriertem System
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
            job_table = { Config.Job },
            coords    = coords,
            message   = title .. ' | ' .. desc,
            code      = Config.Dispatch.Code,
            icon      = Config.Dispatch.Icon,
        })

    else
        -- Fallback: nur Feuerwehr-Spieler benachrichtigen
        for _, playerId in ipairs(GetPlayers()) do
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
    local troubled      = db.getTroubledDevices()
    local stillTroubled = false

    if troubled then
        for _, row in ipairs(troubled) do
            if row.system_id == systemId then
                stillTroubled = true
                break
            end
        end
    end

    if not stillTroubled
    and ActiveSystems[systemId]
    and ActiveSystems[systemId].status == 'trouble' then
        ActiveSystems[systemId].status = 'normal'
        db.updateSystemStatus(systemId, 'normal')
        TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, systemId, 'normal')
        Utils.Log(("System #%s: Trouble aufgehoben."):format(systemId))
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
        -- FIX #2: Set-Eintrag statt table.insert — verhindert Doppel-Sync bei mehrfachem requestSync
        pendingSyncs[src] = true
        Utils.Log(("Spieler %s hat requestSync vor DB-Ready geschickt — wird nachgeholt."):format(src))

        -- FIX #6: Client informieren dass der Sync aussteht
        TriggerClientEvent('ox_lib:notify', src, {
            title       = 'BMA',
            description = 'Server wird initialisiert, Geräte werden gleich geladen...',
            type        = 'inform',
            duration    = 3000
        })
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

-- FIX #10: lib.addCommand für ACE-Integration statt RegisterCommand
lib.addCommand('install_bma', {
    help   = 'BMA Gerät installieren (panel/smoke/pull/siren)',
    params = {
        { name = 'type', type = 'string', help = 'Gerätetyp: panel, smoke, pull, siren' }
    },
    restricted = false -- Job-Check passiert clientseitig + serverseitig
}, function(source, args)
    -- Dieser Callback läuft serverseitig, aber /install_bma öffnet nur den Client-Placement-Modus
    -- Der eigentliche Job-Check passiert in registerDevice unten
end)

RegisterNetEvent('d4rk_firealert:server:registerDevice', function(deviceType, coords, rot, zone, systemName, manualId)
    local src = source

    if not Utils.HasJobServer(src, Config.Job) then
        Utils.Log(("Spieler %s hat versucht ein Gerät ohne Job zu installieren!"):format(src))
        return TriggerClientEvent('ox_lib:notify', src, {
            title = 'BMA Fehler', description = 'Keine Berechtigung.', type = 'error'
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
    if ActiveSystems[id].status == 'alarm' then return end

    -- FIX #1: triggerType 'automatic' darf NICHT vom Client kommen
    -- Ein Cheater könnte sonst Proximity- und Cooldown-Check umgehen
    -- Automatische Alarme werden intern vom Server via separatem Event ausgelöst
    local isAutomatic = false  -- Immer false wenn vom Client — Server setzt das selbst
    local isTriggerAutomatic = (triggerType == 'automatic')

    if isTriggerAutomatic then
        -- Client hat 'automatic' gesendet — als manuell behandeln (Cheating-Versuch)
        Utils.Log(("Spieler %s hat triggerType='automatic' gesendet — wird als manuell behandelt!"):format(src))
    end

    -- Proximity-Check für alle Client-seitigen Trigger
    if deviceCoords then
        local playerCoords = GetEntityCoords(GetPlayerPed(src))
        local dist = #(playerCoords - vector3(deviceCoords.x, deviceCoords.y, deviceCoords.z))
        if dist > 5.0 then
            Utils.Log(("Spieler %s hat Alarm aus %.1fm versucht (max. 5m) — blockiert."):format(src, dist))
            return
        end
    end

    -- Cooldown-Check für alle Client-seitigen Trigger
    local now = os.time()
    if AlarmCooldowns[src] and (now - AlarmCooldowns[src]) < 30 then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'BMA', description = 'Bitte warte kurz vor dem nächsten Alarm.', type = 'error'
        })
        return
    end
    AlarmCooldowns[src] = now

    TriggerAlarm(id, zone, 'manual')
end)

-- FIX #1: Internes Server-Event für automatische Rauchmelder-Alarme
-- Wird NUR vom Server selbst aufgerufen (nicht über das Netzwerk erreichbar)
function TriggerAlarm(systemId, zone, triggerType)
    if not ActiveSystems[systemId] then return end
    if ActiveSystems[systemId].status == 'alarm' then return end

    ActiveSystems[systemId].status = 'alarm'
    db.updateSystemStatus(systemId, 'alarm')
    db.logAlarm(systemId, ActiveSystems[systemId].name, zone, triggerType)

    TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, systemId, 'alarm')

    TriggerClientEvent('ox_lib:notify', -1, {
        title       = '🚨 BMA ALARM: ' .. ActiveSystems[systemId].name,
        description = 'Auslöser: ' .. zone,
        type        = 'error',
        duration    = 10000
    })

    TriggerClientEvent('d4rk_firealert:client:playAlarmSound', -1, ActiveSystems[systemId].coords)
    SendDispatch(systemId, zone, ActiveSystems[systemId].coords)
end

-- FIX #1: Separates Server-Event für automatische Alarme vom Client
-- Client sendet dieses Event wenn ein Rauchmelder Feuer erkennt
-- Server prüft Plausibilität und ruft TriggerAlarm intern auf
RegisterNetEvent('d4rk_firealert:server:triggerAutoAlarm', function(systemId, zone, smokeCoords)
    local src = source
    local id  = tonumber(systemId)

    if not ActiveSystems[id] then return end
    if ActiveSystems[id].status == 'alarm' then return end

    -- Plausibilitätscheck: Spieler muss sich in der Nähe des Rauchmelders befinden
    -- (verhindert dass jemand remote automatische Alarme für beliebige Systeme auslöst)
    if smokeCoords then
        local playerCoords = GetEntityCoords(GetPlayerPed(src))
        local dist = #(playerCoords - vector3(smokeCoords.x, smokeCoords.y, smokeCoords.z))
        -- Großzügigerer Radius (50m) — Spieler muss im Gebäude sein, nicht direkt am Melder
        if dist > 50.0 then
            Utils.Log(("AutoAlarm von Spieler %s aus %.1fm Distanz blockiert."):format(src, dist))
            return
        end
    end

    TriggerAlarm(id, zone, 'automatic')
end)

---------------------------------------------------------
-- Alarm quittieren
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:quittieren', function(systemId)
    local src = source
    local id  = tonumber(systemId)

    if not Utils.HasJobServer(src, Config.Job) then
        Utils.Log(("Spieler %s hat versucht Alarm ohne Job zu quittieren!"):format(src))
        return TriggerClientEvent('ox_lib:notify', src, {
            title = 'BMA Fehler', description = 'Nur Feuerwehr kann Alarme quittieren.', type = 'error'
        })
    end

    if not ActiveSystems[id] then return end

    ActiveSystems[id].status = 'normal'
    db.updateSystemStatus(id, 'normal')
    db.logAcknowledge(id, GetPlayerName(src) or tostring(src))

    TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, id, 'normal')
    TriggerClientEvent('ox_lib:notify', src, {
        title = 'BMA', description = 'System wurde erfolgreich quittiert.', type = 'success'
    })
end)

---------------------------------------------------------
-- Gerät entfernen
---------------------------------------------------------

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
            title = 'BMA Demontage', description = 'Gerät erfolgreich entfernt.', type = 'success'
        })
    else
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'Fehler', description = 'Gerät konnte nicht entfernt werden.', type = 'error'
        })
    end
end)

---------------------------------------------------------
-- Gerät reparieren
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:repairDevice', function(deviceId)
    local src = source

    if not Utils.HasJobServer(src, Config.Job) then return end

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
            hasItem = true
        end

        if not hasItem then
            return TriggerClientEvent('ox_lib:notify', src, {
                title = 'BMA Reparatur', description = 'Benötigt: ' .. repairItem, type = 'error'
            })
        end
    end

    db.updateDeviceHealth(deviceId, 100)
    TriggerClientEvent('d4rk_firealert:client:updateDeviceHealth', -1, deviceId, 100)

    local device = db.getDeviceById(deviceId)
    if device then CheckAndClearTrouble(device.system_id) end

    TriggerClientEvent('ox_lib:notify', src, {
        title = 'BMA Reparatur', description = 'Gerät auf 100% repariert.', type = 'success'
    })
end)

---------------------------------------------------------
-- Alarm-Log abrufen
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:getAlarmLog', function(systemId)
    local src = source
    if not Utils.HasJobServer(src, Config.Job) then return end

    local log = db.getAlarmLog(systemId, 10)
    TriggerClientEvent('d4rk_firealert:client:receiveAlarmLog', src, log)
end)

---------------------------------------------------------
-- Wartungs-Loop (FIX #8: math.randomseed bereits am Anfang gesetzt)
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
-- Test Command (FIX #10: lib.addCommand für ACE)
---------------------------------------------------------

lib.addCommand('test_bma', {
    help   = 'BMA Probealarm auslösen',
    params = {
        { name = 'systemId', type = 'number', help = 'System-ID' }
    },
    restricted = 'group.admin'
}, function(source, args)
    local src      = source
    local systemId = args.systemId

    if not Utils.HasJobServer(src, Config.Job) then return end
    if not ActiveSystems[systemId] then
        return TriggerClientEvent('ox_lib:notify', src, {
            title = 'Fehler', description = 'Ungültige System-ID', type = 'error'
        })
    end

    db.logAlarm(systemId, ActiveSystems[systemId].name, 'Probealarm', 'test')

    TriggerClientEvent('ox_lib:notify', -1, {
        title       = 'BMA PROBEALARM: ' .. ActiveSystems[systemId].name,
        description = 'Dies ist eine geplante Wartung / Test.',
        type        = 'inform',
        duration    = 5000
    })

    TriggerClientEvent('d4rk_firealert:client:playAlarmSound', -1, ActiveSystems[systemId].coords)
end)