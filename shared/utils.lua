-- d4rk_firealert: shared/utils.lua
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

-- FIX #1: Getrennte Funktionen für Client und Server, um Argument-Verwechslung zu vermeiden.

-- SERVERSEITIG: Erwartet eine Spieler-ID (source) und den Job-Namen
function Utils.HasJobServer(serverId, allowedJobs)
    if not allowedJobs or allowedJobs == "" then return true end
    if not serverId then return false end

    local jobName = nil

    if GetResourceState('qbx_core') == 'started' then
        local Player = exports.qbx_core:GetPlayer(serverId)
        if Player then jobName = Player.PlayerData.job.name end
    elseif GetResourceState('qb-core') == 'started' then
        local QBCore = exports['qb-core']:GetCoreObject()
        local Player = QBCore.Functions.GetPlayer(serverId)
        if Player then jobName = Player.PlayerData.job.name end
    end

    if not jobName then return false end

    if type(allowedJobs) == "table" then
        for _, name in ipairs(allowedJobs) do
            if jobName == name then return true end
        end
        return false
    end

    return jobName == allowedJobs
end

-- CLIENTSEITIG: Kein serverId benötigt, liest den eigenen Job aus
function Utils.HasJobClient(allowedJobs)
    if not allowedJobs or allowedJobs == "" then return true end

    local jobName = nil

    if GetResourceState('qbx_core') == 'started' then
        jobName = exports.qbx_core:GetPlayerData().job.name
    elseif GetResourceState('qb-core') == 'started' then
        local QBCore = exports['qb-core']:GetCoreObject()
        jobName = QBCore.Functions.GetPlayerData().job.name
    end

    if not jobName then return false end

    if type(allowedJobs) == "table" then
        for _, name in ipairs(allowedJobs) do
            if jobName == name then return true end
        end
        return false
    end

    return jobName == allowedJobs
end

-- Rückwärtskompatibel: Die alte HasJob-Funktion leitet je nach Kontext weiter
function Utils.HasJob(serverIdOrJob, allowedJobs)
    if IsDuplicityVersion() then
        -- Serverseitig: erstes Argument ist immer die serverId
        return Utils.HasJobServer(serverIdOrJob, allowedJobs)
    else
        -- Clientseitig: erstes Argument ist der Job (kein serverId nötig)
        return Utils.HasJobClient(serverIdOrJob)
    end
end
