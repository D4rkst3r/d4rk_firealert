-- d4rk_firealert: server/database.lua
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
        }
    )
end

-- Alle Systeme beim Start laden
function db.getAllSystems()
    return MySQL.query.await('SELECT * FROM fire_systems')
end

-- Alle Geräte laden (für Client-Sync)
function db.getAllDevices()
    return MySQL.query.await('SELECT * FROM fire_devices')
end

-- Alle Geräte eines Systems laden
function db.getDevicesBySystem(systemId)
    return MySQL.query.await('SELECT * FROM fire_devices WHERE system_id = ?', { systemId })
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

-- Geräte mit kritischer Health holen (für Trouble-Check)
function db.getTroubledDevices()
    return MySQL.query.await('SELECT DISTINCT system_id FROM fire_devices WHERE health < 20')
end

-- Gerät nach ID löschen
function db.removeDevice(deviceId)
    return MySQL.update.await('DELETE FROM fire_devices WHERE id = ?', { deviceId })
end

-- Alle Geräte holen (für Koordinaten-Suche beim Entfernen)
function db.getAllDevicesWithCoords()
    return MySQL.query.await('SELECT id, coords FROM fire_devices')
end
