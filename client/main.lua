-- d4rk_firealert: client/main.lua
spawnedObjects   = {}
currentSystemId  = nil
local activeAlarms   = {}
local triggeredSmoke = {}  -- { [deviceId] = true }

-- Sirenen-Audio: { [systemId] = { soundId = int, lastPlayed = int } }
local sirenAudio     = {}

-- Tracking-Maps für O(1) Zugriff
-- panelObjects ist global damit placement.lua GetNearbyPanels() nutzen kann
panelObjects      = {}  -- { [systemId] = entity }
local sirenObjects    = {}  -- { [systemId] = { entity, ... } }
local smokeObjects    = {}  -- { [systemId] = { { obj, deviceId, zone }, ... } }
local devicesBySystem = {}  -- { [systemId] = { entity, ... } }

-- Option C: Gibt alle Panels zurück die innerhalb von `radius` Metern um `coords` liegen
-- Rückgabe: { { systemId, systemName, dist, entity }, ... } sortiert nach Distanz
function GetNearbyPanels(coords, radius)
    local results = {}
    for sId, panel in pairs(panelObjects) do
        if DoesEntityExist(panel) then
            local dist = #(coords - GetEntityCoords(panel))
            if dist <= radius then
                table.insert(results, {
                    systemId   = sId,
                    systemName = Entity(panel).state.systemName or ('System #' .. sId),
                    dist       = dist,
                    entity     = panel
                })
            end
        end
    end
    -- Nächstes Panel zuerst
    table.sort(results, function(a, b) return a.dist < b.dist end)
    return results
end

local DeviceLabels = {
    [GetHashKey('prop_fire_alarm_03')]              = { label = 'Rauchmelder',     icon = 'wind'          },
    [GetHashKey('prop_fire_alarm_01')]              = { label = 'Handfeuermelder', icon = 'hand-point-up' },
    [GetHashKey('m23_1_prop_m31_controlpanel_02a')] = { label = 'Zentrale',        icon = 'terminal'      },
    [GetHashKey('prop_fire_alarm_02')]              = { label = 'Sirene',          icon = 'bell'          },
}

---------------------------------------------------------
-- Tracking
---------------------------------------------------------

local function TrackProp(obj, data)
    local sId   = data.system_id
    local dId   = data.id
    local model = GetEntityModel(obj)

    -- FIX #7: In devicesBySystem eintragen
    if not devicesBySystem[sId] then devicesBySystem[sId] = {} end
    table.insert(devicesBySystem[sId], obj)

    if model == Config.Devices["panel"].model then
        panelObjects[sId] = obj

    elseif model == Config.Devices["siren"].model then
        if not sirenObjects[sId] then sirenObjects[sId] = {} end
        table.insert(sirenObjects[sId], obj)

    elseif model == Config.Devices["smoke"].model then
        if not smokeObjects[sId] then smokeObjects[sId] = {} end
        table.insert(smokeObjects[sId], { obj = obj, deviceId = dId, zone = data.zone })
    end
end

local function UntrackProp(obj)
    local state = Entity(obj).state
    local sId   = state.systemId
    local dId   = state.deviceId

    -- Aus devicesBySystem entfernen
    if devicesBySystem[sId] then
        for i, o in ipairs(devicesBySystem[sId]) do
            if o == obj then table.remove(devicesBySystem[sId], i) break end
        end
    end

    if panelObjects[sId] == obj then panelObjects[sId] = nil end

    if sirenObjects[sId] then
        for i, s in ipairs(sirenObjects[sId]) do
            if s == obj then table.remove(sirenObjects[sId], i) break end
        end
    end

    if smokeObjects[sId] then
        for i, s in ipairs(smokeObjects[sId]) do
            if s.obj == obj then table.remove(smokeObjects[sId], i) break end
        end
    end

    triggeredSmoke[dId] = nil

    for i, o in ipairs(spawnedObjects) do
        if o == obj then table.remove(spawnedObjects, i) break end
    end
end

---------------------------------------------------------
-- Prop erstellen
---------------------------------------------------------

