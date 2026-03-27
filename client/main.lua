spawnedObjects = {} -- Nicht lokal, damit andere Dateien darauf zugreifen können
currentSystemId = nil -- Global für dieses Script (Wartungsmodus)
local activeAlarms = {}

---------------------------------------------------------
-- Hilfsfunktionen
---------------------------------------------------------

-- Gerät abmontieren Logik
function RemoveDeviceAction(entity)
    local alert = lib.alertDialog({
        header = 'Gerät entfernen?',
        content = 'Möchtest du dieses BMA-Gerät wirklich dauerhaft entfernen?',
        centered = true,
        cancel = true
    })

    if alert == 'confirm' then
        local progress = lib.progressBar({
            duration = 5000,
            label = 'Demontiere Gerät...',
            useWhileDead = false,
            canCancel = true,
            anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' }
        })

        if progress then
            local coords = GetEntityCoords(entity)
            TriggerServerEvent('d4rk_firealert:server:removeDevice', coords)
            DeleteEntity(entity)
        end
    end
end

-- Hilfsfunktion zum Spawnen (Wichtig für State Bags)
function CreateBMAProp(data)
    local model = Config.Devices[data.type].model
    local coords = type(data.coords) == "string" and json.decode(data.coords) or data.coords
    local rot = type(data.rotation) == "string" and json.decode(data.rotation) or data.rotation

    lib.requestModel(model)
    local obj = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    Entity(obj).state:set('systemId', data.system_id, true)
    Entity(obj).state:set('zoneName', data.zone, true)
    
    SetEntityRotation(obj, rot.x, rot.y, rot.z, 2, true)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    table.insert(spawnedObjects, obj)
end

---------------------------------------------------------
-- Events & Threads
---------------------------------------------------------

-- Event: Status-Update vom Server (Alarm an/aus)
RegisterNetEvent('d4rk_firealert:client:updateSystemStatus', function(systemId, status)
    activeAlarms[tonumber(systemId)] = (status == 'alarm')
    if status == 'normal' then
        lib.notify({title = 'BMA', description = 'System '..systemId..' wurde quittiert.', type = 'inform'})
    end
end)

-- Blink-Thread für Alarm-Optik
CreateThread(function()
    while true do
        local sleep = 1500
        local hasAlarm = false
        
        for sId, isAlarm in pairs(activeAlarms) do
            if isAlarm then
                hasAlarm = true
                sleep = 500
                for _, obj in ipairs(spawnedObjects) do
                    if DoesEntityExist(obj) and Entity(obj).state.systemId == sId then
                        -- Nur das Panel blinkt
                        if GetEntityModel(obj) == GetHashKey(Config.Devices["panel"].model) then
                            SetEntityDrawOutline(obj, true)
                            SetEntityDrawOutlineColor(255, 0, 0, 255)
                            local c = GetEntityCoords(obj)
                            DrawLightWithRange(c.x, c.y, c.z, 255, 0, 0, 1.2, 50.0)
                        end
                    end
                end
            end
        end

        if not hasAlarm then
            for _, obj in ipairs(spawnedObjects) do SetEntityDrawOutline(obj, false) end
        end
        Wait(sleep)
    end
end)

