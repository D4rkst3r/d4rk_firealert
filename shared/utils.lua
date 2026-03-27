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

function Utils.HasJob(serverId, allowedJobs) -- serverId hinzugefügt
    if not allowedJobs or allowedJobs == "" then return true end

    local jobName = nil
    
    if IsDuplicityVersion() then -- SERVERSEITIG
        if not serverId then return false end -- Ohne ID kein Check möglich
        
        if GetResourceState('qbx_core') == 'started' then
            local Player = exports.qbx_core:GetPlayer(serverId) -- Nutze serverId statt source
            if Player then jobName = Player.PlayerData.job.name end
        elseif GetResourceState('qb-core') == 'started' then
            local QBCore = exports['qb-core']:GetCoreObject()
            local Player = QBCore.Functions.GetPlayer(serverId)
            if Player then jobName = Player.PlayerData.job.name end
        end
    else -- CLIENTSEITIG
        if GetResourceState('qbx_core') == 'started' then
            jobName = exports.qbx_core:GetPlayerData().job.name
        elseif GetResourceState('qb-core') == 'started' then
            local QBCore = exports['qb-core']:GetCoreObject()
            jobName = QBCore.Functions.GetPlayerData().job.name
        end
    end

    if not jobName then return false end

    if type(allowedJobs) == "table" then
        for _, name in ipairs(allowedJobs) do
            if jobName == name then return true end
        end
    else
        return jobName == allowedJobs
    end

    return false
end