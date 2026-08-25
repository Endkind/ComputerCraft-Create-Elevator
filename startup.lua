-- startup.lua

local config_module = require("config")


if not config_module.exists() then
    print(
        "config.json not found"
    )

    print(
        "Creating default config..."
    )


    local success,
        error_message =
        config_module.create()


    if not success then
        error(
            "Failed to create config.json: "
            .. tostring(error_message)
        )
    end


    print(
        "config.json created"
    )

    print(
        "Rebooting..."
    )


    sleep(1)

    os.reboot()
end


local config,
    config_error =
    config_module.load()


if config == nil then
    error(
        "Failed to load config.json: "
        .. tostring(config_error)
    )
end


local display = require("display")
local debug_display = require("debug_display")
local network = require("network")


local is_master =
    config.floor
    == config.master_floor

local computer_id =
    os.getComputerID()


local network_update =
    config.network_update
    or 300

local display_update =
    config.display_update
    or 0.1

local cabin_lock =
    config.cabin_lock
    or 5

local drive_lock =
    config.drive_lock
    or 30

local wait_time =
    config.wait
    or 30

local wait_tries =
    config.wait_tries
    or 4

local failure_timeout =
    config.failure_timeout
    or 5

local elevator_check_delay_after_call =
    config.elevator_check_delay_after_call
    or 0.5

local elevator_timeout =
    config.elevator_timeout
    or 300

local elevator_check =
    config.elevator_check
    or 60

local display_direction_arrow_count =
    config.display_direction_arrow_count
    or 3

local display_direction_animation_repetitions =
    config.display_direction_animation_repetitions
    or 3

local group_timeout =
    network_update * 2


local function findNetworkModem(
    configured_name
)
    if configured_name ~= nil then
        if peripheral.getType(
            configured_name
        ) ~= "modem"
        then
            error(
                "Configured network peripheral '"
                .. tostring(
                    configured_name
                )
                .. "' is not a modem"
            )
        end


        return configured_name
    end


    -- Prefer a wired modem.
    for _, name in ipairs(
        peripheral.getNames()
    ) do
        if peripheral.getType(name)
            == "modem"
        then
            local modem =
                peripheral.wrap(
                    name
                )


            if modem ~= nil
                and modem.isWireless
                ~= nil
                and not modem.isWireless()
            then
                return name
            end
        end
    end


    -- Fall back to any modem if no wired
    -- modem was found.
    for _, name in ipairs(
        peripheral.getNames()
    ) do
        if peripheral.getType(name)
            == "modem"
        then
            return name
        end
    end


    return nil
end


local network_modem =
    findNetworkModem(
        config.network_side
    )


if network_modem == nil then
    error(
        "No network modem found"
    )
end


print(
    "Network modem: "
    .. network_modem
)


rednet.open(
    network_modem
)


local elevator_here =
    redstone.getInput(
        config.elevator_contact
    )


local known_groups = {}

local floor_controllers = {}


local current_floor = nil

local busy = false

local lock_until = 0

local lock_mode = nil


-- timeout_until:
--
-- -1 = disabled by config
--  0 = parked at master floor
-- >0 = active timeout timestamp
local timeout_until = -1


-- check_until:
--
-- -1 = disabled by config
-- >0 = next position check timestamp
local check_until = -1


local pending_request = nil

local call_queue = {}

local active_call = nil


local heartbeat_timer = nil

local master_sync_timer = nil

local elevator_pulse_timer = nil

local elevator_check_delay_timer = nil

local cabin_lock_timer = nil

local drive_lock_timer = nil

local display_timer = nil

local request_wait_timer = nil

local elevator_timeout_timer = nil

local elevator_position_check_timer = nil


local elevator_check_blocked =
    false


display.init(
    config.display_side,

    config.display_background_color
        or 0x111111,

    config.display_text_color
        or 0xFFFFFF,

    config.display_button_color
        or 0x2563EB,

    config.display_button_text_color
        or 0xFFFFFF,

    config.display_failure_button_color
        or 0xFF0000,

    config.display_failure_text_color
        or 0xFFFFFF
)


debug_display.init(
    config.debug_display_side
)


local function getTime()
    return os.epoch(
        "utc"
    ) / 1000
end


local function createRequestId()
    return tostring(
        computer_id
    )
        .. "-"
        .. tostring(
            os.epoch(
                "utc"
            )
        )
