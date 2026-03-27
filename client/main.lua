local spawnedObjects = {}

-- Hilfsfunktion: Gerät abmontieren (für alle Gerätetypen gleich)
local function RemoveDeviceAction(entity)
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
            -- Trigger an Server zum Löschen aus DB
            TriggerServerEvent('d4rk_firealert:server:removeDevice', coords)
            DeleteEntity(entity)
        end
    end
end

-- Funktion zum Erstellen der permanenten Props
local function CreateBMAProp(data)
    local model = Config.Devices[data.type].model
    local coords = type(data.coords) == "string" and json.decode(data.coords) or data.coords
    local rot = type(data.rotation) == "string" and json.decode(data.rotation) or data.rotation

    lib.requestModel(model)
    local obj = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    
    -- State Bag setzen
    Entity(obj).state:set('systemId', data.system_id, true)
    Entity(obj).state:set('zoneName', data.zone or "Unbekannt", true)
    
    SetEntityRotation(obj, rot.x, rot.y, rot.z, 2, true)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    
    table.insert(spawnedObjects, obj)
end

-- Event zum Laden aller Props
RegisterNetEvent('d4rk_firealert:client:loadInitialDevices', function(devices)
    for _, obj in ipairs(spawnedObjects) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    spawnedObjects = {}

    for _, data in ipairs(devices) do
        CreateBMAProp(data)
    end
end)

-- BMA Menü Logik
local function OpenBMAMenu(entity)
    local sId = Entity(entity).state.systemId
    
    lib.registerContext({
        id = 'bma_main_menu',
        title = 'BMA Zentrale - ID: ' .. (sId or "???"),
        options = {
            {
                title = 'Status prüfen',
                description = 'Alle Melder online. System ID: ' .. (sId or "NA"),
                icon = 'microchip',
                onSelect = function()
                    lib.notify({ title = 'System-Check', description = 'System arbeitet normal.', type = 'success' })
                end
            },
            {
                title = 'Alarm quittieren (ACK)',
                icon = 'bell-slash',
                onSelect = function()
                    lib.notify({ title = 'BMA', description = 'Alarm wurde quittiert.', type = 'inform' })
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

-- 3. Rauchmelder (Smoke) - Hier auch das Abmontieren hinzufügen
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
-- Sound & Benachrichtigung
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:client:playAlarmSound', function(coords)
    local playerCoords = GetEntityCoords(cache.ped)
    local dist = #(playerCoords - vector3(coords.x, coords.y, coords.z))

    if dist < 50.0 then
        PlaySoundFrontend(-1, "TIMER_STOP", "HUD_MINI_GAME_SOUNDSET", 1)
        lib.notify({ title = 'BMA SIRENE', type = 'error', position = 'top' })
    end
end)

AddEventHandler('onResourceStop', function(resourceName)
    if (GetCurrentResourceName() ~= resourceName) then
        return
    end

    -- Alle gespawnten Props löschen
    for _, obj in ipairs(spawnedObjects) do
        if DoesEntityExist(obj) then
            DeleteEntity(obj)
        end
    end
    
    -- Falls der Placement-Mode aktiv war, das Ghost-Objekt löschen
    if ghost and DoesEntityExist(ghost) then
        DeleteEntity(ghost)
    end

    lib.hideTextUI()
    print("^1[d4rk_firealert] Client-seitige Props beim Restart bereinigt.^7")
end)