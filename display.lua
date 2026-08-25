-- display.lua

local config = require("config")

local display = {}

local monitor = nil
local monitor_name = nil


local button = {
    x1 = 1,
    y1 = 1,
    x2 = 1,
    y2 = 1
}


local BACKGROUND_COLOR = colors.black
local TEXT_COLOR = colors.white

local BUTTON_COLOR = colors.blue
local BUTTON_TEXT_COLOR = colors.lightBlue

local FAILURE_BUTTON_COLOR = colors.red
local FAILURE_TEXT_COLOR = colors.orange


local function isMonitor(name)
    if name == nil then
        return false
    end


    return peripheral.getType(name)
        == "monitor"
end


local function isDebugMonitor(name)
    if config.debug_display_side == nil then
        return false
    end


    return name
        == config.debug_display_side
end


local function findMonitor(
    configured_name
)
    -- Explicit display configured.
    if configured_name ~= nil then
        if isDebugMonitor(
            configured_name
        ) then
            error(
                "Display and debug display cannot use the same monitor: "
                .. tostring(
                    configured_name
                )
            )
        end


        if not isMonitor(
            configured_name
        ) then
            error(
                "Configured display '"
                .. tostring(
                    configured_name
                )
                .. "' is not a monitor"
            )
        end


        return configured_name,
            peripheral.wrap(
                configured_name
            )
    end


    -- display_side == nil
    --
    -- Automatically find a monitor.
    -- The configured debug display is always
    -- excluded from this search.
    for _, name in ipairs(
        peripheral.getNames()
    ) do
        if isMonitor(name)
            and not isDebugMonitor(name)
        then
            return name,
                peripheral.wrap(
                    name
                )
        end
    end


    return nil, nil
end


local function configurePalette(
    background_color,
    text_color,
    button_color,
    button_text_color,
    failure_button_color,
    failure_text_color
)
    if not monitor.isColor() then
        return
    end


    monitor.setPaletteColor(
        BACKGROUND_COLOR,
        background_color
    )


    monitor.setPaletteColor(
        TEXT_COLOR,
        text_color
    )


    monitor.setPaletteColor(
        BUTTON_COLOR,
        button_color
    )


    monitor.setPaletteColor(
        BUTTON_TEXT_COLOR,
        button_text_color
    )


    monitor.setPaletteColor(
        FAILURE_BUTTON_COLOR,
        failure_button_color
    )


    monitor.setPaletteColor(
        FAILURE_TEXT_COLOR,
        failure_text_color
    )
end


local function centerText(
    y,
    text,
    foreground,
    background
)
    local width, _ =
        monitor.getSize()


    local x =
        math.floor(
            (width - #text) / 2
        ) + 1


    if x < 1 then
        x = 1
    end


    monitor.setTextColor(
        foreground
    )


    monitor.setBackgroundColor(
        background
    )


    monitor.setCursorPos(
        x,
        y
    )


    monitor.write(
        text
    )
end


local function drawButton(
    text,
    background,
    foreground
)
    for y = button.y1, button.y2 do
        monitor.setCursorPos(
            button.x1,
            y
        )


        monitor.setBackgroundColor(
            background
        )


        monitor.write(
            string.rep(
                " ",
                button.x2
                    - button.x1
                    + 1
            )
        )
    end


    local height =
        button.y2
        - button.y1
        + 1


    local text_y =
        button.y1
        + math.floor(
            height / 2
        )


    centerText(
        text_y,
        text,
        foreground,
        background
    )
end


local function getAnimationText(
    call_state
)
    if call_state == nil then
        return nil
    end


    if not call_state.animation_active then
        return nil
    end


    local max_arrows =
        call_state.animation_arrow_count
        or 1


    local frame =
        call_state.animation_frame
        or 1


    if max_arrows < 1 then
        max_arrows = 1
    end


    local frame_count =
        max_arrows * 2 - 1


    local arrow_count


    if frame <= max_arrows then
        arrow_count =
            frame
    else
        arrow_count =
            frame_count
            - frame
            + 1
    end


    local direction =
        call_state.animation_direction


    if direction == ">" then
        return string.rep(
            " ",
            max_arrows
                - arrow_count
        )
            .. string.rep(
                ">",
                arrow_count
            )
    end


    if direction == "<" then
        return string.rep(
            "<",
            arrow_count
        )
            .. string.rep(
                " ",
                max_arrows
                    - arrow_count
            )
    end


    return nil
end


function display.init(
    configured_name,
    background_color,
    text_color,
    button_color,
    button_text_color,
    failure_button_color,
    failure_text_color
)
    monitor_name,
    monitor =
        findMonitor(
            configured_name
        )


    if monitor == nil then
        if config.debug_display_side
            ~= nil
        then
            error(
                "No display monitor found. Debug monitor '"
                .. tostring(
                    config.debug_display_side
                )
                .. "' is excluded."
            )
        end


        error(
            "No display monitor found"
        )
    end


    print(
        "Display monitor: "
        .. monitor_name
    )


    monitor.setTextScale(
        0.5
    )


    configurePalette(
        background_color,
        text_color,
        button_color,
        button_text_color,
        failure_button_color,
        failure_text_color
    )


    monitor.setBackgroundColor(
        BACKGROUND_COLOR
    )


    monitor.setTextColor(
        TEXT_COLOR
    )


    monitor.clear()
end


function display.update(
    group,
    floor,
    call_state,
    current_time
)
    if monitor == nil then
        return
    end


    local width, height =
        monitor.getSize()


    monitor.setBackgroundColor(
        BACKGROUND_COLOR
    )


    monitor.setTextColor(
        TEXT_COLOR
    )


    monitor.clear()


    local header =
        "G"
        .. group
        .. " | F"
        .. floor


    centerText(
        1,
        header,
        TEXT_COLOR,
        BACKGROUND_COLOR
    )


    button.x1 = 2
    button.x2 = width - 1

    button.y1 = 3
    button.y2 = height - 1


    if button.x2
        < button.x1
    then
        button.x1 = 1
        button.x2 = width
    end


    if button.y2
        < button.y1
    then
        button.y1 = 2
        button.y2 = height
    end


    local button_text =
        "CALL"


    local button_background =
        BUTTON_COLOR


    local button_foreground =
        BUTTON_TEXT_COLOR


    if call_state ~= nil then
        if call_state.status
            == "failed"
        then
            button_text =
                "CALL FAILED"


            button_background =
                FAILURE_BUTTON_COLOR


            button_foreground =
                FAILURE_TEXT_COLOR


        elseif call_state.status
            == "arrived"
        then
            local animation_text =
                getAnimationText(
                    call_state
                )


            if animation_text ~= nil then
                button_text =
                    animation_text
            else
                button_text =
                    "CALL"
            end


        elseif call_state.status
            == "queued"
        then
            button_text =
                "QUEUED"


        elseif call_state.status
            == "waiting"
        then
            local remaining =
                call_state.wait_until
                - current_time


            if remaining < 0 then
                remaining = 0
            end


            button_text =
                string.format(
                    "WAIT %.1fs",
                    remaining
                )
        end
    end


    drawButton(
        button_text,
        button_background,
        button_foreground
    )


    monitor.setBackgroundColor(
        BACKGROUND_COLOR
    )


    monitor.setTextColor(
        TEXT_COLOR
    )
end


function display.isCallButton(
    side,
    x,
    y
)
    if monitor == nil then
        return false
    end


    if side ~= monitor_name then
        return false
    end


    return x >= button.x1
        and x <= button.x2
        and y >= button.y1
        and y <= button.y2
end


function display.getName()
    return monitor_name
end


return display