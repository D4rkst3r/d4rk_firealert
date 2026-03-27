-- d4rk_firealert:server/database.lua
db = {}

-- Ein neues System (BMA) in die DB eintragen
function db.createSystem(name, coords)
    return MySQL.insert.await('INSERT INTO fire_systems (name, coords) VALUES (?, ?)', {
        name, json.encode(coords)
    })
end

-- Ein Gerät an ein System binden
function db.addDevice(systemId, type, coords, rot, zone)
    return MySQL.insert.await(
    'INSERT INTO fire_devices (system_id, type, coords, rotation, zone) VALUES (?, ?, ?, ?, ?)', {
        systemId, type, json.encode(coords), json.encode(rot), zone
    })
end

-- Alle Systeme beim Start laden
function db.getAllSystems()
    return MySQL.query.await('SELECT * FROM fire_systems')
end

-- Wartungszustand aktualisieren
function db.updateDeviceHealth(deviceId, newHealth)
    MySQL.update('UPDATE fire_devices SET health = ?, last_service = CURRENT_TIMESTAMP WHERE id = ?', {
        newHealth, deviceId
    })
end

-- Systemstatus ändern (Normal / Alarm / Trouble)
function db.updateSystemStatus(systemId, status)
    MySQL.update('UPDATE fire_systems SET status = ? WHERE id = ?', {
        status, systemId
    })
end