end


local function cleanupActiveCall()
    if active_call == nil then
        return
    end


    if active_call.status
        ~= "failed"
    then
        return
    end


    if getTime()
        < active_call.failure_until
    then
        return
    end


    active_call =
        nil
end


local function updateDisplays()
    cleanupActiveCall()


    display.update(
        config.group,
        config.floor,
        active_call,
        getTime()
    )


    debug_display.update(
        config.group,
        config.floor,
        known_groups,
        elevator_here
    )
end


local function advanceCallAnimation()
    if active_call == nil then
        return
    end


    if not active_call.animation_active then
        return
    end


    local arrow_count =
        active_call.animation_arrow_count
        or 1


    if arrow_count < 1 then
        arrow_count =
            1
    end


    local frame_count =
        arrow_count * 2 - 1


    active_call.animation_frame =
        active_call.animation_frame
        + 1


    if active_call.animation_frame
        <= frame_count
    then
        return
    end


    active_call.animation_repetition =
        active_call.animation_repetition
        + 1


    if active_call.animation_repetition
        >= active_call.animation_repetitions
    then
        active_call.animation_active =
            false

        active_call =
            nil

        return
    end


    active_call.animation_frame =
        1
end


local function startDirectionAnimation(
    target_group
)
    if active_call == nil then
        return false
    end


    if target_group
        == config.group
    then
        return false
    end


    if display_direction_arrow_count
        <= 0
    then
        return false
    end


    if display_direction_animation_repetitions
        <= 0
    then
        return false
    end


    active_call.status =
        "arrived"

    active_call.animation_active =
        true

    active_call.animation_arrow_count =
        display_direction_arrow_count

    active_call.animation_repetitions =
        display_direction_animation_repetitions

    active_call.animation_repetition =
        0

    active_call.animation_frame =
        1


    if target_group
        > config.group
    then
        active_call.animation_direction =
            ">"
    else
        active_call.animation_direction =
            "<"
    end


    return true
end


local function updateOwnGroupRecord()
    if not is_master then
        return
    end


    known_groups[
        config.group
    ] = {
        last_seen =
            getTime(),

        current_floor =
            current_floor,

        busy =
            busy,

        lock_until =
            lock_until,

        timeout_until =
            timeout_until,

        check_until =
            check_until
    }
end


local function sendGroupStatus()
    if not is_master then
        return
    end


    updateOwnGroupRecord()


    network.sendGroupStatus(
        config.group,
        current_floor,
        busy,
        lock_until,
        timeout_until,
        check_until
    )


    updateDisplays()
end


local function registerGroupStatus(
    message
)
    known_groups[
        message.group
    ] = {
        last_seen =
            getTime(),

        current_floor =
            message.current_floor,

        busy =
            message.busy,

        lock_until =
            message.lock_until,

        timeout_until =
            message.timeout_until,

        check_until =
            message.check_until
    }


    updateDisplays()
end


local function removeExpiredGroups()
    local now =
        getTime()

    local changed =
        false


    for group, state
        in pairs(
            known_groups
        )
    do
        if group
            ~= config.group
            and now
                - state.last_seen
                >= group_timeout
        then
            known_groups[group] =
                nil

            changed =
                true


            print(
                "Group "
                .. group
                .. " timed out"
            )
        end
    end


    if changed then
        updateDisplays()
    end
end


local function scheduleElevatorTimeout()
    if elevator_timeout_timer
        ~= nil
    then
        os.cancelTimer(
            elevator_timeout_timer
        )

        elevator_timeout_timer =
            nil
    end


    if elevator_timeout
        < 0
    then
        timeout_until =
            -1

        return
    end


    if not busy
        and current_floor
            == config.master_floor
    then
        timeout_until =
            0

        return
    end


    timeout_until =
        getTime()
        + elevator_timeout


    elevator_timeout_timer =
        os.startTimer(
            elevator_timeout
        )
end


local function scheduleElevatorCheck()
    if elevator_position_check_timer
        ~= nil
    then
        os.cancelTimer(
            elevator_position_check_timer
        )

        elevator_position_check_timer =
            nil
    end


    if elevator_check
        < 0
    then
        check_until =
            -1

        return
    end


    check_until =
        getTime()
        + elevator_check


    elevator_position_check_timer =
        os.startTimer(
            elevator_check
        )
end


