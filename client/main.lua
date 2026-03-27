-- d4rk_firealert: client/main.lua
spawnedObjects  = {}
currentSystemId = nil
local activeAlarms = {}

-- FIX #7: Separate Tracking-Maps für Panel und Sirenen
-- Statt alle spawnedObjects zu iterieren greifen wir direkt auf die richtigen Objekte zu
local panelObjects = {}  -- { [systemId] = entity }
local sirenObjects = {}  -- { [systemId] = { entity, ... } }

local DeviceLabels = {
    [GetHashKey('prop_fire_alarm_03')]               = { label = 'Rauchmelder',     icon = 'wind'          },
    [GetHashKey('prop_fire_alarm_01')]               = { label = 'Handfeuermelder', icon = 'hand-point-up' },
    [GetHashKey('m23_1_prop_m31_controlpanel_02a')]  = { label = 'Zentrale',        icon = 'terminal'      },
    [GetHashKey('prop_fire_alarm_02')]               = { label = 'Sirene',          icon = 'bell'          },
}

---------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------

-- Prop in alle Tracking-Strukturen eintragen
local function TrackProp(obj, data)
    local sId = data.system_id
    if GetEntityModel(obj) == Config.Devices["panel"].model then
        panelObjects[sId] = obj
    elseif GetEntityModel(obj) == Config.Devices["siren"].model then
        if not sirenObjects[sId] then sirenObjects[sId] = {} end
        table.insert(sirenObjects[sId], obj)
    end
end

-- Prop aus allen Tracking-Strukturen entfernen
local function UntrackProp(obj)
    local sId = Entity(obj).state.systemId
    if panelObjects[sId] == obj then panelObjects[sId] = nil end
    if sirenObjects[sId] then
        for i, s in ipairs(sirenObjects[sId]) do
            if s == obj then table.remove(sirenObjects[sId], i) break end
        end
    end
    for i, o in ipairs(spawnedObjects) do
        if o == obj then table.remove(spawnedObjects, i) break end
    end
end

function RemoveDeviceAction(entity)
    local alert = lib.alertDialog({
        header   = 'Gerät entfernen?',
        content  = 'Möchtest du dieses BMA-Gerät wirklich dauerhaft entfernen?',
        centered = true,
        cancel   = true
    })

    if alert == 'confirm' then
        local progress = lib.progressBar({
            duration     = 5000,
            label        = 'Demontiere Gerät...',
            useWhileDead = false,
            canCancel    = true,
            anim         = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' }
        })

        if progress then
            local coords = GetEntityCoords(entity)
            TriggerServerEvent('d4rk_firealert:server:removeDevice', coords)
            DeleteEntity(entity)
        end
    end
end

-- FIX #3: Reparatur-Logik als eigene Funktion
local function RepairDeviceAction(entity)
    -- FIX #3: Health aus State Bag prüfen bevor Reparatur gestartet wird
    local health = Entity(entity).state.deviceHealth or 100
    if health >= 100 then
        lib.notify({ title = 'BMA', description = 'Dieses Gerät ist voll funktionsfähig.', type = 'inform' })
        return
    end

    local progress = lib.progressBar({
        duration     = 8000,
        label        = 'Repariere Melder...',
        useWhileDead = false,
        canCancel    = true,
        anim         = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' }
    })

    if progress then
        local deviceId = Entity(entity).state.deviceId
        TriggerServerEvent('d4rk_firealert:server:repairDevice', deviceId)
    end
end

function CreateBMAProp(data)
    local model  = Config.Devices[data.type].model
    local coords = type(data.coords)   == "string" and json.decode(data.coords)   or data.coords
    local rot    = type(data.rotation) == "string" and json.decode(data.rotation) or data.rotation

    lib.requestModel(model)
    local obj = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)

    -- FIX #6 (Delta-Sync): deviceId in State Bag für gezieltes Entfernen ohne vollen Resync
    -- FIX #3 (Repair): deviceHealth in State Bag für Client-seitigen Health-Check
    Entity(obj).state:set('systemId',     data.system_id,    true)
    Entity(obj).state:set('zoneName',     data.zone,         true)
    Entity(obj).state:set('deviceId',     data.id,           true)
    Entity(obj).state:set('deviceHealth', data.health or 100, true)

    SetEntityRotation(obj, rot.x, rot.y, rot.z, 2, true)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    table.insert(spawnedObjects, obj)

    TrackProp(obj, data)
