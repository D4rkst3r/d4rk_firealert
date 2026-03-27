-- d4rk_firealert: client/placement.lua
local isPlacing = false
ghost = nil  -- Global damit main.lua beim onResourceStop darauf zugreifen kann

RegisterCommand('install_bma', function(source, args)
    if isPlacing then return end

    local deviceType = args[1]
    if not Config.Devices[deviceType] then
        lib.notify({ title = 'Fehler', description = 'Ungültiger Typ! (panel/smoke/pull/siren)', type = 'error' })
        return
    end

    if not Utils.HasJobClient(Config.Job) then
        lib.notify({ title = 'Fehler', description = 'Keine Berechtigung.', type = 'error' })
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
    -- FIX #5: Startdistanz innerhalb der konfigurierten Grenzen
    local minD  = Config.Placement and Config.Placement.MinDistance or 0.5
    local maxD  = Config.Placement and Config.Placement.MaxDistance or 4.0
    local d     = math.min(1.5, maxD)

    lib.showTextUI(
        '**BMA PLATZIERUNG** \n[E] Bestätigen | [G] Abbrechen \n[↑/↓] Höhe | [←/→] Rotation \n[Mausrad] Distanz (max. ' .. maxD .. 'm) | [ALT] Pitch',
        { position = "left-center" }
    )

    CreateThread(function()
        while DoesEntityExist(ghost) do
            Wait(0)

            DisableControlAction(0, 24, true) -- Attack
            DisableControlAction(0, 25, true) -- Aim
            DisableControlAction(0, 14, true) -- Scroll Up
            DisableControlAction(0, 15, true) -- Scroll Down

            if not IsControlPressed(0, 19) then
                if IsControlPressed(0, 172) then h = h + 0.01 end
                if IsControlPressed(0, 173) then h = h - 0.01 end
            end

            if IsControlPressed(0, 174) then r = r + 2.0 end
            if IsControlPressed(0, 175) then r = r - 2.0 end

            -- FIX #5: Distanz auf Config-Grenzen clampen — kein Fernplatzieren mehr
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

            -- BESTÄTIGEN (E)
            if IsControlJustPressed(0, 38) then
                local finalCoords = GetEntityCoords(ghost)
                local finalRot    = GetEntityRotation(ghost)

                local input = lib.inputDialog('BMA Konfiguration', {
                    { type = 'input', label = 'Zone / Raumname',                         placeholder = 'z.B. Empfang',  required = true },
                    { type = 'input', label = 'Systemname (Nur bei Zentrale notwendig)', placeholder = 'Gebäude Name' }
                })

                if input then
                    TriggerServerEvent('d4rk_firealert:server:registerDevice', deviceType, finalCoords, finalRot, input[1], input[2], currentSystemId)
                    DeleteEntity(ghost)
                    ghost     = nil
                    isPlacing = false
                    lib.hideTextUI()
                    break
                else
                    lib.notify({ description = 'Eingabe abgebrochen.', type = 'inform' })
                end
            end

            -- ABBRECHEN (G)
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