local function resetElevatorStatusTimers()
    if not is_master then
        return
    end


    scheduleElevatorTimeout()

    scheduleElevatorCheck()
end


local function cancelCabinLock()
    if cabin_lock_timer
        ~= nil
    then
        os.cancelTimer(
            cabin_lock_timer
        )

        cabin_lock_timer =
            nil
    end


    if lock_mode
        == "cabin"
    then
        lock_until =
            0

        lock_mode =
            nil
    end
end


local function cancelDriveLock()
    if drive_lock_timer
        ~= nil
    then
        os.cancelTimer(
            drive_lock_timer
        )

        drive_lock_timer =
            nil
    end


    if lock_mode
        == "drive"
    then
        lock_until =
            0

        lock_mode =
            nil
    end
end


local function startDriveLock()
    if not is_master then
        return
    end


    cancelCabinLock()

    cancelDriveLock()


    if drive_lock
        <= 0
    then
        lock_until =
            0

        lock_mode =
            nil


        sendGroupStatus()

        return
    end


    lock_mode =
        "drive"

    lock_until =
        getTime()
        + drive_lock


    drive_lock_timer =
        os.startTimer(
            drive_lock
        )


    print(
        "Drive locked for "
        .. drive_lock
        .. "s"
    )


    sendGroupStatus()
end


local function isStateLocked(
    state
)
    if state == nil then
        return false
    end


    return getTime()
        < state.lock_until
end


local function isGroupCallable(
    group
)
    local state =
        known_groups[
            group
        ]


    if state == nil then
        return false
    end


    if state.current_floor
        == nil
    then
        return false
    end


    if state.busy then
        return false
    end


    if isStateLocked(
        state
    ) then
        return false
    end


    return true
end


local function findNearestGroup()
    local best_group =
        nil

    local best_distance =
        nil


    for group, state
        in pairs(
            known_groups
        )
    do
        if state.current_floor
            ~= nil
        then
            local distance =
                math.abs(
                    state.current_floor
                    - config.floor
                )


            if best_distance
                == nil
                or distance
                    < best_distance
                or (
                    distance
                        == best_distance
                    and group
                        == config.group
                )
            then
                best_group =
                    group

                best_distance =
                    distance
            end
        end
    end


    return best_group
end


local function chooseElevatorGroup()
    local nearest =
        findNearestGroup()


    if nearest == nil then
        print(
            "All elevator positions unknown"
        )


        print(
            "Using own group G"
            .. config.group
            .. " as fallback"
        )


        return config.group
    end


    if isGroupCallable(
        nearest
    ) then
        print(
            "Selected nearest group G"
            .. nearest
        )


        return nearest
    end


    print(
        "Nearest group G"
        .. nearest
        .. " unavailable"
    )


    print(
        "Using own group G"
        .. config.group
        .. " as fallback"
    )


    return config.group
end


local function applyCallStatus(
    message
)
    if message.requester_id
        ~= computer_id
    then
        return
    end


    if active_call
        == nil
    then
        return
    end


    if active_call.request_id
        ~= message.request_id
    then
        return
    end


    if message.status
        == "queued"
    then
        active_call.status =
            "queued"

        active_call.wait_until =
            0


    elseif message.status
        == "waiting"
    then
        active_call.status =
            "waiting"

        active_call.wait_until =
            message.wait_until
            or 0


    elseif message.status
        == "arrived"
    then
        local animation_started =
            startDirectionAnimation(
                message.group
            )


        if not animation_started then
            active_call =
                nil
        end


    elseif message.status
        == "failed"
    then
        active_call.status =
            "failed"

        active_call.animation_active =
            false

        active_call.failure_until =
            getTime()
            + failure_timeout
    end


    updateDisplays()
end


local function publishCallStatus(
    request,
    status,
    wait_until,
    tries_remaining
)
    if request.internal then
        return
    end


    local message = {
        requester_id =
            request.requester_id,

        request_id =
            request.request_id,

        group =
            config.group,

        floor =
            request.floor,

        status =
            status,

        wait_until =
            wait_until,

        tries_remaining =
            tries_remaining
    }


    network.sendCallStatus(
        message.requester_id,
        message.request_id,
        message.group,
        message.floor,
        message.status,
        message.wait_until,
        message.tries_remaining
    )


    if request.requester_id
        == computer_id
    then
        applyCallStatus(
            message
        )
    end
end


