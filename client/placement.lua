-- d4rk_firealert: client/placement.lua
local isPlacing = false

-- FIX #2: ghost als globale Variable deklariert, damit main.lua beim
-- onResourceStop darauf zugreifen und das Objekt korrekt löschen kann.
ghost = nil

RegisterCommand('install_bma', function(source, args)
    if isPlacing then return end

    local deviceType = args[1]
    if not Config.Devices[deviceType] then
        lib.notify({ title = 'Fehler', description = 'Ungültiger Typ! (panel/smoke/pull/siren)', type = 'error' })
        return
    end

    -- FIX #1: Utils.HasJobClient verwenden (kein serverId auf Client-Seite).
    -- Vorher: Utils.HasJob(Config.Job) → serverId = "firefighter", allowedJobs = nil → immer true!
    if not Utils.HasJobClient(Config.Job) then
        lib.notify({ title = 'Fehler', description = 'Du hast nicht die Berechtigung für diesen Befehl.', type = 'error' })
        return
    end

    local model = Config.Devices[deviceType].model
    lib.requestModel(model)

    -- FIX #2: Globale Variable ghost (kein local)
    ghost = CreateObject(model, GetEntityCoords(cache.ped), false, false, false)
    SetEntityAlpha(ghost, 150, false)
    SetEntityCollision(ghost, false, false)

    isPlacing = true

    local h     = 0.0  -- Höhe Offset
    local d     = 1.5  -- Distanz Offset
    local r     = 0.0  -- Rotation Offset (Z-Achse)
    local pitch = 0.0  -- Rotation Offset (X-Achse)

    lib.showTextUI(
        '**BMA PLATZIERUNG** \n[E] Bestätigen | [G] Abbrechen \n[↑/↓] Höhe | [←/→] Rotation \n[Mausrad] Distanz | [ALT] Pitch',
        { position = "left-center" }
    )

    CreateThread(function()
        while DoesEntityExist(ghost) do
            Wait(0)

            -- Steuerungslogik deaktivieren
            DisableControlAction(0, 24, true) -- Attack
            DisableControlAction(0, 25, true) -- Aim
            DisableControlAction(0, 14, true) -- Scroll Up
            DisableControlAction(0, 15, true) -- Scroll Down

            -- Höhe (Pfeiltasten oben/unten, nur wenn ALT NICHT gedrückt)
            if not IsControlPressed(0, 19) then
                if IsControlPressed(0, 172) then h = h + 0.01 end
                if IsControlPressed(0, 173) then h = h - 0.01 end
            end

            -- Rotation (Pfeiltasten links/rechts)
            if IsControlPressed(0, 174) then r = r + 2.0 end
            if IsControlPressed(0, 175) then r = r - 2.0 end

            -- Distanz (Mausrad)
            if IsDisabledControlPressed(0, 14) then d = d + 0.1 end
            if IsDisabledControlPressed(0, 15) then d = d - 0.1 end

            -- Pitch (ALT + Pfeiltasten oben/unten)
            if IsControlPressed(0, 19) then
                if IsControlPressed(0, 172) then pitch = pitch + 2.0 end
                if IsControlPressed(0, 173) then pitch = pitch - 2.0 end
            end

            -- Berechnung der Position
            local playerRot = GetEntityRotation(cache.ped)
            local offset    = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, d, h)

            SetEntityCoords(ghost, offset.x, offset.y, offset.z)
            SetEntityRotation(ghost, playerRot.x + pitch, playerRot.y, playerRot.z + r, 2, true)

            -- BESTÄTIGEN (E)
            if IsControlJustPressed(0, 38) then
                local finalCoords = GetEntityCoords(ghost)
                local finalRot    = GetEntityRotation(ghost)

                local input = lib.inputDialog('BMA Konfiguration', {
                    { type = 'input', label = 'Zone / Raumname',                          placeholder = 'z.B. Empfang',    required = true },
                    { type = 'input', label = 'Systemname (Nur bei Zentrale notwendig)',  placeholder = 'Gebäude Name' }
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
