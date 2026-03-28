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

-- Alle Geräte mit Systemname — für initialen Client-Sync und MDT
function db.getAllDevices()
    return MySQL.query.await([[
        SELECT fd.*, fs.name AS system_name
        FROM fire_devices fd
        JOIN fire_systems fs ON fd.system_id = fs.id
    ]])
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

function db.removeDevice(deviceId)
    return MySQL.update.await('DELETE FROM fire_devices WHERE id = ?', { deviceId })
end

-- Serverseitige Validierung für triggerAutoAlarm —
-- gibt alle Rauchmelder eines Systems zurück
function db.getSmokeDevicesBySystem(systemId)
    return MySQL.query.await(
        "SELECT id, coords FROM fire_devices WHERE system_id = ? AND type = 'smoke'",
        { systemId }
    )
end

---------------------------------------------------------
-- NEU: Wartungsplan / Fälligkeiten
---------------------------------------------------------

-- Setzt das Datum der nächsten Pflichtinspektion.
-- Wird aufgerufen nach Geräte-Einbau und nach Reparatur.
-- intervalDays: Anzahl Tage bis zur nächsten Inspektion (aus Config.ServiceInterval)
function db.resetServiceDate(deviceId, intervalDays)
    MySQL.update(
        'UPDATE fire_devices SET next_service_date = DATE_ADD(CURDATE(), INTERVAL ? DAY) WHERE id = ?',
        { intervalDays, deviceId }
    )
end

-- Gibt alle Geräte zurück deren Inspektion überfällig ist.
-- next_service_date < CURDATE() = überfällig
-- next_service_date IS NULL = noch nicht gesetzt (neu eingebaut, noch nicht fällig)
function db.getOverdueDevices()
    return MySQL.query.await([[
        SELECT fd.id, fd.system_id, fd.zone, fd.health, fs.name AS system_name
        FROM fire_devices fd
        JOIN fire_systems fs ON fd.system_id = fs.id
        WHERE fd.next_service_date IS NOT NULL
          AND fd.next_service_date < CURDATE()
          AND fd.health > 15
    ]])
    -- health > 15: bereits auf Trouble-Level degradierte Geräte nicht nochmals degradieren
end

---------------------------------------------------------
-- NEU: Sabotage-Log
---------------------------------------------------------

-- Protokolliert eine Sabotage-Aktion in der Datenbank.
-- Wird aufgerufen sobald ein Spieler ein Gerät absichtlich beschädigt.
function db.logSabotage(deviceId, systemId, systemName, zone, healthBefore, healthAfter, playerName)
    MySQL.insert(
        [[INSERT INTO fire_sabotage_log
            (device_id, system_id, system_name, zone, health_before, health_after, suspected_player)
          VALUES (?, ?, ?, ?, ?, ?, ?)]],
        { deviceId, systemId, systemName, zone, healthBefore, healthAfter, playerName }
    )
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
        [[UPDATE fire_alarm_log
          SET acknowledged_at = CURRENT_TIMESTAMP, acknowledged_by = ?
          WHERE system_id = ? AND acknowledged_at IS NULL
          ORDER BY triggered_at DESC LIMIT 1]],
        { playerName, systemId }
    )
end

function db.getAlarmLog(systemId, limit)
    return MySQL.query.await(
        'SELECT * FROM fire_alarm_log WHERE system_id = ? ORDER BY triggered_at DESC LIMIT ?',
        { systemId, limit or 10 }
    )
end