local function blockElevatorCheck()
    elevator_check_blocked =
        true


    if elevator_check_delay_timer
        ~= nil
    then
        os.cancelTimer(
            elevator_check_delay_timer
        )
    end


    elevator_check_delay_timer =
        os.startTimer(
            elevator_check_delay_after_call
        )
end


local function pulseElevatorContact()
    blockElevatorCheck()


    redstone.setOutput(
        config.elevator_contact,
        true
    )


    if elevator_pulse_timer
        ~= nil
    then
        os.cancelTimer(
            elevator_pulse_timer
        )
    end


    elevator_pulse_timer =
        os.startTimer(
            0.2
        )
end


local function sendElevatorSignal(
    floor
)
    if not is_master then
        return false
    end


    if floor
        == config.floor
    then
        print(
            "Local dispatch: G"
            .. config.group
            .. " F"
            .. floor
        )


        pulseElevatorContact()


        return true
    end


    local target_computer =
        floor_controllers[
            floor
        ]


    if target_computer
        == nil
    then
        print(
            "ERROR: No floor controller "
            .. "registered for G"
            .. config.group
            .. " F"
            .. floor
        )


        return false
    end


    print(
        "Direct dispatch: G"
        .. config.group
        .. " F"
        .. floor
        .. " -> Computer "
        .. target_computer
    )


    network.dispatchElevator(
        target_computer,
        config.group,
        floor
    )


    return true
end


local function masterIsLocked()
    return getTime()
        < lock_until
end


local function masterCanAcceptCall()
    return not busy
        and not masterIsLocked()
end


local function queueRequest(
    request
)
    table.insert(
        call_queue,
        request
    )


    publishCallStatus(
        request,
        "queued",
        0,
        request.retries_remaining
    )


    print(
        "Queued floor "
        .. request.floor
    )
end


local function startRequestWait()
    if pending_request
        == nil
    then
        return
    end


    if request_wait_timer
        ~= nil
    then
        os.cancelTimer(
            request_wait_timer
        )
    end


    pending_request.wait_until =
        getTime()
        + wait_time


    request_wait_timer =
        os.startTimer(
            wait_time
        )


    publishCallStatus(
        pending_request,
        "waiting",
        pending_request.wait_until,
        pending_request.retries_remaining
    )
end


local function failPendingRequest()
    if pending_request
        == nil
    then
        return
    end


    print(
        "Failed to call elevator to floor "
        .. pending_request.floor
    )


    publishCallStatus(
        pending_request,
        "failed",
        0,
        0
    )


    pending_request =
        nil

    busy =
        false


    cancelDriveLock()

    resetElevatorStatusTimers()

    sendGroupStatus()
end


local function dispatchRequest(
    request
)
    if current_floor
        == request.floor
        and not busy
    then
        publishCallStatus(
            request,
            "arrived",
            0,
            request.retries_remaining
        )


        return
    end


    busy =
        true

    pending_request =
        request

    pending_request.retries_remaining =
        wait_tries


    resetElevatorStatusTimers()


    print(
        "Dispatching G"
        .. config.group
        .. " to F"
        .. request.floor
    )


    local sent =
        sendElevatorSignal(
            request.floor
        )


    if not sent then
        failPendingRequest()

        return
    end


    startRequestWait()

    sendGroupStatus()
end


local function processQueue()
    if not is_master then
        return
    end


    if not masterCanAcceptCall() then
        return
    end


    while #call_queue
        > 0
    do
        local request =
            table.remove(
                call_queue,
                1
            )


        if current_floor
            == request.floor
        then
            publishCallStatus(
                request,
                "arrived",
                0,
                request.retries_remaining
            )
        else
            dispatchRequest(
                request
            )


            return
        end
    end
end


local function acceptElevatorRequest(
    request
)
    if not is_master then
        return
    end


    if request.group
        ~= config.group
    then
        return
    end


    if pending_request
        ~= nil
        and pending_request.request_id
            == request.request_id
    then
        return
    end


    if masterCanAcceptCall() then
        dispatchRequest(
            request
        )
    else
        queueRequest(
            request
        )
    end
end


