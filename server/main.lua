-- d4rk_firealert: server/main.lua
local ActiveSystems  = {}
local AlarmCooldowns = {}   -- { [src] = os.time() } — Cooldown für manuelle Alarme
local SabotageCooldowns = {} -- { [src] = os.time() } — Cooldown für Sabotage-Aktionen
local dbReady        = false
local pendingSyncs   = {}   -- { [src] = true } — Set: verhindert Doppel-Sync

-- Echter Zufalls-Seed damit Degradierung nach Restart nicht deterministisch ist
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

local function SendDispatch(systemId, zone, coords)
    if not Config.Dispatch.Enabled then return end

    local system = ActiveSystems[systemId]
    if not system then return end

    local title        = Config.Dispatch.Code .. ' - Brandmeldung: ' .. system.name
    local desc         = 'Auslöser: ' .. zone
    local dispatchSys  = Config.Dispatch.System

    if dispatchSys == "ps-dispatch" and GetResourceState('ps-dispatch') == 'started' then
        exports['ps-dispatch']:sendPoliceAlert({
            message       = title,
            detailMessage = desc,
            code          = Config.Dispatch.Code,
            icon          = Config.Dispatch.Icon,
            coords        = coords,
            jobs          = { Config.Job },
        })

    elseif dispatchSys == "cd_dispatch" and GetResourceState('cd_dispatch') == 'started' then
        exports['cd_dispatch']:SendAlert({
            job_table = { Config.Job },
            coords    = coords,
            message   = title .. ' | ' .. desc,
            code      = Config.Dispatch.Code,
            icon      = Config.Dispatch.Icon,
        })

    else
        -- Fallback: ox_lib Notify an alle Feuerwehr-Spieler
        for _, playerId in ipairs(GetPlayers()) do
            if Utils.HasJobServer(tonumber(playerId), Config.Job) then
                TriggerClientEvent('ox_lib:notify', tonumber(playerId), {
                    title = title, description = desc, type = 'error', duration = 15000
                })
            end
        end
    end
end

-- Trouble-Status aufheben wenn alle Geräte wieder gesund sind
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
        pendingSyncs[src] = true
        Utils.Log(("Spieler %s: requestSync vor DB-Ready — wird nachgeholt."):format(src))
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'BMA', description = 'Server initialisiert sich, Geräte folgen gleich...', type = 'inform', duration = 3000
        })
    end
end)

RegisterNetEvent('QBCore:Server:PlayerLoaded', function(Player)
    SyncDevices(Player.PlayerData.source)
end)

AddEventHandler('qbx_core:clientLoaded', function()
    SyncDevices(source)
end)

-- Cooldowns beim Disconnect bereinigen — verhindert Memory Leaks
AddEventHandler('playerDropped', function()
    AlarmCooldowns[source]    = nil
    SabotageCooldowns[source] = nil
end)

---------------------------------------------------------
-- Device registrieren
---------------------------------------------------------

RegisterCommand('install_bma', function() end, false)

