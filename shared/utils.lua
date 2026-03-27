-- d4rk_firealert:shared/utils.lua
Utils = {}

-- Formatiert Vektoren für die Datenbank (falls kein JSON genutzt wird)
function Utils.FormatCoords(vector)
    return { x = vector.x, y = vector.y, z = vector.z }
end

-- Distanz-Check für Performance (Client-seitig)
function Utils.GetDistance(coords1, coords2)
    return #(coords1 - coords2)
end

-- Debug Print Funktion
function Utils.Log(msg)
    if Config.Debug then
        print(("^4[d4rk_firealert:DEBUG] ^7%s"):format(msg))
    end
end

-- Job Check (Kompatibilität QBCore / QBX)
function Utils.HasJob(jobName)
    if Config.Framework == "qbx" then
        return exports.qbx_core:GetPlayerData().job.name == jobName
    elseif Config.Framework == "qbcore" then
        local QBCore = exports['qb-core']:GetCoreObject()
        return QBCore.Functions.GetPlayerData().job.name == jobName
    end
    return true -- Fallback für Standalone (muss manuell angepasst werden)
end
