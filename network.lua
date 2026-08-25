-- network.lua

local network = {}

network.PROTOCOL = "elevator"


function network.sendFloorState(
    group,
    floor,
    active,
    cabin_lock
)
    rednet.broadcast({
        type = "floor_state",
        group = group,
        floor = floor,
        active = active,
        cabin_lock = cabin_lock
    }, network.PROTOCOL)
end


function network.requestFloorStates(group)
    rednet.broadcast({
        type = "request_floor_states",
        group = group
    }, network.PROTOCOL)
end


function network.registerFloor(
    group,
    floor
)
    rednet.broadcast({
        type = "floor_register",
        group = group,
        floor = floor
    }, network.PROTOCOL)
end


function network.requestFloorRegistrations(
    group
)
    rednet.broadcast({
        type = "request_floor_registrations",
        group = group
    }, network.PROTOCOL)
end


function network.sendGroupStatus(
    group,
    current_floor,
    busy,
    lock_until,
    timeout_until,
    check_until
)
    rednet.broadcast({
        type = "group_status",

        group = group,
        current_floor = current_floor,

        busy = busy,
        lock_until = lock_until,

        timeout_until = timeout_until,
        check_until = check_until
    }, network.PROTOCOL)
end


function network.requestGroups()
    rednet.broadcast({
        type = "request_groups"
    }, network.PROTOCOL)
end


function network.rebootFloors(group)
    rednet.broadcast({
        type = "reboot_floors",
        group = group
    }, network.PROTOCOL)
end


function network.requestElevator(
    group,
    floor,
    request_id,
    requester_id
)
    rednet.broadcast({
        type = "elevator_request",

        group = group,
        floor = floor,

        request_id = request_id,
        requester_id = requester_id
    }, network.PROTOCOL)
end


function network.dispatchElevator(
    computer_id,
    group,
    floor
)
    rednet.send(
        computer_id,
        {
            type = "dispatch_elevator",
            group = group,
            floor = floor
        },
        network.PROTOCOL
    )
end


function network.sendCallStatus(
    requester_id,
    request_id,
    group,
    floor,
    status,
    wait_until,
    tries_remaining
)
    rednet.broadcast({
        type = "call_status",

        requester_id = requester_id,
        request_id = request_id,

        group = group,
        floor = floor,

        status = status,

        wait_until = wait_until,
        tries_remaining = tries_remaining
    }, network.PROTOCOL)
end


function network.isFloorState(message)
    return type(message) == "table"
        and message.type == "floor_state"
        and type(message.group) == "number"
        and type(message.floor) == "number"
        and type(message.active) == "boolean"
        and type(message.cabin_lock) == "number"
end


function network.isFloorStateRequest(message)
    return type(message) == "table"
        and message.type == "request_floor_states"
        and type(message.group) == "number"
end


function network.isFloorRegister(message)
    return type(message) == "table"
        and message.type == "floor_register"
        and type(message.group) == "number"
        and type(message.floor) == "number"
end


function network.isFloorRegistrationRequest(message)
    return type(message) == "table"
        and message.type == "request_floor_registrations"
        and type(message.group) == "number"
end


function network.isGroupStatus(message)
    if type(message) ~= "table" then
        return false
    end

    if message.type ~= "group_status" then
        return false
    end

    if type(message.group) ~= "number" then
        return false
    end

    if message.current_floor ~= nil
        and type(message.current_floor) ~= "number"
    then
        return false
    end

    return type(message.busy) == "boolean"
        and type(message.lock_until) == "number"
        and type(message.timeout_until) == "number"
        and type(message.check_until) == "number"
end


function network.isGroupRequest(message)
    return type(message) == "table"
        and message.type == "request_groups"
end


function network.isRebootRequest(message)
    return type(message) == "table"
        and message.type == "reboot_floors"
        and type(message.group) == "number"
end


function network.isElevatorRequest(message)
    return type(message) == "table"
        and message.type == "elevator_request"
        and type(message.group) == "number"
        and type(message.floor) == "number"
        and type(message.request_id) == "string"
        and type(message.requester_id) == "number"
end


function network.isElevatorDispatch(message)
    return type(message) == "table"
        and message.type == "dispatch_elevator"
        and type(message.group) == "number"
        and type(message.floor) == "number"
end


function network.isCallStatus(message)
    return type(message) == "table"
        and message.type == "call_status"
        and type(message.requester_id) == "number"
        and type(message.request_id) == "string"
        and type(message.group) == "number"
        and type(message.floor) == "number"
        and type(message.status) == "string"
end


return network