RegisterNetEvent('d4rk_firealert:server:registerDevice', function(deviceType, coords, rot, zone, systemName, manualId)
    local src = source

    if not Utils.HasJobServer(src, Config.Job) then
        Utils.Log(("Spieler %s: Gerät ohne Job installiert!"):format(src))
        return TriggerClientEvent('ox_lib:notify', src, {
            title = 'BMA Fehler', description = 'Keine Berechtigung.', type = 'error'
        })
    end

    local systemId = manualId

    if deviceType == "panel" then
        systemId = db.createSystem(systemName or 'Gebäude BMA', coords)
        ActiveSystems[systemId] = {
            id = systemId, name = systemName or 'Gebäude BMA', coords = coords, status = 'normal'
        }
    end

    if not systemId then
        return TriggerClientEvent('ox_lib:notify', src, {
            title = 'BMA Fehler', description = 'Kein aktives System ausgewählt!', type = 'error'
        })
    end

    local newId = db.addDevice(systemId, deviceType, coords, rot, zone)
    if newId then
        -- NEU: Service-Datum direkt beim Einbau setzen
        db.resetServiceDate(newId, Config.ServiceInterval)

        local newDevice = db.getDeviceWithSystemName(newId)
        if newDevice then
            TriggerClientEvent('d4rk_firealert:client:addDevice', -1, newDevice)
        end
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

    if triggerType == 'automatic' then
        Utils.Log(("Spieler %s: triggerType='automatic' vom Client — wird als manuell behandelt."):format(src))
    end

    if deviceCoords then
        local playerCoords = GetEntityCoords(GetPlayerPed(src))
        local dist = #(playerCoords - vector3(deviceCoords.x, deviceCoords.y, deviceCoords.z))
        if dist > 5.0 then
            Utils.Log(("Spieler %s: Alarm aus %.1fm blockiert."):format(src, dist))
            return
        end
    end

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

-- Zentrale Alarm-Funktion — immer server-intern aufrufen, nie direkt per Event
function TriggerAlarm(systemId, zone, triggerType)
    if not ActiveSystems[systemId] then return end
    if ActiveSystems[systemId].status == 'alarm' then return end

    ActiveSystems[systemId].status = 'alarm'
    db.updateSystemStatus(systemId, 'alarm')
    db.logAlarm(systemId, ActiveSystems[systemId].name, zone, triggerType)

    TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, systemId, 'alarm')
    TriggerClientEvent('ox_lib:notify', -1, {
        title = '🚨 BMA ALARM: ' .. ActiveSystems[systemId].name,
        description = 'Auslöser: ' .. zone, type = 'error', duration = 10000
    })
    TriggerClientEvent('d4rk_firealert:client:playAlarmSound', -1, ActiveSystems[systemId].coords)
    SendDispatch(systemId, zone, ActiveSystems[systemId].coords)
end

RegisterNetEvent('d4rk_firealert:server:triggerAutoAlarm', function(systemId, zone, smokeCoords)
    local src = source
    local id  = tonumber(systemId)

    if not ActiveSystems[id] then return end
    if ActiveSystems[id].status == 'alarm' then return end
    if not smokeCoords then return end

    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    if #(playerCoords - vector3(smokeCoords.x, smokeCoords.y, smokeCoords.z)) > 50.0 then
        Utils.Log(("AutoAlarm Spieler %s: zu weit entfernt — blockiert."):format(src))
        return
    end

    local smokeDevices = db.getSmokeDevicesBySystem(id)
    local validDevice  = false
    if smokeDevices then
        for _, dev in ipairs(smokeDevices) do
            local c = type(dev.coords) == "string" and json.decode(dev.coords) or dev.coords
            if #(vector3(smokeCoords.x, smokeCoords.y, smokeCoords.z) - vector3(c.x, c.y, c.z)) <= 5.0 then
                validDevice = true
                break
            end
        end
    end

    if not validDevice then
        Utils.Log(("AutoAlarm Spieler %s: kein Rauchmelder von System #%s an Coords."):format(src, id))
        return
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
        title = 'BMA', description = 'System erfolgreich quittiert.', type = 'success'
    })
end)

---------------------------------------------------------
-- Gerät entfernen
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:removeDevice', function(deviceId)
    local src = source
    if not Utils.HasJobServer(src, Config.Job) then return end
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
    -- NEU: Nach Reparatur Service-Datum zurücksetzen
    db.resetServiceDate(deviceId, Config.ServiceInterval)

    TriggerClientEvent('d4rk_firealert:client:updateDeviceHealth', -1, deviceId, 100)

    local device = db.getDeviceById(deviceId)
    if device then CheckAndClearTrouble(device.system_id) end

    TriggerClientEvent('ox_lib:notify', src, {
        title = 'BMA Reparatur', description = 'Gerät repariert, Inspektion zurückgesetzt.', type = 'success'
    })
end)

---------------------------------------------------------
-- Alarm-Log abrufen (Panel-Menü in-world)
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:getAlarmLog', function(systemId)
    local src = source
    if not Utils.HasJobServer(src, Config.Job) then return end
    local log = db.getAlarmLog(systemId, 10)
    TriggerClientEvent('d4rk_firealert:client:receiveAlarmLog', src, log)
