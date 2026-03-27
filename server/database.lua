-- d4rk_firealert: server/database.lua
db = {}

function db.createSystem(name, coords)
    return MySQL.insert.await('INSERT INTO fire_systems (name, coords) VALUES (?, ?)', {
        name, json.encode(coords)
    })
end

function db.addDevice(systemId, type, coords, rot, zone)
    return MySQL.insert.await(
        'INSERT INTO fire_devices (system_id, type, coords, rotation, zone) VALUES (?, ?, ?, ?, ?)', {
            systemId, type, json.encode(coords), json.encode(rot), zone
        }
    )
end

function db.getAllSystems()
    return MySQL.query.await('SELECT * FROM fire_systems')
end

function db.getAllDevices()
    return MySQL.query.await('SELECT * FROM fire_devices')
end

function db.getDevicesBySystem(systemId)
    return MySQL.query.await('SELECT * FROM fire_devices WHERE system_id = ?', { systemId })
end

-- FIX #3: Für Reparatur-Logik (Trouble-Reset nach Reparatur)
function db.getDeviceById(deviceId)
    local result = MySQL.query.await('SELECT * FROM fire_devices WHERE id = ?', { deviceId })
    return result and result[1] or nil
end

function db.getAllDevicesWithCoords()
    return MySQL.query.await('SELECT id, coords FROM fire_devices')
end

-- FIX #3: Health auf 100 setzen + last_service aktualisieren
function db.updateDeviceHealth(deviceId, newHealth)
    MySQL.update('UPDATE fire_devices SET health = ?, last_service = CURRENT_TIMESTAMP WHERE id = ?', {
        newHealth, deviceId
    })
end

function db.updateSystemStatus(systemId, status)
    MySQL.update('UPDATE fire_systems SET status = ? WHERE id = ?', {
        status, systemId
    })
end

-- FIX #4: Systeme mit Geräten unter 20% Health
function db.getTroubledDevices()
    return MySQL.query.await('SELECT DISTINCT system_id FROM fire_devices WHERE health < 20')
end

function db.removeDevice(deviceId)
    return MySQL.update.await('DELETE FROM fire_devices WHERE id = ?', { deviceId })
end