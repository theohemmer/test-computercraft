
--================================================
-- CREATE: ENCHANTMENT INDUSTRY PRINTER CONTROLLER
-- CC:Tweaked / Arcadia V2
--================================================

local CONFIG = {
    chest = "left",
    deployer = "create_deployer_0",
    tank = "create_fluid_tank_0",
    printer = "back",
    monitor = "monitor_0",

    minimumFluid = 2000,
    refreshRate = 1,
    monitorScale = 0.5
}

--================================================
-- PERIPHERALS
--================================================

local chest = peripheral.wrap(CONFIG.chest)
local deployer = peripheral.wrap(CONFIG.deployer)
local tank = peripheral.wrap(CONFIG.tank)
local monitor = peripheral.wrap(CONFIG.monitor)

-- Printer must use peripheral.call
local function printerCall(method, ...)
    return peripheral.call(CONFIG.printer, method, ...)
end

assert(chest, "Chest not found")
assert(deployer, "Deployer not found")
assert(tank, "Tank not found")
assert(monitor, "Monitor not found")

assert(
    peripheral.isPresent(CONFIG.printer),
    "Printer not found"
)

--================================================
-- SCREEN
--================================================

monitor.setTextScale(CONFIG.monitorScale)

local W, H = monitor.getSize()

local selected = nil
local books = {}
local page = 1

local status = "SYSTEM READY"
local statusColor = colors.lime

local running = true

--================================================
-- SCREEN FUNCTIONS
--================================================

local function writeAt(x, y, message, color, bg)

    if y < 1 or y > H then
        return
    end

    monitor.setCursorPos(x, y)

    monitor.setTextColor(color or colors.white)
    monitor.setBackgroundColor(bg or colors.black)

    monitor.write(
        string.sub(tostring(message), 1, W - x + 1)
    )
end