end

---------------------------------------------------------
-- Events & Threads
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:client:updateSystemStatus', function(systemId, status)
    activeAlarms[tonumber(systemId)] = (status == 'alarm')
    if status == 'normal' then
        lib.notify({ title = 'BMA', description = 'System ' .. systemId .. ' wurde quittiert.', type = 'inform' })
    elseif status == 'trouble' then
        lib.notify({ title = 'BMA STÖRUNG', description = 'System ' .. systemId .. ' meldet einen Gerätedefekt!', type = 'warning' })
    end
end)

-- FIX #3: Health-Update vom Server nach Reparatur (aktualisiert State Bag ohne vollen Resync)
RegisterNetEvent('d4rk_firealert:client:updateDeviceHealth', function(deviceId, newHealth)
    for _, obj in ipairs(spawnedObjects) do
        if DoesEntityExist(obj) and Entity(obj).state.deviceId == deviceId then
            Entity(obj).state:set('deviceHealth', newHealth, true)
            break
        end
    end
end)

-- FIX #6: Delta-Sync — nur das neue Gerät empfangen statt komplette Liste
RegisterNetEvent('d4rk_firealert:client:addDevice', function(data)
    CreateBMAProp(data)
end)

-- FIX #6: Delta-Sync — einzelnes Gerät per deviceId entfernen
RegisterNetEvent('d4rk_firealert:client:removeDevice', function(deviceId)
    for _, obj in ipairs(spawnedObjects) do
        if DoesEntityExist(obj) and Entity(obj).state.deviceId == deviceId then
            UntrackProp(obj)
            DeleteEntity(obj)
            break
        end
    end
end)

-- FIX #7: Blink-Thread nutzt panelObjects und sirenObjects Maps
-- Statt O(n) über alle Objekte ist der Zugriff jetzt O(1) pro System
CreateThread(function()
    while true do
        local sleep    = 1500
        local hasAlarm = false

        for sId, isAlarm in pairs(activeAlarms) do
            if isAlarm then
                hasAlarm = true
                sleep    = 500

                -- Panel blinken
                local panel = panelObjects[sId]
                if panel and DoesEntityExist(panel) then
                    SetEntityDrawOutline(panel, true)
                    SetEntityDrawOutlineColor(255, 0, 0, 255)
                    local c = GetEntityCoords(panel)
                    DrawLightWithRange(c.x, c.y, c.z, 255, 0, 0, 1.2, 50.0)
                end

                -- Sirenen blinken (vorher nie implementiert)
                if sirenObjects[sId] then
                    for _, siren in ipairs(sirenObjects[sId]) do
                        if DoesEntityExist(siren) then
                            SetEntityDrawOutline(siren, true)
                            SetEntityDrawOutlineColor(255, 80, 0, 255)
                            local c = GetEntityCoords(siren)
                            DrawLightWithRange(c.x, c.y, c.z, 255, 80, 0, 1.5, 30.0)
                        end
                    end
                end
            end
        end

        if not hasAlarm then
            -- FIX #5: Alle Outlines sauber zurücksetzen
            for sId, panel in pairs(panelObjects) do
                if DoesEntityExist(panel) then
                    SetEntityDrawOutline(panel, false)
                    SetEntityDrawOutlineColor(255, 255, 255, 0)
                end
            end
            for sId, sirens in pairs(sirenObjects) do
                for _, siren in ipairs(sirens) do
                    if DoesEntityExist(siren) then
                        SetEntityDrawOutline(siren, false)
                        SetEntityDrawOutlineColor(255, 255, 255, 0)
                    end
                end
            end
        end

        Wait(sleep)
    end
end)

