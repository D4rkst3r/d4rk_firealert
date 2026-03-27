-- d4rk_firealert: server/database.lua
db = {}

---------------------------------------------------------
-- Systeme
---------------------------------------------------------

function db.createSystem(name, coords)
    return MySQL.insert.await('INSERT INTO fire_systems (name, coords) VALUES (?, ?)', {
        name, json.encode(coords)
    })
end

function db.getAllSystems()
    return MySQL.query.await('SELECT * FROM fire_systems')
end

function db.updateSystemStatus(systemId, status)
    MySQL.update('UPDATE fire_systems SET status = ? WHERE id = ?', { status, systemId })
end

---------------------------------------------------------
-- Geräte
---------------------------------------------------------

function db.addDevice(systemId, type, coords, rot, zone)
    return MySQL.insert.await(
        'INSERT INTO fire_devices (system_id, type, coords, rotation, zone) VALUES (?, ?, ?, ?, ?)',
        { systemId, type, json.encode(coords), json.encode(rot), zone }
    )
end

-- Holt ein frisch eingefügtes Gerät inkl. Systemname für den Delta-Sync
function db.getDeviceWithSystemName(deviceId)
    local result = MySQL.query.await([[
        SELECT fd.*, fs.name AS system_name
        FROM fire_devices fd
        JOIN fire_systems fs ON fd.system_id = fs.id
        WHERE fd.id = ?
    ]], { deviceId })
    return result and result[1] or nil
end

-- Join mit fire_systems damit Panels ihren Systemnamen im State Bag speichern können
-- (wird für Option C Hybrid-Systemauswahl beim Platzieren benötigt)
function db.getAllDevices()
    return MySQL.query.await([[
        SELECT fd.*, fs.name AS system_name
        FROM fire_devices fd
        JOIN fire_systems fs ON fd.system_id = fs.id
    ]])
end

function db.getDevicesBySystem(systemId)
    return MySQL.query.await('SELECT * FROM fire_devices WHERE system_id = ?', { systemId })
end

function db.getDeviceById(deviceId)
    local result = MySQL.query.await('SELECT * FROM fire_devices WHERE id = ?', { deviceId })
    return result and result[1] or nil
end

function db.updateDeviceHealth(deviceId, newHealth)
    MySQL.update('UPDATE fire_devices SET health = ?, last_service = CURRENT_TIMESTAMP WHERE id = ?', {
        newHealth, deviceId
    })
end

function db.getTroubledDevices()
    return MySQL.query.await('SELECT DISTINCT system_id FROM fire_devices WHERE health < 20')
end

-- FIX #9: getAllDevicesWithCoords entfernt — war Dead Code seit removeDevice per ID läuft
function db.removeDevice(deviceId)
    return MySQL.update.await('DELETE FROM fire_devices WHERE id = ?', { deviceId })
end

---------------------------------------------------------
-- Alarm-Log
---------------------------------------------------------

function db.logAlarm(systemId, systemName, zone, triggerType)
    return MySQL.insert.await(
        'INSERT INTO fire_alarm_log (system_id, system_name, zone, trigger_type) VALUES (?, ?, ?, ?)',
        { systemId, systemName, zone, triggerType or 'manual' }
    )
end

function db.logAcknowledge(systemId, playerName)
    MySQL.update(
        'UPDATE fire_alarm_log SET acknowledged_at = CURRENT_TIMESTAMP, acknowledged_by = ? WHERE system_id = ? AND acknowledged_at IS NULL ORDER BY triggered_at DESC LIMIT 1',
        { playerName, systemId }
    )
end

function db.getAlarmLog(systemId, limit)
    return MySQL.query.await(
        'SELECT * FROM fire_alarm_log WHERE system_id = ? ORDER BY triggered_at DESC LIMIT ?',
        { systemId, limit or 10 }
    )
end