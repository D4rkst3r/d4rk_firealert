-- d4rk_firealert: client/mdt.lua
local mdtOpen = false

---------------------------------------------------------
-- MDT öffnen
---------------------------------------------------------

local function OpenMDT()
    if mdtOpen then return end

    if not Utils.HasJobClient(Config.Job) then
        lib.notify({ title = 'BMA MDT', description = 'Kein Zugriff — nur für Feuerwehr.', type = 'error' })
        return
    end

    -- Daten vom Server anfordern; Server antwortet mit client:mdt:open
    TriggerServerEvent('d4rk_firealert:server:mdt:getData')
end

---------------------------------------------------------
-- Server schickt Daten → MDT aufschlagen
---------------------------------------------------------

RegisterNetEvent('d4rk_firealert:client:mdt:open', function(data)
    mdtOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ type = 'open', data = data })
end)

---------------------------------------------------------
-- Live-Updates ins MDT weiterleiten (koexistiert mit main.lua-Handlern)
---------------------------------------------------------

AddEventHandler('d4rk_firealert:client:updateSystemStatus', function(systemId, status)
    if mdtOpen then
        SendNUIMessage({ type = 'updateStatus', systemId = systemId, status = status })
    end
end)

AddEventHandler('d4rk_firealert:client:updateDeviceHealth', function(deviceId, newHealth)
    if mdtOpen then
        SendNUIMessage({ type = 'updateHealth', deviceId = deviceId, health = newHealth })
    end
end)

---------------------------------------------------------
-- NUI Callbacks
---------------------------------------------------------

-- MDT schließen
RegisterNUICallback('mdt_close', function(_, cb)
    mdtOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

-- Alarm quittieren direkt aus dem MDT
RegisterNUICallback('mdt_quittieren', function(data, cb)
    TriggerServerEvent('d4rk_firealert:server:quittieren', data.systemId)
    cb('ok')
end)

-- Daten neu laden
RegisterNUICallback('mdt_refresh', function(_, cb)
    TriggerServerEvent('d4rk_firealert:server:mdt:getData')
    cb('ok')
end)

---------------------------------------------------------
-- Command: /bma_mdt
---------------------------------------------------------

RegisterCommand('bma_mdt', function()
    OpenMDT()
end, false)

---------------------------------------------------------
-- ox_target: Feuerwache-Computer öffnet MDT
-- Prop-Modell wird in Config.MDT.ComputerModel gesetzt
-- (nil = ox_target-Integration deaktiviert, nur /bma_mdt nutzen)
---------------------------------------------------------

if Config.MDT and Config.MDT.ComputerModel then
    exports.ox_target:addModel(Config.MDT.ComputerModel, {
        {
            name     = 'open_bma_mdt',
            icon     = 'fas fa-fire-extinguisher',
            label    = 'BMA Terminal öffnen',
            groups   = Config.Job,
            distance = 2.0,
            onSelect = OpenMDT
        }
    })
end