end)

---------------------------------------------------------
-- NEU: Sprinkleranlage manuell schalten
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:toggleSprinkler', function(deviceId, activate)
    local src = source

    -- Nur Feuerwehr darf Sprinkler manuell schalten
    if not Utils.HasJobServer(src, Config.Job) then
        return TriggerClientEvent('ox_lib:notify', src, {
            title = 'BMA', description = 'Nur Feuerwehr kann Sprinkler schalten.', type = 'error'
        })
    end

    -- Proximity-Check: Spieler muss am Sprinkler stehen
    local device = db.getDeviceById(deviceId)
    if not device then return end

    local devCoords    = type(device.coords) == "string" and json.decode(device.coords) or device.coords
    local playerCoords = GetEntityCoords(GetPlayerPed(src))
    local dist         = #(playerCoords - vector3(devCoords.x, devCoords.y, devCoords.z))

    if dist > 5.0 then
        Utils.Log(("Spieler %s: Sprinkler-Toggle aus %.1fm blockiert."):format(src, dist))
        return
    end

    -- An alle Clients broadcasten damit der Partikel-Effekt überall sichtbar ist
    TriggerClientEvent('d4rk_firealert:client:toggleSprinkler', -1, deviceId, activate)

    TriggerClientEvent('ox_lib:notify', src, {
        title = 'BMA Sprinkler',
        description = activate and 'Sprinkler aktiviert.' or 'Sprinkler deaktiviert.',
        type = 'inform'
    })

    Utils.Log(("Sprinkler #%s von Spieler %s %s."):format(deviceId, src, activate and 'aktiviert' or 'deaktiviert'))
end)

---------------------------------------------------------
-- NEU: Sabotage — Spieler beschädigt ein Gerät absichtlich
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:sabotageDevice', function(deviceId, deviceCoords)
    local src = source

    -- Cooldown-Check: verhindert Spam
    local now = os.time()
    if SabotageCooldowns[src] and (now - SabotageCooldowns[src]) < Config.Sabotage.Cooldown then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'BMA', description = 'Nicht so schnell...', type = 'error'
        })
        return
    end

    -- Proximity-Check: Client-Koordinaten gegen Server-Koordinaten validieren
    if deviceCoords then
        local playerCoords = GetEntityCoords(GetPlayerPed(src))
        local dist         = #(playerCoords - vector3(deviceCoords.x, deviceCoords.y, deviceCoords.z))

        if dist > (Config.Sabotage.MaxDistance + 2.0) then
            -- +2m Toleranz für Latenzschwankungen, danach hart blocken
            Utils.Log(("Sabotage Spieler %s: Gerät #%s aus %.1fm — blockiert."):format(src, deviceId, dist))
            return
        end
    end

    -- Gerät aus DB laden um aktuellen Health-Wert zu prüfen
    local device = db.getDeviceById(deviceId)
    if not device then return end

    -- Sabotage an Panels nicht erlauben (verhindert kompletten System-Ausfall durch einzelne Aktion)
    if device.type == 'panel' then
        TriggerClientEvent('ox_lib:notify', src, {
            title = 'BMA', description = 'Die Zentrale lässt sich nicht so einfach sabotieren.', type = 'error'
        })
        return
    end

    local healthBefore = device.health or 100
    local healthAfter  = math.max(0, healthBefore - Config.Sabotage.HealthDamage)

    -- Health in DB aktualisieren und alle Clients informieren
    db.updateDeviceHealth(deviceId, healthAfter)
    TriggerClientEvent('d4rk_firealert:client:updateDeviceHealth', -1, deviceId, healthAfter)

    -- Sabotage-Eintrag in DB schreiben
    local system     = ActiveSystems[device.system_id]
    local systemName = system and system.name or ('System #' .. tostring(device.system_id))
    local playerName = GetPlayerName(src) or tostring(src)

    db.logSabotage(deviceId, device.system_id, systemName, device.zone or 'Unbekannt',
        healthBefore, healthAfter, playerName)

    -- Server-Log für Admins
    print(("^1[d4rk_firealert:SABOTAGE] Spieler '%s' (src:%s) hat Gerät #%s (%s / %s) beschädigt: %s%% → %s%%^7")
        :format(playerName, src, deviceId, systemName, device.zone or '?', healthBefore, healthAfter))

    -- Trouble-Check: löst Trouble-Status aus wenn Health jetzt unter 20%
    if healthAfter < 20 then
        local sId = device.system_id
        if ActiveSystems[sId] and ActiveSystems[sId].status == 'normal' then
            ActiveSystems[sId].status = 'trouble'
            db.updateSystemStatus(sId, 'trouble')
            TriggerClientEvent('d4rk_firealert:client:updateSystemStatus', -1, sId, 'trouble')
        end
    end

    SabotageCooldowns[src] = now
