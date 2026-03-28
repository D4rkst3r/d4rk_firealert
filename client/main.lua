-- d4rk_firealert: client/main.lua
spawnedObjects    = {}
panelObjects      = {}  -- global: { [systemId] = entity } — wird von placement.lua genutzt
local sirenObjects    = {}  -- { [systemId] = { entity, ... } }
local smokeObjects    = {}  -- { [systemId] = { {obj, deviceId, zone}, ... } }
local sprinklerObjects = {} -- NEU: { [systemId] = { {obj, deviceId, zone}, ... } }
local devicesBySystem = {}  -- { [systemId] = { entity, ... } } — für O(1) Gerätelisten
local deviceEntityMap = {}  -- NEU: { [deviceId] = entity } — für O(1) Lookup nach ID

local activeAlarms        = {}  -- { [systemId] = true/false }
local triggeredSmoke      = {}  -- { [deviceId] = true } — verhindert Doppel-Auslösung
local activeSprinklers    = {}  -- NEU: { [deviceId] = particleHandle } — aktive Partikel-Handles
local manualSprinklers    = {}  -- NEU: { [deviceId] = true } — manuell aktivierte Sprinkler
local sirenAudio          = {}  -- { [systemId] = { soundId, lastPlayed } }

---------------------------------------------------------
-- Option C: Panels in der Nähe finden (wird von placement.lua genutzt)
---------------------------------------------------------

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
    table.sort(results, function(a, b) return a.dist < b.dist end)
    return results
end

local DeviceLabels = {
    [GetHashKey('prop_fire_alarm_03')]              = { label = 'Rauchmelder',     icon = 'wind'          },
    [GetHashKey('prop_fire_alarm_01')]              = { label = 'Handfeuermelder', icon = 'hand-point-up' },
    [GetHashKey('m23_1_prop_m31_controlpanel_02a')] = { label = 'Zentrale',        icon = 'terminal'      },
    [GetHashKey('prop_fire_alarm_02')]              = { label = 'Sirene',          icon = 'bell'          },
    [GetHashKey('prop_water_pipe_dist')]            = { label = 'Sprinkler',       icon = 'droplet'       },
}

---------------------------------------------------------
-- Tracking: Prop nach Typ in die richtigen Maps eintragen
---------------------------------------------------------

local function TrackProp(obj, data)
    local sId   = data.system_id
    local dId   = data.id
    local model = GetEntityModel(obj)

    -- In devicesBySystem und deviceEntityMap für schnellen Lookup eintragen
    if not devicesBySystem[sId] then devicesBySystem[sId] = {} end
    table.insert(devicesBySystem[sId], obj)
    deviceEntityMap[dId] = obj

    if model == Config.Devices["panel"].model then
        panelObjects[sId] = obj

    elseif model == Config.Devices["siren"].model then
        if not sirenObjects[sId] then sirenObjects[sId] = {} end
        table.insert(sirenObjects[sId], obj)

    elseif model == Config.Devices["smoke"].model then
        if not smokeObjects[sId] then smokeObjects[sId] = {} end
        table.insert(smokeObjects[sId], { obj = obj, deviceId = dId, zone = data.zone })

    -- NEU: Sprinkler-Tracking
    elseif Config.Devices["sprinkler"] and model == Config.Devices["sprinkler"].model then
        if not sprinklerObjects[sId] then sprinklerObjects[sId] = {} end
        table.insert(sprinklerObjects[sId], { obj = obj, deviceId = dId, zone = data.zone })
    end
end

-- Prop aus allen Tracking-Maps entfernen
local function UntrackProp(obj)
    local state = Entity(obj).state
    local sId   = state.systemId
    local dId   = state.deviceId

    if devicesBySystem[sId] then
        for i, o in ipairs(devicesBySystem[sId]) do
            if o == obj then table.remove(devicesBySystem[sId], i) break end
        end
    end

    deviceEntityMap[dId] = nil

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

    -- NEU: Sprinkler aus Tracking entfernen und ggf. Partikel stoppen
    if sprinklerObjects[sId] then
        for i, s in ipairs(sprinklerObjects[sId]) do
            if s.obj == obj then
                -- Partikel-Effekt stoppen falls aktiv
                if activeSprinklers[dId] then
                    StopParticleFxLooped(activeSprinklers[dId], false)
                    activeSprinklers[dId] = nil
                end
                manualSprinklers[dId] = nil
                table.remove(sprinklerObjects[sId], i)
                break
            end
        end
    end

    triggeredSmoke[dId] = nil

    for i, o in ipairs(spawnedObjects) do
        if o == obj then table.remove(spawnedObjects, i) break end
    end
