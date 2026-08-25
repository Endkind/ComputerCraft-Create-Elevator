-- config.lua

local config = {}


config.PATH = "config.json"


config.defaults = {
    floor = 0,
    group = 1,

    master_floor = 0,

    elevator_contact = "bottom",
    network_side = textutils.json_null,

    display_side = textutils.json_null,
    debug_display_side = textutils.json_null,

    network_update = 300,
    display_update = 0.1,

    cabin_lock = 5,
    drive_lock = 30,

    wait = 30,
    wait_tries = 4,

    failure_timeout = 5,

    elevator_check_delay_after_call = 0.5,

    elevator_timeout = 300,
    elevator_check = 60,

    display_direction_arrow_count = 3,
    display_direction_animation_repetitions = 3,

    display_background_color = 0x111111,
    display_text_color = 0xFFFFFF,

    display_button_color = 0x2563EB,
    display_button_text_color = 0xFFFFFF,

    display_failure_button_color = 0xFF0000,
    display_failure_text_color = 0xFFFFFF
}


config.default = {
    "floor",
    "group"
}


config.extended = {
    "elevator_contact",
    "network_side",
    "cabin_lock",
    "drive_lock"
}


config.advance = {
    "floor",
    "group",

    "master_floor",

    "elevator_contact",
    "network_side",

    "display_side",
    "debug_display_side",

    "network_update",
    "display_update",

    "cabin_lock",
    "drive_lock",

    "wait",
    "wait_tries",

    "failure_timeout",

    "elevator_check_delay_after_call",

    "elevator_timeout",
    "elevator_check",

    "display_direction_arrow_count",
    "display_direction_animation_repetitions",

    "display_background_color",
    "display_text_color",

    "display_button_color",
    "display_button_text_color",

    "display_failure_button_color",
    "display_failure_text_color"
}


local function copyTable(source)
    local target = {}

    for key, value in pairs(source) do
        target[key] = value
    end

    return target
end


local function normalizeValue(value)
    if value == textutils.json_null then
        return nil
    end

    return value
end


local function mergeDefaults(values)
    local result = {}

    for key, default_value in pairs(
        config.defaults
    ) do
        local value =
            normalizeValue(
                default_value
            )

        if value ~= nil then
            result[key] = value
        end
    end


    for key, value in pairs(values) do
        local normalized_value =
            normalizeValue(
                value
            )

        if normalized_value == nil then
            result[key] = nil
        else
            result[key] =
                normalized_value
        end
    end


    return result
end


local function serializeValue(value)
    return textutils.serializeJSON(
        value
    )
end


local function serializeConfig(values)
    local lines = {
        "{"
    }


    for index, key in ipairs(
        config.advance
    ) do
        local value =
            values[key]


        if value == nil then
            value =
                textutils.json_null
        end


        local serialized_key =
            serializeValue(
                key
            )


        local serialized_value =
            serializeValue(
                value
            )


        local comma = ""


        if index < #config.advance then
            comma = ","
        end


        table.insert(
            lines,
            "    "
                .. serialized_key
                .. ": "
                .. serialized_value
                .. comma
        )
    end


    table.insert(
        lines,
        "}"
    )


    return table.concat(
        lines,
        "\n"
    )
end


function config.exists(path)
    path =
        path
        or config.PATH


    return fs.exists(
        path
    )
end


function config.create(
    path,
    overwrite
)
    path =
        path
        or config.PATH


    overwrite =
        overwrite
        or false


    if fs.exists(path)
        and not overwrite
    then
        return false,
            "Config already exists"
    end


    local values =
        copyTable(
            config.defaults
        )


    local json =
        serializeConfig(
            values
        )


    local file,
        error_message =
        fs.open(
            path,
            "w"
        )


    if file == nil then
        return false,
            error_message
            or "Failed to open config file"
    end


    file.write(
        json
    )

    file.close()


    return true
end


function config.load(path)
    path =
        path
        or config.PATH


    if not fs.exists(path) then
        return nil,
            "Config file does not exist"
    end


    local file,
        error_message =
        fs.open(
            path,
            "r"
        )


    if file == nil then
        return nil,
            error_message
            or "Failed to open config file"
    end


    local content =
        file.readAll()


    file.close()


    local values,
        json_error =
        textutils.unserializeJSON(
            content,
            {
                parse_null = true
            }
        )


    if values == nil then
        return nil,
            json_error
            or "Invalid JSON config"
    end


    if type(values)
        ~= "table"
    then
        return nil,
            "Config root must be a JSON object"
    end


    return mergeDefaults(
        values
    )
end


function config.getDefaults()
    return copyTable(
        config.defaults
    )
end


function config.save(
    values,
    path
)
    path =
        path
        or config.PATH


    local merged =
        mergeDefaults(
            values
        )


    local json =
        serializeConfig(
            merged
        )


    local file,
        error_message =
        fs.open(
            path,
            "w"
        )


    if file == nil then
        return false,
            error_message
            or "Failed to open config file"
    end


    file.write(
        json
    )

    file.close()


    return true
end


return config