local function requestElevator()
    if active_call
        ~= nil
    then
        if active_call.status
            ~= "failed"
        then
            return
        end


        if getTime()
            < active_call.failure_until
        then
            return
        end
    end


    local target_group =
        chooseElevatorGroup()


    local request = {
        group =
            target_group,

        floor =
            config.floor,

        request_id =
            createRequestId(),

        requester_id =
            computer_id,

        retries_remaining =
            wait_tries,

        internal =
            false
    }


    active_call = {
        request_id =
            request.request_id,

        target_group =
            target_group,

        status =
            "queued",

        wait_until =
            0,

        failure_until =
            0,

        animation_active =
            false,

        animation_direction =
            nil,

        animation_arrow_count =
            display_direction_arrow_count,

        animation_repetitions =
            display_direction_animation_repetitions,

        animation_repetition =
            0,

        animation_frame =
            1
    }


    updateDisplays()


    print(
        "CALL: G"
        .. config.group
        .. " F"
        .. config.floor
        .. " -> selected G"
        .. target_group
    )


    if is_master
        and target_group
            == config.group
    then
        acceptElevatorRequest(
            request
        )


        return
    end


    network.requestElevator(
        request.group,
        request.floor,
        request.request_id,
        request.requester_id
    )
end


local function startCabinLock(
    duration
)
    duration =
        duration
        or cabin_lock


    if duration < 0 then
        duration =
            0
    end


    cancelDriveLock()

    cancelCabinLock()


    if duration == 0 then
        lock_until =
            0

        lock_mode =
            nil


        sendGroupStatus()

        processQueue()


        return
    end


    lock_mode =
        "cabin"


    lock_until =
        getTime()
        + duration


    cabin_lock_timer =
        os.startTimer(
            duration
        )


    print(
        "Cabin locked for "
        .. duration
        .. "s"
    )


    sendGroupStatus()
end


local function completePendingRequest(
    floor
)
    if pending_request
        == nil
    then
        return
    end


    if pending_request.floor
        ~= floor
    then
        return
    end


    if request_wait_timer
        ~= nil
    then
        os.cancelTimer(
            request_wait_timer
        )

        request_wait_timer =
            nil
    end


    print(
        "Call completed at floor "
        .. floor
    )


    publishCallStatus(
        pending_request,
        "arrived",
        0,
        pending_request.retries_remaining
    )


    pending_request =
        nil
end


local function handleMasterFloorState(
    floor,
    active,
    floor_cabin_lock
)
    if not is_master then
        return
    end


    if active then
        local changed =
            current_floor
                ~= floor
            or busy


        if not changed then
            return
        end


        cancelDriveLock()


        current_floor =
            floor

        busy =
            false


        completePendingRequest(
            floor
        )


        resetElevatorStatusTimers()


        print(
            "Elevator G"
            .. config.group
            .. " arrived at F"
            .. floor
        )


        startCabinLock(
            floor_cabin_lock
        )


        return
    end


    if current_floor
        == floor
    then
        current_floor =
            nil


        print(
            "Elevator G"
            .. config.group
            .. " left F"
            .. floor
        )


        startDriveLock()


        resetElevatorStatusTimers()


        sendGroupStatus()
    end
end


local function processElevatorInput()
    local new_state =
        redstone.getInput(
            config.elevator_contact
        )


    if new_state
        == elevator_here
    then
        return
    end


    elevator_here =
        new_state


    if is_master then
        handleMasterFloorState(
            config.floor,
            elevator_here,
            cabin_lock
        )


        return
    end


    network.sendFloorState(
        config.group,
        config.floor,
        elevator_here,
        cabin_lock
    )


    updateDisplays()
end


local function handleRedstone()
    if elevator_check_blocked then
        return
    end


    processElevatorInput()
end


local function handleRequestTimeout()
    request_wait_timer =
        nil


    if pending_request
        == nil
    then
        return
    end


    if pending_request.retries_remaining
        > 0
    then
        pending_request.retries_remaining =
            pending_request.retries_remaining
            - 1


        print(
            "Elevator did not arrive"
        )


        print(
            "Retry G"
            .. config.group
            .. " F"
            .. pending_request.floor
            .. " | remaining: "
            .. pending_request.retries_remaining
        )


        local sent =
            sendElevatorSignal(
                pending_request.floor
            )


        if not sent then
            failPendingRequest()

            processQueue()


            return
        end


        startRequestWait()


        return
    end


    failPendingRequest()

    processQueue()
end


local function createTimeoutReturnRequest()
    return {
        group =
            config.group,

        floor =
            config.master_floor,

        request_id =
            "timeout-"
            .. createRequestId(),

        requester_id =
            computer_id,

        retries_remaining =
            wait_tries,

        internal =
            true
    }