local function OpenDeviceList(sId)
    local deviceElements = {}
    local count = 0

    -- Wir gehen durch alle gespawnten Objekte und suchen die passenden
    for _, obj in ipairs(spawnedObjects) do
        if DoesEntityExist(obj) then
            local state = Entity(obj).state
            if state.systemId == sId then
                count = count + 1
                local coords = GetEntityCoords(obj)
                local zone = state.zoneName or "Unbekannte Zone"
                local model = GetEntityModel(obj)
                
                -- Typ-Bestimmung für das Icon
                local deviceIcon = 'microchip'
                if model == GetHashKey(Config.Devices["smoke"].model) then deviceIcon = 'wind'
                elseif model == GetHashKey(Config.Devices["pull"].model) then deviceIcon = 'hand-point-up'
                elseif model == GetHashKey(Config.Devices["panel"].model) then deviceIcon = 'terminal'
                end

                table.insert(deviceElements, {
                    title = zone,
                    description = string.format("Typ: %s | Distanz: %.1fm", deviceIcon, #(coords - GetEntityCoords(cache.ped))),
                    icon = deviceIcon,
                    metadata = {
                        {label = 'ID', value = count},
                        {label = 'Coords', value = string.format("%.1f, %.1f", coords.x, coords.y)}
                    },
                    onSelect = function()
                        -- Kleiner Bonus: Markiert das Gerät kurz für den Techniker
                        SetEntityDrawOutline(obj, true)
                        SetEntityDrawOutlineColor(0, 255, 0, 255)
                        lib.notify({description = 'Gerät in '..zone..' wurde markiert.', type = 'inform'})
                        Wait(3000)
                        SetEntityDrawOutline(obj, false)
                    end
                })
            end
        end
    end

    if #deviceElements == 0 then
        table.insert(deviceElements, { title = 'Keine Geräte gefunden', disabled = true })
    end

    lib.registerContext({
        id = 'bma_device_list',
        title = 'Verbundene Geräte (Gesamt: '..count..')',
        menu = 'bma_main_menu', -- Erlaubt "Zurück"-Button
        options = deviceElements
    })
    lib.showContext('bma_device_list')
end
-- Das Hauptmenü am Panel
local function OpenBMAMenu(entity)
    local sId = Entity(entity).state.systemId
    if not sId then return end

    lib.registerContext({
        id = 'bma_main_menu',
        title = 'BMA Zentrale - ID: ' .. sId,
        options = {
            {
                title = 'Verbundene Geräte',
                description = 'Zeigt alle Melder an, die mit diesem System gekoppelt sind.',
                icon = 'list-check',
                onSelect = function()
                    OpenDeviceList(sId)
                end
            },
            {
                title = 'Wartungsmodus',
                description = (currentSystemId == sId) and '✅ AKTIV - Du kannst Melder koppeln' or '❌ INAKTIV - Klicke zum Starten',
                icon = 'wrench',
                onSelect = function()
                    if currentSystemId == sId then
                        currentSystemId = nil
                        lib.notify({ title = 'BMA', description = 'Wartungsmodus beendet.', type = 'inform' })
                    else
                        currentSystemId = sId
                        lib.notify({ title = 'BMA', description = 'Wartung aktiv. Neue Geräte gehören nun zu ID '..sId, type = 'success' })
                    end
                    OpenBMAMenu(entity)
                end
            },
            {
                title = 'Alarm quittieren (ACK)',
                description = 'Stoppt Sirenen und Blinken',
                icon = 'bell-slash',
                onSelect = function()
                    TriggerServerEvent('d4rk_firealert:server:quittieren', sId)
                end
            },
            {
                title = 'Status prüfen',
                icon = 'microchip',
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

-- 1. Die Zentrale (Panel)
exports.ox_target:addModel(Config.Devices["panel"].model, {
    {
        name = 'open_bma',
        icon = 'fas fa-terminal',
        label = 'System-Konsole öffnen',
        groups = Config.Job,
        onSelect = function(data)
            OpenBMAMenu(data.entity)
        end
    },
    {
        name = 'remove_device_panel',
        icon = 'fas fa-hammer',
        label = 'Zentrale abmontieren',
        groups = Config.Job,
        onSelect = function(data)
            RemoveDeviceAction(data.entity)
        end
    }
})

-- 2. Handfeuermelder (Pull)
exports.ox_target:addModel(Config.Devices["pull"].model, {
    {
        name = 'pull_alarm',
        icon = 'fas fa-hand-rock',
        label = 'Alarm auslösen',
        onSelect = function(data)
            local sId = Entity(data.entity).state.systemId
            local zone = Entity(data.entity).state.zoneName or "Manueller Melder"
            if sId then
                TriggerServerEvent('d4rk_firealert:server:triggerAlarm', sId, zone)
            end
        end
    },
    {
        name = 'remove_device_pull',
        icon = 'fas fa-hammer',
        label = 'Melder abmontieren',
        groups = Config.Job,
        onSelect = function(data)
            RemoveDeviceAction(data.entity)
        end
    }
})

-- 3. Rauchmelder (Smoke)
exports.ox_target:addModel(Config.Devices["smoke"].model, {
    {
        name = 'remove_device_smoke',
        icon = 'fas fa-hammer',
        label = 'Rauchmelder abmontieren',
        groups = Config.Job,
        onSelect = function(data)
            RemoveDeviceAction(data.entity)
        end
    }
})

---------------------------------------------------------
-- Initialisierung & Cleanup
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:client:loadInitialDevices', function(devices)
    for _, obj in ipairs(spawnedObjects) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
    spawnedObjects = {}
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
    if (GetCurrentResourceName() ~= resourceName) then return end

    for _, obj in ipairs(spawnedObjects) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    
    if ghost and DoesEntityExist(ghost) then DeleteEntity(ghost) end

    lib.hideTextUI()
    print("^1[d4rk_firealert] Client-seitige Props beim Restart bereinigt.^7")
end)