end

---------------------------------------------------------
-- Prop in der Welt erstellen
---------------------------------------------------------

function CreateBMAProp(data)
    if not Config.Devices[data.type] then return end

    local model  = Config.Devices[data.type].model
    local coords = type(data.coords)   == "string" and json.decode(data.coords)   or data.coords
    local rot    = type(data.rotation) == "string" and json.decode(data.rotation) or data.rotation

    lib.requestModel(model)
    local obj = CreateObject(model, coords.x, coords.y, coords.z, false, false, false)

    -- State Bags: Daten am Objekt speichern damit ox_target und andere Systeme drauf zugreifen können
    Entity(obj).state:set('systemId',     data.system_id,     true)
    Entity(obj).state:set('zoneName',     data.zone,          true)
    Entity(obj).state:set('deviceId',     data.id,            true)
    Entity(obj).state:set('deviceHealth', data.health or 100, true)

    if model == Config.Devices["panel"].model then
        Entity(obj).state:set('systemName',
            data.system_name or ('System #' .. tostring(data.system_id)), true)
    end

    SetEntityRotation(obj, rot.x, rot.y, rot.z, 2, true)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    table.insert(spawnedObjects, obj)

    TrackProp(obj, data)
end

---------------------------------------------------------
-- Aktionen (werden von ox_target aufgerufen)
---------------------------------------------------------

function RemoveDeviceAction(entity)
    local alert = lib.alertDialog({
        header = 'Gerät entfernen?',
        content = 'Möchtest du dieses BMA-Gerät wirklich dauerhaft entfernen?',
        centered = true, cancel = true
    })

    if alert == 'confirm' then
        local progress = lib.progressBar({
            duration = 5000, label = 'Demontiere Gerät...', useWhileDead = false, canCancel = true,
            anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' }
        })
        if progress then
            TriggerServerEvent('d4rk_firealert:server:removeDevice', Entity(entity).state.deviceId)
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
        duration = 8000, label = 'Repariere Melder...', useWhileDead = false, canCancel = true,
        anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' }
    })
    if progress then
        TriggerServerEvent('d4rk_firealert:server:repairDevice', Entity(entity).state.deviceId)
    end
end

-- NEU: Sabotage-Aktion — für jeden Spieler (keine Job-Restriktion)
local function SabotageDeviceAction(entity)
    local health = Entity(entity).state.deviceHealth or 100
    if health <= 0 then
        lib.notify({ title = 'BMA', description = 'Gerät ist bereits zerstört.', type = 'error' })
        return
    end

    local progress = lib.progressBar({
        duration     = Config.Sabotage.ActionDuration,
        label        = 'Beschädige Gerät...',
        useWhileDead = false,
        canCancel    = true,
        anim         = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' }
    })

    if progress then
        local deviceId     = Entity(entity).state.deviceId
        local deviceCoords = GetEntityCoords(entity)
        TriggerServerEvent('d4rk_firealert:server:sabotageDevice', deviceId, deviceCoords)
    end
end

