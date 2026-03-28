-- d4rk_firealert: client/placement.lua
local isPlacing = false
ghost = nil  -- Global damit main.lua beim onResourceStop darauf zugreifen kann

---------------------------------------------------------
-- Option C: System-Auswahl nach Platzierung
--
-- Ablauf für nicht-Panel Geräte:
--   1. Genau 1 Panel in Reichweite  → automatisch verknüpfen + grüne Notify
--   2. Mehrere Panels in Reichweite → ox_lib Auswahlmenü nach Systemname + Distanz
--   3. Kein Panel in Reichweite     → Fehlermeldung (RP-Immersion: kein Globalmenü)
--
-- Panels zeichnen beim Platzieren eine blaue Linie zum Ghost-Objekt
-- damit der Techniker sieht womit er gerade verbunden wäre.
---------------------------------------------------------

local function SelectSystemForDevice(deviceType, finalCoords, finalRot, zone)
    if deviceType == "panel" then
        TriggerServerEvent('d4rk_firealert:server:registerDevice', deviceType, finalCoords, finalRot, zone, nil, nil)
        return
    end

    local radius = Config.Placement and Config.Placement.SystemSearchRadius or 50.0
    local nearby = GetNearbyPanels(finalCoords, radius)

    if #nearby == 0 then
        lib.notify({
            title       = 'BMA Fehler',
            description = 'Kein BMA-Panel in ' .. radius .. 'm Reichweite.\nInstalliere zuerst eine Zentrale.',
            type        = 'error',
            duration    = 6000
        })
        return
    end

    if #nearby == 1 then
        local system = nearby[1]
        lib.notify({
            title       = 'BMA',
            description = '✅ Verknüpft mit: ' .. system.systemName .. ' (' .. string.format('%.1fm', system.dist) .. ')',
            type        = 'success',
            duration    = 4000
        })
        TriggerServerEvent('d4rk_firealert:server:registerDevice',
            deviceType, finalCoords, finalRot, zone, nil, system.systemId)
        return
    end

    local options = {}
    for _, system in ipairs(nearby) do
        table.insert(options, {
            title       = system.systemName,
            description = string.format('%.1fm entfernt', system.dist),
            icon        = 'terminal',
            onSelect    = function()
                lib.notify({
                    title       = 'BMA',
                    description = 'Verknüpft mit: ' .. system.systemName,
                    type        = 'success'
                })
                TriggerServerEvent('d4rk_firealert:server:registerDevice',
                    deviceType, finalCoords, finalRot, zone, nil, system.systemId)
            end
        })
    end

    lib.registerContext({
        id      = 'bma_system_select',
        title   = '🔗 Mit welchem System verknüpfen?',
        options = options
    })
    lib.showContext('bma_system_select')
end

---------------------------------------------------------
-- Placement-Command
---------------------------------------------------------