function CreateBMAProp(data)
    if not Config.Devices[data.type] then return end

    local model  = Config.Devices[data.type].model
    local coords = type(data.coords)   == "string" and json.decode(data.coords)   or data.coords
    local rot    = type(data.rotation) == "string" and json.decode(data.rotation) or data.rotation

    lib.requestModel(model)
    local obj = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)

    Entity(obj).state:set('systemId',     data.system_id,          true)
    Entity(obj).state:set('zoneName',     data.zone,               true)
    Entity(obj).state:set('deviceId',     data.id,                 true)
    Entity(obj).state:set('deviceHealth', data.health or 100,      true)
    -- Option C: Systemname im State Bag damit GetNearbyPanels ihn lesen kann
    if model == Config.Devices["panel"].model then
        Entity(obj).state:set('systemName', data.system_name or ('System #' .. tostring(data.system_id)), true)
    end

    SetEntityRotation(obj, rot.x, rot.y, rot.z, 2, true)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    table.insert(spawnedObjects, obj)

    TrackProp(obj, data)
end

---------------------------------------------------------
-- Aktionen
---------------------------------------------------------

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
            local deviceId = Entity(entity).state.deviceId
            TriggerServerEvent('d4rk_firealert:server:removeDevice', deviceId)
        end
    end
end

local function RepairDeviceAction(entity)
    local health = Entity(entity).state.deviceHealth or 100
    if health >= 100 then
        lib.notify({ title = 'BMA', description = 'Gerät ist voll funktionsfähig.', type = 'inform' })
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

---------------------------------------------------------
-- Events
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:client:updateSystemStatus', function(systemId, status)
    local id = tonumber(systemId)
    activeAlarms[id] = (status == 'alarm')

    if status == 'normal' then
        lib.notify({ title = 'BMA', description = 'System ' .. systemId .. ' wurde quittiert.', type = 'inform' })
        -- Sirenen-Sound sofort stoppen
        if sirenAudio[id] and sirenAudio[id].soundId ~= -1 then
            StopSound(sirenAudio[id].soundId)
            ReleaseSoundId(sirenAudio[id].soundId)
        end
        sirenAudio[id] = nil
        if smokeObjects[id] then
            for _, s in ipairs(smokeObjects[id]) do
                triggeredSmoke[s.deviceId] = nil
            end
        end
    elseif status == 'trouble' then
        lib.notify({ title = 'BMA STÖRUNG', description = 'System ' .. systemId .. ' meldet Gerätedefekt!', type = 'warning' })
    end
end)

RegisterNetEvent('d4rk_firealert:client:updateDeviceHealth', function(deviceId, newHealth)
    for _, obj in ipairs(spawnedObjects) do
        if DoesEntityExist(obj) and Entity(obj).state.deviceId == deviceId then
            Entity(obj).state:set('deviceHealth', newHealth, true)
            break
        end
    end
end)

RegisterNetEvent('d4rk_firealert:client:addDevice', function(data)
    CreateBMAProp(data)
end)

RegisterNetEvent('d4rk_firealert:client:removeDevice', function(deviceId)
    for _, obj in ipairs(spawnedObjects) do
        if DoesEntityExist(obj) and Entity(obj).state.deviceId == deviceId then
            UntrackProp(obj)
            DeleteEntity(obj)
            break
        end
    end
end)

RegisterNetEvent('d4rk_firealert:client:playAlarmSound', function(coords)
    local playerCoords = GetEntityCoords(cache.ped)
    local dist = #(playerCoords - vector3(coords.x, coords.y, coords.z))
    if dist < 80.0 then
        PlaySoundFrontend(-1, "TIMER_STOP", "HUD_MINI_GAME_SOUNDSET", 1)
        lib.notify({ title = '🚨 BMA SIRENE', type = 'error', position = 'top' })
    end
end)

RegisterNetEvent('d4rk_firealert:client:receiveAlarmLog', function(logEntries)
    if not logEntries or #logEntries == 0 then
        lib.notify({ title = 'Alarm-Log', description = 'Keine Einträge vorhanden.', type = 'inform' })
        return
    end

    local options = {}
    for _, entry in ipairs(logEntries) do
        local ackStr   = entry.acknowledged_by and ('✅ ' .. entry.acknowledged_by) or '❌ Nicht quittiert'
        local typeIcon = entry.trigger_type == 'automatic' and '🤖' or (entry.trigger_type == 'test' and '🔧' or '👤')

        table.insert(options, {
            title       = typeIcon .. ' ' .. entry.zone,
            description = entry.triggered_at or 'Unbekannt',
            metadata    = {
                { label = 'Typ',         value = entry.trigger_type },
                { label = 'Quittierung', value = ackStr },
            }
        })
    end

    lib.registerContext({
        id      = 'bma_alarm_log',
        title   = 'Alarm-Protokoll (letzte 10)',
        menu    = 'bma_main_menu',
        options = options
    })
    lib.showContext('bma_alarm_log')
end)