---------------------------------------------------------
-- Events vom Server
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:client:updateSystemStatus', function(systemId, status)
    local id = tonumber(systemId)
    activeAlarms[id] = (status == 'alarm')

    if status == 'normal' then
        lib.notify({ title = 'BMA', description = 'System ' .. systemId .. ' quittiert.', type = 'inform' })

        -- Sirenen-Sound stoppen
        if sirenAudio[id] and sirenAudio[id].soundId ~= -1 then
            StopSound(sirenAudio[id].soundId)
            ReleaseSoundId(sirenAudio[id].soundId)
        end
        sirenAudio[id] = nil

        -- Rauchmelder-Trigger zurücksetzen
        if smokeObjects[id] then
            for _, s in ipairs(smokeObjects[id]) do triggeredSmoke[s.deviceId] = nil end
        end

        -- NEU: Alarm-gesteuerte Sprinkler deaktivieren
        -- (manuell aktivierte bleiben aktiv bis manuell deaktiviert)
        if sprinklerObjects[id] then
            for _, s in ipairs(sprinklerObjects[id]) do
                if activeSprinklers[s.deviceId] and not manualSprinklers[s.deviceId] then
                    StopParticleFxLooped(activeSprinklers[s.deviceId], false)
                    activeSprinklers[s.deviceId] = nil
                end
            end
        end

    elseif status == 'alarm' then
        -- NEU: Bei Alarm alle Sprinkler des Systems aktivieren
        if sprinklerObjects[id] then
            for _, s in ipairs(sprinklerObjects[id]) do
                if DoesEntityExist(s.obj) and not activeSprinklers[s.deviceId] then
                    local c       = GetEntityCoords(s.obj)
                    local handle  = StartParticleFxLoopedAtCoord(
                        Config.Sprinkler.ParticleEffect,
                        c.x, c.y, c.z,
                        0.0, 0.0, 0.0,
                        Config.Sprinkler.ParticleScale,
                        false, false, false, false
                    )
                    activeSprinklers[s.deviceId] = handle
                end
            end
        end

    elseif status == 'trouble' then
        lib.notify({ title = 'BMA STÖRUNG', description = 'System ' .. systemId .. ' meldet Defekt!', type = 'warning' })
    end
end)

RegisterNetEvent('d4rk_firealert:client:updateDeviceHealth', function(deviceId, newHealth)
    -- NEU: deviceEntityMap für O(1) Lookup statt alle spawnedObjects durchsuchen
    local obj = deviceEntityMap[deviceId]
    if obj and DoesEntityExist(obj) then
        Entity(obj).state:set('deviceHealth', newHealth, true)
    end
end)

RegisterNetEvent('d4rk_firealert:client:addDevice', function(data)
    CreateBMAProp(data)
end)

RegisterNetEvent('d4rk_firealert:client:removeDevice', function(deviceId)
    local obj = deviceEntityMap[deviceId]
    if obj and DoesEntityExist(obj) then
        UntrackProp(obj)
        DeleteEntity(obj)
    end
end)

RegisterNetEvent('d4rk_firealert:client:playAlarmSound', function(coords)
    local dist = #(GetEntityCoords(cache.ped) - vector3(coords.x, coords.y, coords.z))
    if dist < 80.0 then
        PlaySoundFrontend(-1, "TIMER_STOP", "HUD_MINI_GAME_SOUNDSET", 1)
        lib.notify({ title = '🚨 BMA ALARM', type = 'error', position = 'top' })
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
        id = 'bma_alarm_log', title = 'Alarm-Protokoll (letzte 10)', menu = 'bma_main_menu', options = options
    })
    lib.showContext('bma_alarm_log')
end)

-- NEU: Einzelnen Sprinkler manuell ein-/ausschalten (vom Server gebroadcastet)
RegisterNetEvent('d4rk_firealert:client:toggleSprinkler', function(deviceId, activate)
    local obj = deviceEntityMap[deviceId]
    if not obj or not DoesEntityExist(obj) then return end

    if activate then
        if activeSprinklers[deviceId] then return end  -- bereits aktiv
        local c      = GetEntityCoords(obj)
        local handle = StartParticleFxLoopedAtCoord(
            Config.Sprinkler.ParticleEffect,
            c.x, c.y, c.z,
            0.0, 0.0, 0.0,
            Config.Sprinkler.ParticleScale,
            false, false, false, false
        )
        activeSprinklers[deviceId] = handle
        manualSprinklers[deviceId] = true
    else
        if activeSprinklers[deviceId] then
            StopParticleFxLooped(activeSprinklers[deviceId], false)
            activeSprinklers[deviceId] = nil
        end
        manualSprinklers[deviceId] = nil
    end
end)

---------------------------------------------------------
-- Threads
---------------------------------------------------------