local function center(y, message, color)

    message = tostring(message)

    local x = math.max(
        1,
        math.floor((W - #message) / 2) + 1
    )

    writeAt(x, y, message, color)
end

local function setStatus(message, color)

    status = message
    statusColor = color or colors.white

end

--================================================
-- FLUID FUNCTIONS
--================================================

local function extractFluid(data)

    if type(data) ~= "table" then
        return 0, nil
    end

    -- Single fluid entry
    if type(data.amount) == "number" then

        return data.amount,
            data.name or
            (data.fluid and data.fluid.name)

    end

    -- Nested fluid entry
    if type(data.fluid) == "table" then

        return tonumber(data.fluid.amount)
            or tonumber(data.amount)
            or 0,
            data.fluid.name or data.name

    end

    -- Multiple tanks or fluid entries
    local total = 0
    local fluidName = nil

    for _, entry in pairs(data) do

        if type(entry) == "table" then

            local amount = tonumber(entry.amount) or 0

            local name = entry.name

            if type(entry.fluid) == "table" then

                amount = tonumber(entry.fluid.amount)
                    or amount

                name = entry.fluid.name or name

            end

            total = total + amount

            if amount > 0 then
                fluidName = fluidName or name
            end

        end

    end

    return total, fluidName

end

local function readTank()

    local ok, result = pcall(
        tank.getFluids
    )

    if not ok then
        return nil, nil
    end

    return extractFluid(result)

end

local function readPrinter()

    local ok, result = pcall(
        printerCall,
        "tanks"
    )

    if not ok then
        return nil, nil
    end

    return extractFluid(result)

end

--================================================
-- AUTOMATIC PRINTER REFILL
--================================================

local function refillPrinter()

    local sourceAmount, sourceFluid = readTank()

    local printerAmount, printerFluid = readPrinter()

    if sourceAmount == nil or printerAmount == nil then

        return false, "FLUID READING ERROR"

    end

    -- Already enough fluid
    if printerAmount >= CONFIG.minimumFluid then

        return true, "FLUID OK"

    end

    -- Check source tank
    if sourceAmount <= 0 then

        return false, "SOURCE TANK EMPTY"

    end

    if not sourceFluid then

        return false, "UNKNOWN SOURCE FLUID"

    end

    -- Avoid mixing fluid types
    if printerFluid
        and printerFluid ~= sourceFluid then

        return false, "FLUID TYPE MISMATCH"

    end

    local needed =
        CONFIG.minimumFluid - printerAmount

    local transfer =
        math.min(needed, sourceAmount)

    setStatus("REFILLING PRINTER...", colors.yellow)

    drawUI()

    local ok, result = pcall(

        printerCall,

        "pullFluid",

        CONFIG.tank,

        transfer,

        sourceFluid

    )

    if not ok then

        return false,
            "REFILL ERROR: " .. tostring(result)

    end

    -- Verify actual Printer fluid amount
    local updatedAmount = readPrinter()

    if updatedAmount
        and updatedAmount >= CONFIG.minimumFluid then

        return true, "REFILL COMPLETE"

    end

    return false, "INSUFFICIENT FLUID"

end

--================================================
-- INVENTORY FUNCTIONS
--================================================

local function getChestItems()

    local result = {}

    local inventory = chest.list()

    for slot, item in pairs(inventory) do

        local detail = chest.getItemDetails(slot)

        result[#result + 1] = {

            slot = slot,

            id = item.name,

            count = item.count,

            name = detail
                and detail.displayName
                or item.name

        }

    end

    table.sort(result, function(a, b)

        return a.slot < b.slot

    end)

    return result

end

local function getDeployerItems()

    local result = {}

    local inventory = deployer.list()

    for slot, item in pairs(inventory) do

        local detail = deployer.getItemDetail(slot)

        result[#result + 1] = {

            slot = slot,

            id = item.name,

            count = item.count,

            name = detail
                and detail.displayName
                or item.name

        }

    end

    return result

end

local function refreshInventory()

    books = getChestItems()

    if selected then

        local found = false

        for _, item in ipairs(books) do

            if item.slot == selected.slot
                and item.id == selected.id then

                selected = item
                found = true

                break

            end

        end

        if not found then
            selected = nil
        end

    end

end

--================================================
-- EMPTY DEPLOYER
--================================================

local function emptyDeployer()

    local inventory = deployer.list()

    for slot, item in pairs(inventory) do

        local moved = deployer.pushItems(

            CONFIG.chest,

            slot,

            item.count

        )

        if moved ~= item.count then

            return false,
                "CANNOT RETURN ITEM FROM SLOT " .. slot

        end

    end

    -- Verify actual inventory
    local remaining = deployer.list()

    for _, item in pairs(remaining) do

        if item.count > 0 then

            return false, "DEPLOYER NOT EMPTY"

        end

    end

    return true

end

--================================================
-- LOAD SELECTED BOOK
--================================================

local busy = false

local function loadSelected()

    if busy then
        return
    end

    if not selected then

        setStatus("SELECT AN ITEM FIRST", colors.red)
        return

    end

    busy = true

    local function finish(message, color)

        setStatus(message, color)
        busy = false
        refreshInventory()
        drawUI()

    end

    -- FIRST FLUID CHECK
    local success, message = refillPrinter()

    if not success then

        finish(message, colors.red)
        return

    end

    -- VERIFY SELECTED CHEST ITEM
    local current = chest.list()[selected.slot]

    if not current or current.name ~= selected.id then

        finish("ITEM NO LONGER AVAILABLE", colors.red)
        return

    end

    -- RETURN PREVIOUS DEPLOYER ITEM
    setStatus("RETURNING OLD ITEM...", colors.yellow)
    drawUI()

    local emptied, reason = emptyDeployer()

    if not emptied then

        finish(reason, colors.red)
        return

    end

    -- REFILL / CHECK AGAIN
    success, message = refillPrinter()

    if not success then

        finish(message, colors.red)
        return

    end

    -- VERIFY ITEM STILL EXISTS
    current = chest.list()[selected.slot]

    if not current or current.name ~= selected.id then

        finish("SELECTED ITEM MISSING", colors.red)
        return

    end

    -- INSERT ONE ITEM
    setStatus("INSERTING ITEM...", colors.yellow)
    drawUI()

    local moved = chest.pushItems(

        CONFIG.deployer,

        selected.slot,

        1

    )

    if moved ~= 1 then

        finish("ITEM INSERTION FAILED", colors.red)
        return

    end

    -- VERIFY USING REAL DEPLOYER INVENTORY
    local actual = getDeployerItems()

    local found = false

    for _, item in ipairs(actual) do

        if item.id == selected.id then

            found = true
            break

        end

    end

    if found then

        finish("ITEM INSTALLED SUCCESSFULLY", colors.lime)

    else

        finish("ITEM VERIFICATION FAILED", colors.red)

    end

end

--================================================
-- USER INTERFACE
--================================================

function drawUI()

    monitor.setBackgroundColor(colors.black)
    monitor.clear()

    center(1, "CREATE PRINTER CONTROL", colors.cyan)

    -- SOURCE TANK
    local sourceAmount = readTank()

    writeAt(2, 2, "SOURCE TANK:", colors.lightBlue)

    writeAt(
        15,
        2,
        sourceAmount and
            (sourceAmount .. " mB")
            or "ERROR",
        sourceAmount and
            colors.lime or colors.red
    )

    -- PRINTER FLUID
    local printerAmount = readPrinter()

    writeAt(2, 3, "PRINTER FLUID:", colors.lightBlue)

    writeAt(
        17,
        3,
        printerAmount and
            (printerAmount .. " mB")
            or "ERROR",
        printerAmount
            and printerAmount >= CONFIG.minimumFluid
            and colors.lime
            or colors.red
    )

    -- DEPLOYER CONTENTS
    writeAt(2, 4, "DEPLOYER:", colors.yellow)

    local contents = getDeployerItems()

    if #contents == 0 then

        writeAt(13, 4, "EMPTY", colors.gray)

    else

        local item = contents[1]

        writeAt(
            13,
            4,
            item.name .. " x" .. item.count,
            colors.lime
        )

    end

    writeAt(
        1,
        5,
        string.rep("-", W),
        colors.gray
    )

    center(6, "SELECT PRINTABLE ITEM", colors.cyan)

    -- ITEM LIST
    local rows = math.max(1, H - 9)

    local start = (page - 1) * rows + 1

    for i = 0, rows - 1 do

        local item = books[start + i]

        if item then

            local prefix = "  "

            if selected
                and selected.slot == item.slot then

                prefix = "> "

            end

            local label =
                prefix ..
                item.name ..
                " x" ..
                item.count

            if selected
                and selected.slot == item.slot then

                writeAt(
                    2,
                    7 + i,
                    label,
                    colors.black,
                    colors.lime
                )

            else

                writeAt(
                    2,
                    7 + i,
                    label,
                    colors.white
                )

            end

        end

    end

    -- PAGE
    local totalPages = math.max(
        1,
        math.ceil(#books / rows)
    )

    writeAt(
        2,
        H - 2,
        "PAGE " .. page .. "/" .. totalPages,
        colors.lightBlue
    )

    -- STATUS
    writeAt(
        2,
        H - 1,
        status,
        statusColor
    )

    -- BUTTONS
    local buttonWidth = math.floor(W / 4)

    writeAt(
        1,
        H,
        "[PREV]",
        colors.white,
        colors.gray
    )

    writeAt(
        buttonWidth + 1,
        H,
        "[LOAD]",
        colors.white,
        colors.blue
    )

    writeAt(
        buttonWidth * 2 + 1,
        H,
        "[NEXT]",
        colors.white,
        colors.gray
    )

    writeAt(
        buttonWidth * 3 + 1,
        H,
        "[REFRESH]",
        colors.white,
        colors.green
    )

    monitor.setBackgroundColor(colors.black)

end

--================================================
-- TOUCHSCREEN
--================================================

local function handleTouch(x, y)

    local rows = math.max(1, H - 9)

    local buttonWidth = math.floor(W / 4)

    if y == H then

        if x <= buttonWidth then

            page = math.max(1, page - 1)

        elseif x <= buttonWidth * 2 then

            loadSelected()

            return

        elseif x <= buttonWidth * 3 then

            local maxPages = math.max(
                1,
                math.ceil(#books / rows)
            )

            page = math.min(maxPages, page + 1)

        else

            refreshInventory()

            setStatus("INVENTORY REFRESHED", colors.lime)

        end

        drawUI()
        return

    end

    -- ITEM SELECTION
    if y >= 7 and y <= H - 3 then

        local index =
            (page - 1) * rows + (y - 7) + 1

        if books[index] then

            selected = books[index]

            setStatus(
                "SELECTED: " .. selected.name,
                colors.cyan
            )

            drawUI()

        end

    end

end

--================================================
-- MAIN LOOP
--================================================

refreshInventory()
drawUI()

local lastRefresh = os.clock()
local lastRefill = os.clock()

while running do

    local event, p1, p2, p3 = os.pullEvent()

    if event == "monitor_touch"
        and p1 == CONFIG.monitor then

        handleTouch(p2, p3)

    elseif event == "terminate" then

        running = false

    end

    -- PERIODIC REFRESH
    if os.clock() - lastRefresh >= CONFIG.refreshRate then

        refreshInventory()

        lastRefresh = os.clock()

        drawUI()

    end

    -- AUTOMATIC FLUID REFILL
    if not busy and os.clock() - lastRefill >= 2 then

        lastRefill = os.clock()

        local ok, message = refillPrinter()

        if not ok then

            setStatus(message, colors.red)

        elseif message == "REFILL COMPLETE" then

            setStatus(message, colors.lime)

        end

        drawUI()

    end

end

monitor.setBackgroundColor(colors.black)
monitor.clear()

print("Printer controller stopped.")
