-- debug_display.lua

local debug_display = {}

local monitor = nil
local monitor_name = nil
local enabled = false


local function isMonitor(name)
    if name == nil then
        return false
    end

    return peripheral.getType(name)
        == "monitor"
end


local function getTime()
    return os.epoch("utc") / 1000
end


local function getSortedGroups(
    known_groups
)
    local groups = {}


    for group in pairs(
        known_groups
    ) do
        table.insert(
            groups,
            group
        )
    end


    table.sort(groups)


    return groups
end


local function getRemaining(
    timestamp
)
    if timestamp == nil then
        return nil
    end


    if timestamp < 0 then
        return -1
    end


    if timestamp == 0 then
        return 0
    end


    local remaining =
        timestamp - getTime()


    if remaining < 0 then
        remaining = 0
    end


    return remaining
end


function debug_display.init(
    configured_name
)
    -- nil explicitly disables the debug display.
    if configured_name == nil then
        enabled = false
        monitor = nil
        monitor_name = nil

        print(
            "Debug display disabled"
        )

        return false
    end


    -- The configured value can either be
    -- a directly connected side or a Wired
    -- Modem peripheral name.
    if not isMonitor(
        configured_name
    ) then
        enabled = false
        monitor = nil
        monitor_name = nil

        print(
            "Debug display '"
            .. tostring(configured_name)
            .. "' not found, continuing without it"
        )

        return false
    end


    monitor_name =
        configured_name

    monitor =
        peripheral.wrap(
            configured_name
        )


    if monitor == nil then
        enabled = false

        print(
            "Could not wrap debug display '"
            .. tostring(configured_name)
            .. "', continuing without it"
        )

        return false
    end


    enabled = true


    print(
        "Debug monitor: "
        .. monitor_name
    )


    monitor.setTextScale(1)

    monitor.setBackgroundColor(
        colors.black
    )

    monitor.setTextColor(
        colors.white
    )

    monitor.clear()


    return true
end


function debug_display.update(
    own_group,
    floor,
    known_groups,
    elevator_here
)
    if not enabled
        or monitor == nil
    then
        return
    end


    monitor.setBackgroundColor(
        colors.black
    )

    monitor.clear()

    monitor.setTextColor(
        colors.white
    )


    local groups =
        getSortedGroups(
            known_groups
        )


    local own_state =
        known_groups[
            own_group
        ]


    monitor.setCursorPos(
        1,
        1
    )

    monitor.write(
        "Groups: "
        .. #groups
    )


    monitor.setCursorPos(
        1,
        2
    )

    monitor.write(
        "Group: "
        .. own_group
    )


    monitor.setCursorPos(
        1,
        3
    )

    monitor.write(
        "Floor: "
        .. floor
    )


    monitor.setCursorPos(
        1,
        5
    )

    monitor.write(
        "Current Floors:"
    )


    local y = 6


    for _, group in ipairs(
        groups
    ) do
        local state =
            known_groups[
                group
            ]


        monitor.setCursorPos(
            1,
            y
        )


        if state.current_floor
            == nil
        then
            monitor.write(
                "G"
                .. group
                .. ": Unknown"
            )
        else
            monitor.write(
                "G"
                .. group
                .. ": "
                .. state.current_floor
            )
        end


        y = y + 1
    end


    monitor.setCursorPos(
        1,
        y + 1
    )


    if elevator_here then
        monitor.setTextColor(
            colors.lime
        )

        monitor.write(
            "Elevator: HERE"
        )
    else
        monitor.setTextColor(
            colors.red
        )

        monitor.write(
            "Elevator: AWAY"
        )
    end


    local lock_remaining = nil
    local timeout_remaining = nil
    local check_remaining = nil


    if own_state ~= nil then
        lock_remaining =
            getRemaining(
                own_state.lock_until
            )

        timeout_remaining =
            getRemaining(
                own_state.timeout_until
            )

        check_remaining =
            getRemaining(
                own_state.check_until
            )
    end


    monitor.setCursorPos(
        1,
        y + 2
    )


    if lock_remaining == nil then
        monitor.setTextColor(
            colors.white
        )

        monitor.write(
            "Lock: Unknown"
        )

    elseif lock_remaining > 0 then
        monitor.setTextColor(
            colors.orange
        )

        monitor.write(
            string.format(
                "Lock: %.1fs",
                lock_remaining
            )
        )

    else
        monitor.setTextColor(
            colors.lime
        )

        monitor.write(
            "Lock: FREE"
        )
    end


    monitor.setCursorPos(
        1,
        y + 3
    )

    monitor.setTextColor(
        colors.white
    )


    if timeout_remaining == nil then
        monitor.write(
            "Timeout: Unknown"
        )

    elseif timeout_remaining < 0 then
        monitor.write(
            "Timeout: DISABLED"
        )

    elseif own_state.timeout_until == 0 then
        monitor.write(
            "Timeout: PARKED"
        )

    else
        monitor.write(
            string.format(
                "Timeout: %.1fs",
                timeout_remaining
            )
        )
    end


    monitor.setCursorPos(
        1,
        y + 4
    )


    if check_remaining == nil then
        monitor.write(
            "Check: Unknown"
        )

    elseif check_remaining < 0 then
        monitor.write(
            "Check: DISABLED"
        )

    else
        monitor.write(
            string.format(
                "Check: %.1fs",
                check_remaining
            )
        )
    end
end


function debug_display.isEnabled()
    return enabled
end


function debug_display.getName()
    return monitor_name
end


return debug_display