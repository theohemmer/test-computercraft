
--[[
    CREATE PRINTER CONTROLLER
    CC:Tweaked + Create: Enchantment Industry

    Chest:    left
    Deployer: create_deployer_0
    Tank:     create_fluid_tank_0
    Printer:  back
    Monitor:  monitor_0

    Minimum source fluid: 2000 mB
]]

local CHEST_NAME = "left"
local DEPLOYER_NAME = "create_deployer_0"
local TANK_NAME = "create_fluid_tank_0"
local PRINTER_NAME = "back"
local MONITOR_NAME = "monitor_0"

local MIN_FLUID = 2000
local REFRESH_INTERVAL = 1

local chest = peripheral.wrap(CHEST_NAME)
local deployer = peripheral.wrap(DEPLOYER_NAME)
local tank = peripheral.wrap(TANK_NAME)
local printer = peripheral.wrap(PRINTER_NAME)
local monitor = peripheral.wrap(MONITOR_NAME)

assert(chest, "Chest not found!")
assert(deployer, "Deployer not found!")
assert(tank, "Fluid tank not found!")
assert(printer, "Printer not found!")
assert(monitor, "Monitor not found!")

monitor.setTextScale(0.5)

local W, H = monitor.getSize()

local selected = nil
local page = 1
local books = {}

local status = "Ready"
local statusColor = colors.lime

--------------------------------------------------
-- DISPLAY HELPERS
--------------------------------------------------

local function writeAt(x, y, str, color, bg)
    if y < 1 or y > H then return end

    if bg then
        monitor.setBackgroundColor(bg)
    else
        monitor.setBackgroundColor(colors.black)
    end

    if color then
        monitor.setTextColor(color)
    else
        monitor.setTextColor(colors.white)
    end

    monitor.setCursorPos(x, y)
    monitor.write(string.sub(str, 1, W - x + 1))
end