---------------------------------------------------------
-- Threads
---------------------------------------------------------

-- Blink-Thread
CreateThread(function()
    while true do
        local sleep    = 1500
        local hasAlarm = false

        for sId, isAlarm in pairs(activeAlarms) do
            if isAlarm then
                hasAlarm = true
                sleep    = 500

                local panel = panelObjects[sId]
                if panel and DoesEntityExist(panel) then
                    SetEntityDrawOutline(panel, true)
                    SetEntityDrawOutlineColor(255, 0, 0, 255)
                    local c = GetEntityCoords(panel)
                    DrawLightWithRange(c.x, c.y, c.z, 255, 0, 0, 1.2, 50.0)
                end

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
            for _, panel in pairs(panelObjects) do
                if DoesEntityExist(panel) then
                    SetEntityDrawOutline(panel, false)
                    SetEntityDrawOutlineColor(255, 255, 255, 0)
                end
            end
            for _, sirens in pairs(sirenObjects) do
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

-- Sirenen-Audio-Thread
-- Soundbank muss mit RequestScriptAudioBank geladen werden,
-- sonst liefert PlaySoundFromCoord Stille auch wenn der Sound existiert.
-- Manueller Distanz-Check vor dem Abspielen da range-Parameter bei
-- isNetwork=false von GTA ignoriert wird.
CreateThread(function()
    local SOUND_NAME  = "Altitude_Warning"
    local SOUND_SET   = "EXILE_1"
    local INTERVAL_MS = 2500  -- Sound ist ~2.5s lang
    local RANGE       = 40


    -- Soundbank vorab laden — ohne das kein Sound
    RequestScriptAudioBank(SOUND_SET, false)

    -- Kurz warten bis Bank geladen ist
    Wait(500)

    while true do
        Wait(500)

        for sId, isAlarm in pairs(activeAlarms) do
            if isAlarm and sirenObjects[sId] and #sirenObjects[sId] > 0 then
                local now = GetGameTimer()

                if not sirenAudio[sId] then
                    sirenAudio[sId] = { soundId = -1, lastPlayed = 0 }
                end

                local audio = sirenAudio[sId]

                if (now - audio.lastPlayed) >= INTERVAL_MS then
                    -- Vorherigen Sound-Handle sauber beenden
                    if audio.soundId ~= -1 then
                        StopSound(audio.soundId)
                        ReleaseSoundId(audio.soundId)
                        audio.soundId = -1
                    end

                    local played = false
                    local playerCoords = GetEntityCoords(cache.ped)

                    for _, siren in ipairs(sirenObjects[sId]) do
                        if DoesEntityExist(siren) then
                            local c    = GetEntityCoords(siren)
                            local dist = #(playerCoords - c)

                            if dist <= RANGE then
                                local soundId = GetSoundId()
                                -- range=0 da isNetwork=false den Parameter ignoriert
                                -- der manuelle Distanz-Check oben übernimmt die Reichweite
                                PlaySoundFromCoord(soundId, SOUND_NAME, c.x, c.y, c.z, SOUND_SET, false, 0, false)
                                audio.soundId    = soundId
                                audio.lastPlayed = now
                                played = true
                            else
                                -- Außerhalb Reichweite — lastPlayed setzen damit
                                -- beim nächsten Tick wieder geprüft wird
                                audio.lastPlayed = now
                                played = true
                            end
                            break
                        end
                    end

                    if not played then
                        sirenAudio[sId] = nil
                    end
                end
            end
        end

        -- Systeme ohne aktiven Alarm: Sound stoppen und aufräumen
        for sId, audio in pairs(sirenAudio) do
            if not activeAlarms[sId] then
                if audio.soundId ~= -1 then
                    StopSound(audio.soundId)
                    ReleaseSoundId(audio.soundId)
                end
                sirenAudio[sId] = nil
            end
        end
    end
end)

-- FIX #1: Automatische Rauchmelder-Auslösung nutzt jetzt triggerAutoAlarm
-- statt triggerAlarm mit 'automatic' — Server-seitig getrennt und geschützt
CreateThread(function()
    if not Config.AutoSmoke.Enabled then return end

    while true do
        Wait(Config.AutoSmoke.CheckInterval * 1000)

        for sId, smokeList in pairs(smokeObjects) do
            if not activeAlarms[sId] then
                for _, smokeData in ipairs(smokeList) do
                    if DoesEntityExist(smokeData.obj) and not triggeredSmoke[smokeData.deviceId] then
                        local smokeCoords = GetEntityCoords(smokeData.obj)
                        local fireCount   = GetNumberOfFiresInRange(smokeCoords.x, smokeCoords.y, smokeCoords.z, Config.AutoSmoke.CheckRadius)

                        if fireCount > 0 then
                            triggeredSmoke[smokeData.deviceId] = true

                            lib.notify({
                                title       = '🔥 Rauchmelder ausgelöst',
                                description = 'Zone: ' .. (smokeData.zone or 'Unbekannt'),
                                type        = 'error',
                                position    = 'top'
                            })

                            -- FIX #1: Separates Event — Server kann diesen Typ nicht mit
                            -- manuellem Alarm verwechseln, Cheater können 'automatic' nicht injecten
                            TriggerServerEvent(
                                'd4rk_firealert:server:triggerAutoAlarm',
                                sId,
                                smokeData.zone or 'Automatischer Rauchmelder',
                                smokeCoords
                            )

                            break
                        end
                    end
                end
            end
        end
    end
end)

---------------------------------------------------------
-- Menüs
---------------------------------------------------------

-- FIX #7: Nutzt devicesBySystem[sId] statt alle spawnedObjects zu durchsuchen
local function OpenDeviceList(sId)
    local deviceElements = {}
    local count          = 0
    local playerCoords   = GetEntityCoords(cache.ped)
    local systemDevices  = devicesBySystem[sId] or {}

    for _, obj in ipairs(systemDevices) do
        if DoesEntityExist(obj) then
            count = count + 1
            local state      = Entity(obj).state
            local coords     = GetEntityCoords(obj)
            local zone       = state.zoneName    or "Unbekannte Zone"
            local health     = state.deviceHealth or 100
            local model      = GetEntityModel(obj)
            local deviceInfo = DeviceLabels[model] or { label = 'Unbekannt', icon = 'microchip' }

            local healthStr
            if health >= 75 then     healthStr = '🟢 ' .. health .. '%'
            elseif health >= 30 then healthStr = '🟡 ' .. health .. '%'
            else                     healthStr = '🔴 ' .. health .. '%'
            end

            table.insert(deviceElements, {
                title       = zone,
                description = string.format('%s | %s | %.1fm', deviceInfo.label, healthStr, #(coords - playerCoords)),
                icon        = deviceInfo.icon,
                metadata    = {
                    { label = 'Nr.',    value = count },
                    { label = 'Health', value = health .. '%' },
                    { label = 'Coords', value = string.format('%.1f, %.1f', coords.x, coords.y) }
                },
                onSelect = function()
                    SetEntityDrawOutline(obj, true)
                    SetEntityDrawOutlineColor(0, 255, 0, 255)
                    lib.notify({ description = 'Gerät in ' .. zone .. ' markiert.', type = 'inform' })
                    Wait(3000)
                    SetEntityDrawOutline(obj, false)
                    SetEntityDrawOutlineColor(255, 255, 255, 0)
                end
            })
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
                description = 'Alle Melder inkl. Health-Status.',
                icon        = 'list-check',
                onSelect    = function() OpenDeviceList(sId) end
            },
            {
                title       = 'Alarm-Protokoll',
                description = 'Letzte 10 Alarm-Ereignisse dieses Systems.',
                icon        = 'clipboard-list',
                onSelect    = function()
                    TriggerServerEvent('d4rk_firealert:server:getAlarmLog', sId)
                end
            },
            {
                title       = 'Wartungsmodus',
                description = (currentSystemId == sId)
                    and '✅ AKTIV - Du kannst Melder koppeln'
                    or  '❌ INAKTIV - Klicke zum Starten',
                icon        = 'wrench',
                onSelect    = function()
                    if currentSystemId and currentSystemId ~= sId then
                        lib.notify({
                            title       = 'BMA',
                            description = 'Beende erst die Wartung an System ' .. currentSystemId .. '!',
                            type        = 'error'
                        })
                        return
                    end

                    if currentSystemId == sId then
                        currentSystemId = nil
                        lib.notify({ title = 'BMA', description = 'Wartungsmodus beendet.', type = 'inform' })
                    else
                        currentSystemId = sId
                        lib.notify({ title = 'BMA', description = 'Wartung aktiv. Neue Geräte → ID ' .. sId, type = 'success' })
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
-- Target-System
---------------------------------------------------------

exports.ox_target:addModel(Config.Devices["panel"].model, {
    {
        name     = 'open_bma',
        icon     = 'fas fa-terminal',
        label    = 'System-Konsole öffnen',
        groups   = Config.Job,
        distance = Config.Interaction.DistancePanel,
        onSelect = function(data) OpenBMAMenu(data.entity) end
    },
    {
        name     = 'remove_device_panel',
        icon     = 'fas fa-hammer',
        label    = 'Zentrale abmontieren',
        groups   = Config.Job,
        distance = Config.Interaction.DistancePanel,
        onSelect = function(data) RemoveDeviceAction(data.entity) end
    }
})

exports.ox_target:addModel(Config.Devices["pull"].model, {
    {
        name     = 'pull_alarm',
        icon     = 'fas fa-hand-rock',
        label    = 'Alarm auslösen',
        distance = Config.Interaction.DistancePanel,
        onSelect = function(data)
            local sId    = Entity(data.entity).state.systemId
            local zone   = Entity(data.entity).state.zoneName or "Manueller Melder"
            local coords = GetEntityCoords(data.entity)
            if sId then
                TriggerServerEvent('d4rk_firealert:server:triggerAlarm', sId, zone, coords, 'manual')
            end
        end
    },
    {
        name     = 'repair_device_pull',
        icon     = 'fas fa-tools',
        label    = 'Melder reparieren',
        groups   = Config.Job,
        distance = Config.Interaction.DistancePanel,
        onSelect = function(data) RepairDeviceAction(data.entity) end
    },
    {
        name     = 'remove_device_pull',
        icon     = 'fas fa-hammer',
        label    = 'Melder abmontieren',
        groups   = Config.Job,
        distance = Config.Interaction.DistancePanel,
        onSelect = function(data) RemoveDeviceAction(data.entity) end
    }
})

exports.ox_target:addModel(Config.Devices["smoke"].model, {
    {
        name     = 'repair_device_smoke',
        icon     = 'fas fa-tools',
        label    = 'Rauchmelder reparieren',
        groups   = Config.Job,
        distance = Config.Interaction.DistancePanel,
        onSelect = function(data) RepairDeviceAction(data.entity) end
    },
    {
        name     = 'remove_device_smoke',
        icon     = 'fas fa-hammer',
        label    = 'Rauchmelder abmontieren',
        groups   = Config.Job,
        distance = Config.Interaction.DistancePanel,
        onSelect = function(data) RemoveDeviceAction(data.entity) end
    }
})

exports.ox_target:addModel(Config.Devices["siren"].model, {
    {
        name     = 'repair_device_siren',
        icon     = 'fas fa-tools',
        label    = 'Sirene reparieren',
        groups   = Config.Job,
        distance = Config.Interaction.DistancePanel,
        onSelect = function(data) RepairDeviceAction(data.entity) end
    },
    {
        name     = 'remove_device_siren',
        icon     = 'fas fa-hammer',
        label    = 'Sirene abmontieren',
        groups   = Config.Job,
        distance = Config.Interaction.DistancePanel,
        onSelect = function(data) RemoveDeviceAction(data.entity) end
    }
})

---------------------------------------------------------
-- Initialisierung & Cleanup
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:client:loadInitialDevices', function(devices)
    for _, obj in ipairs(spawnedObjects) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end
    spawnedObjects   = {}
    panelObjects     = {}  -- global
    sirenObjects     = {}
    smokeObjects     = {}
    devicesBySystem  = {}
    activeAlarms     = {}
    triggeredSmoke   = {}
    -- Laufende Sirenen-Sounds stoppen
    for _, audio in pairs(sirenAudio) do
        if audio.soundId ~= -1 then
            StopSound(audio.soundId)
            ReleaseSoundId(audio.soundId)
        end
    end
    sirenAudio = {}

    for _, data in ipairs(devices) do CreateBMAProp(data) end
end)

AddEventHandler('onResourceStart', function(resourceName)
    if GetCurrentResourceName() ~= resourceName then return end
    TriggerServerEvent('d4rk_firealert:server:requestSync')
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

    -- Sirenen-Sounds sauber beenden
    for _, audio in pairs(sirenAudio) do
        if audio.soundId ~= -1 then
            StopSound(audio.soundId)
            ReleaseSoundId(audio.soundId)
        end
    end
    sirenAudio = {}

    lib.hideTextUI()
    print("^1[d4rk_firealert] Client-seitige Props bereinigt.^7")
end)