end


local function handleElevatorTimeout()
    elevator_timeout_timer =
        nil


    if timeout_until
        <= 0
    then
        return
    end


    print(
        "Elevator timeout reached for G"
        .. config.group
    )


    local should_return =
        not busy
        and (
            current_floor
                == nil
            or current_floor
                ~= config.master_floor
        )


    if should_return then
        print(
            "Returning G"
            .. config.group
            .. " to master floor F"
            .. config.master_floor
        )


        local request =
            createTimeoutReturnRequest()


        if masterCanAcceptCall() then
            dispatchRequest(
                request
            )
        else
            queueRequest(
                request
            )
        end
    else
        scheduleElevatorTimeout()

        sendGroupStatus()
    end
end


local function handleElevatorPositionCheck()
    elevator_position_check_timer =
        nil


    print(
        "Checking elevator position for G"
        .. config.group
    )


    network.requestFloorStates(
        config.group
    )


    scheduleElevatorCheck()

    sendGroupStatus()
end


local function handleMonitorTouch(
    event
)
    local side =
        event[2]

    local x =
        event[3]

    local y =
        event[4]


    if display.isCallButton(
        side,
        x,
        y
    ) then
        requestElevator()
    end
end


local function handleGroupRequest()
    if is_master then
        sendGroupStatus()
    end
end


local function handleFloorRegister(
    sender_id,
    message
)
    if not is_master then
        return
    end


    if message.group
        ~= config.group
    then
        return
    end


    floor_controllers[
        message.floor
    ] = sender_id


    print(
        "Registered floor controller: "
        .. "G"
        .. message.group
        .. " F"
        .. message.floor
        .. " -> Computer "
        .. sender_id
    )
end


local function handleFloorRegistrationRequest(
    message
)
    if message.group
        ~= config.group
    then
        return
    end


    network.registerFloor(
        config.group,
        config.floor
    )
end


local function handleFloorState(
    message
)
    if not is_master then
        return
    end


    if message.group
        ~= config.group
    then
        return
    end


    handleMasterFloorState(
        message.floor,
        message.active,
        message.cabin_lock
    )
end


local function handleFloorStateRequest(
    message
)
    if message.group
        ~= config.group
    then
        return
    end


    network.sendFloorState(
        config.group,
        config.floor,
        elevator_here,
        cabin_lock
    )
end


local function handleRebootRequest(
    message
)
    if message.group
        ~= config.group
    then
        return
    end


    if is_master then
        return
    end


    print(
        "Reboot requested by master"
    )


    os.reboot()
end


local function handleElevatorRequest(
    message
)
    if not is_master then
        return
    end


    if message.group
        ~= config.group
    then
        return
    end


    acceptElevatorRequest({
        group =
            message.group,

        floor =
            message.floor,

        request_id =
            message.request_id,

        requester_id =
            message.requester_id,

        retries_remaining =
            wait_tries,

        internal =
            false
    })
end


local function handleElevatorDispatch(
    sender_id,
    message
)
    if message.group
        ~= config.group
    then
        return
    end


    if message.floor
        ~= config.floor
    then
        return
    end


    print(
        "Dispatch accepted from Computer "
        .. sender_id
        .. ": G"
        .. config.group
        .. " F"
        .. config.floor
    )


    pulseElevatorContact()
end


local function handleCallStatus(
    message
)
    applyCallStatus(
        message
    )
end


local function handleNetworkMessage(
    event
)
    local sender_id =
        event[2]

    local message =
        event[3]

    local protocol =
        event[4]


    if protocol
        ~= network.PROTOCOL
    then
        return
    end


    if network.isGroupStatus(
        message
    ) then
        registerGroupStatus(
            message
        )


        return
    end


    if network.isGroupRequest(
        message
    ) then
        handleGroupRequest()


        return
    end


    if network.isFloorRegister(
        message
    ) then
        handleFloorRegister(
            sender_id,
            message
        )


        return
    end


    if network.isFloorRegistrationRequest(
        message
    ) then
        handleFloorRegistrationRequest(
            message
        )


        return
    end


    if network.isFloorState(
        message
    ) then
        handleFloorState(
            message
        )


        return
    end


    if network.isFloorStateRequest(
        message
    ) then
        handleFloorStateRequest(
            message
        )


        return
    end


    if network.isRebootRequest(
        message
    ) then
        handleRebootRequest(
            message
        )


        return
    end


    if network.isElevatorRequest(
        message
    ) then
        handleElevatorRequest(
            message
        )


        return
    end


    if network.isElevatorDispatch(
        message
    ) then
        handleElevatorDispatch(
            sender_id,
            message
        )


        return
    end


    if network.isCallStatus(
        message
    ) then
        handleCallStatus(
            message
        )
    end