local function center(y, str, color)
    local x = math.max(1, math.floor((W - #str) / 2) + 1)
    writeAt(x, y, str, color)
end

local function setStatus(message, color)
    status = message
    statusColor = color or colors.white
end

--------------------------------------------------
-- FLUID READING
--------------------------------------------------

local function getFluidAmount(data)
    if type(data) ~= "table" then
        return 0
    end

    local total = 0

    -- Handle a single fluid entry.
    if type(data.amount) == "number" then
        return data.amount
    end

    if type(data.fluid) == "table"
        and type(data.fluid.amount) == "number" then
        return data.fluid.amount
    end

    -- Handle a list of fluid entries.
    for _, entry in pairs(data) do
        if type(entry) == "table" then
            if type(entry.amount) == "number" then
                total = total + entry.amount
            elseif type(entry.fluid) == "table"
                and type(entry.fluid.amount) == "number" then
                total = total + entry.fluid.amount
            end
        end
    end

    return total
end

local function readTank()
    local ok, result = pcall(tank.getFluids)

    if not ok then return nil end

    return getFluidAmount(result)
end

local function readPrinterFluid()
    local ok, result = pcall(printer.tanks)

    if not ok then return nil end

    return getFluidAmount(result)
end

--------------------------------------------------
-- INVENTORY READING
--------------------------------------------------

local function getItemName(item)
    if not item then return "Empty" end

    return item.displayName or item.name or "Unknown item"
end

local function getDeployerItems()
    local result = {}

    local inventory = deployer.list()

    for slot, item in pairs(inventory) do
        local detail = deployer.getItemDetail(slot)

        result[#result + 1] = {
            slot = slot,
            name = getItemName(detail or item),
            count = item.count,
            id = item.name
        }
    end

    return result
end

local function getChestItems()
    local result = {}

    local inventory = chest.list()

    for slot, item in pairs(inventory) do
        local detail = chest.getItemDetails(slot)

        result[#result + 1] = {
            slot = slot,
            name = getItemName(detail or item),
            count = item.count,
            id = item.name
        }
    end

    table.sort(result, function(a, b)
        return a.slot < b.slot
    end)

    return result
end

--------------------------------------------------
-- RETURN DEPLOYER CONTENTS TO CHEST
--------------------------------------------------

local function emptyDeployer()
    local inventory = deployer.list()

    for slot, item in pairs(inventory) do

        local moved = deployer.pushItems(
            CHEST_NAME,
            slot,
            item.count
        )

        if moved ~= item.count then
            return false,
                "Could not empty slot " .. slot
        end
    end

    -- Verify that the Deployer is empty.
    local remaining = deployer.list()

    for _, item in pairs(remaining) do
        if item.count > 0 then
            return false, "Deployer is not empty!"
        end
    end

    return true
end

--------------------------------------------------
-- INSERT SELECTED ITEM
--------------------------------------------------

local function insertItem(item)

    if not item then
        setStatus("No item selected!", colors.red)
        return
    end

    -- Always check the source tank first.
    local fluid = readTank()

    if fluid == nil then
        setStatus("Cannot read source tank!", colors.red)
        return
    end

    if fluid < MIN_FLUID then
        setStatus("Insufficient fluid! Need 2000 mB",
            colors.red)
        return
    end

    -- Make sure the selected chest slot still contains
    -- the selected item.
    local current = chest.list()[item.slot]

    if not current or current.name ~= item.id then
        setStatus("Item no longer in chest!", colors.red)
        return
    end

    setStatus("Returning old item...", colors.yellow)
    drawUI()

    -- IMPORTANT:
    -- Return the current Deployer contents FIRST.
    local success, reason = emptyDeployer()

    if not success then
        setStatus(reason, colors.red)
        return
    end

    -- Check fluid again before inserting.
    fluid = readTank()

    if not fluid or fluid < MIN_FLUID then
        setStatus("Fluid below 2000 mB!", colors.red)
        return
    end

    setStatus("Inserting selected item...", colors.yellow)
    drawUI()

    -- Transfer exactly one item.
    local moved = chest.pushItems(
        DEPLOYER_NAME,
        item.slot,
        1
    )

    if moved ~= 1 then
        setStatus("Insertion failed!", colors.red)
        return
    end

    -- Read the Deployer again.
    -- Never rely on an in-memory item selection.
    local actual = getDeployerItems()

    local found = false

    for _, entry in ipairs(actual) do
        if entry.id == item.id then
            found = true
            break
        end
    end

    if found then
        setStatus("Item successfully installed!",
            colors.lime)
    else
        setStatus("Verification failed!", colors.red)
    end

    selected = nil
    books = getChestItems()
end

--------------------------------------------------
-- UI
--------------------------------------------------

local function drawUI()

    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    -- Header
    center(1, "CREATE PRINTER CONTROL", colors.cyan)

    writeAt(2, 2, "SOURCE TANK:", colors.lightBlue)

    local tankAmount = readTank()

    if tankAmount then
        local color = tankAmount >= MIN_FLUID
            and colors.lime or colors.red

        writeAt(15, 2,
            tostring(tankAmount) .. " mB", color)
    else
        writeAt(15, 2, "ERROR", colors.red)
    end

    writeAt(2, 3, "PRINTER FLUID:", colors.lightBlue)

    local printerAmount = readPrinterFluid()

    if printerAmount then
        writeAt(17, 3,
            tostring(printerAmount) .. " mB",
            colors.orange)
    else
        writeAt(17, 3, "ERROR", colors.red)
    end

    -- Actual Deployer contents
    writeAt(2, 4, "DEPLOYER:", colors.yellow)

    local contents = getDeployerItems()

    if #contents == 0 then
        writeAt(13, 4, "EMPTY", colors.gray)
    else
        local first = contents[1]

        writeAt(13, 4,
            first.name .. " x" .. first.count,
            colors.lime)
    end

    -- Separator
    writeAt(1, 5, string.rep("-", W), colors.gray)

    center(6, "SELECT PRINTABLE ITEM", colors.cyan)

    -- Item list
    local rows = H - 9

    if rows < 1 then rows = 1 end

    local startIndex = (page - 1) * rows + 1

    for i = 0, rows - 1 do

        local index = startIndex + i
        local item = books[index]

        local y = 7 + i

        if item then

            local prefix = "  "

            if selected and selected.slot == item.slot then
                prefix = "> "
            end

            local label = prefix
                .. item.name
                .. " x"
                .. item.count

            if selected and selected.slot == item.slot then
                writeAt(2, y, label,
                    colors.black, colors.lime)
            else
                writeAt(2, y, label, colors.white)
            end
        end
    end

    -- Page indicator
    local totalPages = math.max(
        1,
        math.ceil(#books / rows)
    )

    writeAt(2, H - 2,
        "PAGE " .. page .. "/" .. totalPages,
        colors.lightBlue)

    -- Buttons
    local buttonWidth = math.floor(W / 4)

    writeAt(1, H,
        "[PREV]", colors.white, colors.gray)

    writeAt(buttonWidth + 1, H,
        "[LOAD]", colors.white, colors.blue)

    writeAt(buttonWidth * 2 + 1, H,
        "[NEXT]", colors.white, colors.gray)

    writeAt(buttonWidth * 3 + 1, H,
        "[REFRESH]", colors.white, colors.green)

    -- Status
    writeAt(2, H - 1, status, statusColor)

    monitor.setBackgroundColor(colors.black)
end

--------------------------------------------------
-- TOUCHSCREEN EVENTS
--------------------------------------------------

local function handleTouch(x, y)

    local rows = H - 9
    if rows < 1 then rows = 1 end

    local buttonWidth = math.floor(W / 4)

    -- PREVIOUS PAGE
    if y == H and x <= buttonWidth then
        page = math.max(1, page - 1)
        drawUI()
        return
    end

    -- LOAD SELECTED
    if y == H and x > buttonWidth
        and x <= buttonWidth * 2 then

        insertItem(selected)
        drawUI()
        return
    end

    -- NEXT PAGE
    if y == H and x > buttonWidth * 2
        and x <= buttonWidth * 3 then

        local maxPages = math.max(
            1,
            math.ceil(#books / rows)
        )

        page = math.min(maxPages, page + 1)
        drawUI()
        return
    end

    -- REFRESH
    if y == H and x > buttonWidth * 3 then
        books = getChestItems()
        setStatus("Inventory refreshed", colors.lime)
        drawUI()
        return
    end

    -- ITEM SELECTION
    if y >= 7 and y <= H - 3 then

        local index = (page - 1) * rows
            + (y - 7) + 1

        if books[index] then
            selected = books[index]

            setStatus(
                "Selected: " .. selected.name,
                colors.cyan
            )

            drawUI()
        end
    end
end

--------------------------------------------------
-- MAIN PROGRAM
--------------------------------------------------

books = getChestItems()

drawUI()

local lastRefresh = os.clock()

while true do

    local event, p1, p2, p3 = os.pullEvent()

    if event == "monitor_touch"
        and p1 == MONITOR_NAME then

        handleTouch(p2, p3)

    elseif event == "timer" then
        -- Timer handling is not required here.
    end

    -- Automatic refresh
    if os.clock() - lastRefresh >= REFRESH_INTERVAL then

        books = getChestItems()

        -- Keep selected item synchronized with chest.
        if selected then
            local stillExists = false

            for _, item in ipairs(books) do
                if item.slot == selected.slot
                    and item.id == selected.id then
                    stillExists = true
                    selected = item
                    break
                end
            end

            if not stillExists then
                selected = nil
            end
        end

        lastRefresh = os.clock()
        drawUI()
    end
end
