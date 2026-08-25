-- install.lua

local base_url =
    "https://raw.githubusercontent.com/Endkind/ComputerCraft-Create-Elevator/main/"


local files = {
    "startup.lua",
    "config.lua",
    "network.lua",
    "display.lua",
    "debug_display.lua"
}


local timeout = 5


local config_modes = {
    "default",
    "extended",
    "advance"
}


local function downloadFile(
    file_name
)
    local url =
        base_url
        .. file_name


    print(
        "Downloading "
        .. file_name
        .. "..."
    )


    local response,
        error_message =
        http.get(
            url
        )


    if response == nil then
        return false,
            error_message
            or "HTTP request failed"
    end


    local content =
        response.readAll()


    response.close()


    local file,
        file_error =
        fs.open(
            file_name,
            "w"
        )


    if file == nil then
        return false,
            file_error
            or "Could not open file"
    end


    file.write(
        content
    )

    file.close()


    return true
end


local function downloadFiles()
    print(
        "Installing ComputerCraft Create Elevator"
    )

    print()


    for _, file_name in ipairs(
        files
    ) do
        local success,
            error_message =
            downloadFile(
                file_name
            )


        if not success then
            error(
                "Failed to download "
                .. file_name
                .. ": "
                .. tostring(
                    error_message
                )
            )
        end
    end


    print()

    print(
        "All files downloaded"
    )
end


local function createDefaultConfig()
    package.loaded[
        "config"
    ] = nil


    local config =
        require(
            "config"
        )


    local success,
        error_message =
        config.create(
            nil,
            true
        )


    if not success then
        error(
            "Failed to create config.json: "
            .. tostring(
                error_message
            )
        )
    end


    print(
        "Default config.json created"
    )


    return config
end


local function waitForConfigurationRequest()
    print()

    print(
        "Press ENTER within "
        .. timeout
        .. " seconds to configure."
    )

    print(
        "Otherwise defaults will be used."
    )


    local timer =
        os.startTimer(
            timeout
        )


    while true do
        local event,
            value =
            os.pullEvent()


        if event == "key"
            and value == keys.enter
        then
            os.cancelTimer(
                timer
            )

            return true
        end


        if event == "timer"
            and value == timer
        then
            return false
        end
    end
end


local function isValidConfigMode(
    mode
)
    for _, valid_mode in ipairs(
        config_modes
    ) do
        if mode == valid_mode then
            return true
        end
    end


    return false
end


local function askConfigMode()
    print()

    print(
        "Configuration modes:"
    )


    for _, mode in ipairs(
        config_modes
    ) do
        print(
            " - "
            .. mode
        )
    end


    print()


    while true do
        write(
            "Mode (default): "
        )


        local input =
            read()


        input =
            string.lower(
                input
            )


        if input == "" then
            return "default"
        end


        if isValidConfigMode(
            input
        ) then
            return input
        end


        print(
            "Unknown configuration mode"
        )
    end
end


local function appendUnique(
    target,
    source
)
    local existing = {}


    for _, key in ipairs(
        target
    ) do
        existing[key] =
            true
    end


    for _, key in ipairs(
        source
    ) do
        if not existing[key] then
            table.insert(
                target,
                key
            )

            existing[key] =
                true
        end
    end
end


local function getConfigKeys(
    config,
    mode
)
    local keys_to_configure = {}


    if mode == "default" then
        appendUnique(
            keys_to_configure,
            config.default
        )


    elseif mode == "extended" then
        appendUnique(
            keys_to_configure,
            config.default
        )

        appendUnique(
            keys_to_configure,
            config.extended
        )


    elseif mode == "advance" then
        appendUnique(
            keys_to_configure,
            config.advance
        )
    end


    return keys_to_configure
end


local function getDefaultValue(
    config,
    key
)
    local value =
        config.defaults[
            key
        ]


    if value
        == textutils.json_null
    then
        return nil
    end


    return value
end


local function valueToString(
    value
)
    if value == nil then
        return "null"
    end


    if type(value)
        == "boolean"
    then
        if value then
            return "true"
        end

        return "false"
    end


    return tostring(
        value
    )
end


local function parseBoolean(
    input
)
    local normalized =
        string.lower(
            input
        )


    if normalized == "true"
        or normalized == "yes"
        or normalized == "y"
        or normalized == "1"
    then
        return true
    end


    if normalized == "false"
        or normalized == "no"
        or normalized == "n"
        or normalized == "0"
    then
        return false
    end


    return nil
end


local function parseInput(
    input,
    default_value
)
    if input == "" then
        return true,
            default_value
    end


    if string.lower(input)
        == "null"
    then
        return true,
            nil
    end


    local value_type =
        type(
            default_value
        )


    if value_type == "number" then
        local number =
            tonumber(
                input
            )


        if number == nil then
            return false,
                nil
        end


        return true,
            number
    end


    if value_type == "boolean" then
        local boolean =
            parseBoolean(
                input
            )


        if boolean == nil then
            return false,
                nil
        end


        return true,
            boolean
    end


    -- A null default has no type information.
    -- In this project nullable config values
    -- such as network_side/display_side are strings.
    if default_value == nil then
        return true,
            input
    end


    return true,
        input
end


local function askConfigValue(
    config,
    key
)
    local default_value =
        getDefaultValue(
            config,
            key
        )


    while true do
        write(
            key
            .. " ("
            .. valueToString(
                default_value
            )
            .. "): "
        )


        local input =
            read()


        local success,
            value =
            parseInput(
                input,
                default_value
            )


        if success then
            return value
        end


        print(
            "Invalid value"
        )
    end
end


local function configure(
    config,
    mode
)
    local values,
        error_message =
        config.load()


    if values == nil then
        error(
            "Failed to load config.json: "
            .. tostring(
                error_message
            )
        )
    end


    local keys_to_configure =
        getConfigKeys(
            config,
            mode
        )


    print()

    print(
        "Configuration mode: "
        .. mode
    )

    print(
        "Press ENTER to keep the default value."
    )

    print(
        "Use 'null' for nullable values."
    )

    print()


    for _, key in ipairs(
        keys_to_configure
    ) do
        local value =
            askConfigValue(
                config,
                key
            )


        values[key] =
            value
    end


    local success,
        save_error =
        config.save(
            values
        )


    if not success then
        error(
            "Failed to save config.json: "
            .. tostring(
                save_error
            )
        )
    end


    print()

    print(
        "Configuration saved"
    )
end


local function reboot()
    print()

    print(
        "Installation complete"
    )

    print(
        "Rebooting..."
    )


    sleep(1)

    os.reboot()
end


downloadFiles()


local config =
    createDefaultConfig()


if not waitForConfigurationRequest() then
    print()

    print(
        "Configuration skipped"
    )

    reboot()

    return
end


local mode =
    askConfigMode()


configure(
    config,
    mode
)


reboot()