end


local function handleTimer(
    timer_id
)
    if timer_id
        == elevator_pulse_timer
    then
        redstone.setOutput(
            config.elevator_contact,
            false
        )


        elevator_pulse_timer =
            nil


        return
    end


    if timer_id
        == elevator_check_delay_timer
    then
        elevator_check_delay_timer =
            nil

        elevator_check_blocked =
            false


        processElevatorInput()


        return
    end


    if timer_id
        == request_wait_timer
    then
        handleRequestTimeout()


        return
    end


    if timer_id
        == cabin_lock_timer
    then
        cabin_lock_timer =
            nil


        if lock_mode
            == "cabin"
        then
            lock_mode =
                nil

            lock_until =
                0


            print(
                "Cabin lock released"
            )


            sendGroupStatus()

            processQueue()
        end


        return
    end


    if timer_id
        == drive_lock_timer
    then
        drive_lock_timer =
            nil


        if lock_mode
            == "drive"
        then
            lock_mode =
                nil

            lock_until =
                0


            print(
                "Drive lock released"
            )


            sendGroupStatus()

            processQueue()
        end


        return
    end


    if timer_id
        == elevator_timeout_timer
    then
        handleElevatorTimeout()


        return
    end


    if timer_id
        == elevator_position_check_timer
    then
        handleElevatorPositionCheck()


        return
    end


    if timer_id
        == master_sync_timer
    then
        master_sync_timer =
            nil


        network.requestFloorStates(
            config.group
        )


        network.requestFloorRegistrations(
            config.group
        )


        network.requestGroups()


        return
    end


    if timer_id
        == display_timer
    then
        advanceCallAnimation()

        updateDisplays()


        display_timer =
            os.startTimer(
                display_update
            )


        return
    end


    if timer_id
        == heartbeat_timer
    then
        removeExpiredGroups()


        if is_master then
            sendGroupStatus()


            network.requestFloorRegistrations(
                config.group
            )
        else
            network.requestGroups()


            network.registerFloor(
                config.group,
                config.floor
            )
        end


        heartbeat_timer =
            os.startTimer(
                network_update
            )
    end
end


local function initializeMaster()
    print(
        "Master started for group "
        .. config.group
    )


    floor_controllers[
        config.floor
    ] = computer_id


    if elevator_here then
        current_floor =
            config.floor
    end


    resetElevatorStatusTimers()


    if elevator_here then
        startCabinLock(
            cabin_lock
        )
    else
        sendGroupStatus()
    end


    print(
        "Rebooting floor controllers"
    )


    network.rebootFloors(
        config.group
    )


    print(
        "Calling elevator to master floor "
        .. config.master_floor
    )


    pulseElevatorContact()


    master_sync_timer =
        os.startTimer(
            1
        )


    heartbeat_timer =
        os.startTimer(
            network_update
        )
end


local function initializeFloor()
    network.registerFloor(
        config.group,
        config.floor
    )


    network.sendFloorState(
        config.group,
        config.floor,
        elevator_here,
        cabin_lock
    )


    network.requestGroups()


    heartbeat_timer =
        os.startTimer(
            network_update
        )
end


print(
    "Floor controller started"
)

print(
    "Computer ID: "
    .. computer_id
)

print(
    "Group: "
    .. config.group
)

print(
    "Floor: "
    .. config.floor
)


updateDisplays()


display_timer =
    os.startTimer(
        display_update
    )


if is_master then
    initializeMaster()
else
    initializeFloor()
end


while true do
    local event = {
        os.pullEvent()
    }


    if event[1]
        == "redstone"
    then
        handleRedstone()


    elseif event[1]
        == "monitor_touch"
    then
        handleMonitorTouch(
            event
        )


    elseif event[1]
        == "rednet_message"
    then
        handleNetworkMessage(
            event
        )


    elseif event[1]
        == "timer"
    then
        handleTimer(
            event[2]
        )
    end
end