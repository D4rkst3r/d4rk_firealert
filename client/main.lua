local function OpenBMAMenu(entity)
    -- Hier könnten wir Infos aus der DB abfragen
    lib.registerContext({
        id = 'bma_main_menu',
        title = 'BMA Zentrale - Kontrolle',
        options = {
            {
                title = 'Status prüfen',
                description = 'Alle Melder und Batterien scannen',
                icon = 'microchip',
                onSelect = function()
                    lib.notify({ title = 'System-Check', description = 'Alle Systeme im grünen Bereich.', type =
                    'success' })
                end
            },
            {
                title = 'Alarm quittieren (ACK)',
                icon = 'bell-slash',
                onSelect = function()
                    -- Trigger Reset Event
                end
            }
        }
    })
    lib.showContext('bma_main_menu')
end

-- Target für das Panel
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

-- Trigger für Handfeuermelder
exports.ox_target:addModel(Config.Devices["pull"].model, {
    {
        name = 'pull_alarm',
        icon = 'fas fa-hand-rock',
        label = 'Alarm auslösen',
        onSelect = function(data)
            -- Simpel: Wir lösen das System ID 1 aus (erweiterbar)
            TriggerServerEvent('d4rk_firealert:server:triggerAlarm', 1, "Manueller Melder")
        end
    }
})

RegisterNetEvent('d4rk_firealert:client:playAlarmSound', function(coords)
    local playerCoords = GetEntityCoords(cache.ped)
    local dist = #(playerCoords - vector3(coords.x, coords.y, coords.z))

    if dist < 50.0 then
        -- Hier könntest du InteractSound oder xSound nutzen
        PlaySoundFrontend(-1, "TIMER_STOP", "HUD_MINI_GAME_SOUNDSET", 1)
        lib.notify({ title = 'BMA SIRENE', type = 'error' })
    end
end)
