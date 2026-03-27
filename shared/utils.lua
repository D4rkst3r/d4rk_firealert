-- d4rk_firealert:shared/utils.lua
Utils = {}

-- Formatiert Vektoren für die Datenbank
function Utils.FormatCoords(vector)
    return { x = vector.x, y = vector.y, z = vector.z }
end

-- Distanz-Check für Performance
function Utils.GetDistance(coords1, coords2)
    return #(coords1 - coords2)
end

-- Debug Print Funktion
function Utils.Log(msg)
    if Config.Debug then
        print(("^4[d4rk_firealert:DEBUG] ^7%s"):format(msg))
    end
end

function Utils.HasJob(allowedJobs)
    if not allowedJobs or allowedJobs == "" then return true end

    local jobName = nil
    
    -- QBX Way (Nutzt State Bags oder Exports korrekt)
    if GetResourceState('qbx_core') == 'started' then
        -- In QBX ist PlayerData oft direkt über QBX.PlayerData (Client) verfügbar
        -- Wir nutzen hier den sichersten Weg für Client & Server:
        if IsDuplicityVersion() then -- Serverseitig
            local Player = exports.qbx_core:GetPlayer(source)
            if Player then jobName = Player.PlayerData.job.name end
        else -- Clientseitig
            jobName = exports.qbx_core:GetPlayerData().job.name
        end
    -- Klassischer QB-Core Way
    elseif GetResourceState('qb-core') == 'started' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local PlayerData = QBCore.Functions.GetPlayerData()
        if PlayerData and PlayerData.job then jobName = PlayerData.job.name end
    end

    if not jobName then return false end

    -- Check ob allowedJobs eine Tabelle oder ein String ist
    if type(allowedJobs) == "table" then
        for _, name in ipairs(allowedJobs) do
            if jobName == name then return true end
        end
    else
        return jobName == allowedJobs
    end

    return false
end