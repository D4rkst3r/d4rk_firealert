RegisterCommand('install_bma', function(source, args)
    local deviceType = args[1]
    if not Config.Devices[deviceType] then return end

    local model = Config.Devices[deviceType].model
    lib.requestModel(model)

    local ghost = CreateObject(model, GetEntityCoords(cache.ped), false, false, false)
    SetEntityAlpha(ghost, 150, false)
    SetEntityCollision(ghost, false, false)
    AttachEntityToEntity(ghost, cache.ped, GetPedBoneIndex(cache.ped, 28422), 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, false, false,
        false, true, 2, true)

    lib.showTextUI('[E] Platzieren  \n[G] Abbrechen', { position = "left-center" })

    CreateThread(function()
        while DoesEntityExist(ghost) do
            if IsControlJustPressed(0, 38) then -- E
                local coords = GetEntityCoords(ghost)
                local rot = GetEntityRotation(ghost)

                local input = lib.inputDialog('BMA Installation', {
                    { type = 'input', label = 'Name der Zone',                 placeholder = 'Lagerhalle 1' },
                    { type = 'input', label = 'Systemname (Nur bei Zentrale)', placeholder = 'Post OP Depot' }
                })

                if input then
                    TriggerServerEvent('d4rk_firealert:server:registerDevice', deviceType, coords, rot, input[1],
                        input[2])
                    DeleteEntity(ghost)
                    lib.hideTextUI()
                end
            elseif IsControlJustPressed(0, 47) then -- G
                DeleteEntity(ghost)
                lib.hideTextUI()
            end
            Wait(0)
        end
    end)
end)