-- Blink-Thread: Rote Umrandung und Licht bei aktiven Alarmen
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
CreateThread(function()
    local SOUND_NAME  = "Altitude_Warning"
    local SOUND_SET   = "EXILE_1"
    local INTERVAL_MS = 2500
    local RANGE       = 40

    RequestScriptAudioBank(SOUND_SET, false)
    Wait(500)

    while true do
        Wait(500)

        for sId, isAlarm in pairs(activeAlarms) do
            if isAlarm and sirenObjects[sId] and #sirenObjects[sId] > 0 then
                local now = GetGameTimer()
                if not sirenAudio[sId] then sirenAudio[sId] = { soundId = -1, lastPlayed = 0 } end

                local audio = sirenAudio[sId]
                if (now - audio.lastPlayed) >= INTERVAL_MS then
                    if audio.soundId ~= -1 then
                        StopSound(audio.soundId)
                        ReleaseSoundId(audio.soundId)
                        audio.soundId = -1
                    end

                    local played       = false
                    local playerCoords = GetEntityCoords(cache.ped)

                    for _, siren in ipairs(sirenObjects[sId]) do
                        if DoesEntityExist(siren) then
                            local c    = GetEntityCoords(siren)
                            local dist = #(playerCoords - c)
                            if dist <= RANGE then
                                local soundId = GetSoundId()
                                PlaySoundFromCoord(soundId, SOUND_NAME, c.x, c.y, c.z, SOUND_SET, false, 0, false)
                                audio.soundId = soundId
                            end
                            audio.lastPlayed = now
                            played = true
                            break
                        end
                    end

                    if not played then sirenAudio[sId] = nil end
                end
            end
        end

        for sId, audio in pairs(sirenAudio) do
            if not activeAlarms[sId] then
                if audio.soundId ~= -1 then StopSound(audio.soundId) ReleaseSoundId(audio.soundId) end
                sirenAudio[sId] = nil
            end
        end
    end
end)

-- Rauchmelder-Thread: Feuer in der Nähe erkennen
CreateThread(function()
    if not Config.AutoSmoke.Enabled then return end
    while true do
        Wait(Config.AutoSmoke.CheckInterval * 1000)
        for sId, smokeList in pairs(smokeObjects) do
            if not activeAlarms[sId] then
                for _, smokeData in ipairs(smokeList) do
                    if DoesEntityExist(smokeData.obj) and not triggeredSmoke[smokeData.deviceId] then
                        local c         = GetEntityCoords(smokeData.obj)
                        local fireCount = GetNumberOfFiresInRange(c.x, c.y, c.z, Config.AutoSmoke.CheckRadius)
                        if fireCount > 0 then
                            triggeredSmoke[smokeData.deviceId] = true
                            lib.notify({
                                title = '🔥 Rauchmelder ausgelöst',
                                description = 'Zone: ' .. (smokeData.zone or 'Unbekannt'),
                                type = 'error', position = 'top'
                            })
                            TriggerServerEvent('d4rk_firealert:server:triggerAutoAlarm',
                                sId, smokeData.zone or 'Automatischer Rauchmelder', c)
                            break
                        end
                    end
                end
            end
        end
    end
end)

-- NEU: Sprinkler-Thread — Feuer im Radius aktiver Sprinkler löschen
CreateThread(function()
    -- Partikel-Dictionary vorab laden damit der Effekt sofort sichtbar ist
    RequestNamedPtfxAsset(Config.Sprinkler.ParticleDict)
    while not HasNamedPtfxAssetLoaded(Config.Sprinkler.ParticleDict) do Wait(100) end

    while true do
        Wait(Config.Sprinkler.ExtinguishInterval)

        for deviceId, handle in pairs(activeSprinklers) do
            local obj = deviceEntityMap[deviceId]
            if obj and DoesEntityExist(obj) then
                local c = GetEntityCoords(obj)
                -- Feuer im Löschradius des Sprinklers entfernen
                RemoveAllFiresInRange(c.x, c.y, c.z, Config.Sprinkler.ExtinguishRadius)
            else
                -- Objekt existiert nicht mehr — Partikel aufräumen
                if handle then StopParticleFxLooped(handle, false) end
                activeSprinklers[deviceId] = nil
            end
        end
    end
end)

---------------------------------------------------------
-- Menüs (Panel-Kontextmenü in-world)
---------------------------------------------------------