end)

---------------------------------------------------------
-- MDT: Alle Systemdaten für d4rk_firemdt
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:server:mdt:getData', function()
    local src = source

    if not Utils.HasJobServer(src, Config.Job) then
        Utils.Log(("Spieler %s: MDT-Daten ohne Job angefragt."):format(src))
        return
    end

    local allDevices   = db.getAllDevices()
    local devsBySystem = {}

    if allDevices then
        for _, dev in ipairs(allDevices) do
            local sId = dev.system_id
            if not devsBySystem[sId] then devsBySystem[sId] = {} end
            table.insert(devsBySystem[sId], dev)
        end
    end

    local result = {}
    for sId, system in pairs(ActiveSystems) do
        local logs = db.getAlarmLog(sId, 5)
        table.insert(result, {
            id      = sId,
            name    = system.name,
            status  = system.status,
            devices = devsBySystem[sId] or {},
            logs    = logs or {}
        })
    end

    table.sort(result, function(a, b)
        local order = { alarm = 0, trouble = 1, normal = 2 }
        local ao, bo = order[a.status] or 2, order[b.status] or 2
        if ao ~= bo then return ao < bo end
        return (a.name or '') < (b.name or '')
    end)

    TriggerClientEvent('d4rk_firealert:client:mdt:open', src, result)
end)

---------------------------------------------------------
-- Wartungs-Loop
---------------------------------------------------------

CreateThread(function()
    while true do
        Wait(Config.Maintenance.CheckInterval * 60000)

        -- 1) Zufällige Health-Degradierung
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

        -- 2) NEU: Überfällige Inspektionen → Gerät auf Trouble-Health setzen
        local overdueDevices = db.getOverdueDevices()
        if overdueDevices then
            for _, dev in ipairs(overdueDevices) do
                -- Health auf 15% setzen — unterhalb Trouble-Grenze (20%)
                db.updateDeviceHealth(dev.id, 15)
                TriggerClientEvent('d4rk_firealert:client:updateDeviceHealth', -1, dev.id, 15)
                Utils.Log(("Gerät #%s (%s / %s): Inspektion überfällig → Health auf 15%%"):format(
                    dev.id, dev.system_name, dev.zone))
            end
        end

        -- 3) Trouble-Status für Systeme mit kaputten Geräten setzen
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

lib.addCommand('test_bma', {
    help       = 'BMA Probealarm auslösen',
    params     = { { name = 'systemId', type = 'number', help = 'System-ID' } },
    restricted = 'group.admin'
}, function(source, args)
    local systemId = args.systemId
    if not ActiveSystems[systemId] then
        return TriggerClientEvent('ox_lib:notify', source, {
            title = 'Fehler', description = 'Ungültige System-ID', type = 'error'
        })
    end

    if ActiveSystems[systemId].status == 'alarm' then
        ActiveSystems[systemId].status = 'normal'
    end

    TriggerAlarm(systemId, 'Probealarm', 'test')

    TriggerClientEvent('ox_lib:notify', -1, {
        title = '🔧 BMA PROBEALARM: ' .. ActiveSystems[systemId].name,
        description = 'Dies ist eine geplante Wartung / Test.',
        type = 'inform', duration = 5000
    })
end)