local function OpenDeviceList(sId)
    local deviceElements = {}
    local count = 0

    for _, obj in ipairs(spawnedObjects) do
        if DoesEntityExist(obj) then
            local state = Entity(obj).state
            if state.systemId == sId then
                count = count + 1
                local coords     = GetEntityCoords(obj)
                local zone       = state.zoneName or "Unbekannte Zone"
                local health     = state.deviceHealth or 100
                local model      = GetEntityModel(obj)
                local deviceInfo = DeviceLabels[model] or { label = 'Unbekannt', icon = 'microchip' }

                -- Health-Farbe für schnelle visuelle Übersicht
                local healthStr
                if health >= 75 then
                    healthStr = '🟢 ' .. health .. '%'
                elseif health >= 30 then
                    healthStr = '🟡 ' .. health .. '%'
                else
                    healthStr = '🔴 ' .. health .. '%'
                end

                table.insert(deviceElements, {
                    title       = zone,
                    description = string.format('%s | %s | %.1fm', deviceInfo.label, healthStr, #(coords - GetEntityCoords(cache.ped))),
                    icon        = deviceInfo.icon,
                    metadata    = {
                        { label = 'Nr.',    value = count },
                        { label = 'Health', value = health .. '%' },
                        { label = 'Coords', value = string.format('%.1f, %.1f', coords.x, coords.y) }
                    },
                    onSelect = function()
                        SetEntityDrawOutline(obj, true)
                        SetEntityDrawOutlineColor(0, 255, 0, 255)
                        lib.notify({ description = 'Gerät in ' .. zone .. ' wurde markiert.', type = 'inform' })
                        Wait(3000)
                        SetEntityDrawOutline(obj, false)
                        SetEntityDrawOutlineColor(255, 255, 255, 0)
                    end
                })
            end
        end
    end

    if #deviceElements == 0 then
        table.insert(deviceElements, { title = 'Keine Geräte gefunden', disabled = true })
    end

    lib.registerContext({
        id      = 'bma_device_list',
        title   = 'Verbundene Geräte (Gesamt: ' .. count .. ')',
        menu    = 'bma_main_menu',
        options = deviceElements
    })
    lib.showContext('bma_device_list')
end

local function OpenBMAMenu(entity)
    local sId = Entity(entity).state.systemId
    if not sId then return end

    lib.registerContext({
        id      = 'bma_main_menu',
        title   = 'BMA Zentrale - ID: ' .. sId,
        options = {
            {
                title       = 'Verbundene Geräte',
                description = 'Zeigt alle Melder inkl. Health-Status an.',
                icon        = 'list-check',
                onSelect    = function() OpenDeviceList(sId) end
            },
            {
                title       = 'Wartungsmodus',
                description = (currentSystemId == sId)
                    and '✅ AKTIV - Du kannst Melder koppeln'
                    or  '❌ INAKTIV - Klicke zum Starten',
                icon        = 'wrench',
                onSelect    = function()
                    if currentSystemId == sId then
                        currentSystemId = nil
                        lib.notify({ title = 'BMA', description = 'Wartungsmodus beendet.', type = 'inform' })
                    else
                        currentSystemId = sId
                        lib.notify({ title = 'BMA', description = 'Wartung aktiv. Neue Geräte gehören nun zu ID ' .. sId, type = 'success' })
                    end
                    OpenBMAMenu(entity)
                end
            },
            {
                title       = 'Alarm quittieren (ACK)',
                description = 'Stoppt Sirenen und Blinken',
                icon        = 'bell-slash',
                onSelect    = function()
                    TriggerServerEvent('d4rk_firealert:server:quittieren', sId)
                end
            },
            {
                title    = 'Status prüfen',
                icon     = 'microchip',
                onSelect = function()
                    lib.notify({ title = 'System-Check', description = 'Alle Komponenten innerhalb der Toleranz.', type = 'success' })
                end
            }
        }
    })
    lib.showContext('bma_main_menu')
end

---------------------------------------------------------
-- Target-System Konfiguration
---------------------------------------------------------

exports.ox_target:addModel(Config.Devices["panel"].model, {
    {
        name     = 'open_bma',
        icon     = 'fas fa-terminal',
        label    = 'System-Konsole öffnen',
        groups   = Config.Job,
        onSelect = function(data) OpenBMAMenu(data.entity) end
    },
    {
        name     = 'remove_device_panel',
        icon     = 'fas fa-hammer',
        label    = 'Zentrale abmontieren',
        groups   = Config.Job,
        onSelect = function(data) RemoveDeviceAction(data.entity) end
    }
})

exports.ox_target:addModel(Config.Devices["pull"].model, {
    {
        name     = 'pull_alarm',
        icon     = 'fas fa-hand-rock',
        label    = 'Alarm auslösen',
        onSelect = function(data)
            local sId    = Entity(data.entity).state.systemId
            local zone   = Entity(data.entity).state.zoneName or "Manueller Melder"
            -- FIX #1: Gerät-Coords mitsenden damit Server Proximity prüfen kann
            local coords = GetEntityCoords(data.entity)
            if sId then
                TriggerServerEvent('d4rk_firealert:server:triggerAlarm', sId, zone, coords)
            end
        end
    },
    {
        -- FIX #3: Reparatur-Option an Pull-Meldern
        name     = 'repair_device_pull',
        icon     = 'fas fa-tools',
        label    = 'Melder reparieren',
        groups   = Config.Job,
        onSelect = function(data) RepairDeviceAction(data.entity) end
    },
    {
        name     = 'remove_device_pull',
        icon     = 'fas fa-hammer',
        label    = 'Melder abmontieren',
        groups   = Config.Job,
        onSelect = function(data) RemoveDeviceAction(data.entity) end
    }
})

exports.ox_target:addModel(Config.Devices["smoke"].model, {
    {
        -- FIX #3: Reparatur-Option an Rauchmeldern
        name     = 'repair_device_smoke',
        icon     = 'fas fa-tools',
        label    = 'Rauchmelder reparieren',
        groups   = Config.Job,
        onSelect = function(data) RepairDeviceAction(data.entity) end
    },
    {
        name     = 'remove_device_smoke',
        icon     = 'fas fa-hammer',
        label    = 'Rauchmelder abmontieren',
        groups   = Config.Job,
        onSelect = function(data) RemoveDeviceAction(data.entity) end
    }
})

-- FIX #5: Sirene hat jetzt ein Target (vorher komplett fehlend)
exports.ox_target:addModel(Config.Devices["siren"].model, {
    {
        name     = 'remove_device_siren',
        icon     = 'fas fa-hammer',
        label    = 'Sirene abmontieren',
        groups   = Config.Job,
        onSelect = function(data) RemoveDeviceAction(data.entity) end
    }
})

---------------------------------------------------------
-- Initialisierung & Cleanup
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:client:loadInitialDevices', function(devices)
    -- Alles aufräumen
    for _, obj in ipairs(spawnedObjects) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    spawnedObjects = {}
    panelObjects   = {}
    sirenObjects   = {}
    activeAlarms   = {}

    for _, data in ipairs(devices) do CreateBMAProp(data) end
end)

RegisterNetEvent('d4rk_firealert:client:playAlarmSound', function(coords)
    local playerCoords = GetEntityCoords(cache.ped)
    local dist = #(playerCoords - vector3(coords.x, coords.y, coords.z))

    if dist < 50.0 then
        PlaySoundFrontend(-1, "TIMER_STOP", "HUD_MINI_GAME_SOUNDSET", 1)
        lib.notify({ title = 'BMA SIRENE', type = 'error', position = 'top' })
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end

    for _, obj in ipairs(spawnedObjects) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end

    if ghost and DoesEntityExist(ghost) then
        DeleteEntity(ghost)
        ghost = nil
    end

    lib.hideTextUI()
    print("^1[d4rk_firealert] Client-seitige Props beim Restart bereinigt.^7")
end)

-- FIX #9: Kein Wait(1000) mehr — Server signalisiert selbst wenn er bereit ist
AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    TriggerServerEvent('d4rk_firealert:server:requestSync')
end)