local function OpenDeviceList(sId)
    local deviceElements = {}
    local count          = 0
    local playerCoords   = GetEntityCoords(cache.ped)

    for _, obj in ipairs(devicesBySystem[sId] or {}) do
        if DoesEntityExist(obj) then
            count = count + 1
            local state      = Entity(obj).state
            local coords     = GetEntityCoords(obj)
            local zone       = state.zoneName    or "Unbekannte Zone"
            local health     = state.deviceHealth or 100
            local model      = GetEntityModel(obj)
            local deviceInfo = DeviceLabels[model] or { label = 'Unbekannt', icon = 'microchip' }
            local healthStr  = health >= 75 and ('🟢 ' .. health .. '%')
                            or health >= 30 and ('🟡 ' .. health .. '%')
                            or ('🔴 ' .. health .. '%')

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
        id = 'bma_device_list',
        title = 'Verbundene Geräte (Gesamt: ' .. count .. ')',
        menu = 'bma_main_menu',
        options = deviceElements
    })
    lib.showContext('bma_device_list')
end

local function OpenBMAMenu(entity)
    local sId = Entity(entity).state.systemId
    if not sId then return end

    lib.registerContext({
        id = 'bma_main_menu',
        title = 'BMA Zentrale - ID: ' .. sId,
        options = {
            {
                title = 'Verbundene Geräte',
                description = 'Alle Melder inkl. Health-Status.',
                icon = 'list-check',
                onSelect = function() OpenDeviceList(sId) end
            },
            {
                title = 'Alarm-Protokoll',
                description = 'Letzte 10 Alarm-Ereignisse.',
                icon = 'clipboard-list',
                onSelect = function()
                    TriggerServerEvent('d4rk_firealert:server:getAlarmLog', sId)
                end
            },
            {
                title = 'Alarm quittieren (ACK)',
                description = 'Stoppt Sirenen und Blinken.',
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
-- ox_target: Interaktionen für alle Gerätetypen
---------------------------------------------------------

exports.ox_target:addModel(Config.Devices["panel"].model, {
    {
        name = 'open_bma', icon = 'fas fa-terminal', label = 'System-Konsole öffnen',
        groups = Config.Job, distance = Config.Interaction.DistancePanel,
        onSelect = function(data) OpenBMAMenu(data.entity) end
    },
    {
        name = 'remove_device_panel', icon = 'fas fa-hammer', label = 'Zentrale abmontieren',
        groups = Config.Job, distance = Config.Interaction.DistancePanel,
        onSelect = function(data) RemoveDeviceAction(data.entity) end
    }
})

exports.ox_target:addModel(Config.Devices["pull"].model, {
    {
        name = 'pull_alarm', icon = 'fas fa-hand-rock', label = 'Alarm auslösen',
        distance = Config.Interaction.DistanceDevice,
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
        name = 'repair_device_pull', icon = 'fas fa-tools', label = 'Melder reparieren',
        groups = Config.Job, distance = Config.Interaction.DistanceDevice,
        onSelect = function(data) RepairDeviceAction(data.entity) end
    },
    {
        name = 'remove_device_pull', icon = 'fas fa-hammer', label = 'Melder abmontieren',
        groups = Config.Job, distance = Config.Interaction.DistanceDevice,
        onSelect = function(data) RemoveDeviceAction(data.entity) end
    },
    -- NEU: Sabotage — keine Job-Restriktion (jeder Spieler kann sabotieren)
    {
        name = 'sabotage_pull', icon = 'fas fa-bolt', label = '⚠ Gerät beschädigen',
        distance = Config.Interaction.DistanceDevice,
        onSelect = function(data) SabotageDeviceAction(data.entity) end
    },
})

exports.ox_target:addModel(Config.Devices["smoke"].model, {
    {
        name = 'repair_device_smoke', icon = 'fas fa-tools', label = 'Rauchmelder reparieren',
        groups = Config.Job, distance = Config.Interaction.DistanceDevice,
        onSelect = function(data) RepairDeviceAction(data.entity) end
    },
    {
        name = 'remove_device_smoke', icon = 'fas fa-hammer', label = 'Rauchmelder abmontieren',
        groups = Config.Job, distance = Config.Interaction.DistanceDevice,
        onSelect = function(data) RemoveDeviceAction(data.entity) end
    },
    {
        name = 'sabotage_smoke', icon = 'fas fa-bolt', label = '⚠ Gerät beschädigen',
        distance = Config.Interaction.DistanceDevice,
        onSelect = function(data) SabotageDeviceAction(data.entity) end
    },
})

exports.ox_target:addModel(Config.Devices["siren"].model, {
    {
        name = 'repair_device_siren', icon = 'fas fa-tools', label = 'Sirene reparieren',
        groups = Config.Job, distance = Config.Interaction.DistanceDevice,
        onSelect = function(data) RepairDeviceAction(data.entity) end
    },
    {
        name = 'remove_device_siren', icon = 'fas fa-hammer', label = 'Sirene abmontieren',
        groups = Config.Job, distance = Config.Interaction.DistanceDevice,
        onSelect = function(data) RemoveDeviceAction(data.entity) end
    },
    {
        name = 'sabotage_siren', icon = 'fas fa-bolt', label = '⚠ Gerät beschädigen',
        distance = Config.Interaction.DistanceDevice,
        onSelect = function(data) SabotageDeviceAction(data.entity) end
    },
})

-- NEU: ox_target für Sprinkleranlage
exports.ox_target:addModel(Config.Devices["sprinkler"].model, {
    {
        -- Manuell aktivieren — nur Feuerwehr
        name = 'sprinkler_on', icon = 'fas fa-droplet', label = 'Sprinkler aktivieren',
        groups = Config.Job, distance = Config.Interaction.DistanceDevice,
        onSelect = function(data)
            local dId = Entity(data.entity).state.deviceId
            TriggerServerEvent('d4rk_firealert:server:toggleSprinkler', dId, true)
        end
    },
    {
        -- Manuell deaktivieren — nur Feuerwehr
        name = 'sprinkler_off', icon = 'fas fa-droplet-slash', label = 'Sprinkler deaktivieren',
        groups = Config.Job, distance = Config.Interaction.DistanceDevice,
        onSelect = function(data)
            local dId = Entity(data.entity).state.deviceId
            TriggerServerEvent('d4rk_firealert:server:toggleSprinkler', dId, false)
        end
    },
    {
        name = 'repair_device_sprinkler', icon = 'fas fa-tools', label = 'Sprinkler reparieren',
        groups = Config.Job, distance = Config.Interaction.DistanceDevice,
        onSelect = function(data) RepairDeviceAction(data.entity) end
    },
    {
        name = 'remove_device_sprinkler', icon = 'fas fa-hammer', label = 'Sprinkler abmontieren',
        groups = Config.Job, distance = Config.Interaction.DistanceDevice,
        onSelect = function(data) RemoveDeviceAction(data.entity) end
    },
    {
        name = 'sabotage_sprinkler', icon = 'fas fa-bolt', label = '⚠ Gerät beschädigen',
        distance = Config.Interaction.DistanceDevice,
        onSelect = function(data) SabotageDeviceAction(data.entity) end
    },
})

---------------------------------------------------------
-- Initialisierung & Cleanup
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:client:loadInitialDevices', function(devices)
    -- Alle bestehenden Props löschen und alle Maps zurücksetzen
    for _, obj in ipairs(spawnedObjects) do
        if DoesEntityExist(obj) then DeleteEntity(obj) end
    end

    -- NEU: Aktive Sprinkler-Partikel vor dem Reset stoppen
    for _, handle in pairs(activeSprinklers) do
        if handle then StopParticleFxLooped(handle, false) end
    end

    spawnedObjects     = {}
    panelObjects       = {}
    sirenObjects       = {}
    smokeObjects       = {}
    sprinklerObjects   = {}  -- NEU
    devicesBySystem    = {}
    deviceEntityMap    = {}  -- NEU
    activeAlarms       = {}
    triggeredSmoke     = {}
    activeSprinklers   = {}  -- NEU
    manualSprinklers   = {}  -- NEU

    for _, audio in pairs(sirenAudio) do
        if audio.soundId ~= -1 then StopSound(audio.soundId) ReleaseSoundId(audio.soundId) end
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

    -- NEU: Sprinkler-Partikel beim Resource-Stop sauber beenden
    for _, handle in pairs(activeSprinklers) do
        if handle then StopParticleFxLooped(handle, false) end
    end
    activeSprinklers = {}

    for _, audio in pairs(sirenAudio) do
        if audio.soundId ~= -1 then StopSound(audio.soundId) ReleaseSoundId(audio.soundId) end
    end
    sirenAudio = {}

    lib.hideTextUI()
    print("^1[d4rk_firealert] Client-seitige Props bereinigt.^7")
end)