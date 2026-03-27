local spawnedObjects = {}

-- Funktion zum Erstellen der permanenten Props
local function CreateBMAProp(data)
    local model = Config.Devices[data.type].model
    local coords = type(data.coords) == "string" and json.decode(data.coords) or data.coords
    local rot = type(data.rotation) == "string" and json.decode(data.rotation) or data.rotation

    lib.requestModel(model)
    local obj = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)
    
    SetEntityRotation(obj, rot.x, rot.y, rot.z, 2, true)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    
    table.insert(spawnedObjects, obj)
end

-- Event zum Laden aller Props (vom Server getriggert)
RegisterNetEvent('d4rk_firealert:client:loadInitialDevices', function(devices)
    -- Alte Props entfernen, um Duplikate beim Re-Sync zu vermeiden
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
    lib.registerContext({
        id = 'bma_main_menu',
        title = 'BMA Zentrale - Kontrolle',
        options = {
            {
                title = 'Status prüfen',
                description = 'Alle Melder und Batterien scannen',
                icon = 'microchip',
                onSelect = function()
                    lib.notify({ title = 'System-Check', description = 'Alle Systeme im grünen Bereich.', type = 'success' })
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

-- Target-System Konfiguration
exports.ox_target:addModel(Config.Devices["panel"].model, {
    {
        name = 'open_bma',
        icon = 'fas fa-terminal',
        label = 'System-Konsole öffnen',
        groups = Config.Job,
        onSelect = function(data)
            OpenBMAMenu(data.entity)
        end
    }
})

exports.ox_target:addModel(Config.Devices["pull"].model, {
    {
        name = 'pull_alarm',
        icon = 'fas fa-hand-rock',
        label = 'Alarm auslösen',
        onSelect = function(data)
            -- Hier nutzen wir System ID 1 als Default (kann für Multi-BMA erweitert werden)
            TriggerServerEvent('d4rk_firealert:server:triggerAlarm', 1, "Handfeuermelder")
        end
    }
})

-- Sound & Benachrichtigung
RegisterNetEvent('d4rk_firealert:client:playAlarmSound', function(coords)
    local playerCoords = GetEntityCoords(cache.ped)
    local dist = #(playerCoords - vector3(coords.x, coords.y, coords.z))

    if dist < 50.0 then
        PlaySoundFrontend(-1, "TIMER_STOP", "HUD_MINI_GAME_SOUNDSET", 1)
        lib.notify({ title = 'BMA SIRENE', type = 'error', position = 'top' })
    end
end)