RegisterCommand('install_bma', function(source, args)
    if isPlacing then return end

    local deviceType = args[1]
    if not Config.Devices[deviceType] then
        -- FIX: Sprinkler als gültigen Typ ergänzt
        lib.notify({ title = 'Fehler', description = 'Ungültiger Typ! (panel/smoke/pull/siren/sprinkler)', type = 'error' })
        return
    end

    if not Utils.HasJobClient(Config.Job) then
        lib.notify({ title = 'Fehler', description = 'Keine Berechtigung.', type = 'error' })
        return
    end

    local isPanel = (deviceType == "panel")

    if not isPanel and not next(panelObjects) then
        lib.notify({
            title       = 'BMA Hinweis',
            description = 'Noch keine Zentrale installiert. Starte mit /install_bma panel.',
            type        = 'warning',
            duration    = 5000
        })
        return
    end

    local model = Config.Devices[deviceType].model
    lib.requestModel(model)

    ghost = CreateObject(model, GetEntityCoords(cache.ped), false, false, false)
    SetEntityAlpha(ghost, 150, false)
    SetEntityCollision(ghost, false, false)

    isPlacing = true

    local h     = 0.0
    local r     = 0.0
    local pitch = 0.0
    local minD  = Config.Placement and Config.Placement.MinDistance or 0.5
    local maxD  = Config.Placement and Config.Placement.MaxDistance or 4.0
    local d     = math.min(1.5, maxD)

    local hint = isPanel
        and '**BMA PLATZIERUNG** (Zentrale)\n[E] Bestätigen | [G] Abbrechen\n[↑/↓] Höhe | [←/→] Rotation | [Mausrad] Distanz | [ALT] Pitch'
        or  ('**BMA PLATZIERUNG** (' .. Config.Devices[deviceType].label .. ')\n[E] Bestätigen | [G] Abbrechen\n[↑/↓] Höhe | [←/→] Rotation | [Mausrad] Distanz | [ALT] Pitch\n🔗 System wird automatisch per Nähe erkannt')

    lib.showTextUI(hint, { position = "left-center" })

    CreateThread(function()
        while DoesEntityExist(ghost) do
            Wait(0)

            DisableControlAction(0, 24, true)
            DisableControlAction(0, 25, true)
            DisableControlAction(0, 14, true)
            DisableControlAction(0, 15, true)

            if not IsControlPressed(0, 19) then
                if IsControlPressed(0, 172) then h = h + 0.01 end
                if IsControlPressed(0, 173) then h = h - 0.01 end
            end

            if IsControlPressed(0, 174) then r = r + 2.0 end
            if IsControlPressed(0, 175) then r = r - 2.0 end

            if IsDisabledControlPressed(0, 14) then d = d + 0.05 end
            if IsDisabledControlPressed(0, 15) then d = d - 0.05 end
            d = math.max(minD, math.min(maxD, d))

            if IsControlPressed(0, 19) then
                if IsControlPressed(0, 172) then pitch = pitch + 2.0 end
                if IsControlPressed(0, 173) then pitch = pitch - 2.0 end
            end

            local playerRot = GetEntityRotation(cache.ped)
            local offset    = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, d, h)

            SetEntityCoords(ghost, offset.x, offset.y, offset.z)
            SetEntityRotation(ghost, playerRot.x + pitch, playerRot.y, playerRot.z + r, 2, true)

            if not isPanel then
                local radius = Config.Placement and Config.Placement.SystemSearchRadius or 50.0
                local nearby = GetNearbyPanels(offset, radius)
                for _, system in ipairs(nearby) do
                    if system.dist < 30.0 then
                        local panelCoords = GetEntityCoords(system.entity)
                        DrawLine(
                            offset.x,       offset.y,       offset.z,
                            panelCoords.x,  panelCoords.y,  panelCoords.z,
                            0, 180, 255, 200
                        )
                    end
                end
            end

            if IsControlJustPressed(0, 38) then
                local finalCoords = GetEntityCoords(ghost)
                local finalRot    = GetEntityRotation(ghost)

                local inputFields = isPanel and {
                    { type = 'input', label = 'Gebäude / Systemname', placeholder = 'z.B. Krankenhaus',   required = true },
                    { type = 'input', label = 'Zone / Raumname',      placeholder = 'z.B. Leitstelle EG'                 },
                } or {
                    { type = 'input', label = 'Zone / Raumname', placeholder = 'z.B. Küche EG', required = true },
                }

                local input = lib.inputDialog('BMA Konfiguration', inputFields)

                if input then
                    DeleteEntity(ghost)
                    ghost     = nil
                    isPlacing = false
                    lib.hideTextUI()

                    if isPanel then
                        TriggerServerEvent('d4rk_firealert:server:registerDevice',
                            deviceType,
                            finalCoords,
                            finalRot,
                            input[2] or 'Panel',
                            input[1],
                            nil
                        )
                    else
                        SelectSystemForDevice(deviceType, finalCoords, finalRot, input[1])
                    end
                    break
                else
                    lib.notify({ description = 'Eingabe abgebrochen.', type = 'inform' })
                end
            end

            if IsControlJustPressed(0, 47) then
                DeleteEntity(ghost)
                ghost     = nil
                isPlacing = false
                lib.hideTextUI()
                break
            end
        end
    end)
end)