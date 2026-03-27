-- d4rk_firealert: client/placement.lua
local isPlacing = false

RegisterCommand('install_bma', function(source, args)
    if isPlacing then return end
    
    local deviceType = args[1]
    if not Config.Devices[deviceType] then 
        lib.notify({title = 'Fehler', description = 'Ungültiger Typ! (panel/smoke/pull/siren)', type = 'error'})
        return 
    end

    -- Job Check über Utils
    if not Utils.HasJob(Config.Job) then return end

    local model = Config.Devices[deviceType].model
    lib.requestModel(model)

    -- Ghost Objekt erstellen
    local ghost = CreateObject(model, GetEntityCoords(cache.ped), false, false, false)
    SetEntityAlpha(ghost, 150, false)
    SetEntityCollision(ghost, false, false)
    
    isPlacing = true
    
    -- Start-Werte für die Platzierung
    local h = 0.0 -- Höhe Offset
    local d = 1.5 -- Distanz Offset
    local r = 0.0 -- Rotation Offset (Z-Achse)
    local pitch = 0.0 -- Rotation Offset (X-Achse)

    lib.showTextUI('**BMA PLATZIERUNG** \n[E] Bestätigen | [G] Abbrechen \n[↑/↓] Höhe | [←/→] Rotation \n[Mausrad] Distanz | [ALT] Pitch', { position = "left-center" })

    CreateThread(function()
        while DoesEntityExist(ghost) do
            Wait(0)
            
            -- Steuerungslogik deaktivieren
            DisableControlAction(0, 24, true) -- Attack
            DisableControlAction(0, 25, true) -- Aim
            DisableControlAction(0, 14, true) -- Scroll Up
            DisableControlAction(0, 15, true) -- Scroll Down

            -- Höhe (Pfeiltasten oben/unten)
            if not IsControlPressed(0, 19) then -- Nur wenn ALT NICHT gedrückt ist
                if IsControlPressed(0, 172) then h = h + 0.01 end
                if IsControlPressed(0, 173) then h = h - 0.01 end
            end

            -- Rotation (Pfeiltasten links/rechts)
            if IsControlPressed(0, 174) then r = r + 2.0 end
            if IsControlPressed(0, 175) then r = r - 2.0 end

            -- Distanz (Mausrad)
            if IsDisabledControlPressed(0, 14) then d = d + 0.1 end
            if IsDisabledControlPressed(0, 15) then d = d - 0.1 end
            
            -- Pitch (ALT + Pfeiltasten oben/unten) für Wand/Decke
            if IsControlPressed(0, 19) then -- LEFT ALT
                if IsControlPressed(0, 172) then pitch = pitch + 2.0 end
                if IsControlPressed(0, 173) then pitch = pitch - 2.0 end
            end

            -- Berechnung der Position
            local playerRot = GetEntityRotation(cache.ped)
            local offset = GetOffsetFromEntityInWorldCoords(cache.ped, 0.0, d, h)
            
            SetEntityCoords(ghost, offset.x, offset.y, offset.z)
            SetEntityRotation(ghost, playerRot.x + pitch, playerRot.y, playerRot.z + r, 2, true)

            -- BESTÄTIGEN (E)
            if IsControlJustPressed(0, 38) then
                local finalCoords = GetEntityCoords(ghost)
                local finalRot = GetEntityRotation(ghost)

                -- Dialog nach der Platzierung
                local input = lib.inputDialog('BMA Konfiguration', {
                    { type = 'input', label = 'Zone / Raumname', placeholder = 'z.B. Empfang', required = true },
                    { type = 'input', label = 'Systemname (Nur bei Zentrale notwendig)', placeholder = 'Gebäude Name' }
                })

                if input then
                    -- Trigger an den Server mit der globalen currentSystemId aus der main.lua
                    TriggerServerEvent('d4rk_firealert:server:registerDevice', deviceType, finalCoords, finalRot, input[1], input[2], currentSystemId)

                    DeleteEntity(ghost)
                    isPlacing = false
                    lib.hideTextUI()
                    break
                else
                    -- Falls Dialog abgebrochen wurde, darf man weiter platzieren oder muss abbrechen
                    lib.notify({description = 'Eingabe abgebrochen.', type = 'inform'})
                end
            end

            -- ABBRECHEN (G)
            if IsControlJustPressed(0, 47) then
                DeleteEntity(ghost)
                isPlacing = false
                lib.hideTextUI()
                break
            end
        end
    end)
end)