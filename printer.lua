
--------------------------------------------------
-- CREATE BOOK PRINTING STATION
-- ComputerCraft: Tweaked
-- Advanced Monitor + Create Printer
--------------------------------------------------

--------------------------------------------------
-- CONFIGURATION
--------------------------------------------------

local CONFIG = {

    -- Peripheral names (all configurable)
    PERIPHERALS = {
        raw_books = "minecraft:chest_6",
        available_books = "minecraft:chest_1",
        input_raw_books = "minecraft:chest_4",
        printed_books = "minecraft:chest_2",
        output_books = "minecraft:chest_5",
        input_book = "minecraft:chest_0",

        fluid_tank = "create:fluid_tank_1",
        printer = "create_enchantment_industry:printer_0",

        monitor = "monitor_1",
        redstone_relay = "redstone_relay_0"
    },

    -- Main fluid tank
    FLUID_TANK_CAPACITY_MB = 64000,
    MIN_MAIN_FLUID_MB = 10000,

    -- Printer fluid
    MIN_PRINTER_FLUID_MB = 500,

    -- Production
    SECONDS_PER_BOOK = 3,
    MAX_BOOKS = 5,

    -- Redstone
    REDSTONE_SIDE = "left",
    RESET_DURATION = 3,

    -- Interface
    MONITOR_SCALE = 0.5,
    REFRESH_RATE = 0.5,

    -- Number of books displayed at once
    VISIBLE_BOOKS = 5
}

--------------------------------------------------
-- PERIPHERAL INITIALIZATION
--------------------------------------------------

local function getPeripheral(configName)
    local name = CONFIG.PERIPHERALS[configName]

    if not name then
        error("Missing peripheral configuration: " .. configName)
    end

    local p = peripheral.wrap(name)

    if not p then
        error("Peripheral not found: " .. name)
    end

    return p
end

local rawBooks = getPeripheral("raw_books")
local availableBooks = getPeripheral("available_books")
local inputRawBooks = getPeripheral("input_raw_books")
local printedBooks = getPeripheral("printed_books")
local outputBooks = getPeripheral("output_books")
local inputBook = getPeripheral("input_book")

local fluidTank = getPeripheral("fluid_tank")
local printer = getPeripheral("printer")

local monitor = getPeripheral("monitor")
local relay = getPeripheral("redstone_relay")

local function peripheralName(name)
    return CONFIG.PERIPHERALS[name]
end

--------------------------------------------------
-- STATE
--------------------------------------------------

monitor.setTextScale(CONFIG.MONITOR_SCALE)

local W, H = monitor.getSize()

local selectedBook = nil
local selectedQuantity = 1
local scrollOffset = 0

local status = "READY"
local message = "Select a book"

local busy = false
local remainingTime = 0

local catalogue = {}

--------------------------------------------------
-- REDSTONE
--------------------------------------------------

local function machineOn()
    relay.setOutput(CONFIG.REDSTONE_SIDE, true)
end

local function machineOff()
    relay.setOutput(CONFIG.REDSTONE_SIDE, false)
end

machineOn()

--------------------------------------------------
-- INVENTORY
--------------------------------------------------

local function countItems(inv)

    local total = 0

    for _, item in pairs(inv.list()) do
        total = total + item.count
    end

    return total

end

local function inventoryEmpty(inv)
    return countItems(inv) == 0
end

local function moveItems(source, destination, amount)

    local remaining = amount
    local moved = 0

    local destinationName = nil

    local destinations = {
        [rawBooks] = "raw_books",
        [availableBooks] = "available_books",
        [inputRawBooks] = "input_raw_books",
        [printedBooks] = "printed_books",
        [outputBooks] = "output_books",
        [inputBook] = "input_book"
    }

    destinationName = destinations[destination]

    if not destinationName then
        error("Unknown destination inventory")
    end

    for slot, item in pairs(source.list()) do

        if remaining <= 0 then
            break
        end

        local amountToMove = math.min(item.count, remaining)

        local transferred = source.pushItems(
            peripheralName(destinationName),
            slot,
            amountToMove
        )

        moved = moved + transferred
        remaining = remaining - transferred

    end

    return moved

end

--------------------------------------------------
-- FLUID
--------------------------------------------------

local function getFluidAmount(p)

    local total = 0

    for _, tank in pairs(p.tanks()) do

        if tank and tank.amount then
            total = total + tank.amount
        end

    end

    return total

end

local function getMainFluid()
    return getFluidAmount(fluidTank)
end

local function getPrinterFluid()
    return getFluidAmount(printer)
end

local function getMainPercentage()

    return math.floor(
        getMainFluid() /
        CONFIG.FLUID_TANK_CAPACITY_MB * 100
    )

end

--------------------------------------------------
-- BOOK IDENTIFICATION
--------------------------------------------------

local function getFingerprint(detail)

    if not detail then
        return nil
    end

    local nbt = ""

    if detail.nbt then
        nbt = textutils.serialize(detail.nbt)
    end

    return detail.name .. "|" .. nbt

end

--------------------------------------------------
-- CATALOGUE
--------------------------------------------------

local function refreshCatalogue()

    local newCatalogue = {}
    local indexed = {}

    for slot, item in pairs(availableBooks.list()) do

        local detail = availableBooks.getItemDetail(slot)

        if detail then

            local fingerprint = getFingerprint(detail)

            if not indexed[fingerprint] then

                indexed[fingerprint] = {
                    fingerprint = fingerprint,
                    name = detail.displayName or detail.name,
                    count = 0
                }

                table.insert(
                    newCatalogue,
                    indexed[fingerprint]
                )

            end

            indexed[fingerprint].count =
                indexed[fingerprint].count + item.count

        end

    end

    table.sort(newCatalogue, function(a, b)
        return a.name < b.name
    end)

    catalogue = newCatalogue

end

local function findBook(fingerprint)

    for slot, item in pairs(availableBooks.list()) do

        local detail = availableBooks.getItemDetail(slot)

        if detail and getFingerprint(detail) == fingerprint then
            return slot
        end

    end

    return nil

end

--------------------------------------------------
-- LOW LEVEL DRAWING
--------------------------------------------------

local function writeAt(x, y, text, fg, bg)

    if y < 1 or y > H or x > W then
        return
    end

    text = tostring(text)

    if x < 1 then
        text = text:sub(2 - x)
        x = 1
    end

    text = text:sub(1, W - x + 1)

    monitor.setCursorPos(x, y)
    monitor.setTextColor(fg or colors.white)
    monitor.setBackgroundColor(bg or colors.black)

    monitor.write(text)

end

local function centerText(y, text, fg, bg)

    local x = math.floor((W - #text) / 2) + 1

    writeAt(x, y, text, fg, bg)

end

local function clearLine(y, bg)

    writeAt(
        1,
        y,
        string.rep(" ", W),
        colors.white,
        bg or colors.black
    )

end

--------------------------------------------------
-- LAYOUT
--------------------------------------------------

local UI = {}

local function calculateLayout()

    UI.bookStart = 7

    -- Reserve more vertical space for buttons.
    UI.quantityTitle = H - 7
    UI.quantity = H - 6
    UI.print = H - 4
    UI.status = H - 3
    UI.message = H - 2
    UI.eta = H

    UI.scroll = H - 8

    UI.visibleBooks = math.min(
        CONFIG.VISIBLE_BOOKS,
        UI.scroll - UI.bookStart
    )

    if UI.visibleBooks < 1 then
        error("Monitor too small for interface")
    end

end

calculateLayout()

--------------------------------------------------
-- DRAW FLUIDS ONLY
--------------------------------------------------

local function drawFluids()

    local main = getMainFluid()
    local printerAmount = getPrinterFluid()

    local mainColor = colors.lime
    local printerColor = colors.lime

    if main < CONFIG.MIN_MAIN_FLUID_MB then
        mainColor = colors.red
    end

    if printerAmount < CONFIG.MIN_PRINTER_FLUID_MB then
        printerColor = colors.red
    end

    -- Only update the changing values.
    -- No screen clear, no catalogue redraw.

    writeAt(
        14, 3,
        getMainPercentage() .. "% (" ..
        main .. "/" ..
        CONFIG.FLUID_TANK_CAPACITY_MB .. " mB)   ",
        mainColor
    )

    writeAt(
        14, 4,
        printerAmount .. " mB     ",
        printerColor
    )

end

--------------------------------------------------
-- DRAW BOOK LIST
--------------------------------------------------

local function drawBooks()

    refreshCatalogue()

    for i = 1, UI.visibleBooks do

        local index = i + scrollOffset
        local book = catalogue[index]
        local y = UI.bookStart + i - 1

        clearLine(y)

        if book then

            local prefix = "  "
            local fg = colors.white
            local bg = colors.black

            if selectedBook == book.fingerprint then
                prefix = "> "
                fg = colors.black
                bg = colors.yellow
            end

            local label = book.name

            local maxLength = W - 14

            if #label > maxLength then
                label = label:sub(1, maxLength - 3) .. "..."
            end

            clearLine(y, bg)

            writeAt(2, y, prefix .. label, fg, bg)

            writeAt(
                W - 8,
                y,
                "x" .. book.count,
                fg,
                bg
            )

        end

    end

end

--------------------------------------------------
-- DRAW QUANTITY BUTTONS
--------------------------------------------------

local function drawQuantity()

    local buttonWidth = math.floor(W / 5)

    for i = 1, 5 do

        local x = (i - 1) * buttonWidth + 1

        local fg = colors.white
        local bg = colors.gray

        if selectedQuantity == i then
            fg = colors.black
            bg = colors.green
        end

        -- Entire button area is colored.

        for row = UI.quantityTitle, UI.quantity do

            writeAt(
                x,
                row,
                string.rep(" ", buttonWidth),
                fg,
                bg
            )

        end

        local label = "[ " .. i .. " ]"

        writeAt(
            x + math.floor((buttonWidth - #label) / 2),
            UI.quantity,
            label,
            fg,
            bg
        )

    end

end

--------------------------------------------------
-- DRAW START BUTTON
--------------------------------------------------

local function drawStartButton()

    local label = " START PRINTING "

    local width = math.min(W, #label + 8)
    local x = math.floor((W - width) / 2) + 1

    for row = UI.print, UI.print + 1 do

        writeAt(
            x,
            row,
            string.rep(" ", width),
            colors.black,
            colors.lime
        )

    end

    centerText(
        UI.print,
        label,
        colors.black,
        colors.lime
    )

    -- Second row gives the button a larger touch area.

    centerText(
        UI.print + 1,
        string.rep(" ", width),
        colors.black,
        colors.lime
    )

end

--------------------------------------------------
-- DRAW STATUS ONLY
--------------------------------------------------

local function drawStatus()

    local statusColor = colors.white

    if status == "READY" then
        statusColor = colors.lime
    elseif status == "ERROR" then
        statusColor = colors.red
    elseif status == "PRINTING" then
        statusColor = colors.yellow
    end

    centerText(UI.status, status, statusColor)

    centerText(UI.message, message, colors.white)

    local etaText = ""

    if busy then
        etaText = "ETA: " .. remainingTime .. "s"
    end

    centerText(UI.eta, etaText, colors.orange)

end

--------------------------------------------------
-- DRAW COMPLETE SCREEN
--------------------------------------------------

local function drawMonitor()

    W, H = monitor.getSize()
    calculateLayout()

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()

    clearLine(1, colors.blue)

    centerText(
        1,
        "BOOK PRINTING STATION",
        colors.white,
        colors.blue
    )

    writeAt(2, 3, "MAIN TANK:", colors.white)
    writeAt(2, 4, "PRINTER:", colors.white)

    centerText(6, "AVAILABLE BOOKS", colors.yellow)

    drawFluids()
    drawBooks()

    centerText(
        UI.scroll,
        "< PREVIOUS       NEXT >",
        colors.cyan
    )

    centerText(
        UI.quantityTitle,
        "QUANTITY",
        colors.yellow
    )

    drawQuantity()
    drawStartButton()
    drawStatus()

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)

end

--------------------------------------------------
-- FLUID SAFETY
--------------------------------------------------

local function checkFluids()

    if getMainFluid() < CONFIG.MIN_MAIN_FLUID_MB then
        return false, "Main tank below 10000 mB!"
    end

    if getPrinterFluid() < CONFIG.MIN_PRINTER_FLUID_MB then
        return false, "Printer below 500 mB!"
    end

    return true

end

--------------------------------------------------
-- ERROR DISPLAY
--------------------------------------------------

local function showError(text)

    status = "ERROR"
    message = text

    busy = false
    remainingTime = 0

    drawStatus()

end

--------------------------------------------------
-- MOVE PREVIOUS TEMPLATE BACK
--------------------------------------------------

local function returnPreviousTemplate()

    local amount = countItems(inputBook)

    if amount == 0 then
        return true
    end

    local moved = moveItems(
        inputBook,
        availableBooks,
        amount
    )

    return moved == amount

end

--------------------------------------------------
-- LOAD TEMPLATE
--------------------------------------------------

local function loadSelectedTemplate(fingerprint)

    if not returnPreviousTemplate() then
        return false, "Cannot return previous book"
    end

    local slot = findBook(fingerprint)

    if not slot then
        return false, "Selected book unavailable"
    end

    local moved = availableBooks.pushItems(
        peripheralName("input_book"),
        slot,
        1
    )

    if moved ~= 1 then
        return false, "Cannot load selected book"
    end

    return true

end

--------------------------------------------------
-- PRODUCTION
--------------------------------------------------

local function printBooks(book, quantity)

    busy = true

    status = "CHECKING"
    message = "Checking machine..."

    drawStatus()

    --------------------------------------------------
    -- FLUID CHECK
    --------------------------------------------------

    local fluidsOK, fluidError = checkFluids()

    if not fluidsOK then
        showError(fluidError)
        return
    end

    --------------------------------------------------
    -- INVENTORY CHECKS
    --------------------------------------------------

    if countItems(rawBooks) < quantity then
        showError("Not enough raw books")
        return
    end

    if not inventoryEmpty(inputRawBooks) then
        showError("Input raw books not empty")
        return
    end

    if not inventoryEmpty(printedBooks) then
        showError("Printed buffer not empty")
        return
    end

    --------------------------------------------------
    -- LOAD TEMPLATE
    --------------------------------------------------

    status = "LOADING"
    message = "Loading selected book..."

    drawStatus()

    local loaded, err = loadSelectedTemplate(
        book.fingerprint
    )

    if not loaded then
        showError(err)
        return
    end

    --------------------------------------------------
    -- LOAD RAW BOOKS
    --------------------------------------------------

    message = "Loading raw books..."

    drawStatus()

    local moved = moveItems(
        rawBooks,
        inputRawBooks,
        quantity
    )

    if moved ~= quantity then
        showError("Cannot load all raw books")
        return
    end

    --------------------------------------------------
    -- RECORD INITIAL OUTPUT
    --------------------------------------------------

    local initialPrinted = countItems(printedBooks)

    --------------------------------------------------
    -- START PRINTING
    --------------------------------------------------

    machineOn()

    status = "PRINTING"
    message = "Printing in progress..."

    local expectedTime =
        quantity * CONFIG.SECONDS_PER_BOOK

    remainingTime = expectedTime

    local startTime = os.clock()

    drawStatus()

    --------------------------------------------------
    -- WAIT FOR OUTPUT
    --------------------------------------------------

    local lastFluidRefresh = 0
    local lastStatusRefresh = 0

    while countItems(printedBooks) <
        initialPrinted + quantity do

        local elapsed = os.clock() - startTime

        remainingTime = math.max(
            0,
            math.ceil(expectedTime - elapsed)
        )

        -- Fluid readings update without redrawing the GUI.

        if elapsed - lastFluidRefresh >= CONFIG.REFRESH_RATE then

            local fluidsOK = checkFluids()

            if not fluidsOK then
                showError("Fluid level too low!")
                return
            end

            drawFluids()

            lastFluidRefresh = elapsed

        end

        -- ETA only updates when the displayed second changes.

        if elapsed - lastStatusRefresh >= 1 then

            drawStatus()

            lastStatusRefresh = elapsed

        end

        sleep(0.1)

    end

    --------------------------------------------------
    -- TRANSFER PRINTED BOOKS
    --------------------------------------------------

    status = "TRANSFERRING"
    message = "Transferring printed books..."

    drawStatus()

    local transferred = moveItems(
        printedBooks,
        outputBooks,
        quantity
    )

    if transferred ~= quantity then
        showError("Output transfer incomplete")
        return
    end

    --------------------------------------------------
    -- REDSTONE RESET
    --------------------------------------------------

    status = "RESETTING"
    message = "Resetting printer..."

    machineOff()

    drawStatus()

    sleep(CONFIG.RESET_DURATION)

    machineOn()

    --------------------------------------------------
    -- FINISHED
    --------------------------------------------------

    status = "READY"
    message = "Production completed!"

    remainingTime = 0
    busy = false

    refreshCatalogue()

    drawBooks()
    drawFluids()
    drawStatus()

end

--------------------------------------------------
-- TOUCHSCREEN
--------------------------------------------------

local function handleTouch(x, y)

    if busy then
        return
    end

    --------------------------------------------------
    -- BOOK SELECTION
    --------------------------------------------------

    if y >= UI.bookStart and
        y < UI.bookStart + UI.visibleBooks then

        local index = y - UI.bookStart + 1 + scrollOffset

        local book = catalogue[index]

        if book then

            selectedBook = book.fingerprint

            status = "READY"
            message = "Book selected"

            drawBooks()
            drawStatus()

        end

        return

    end

    --------------------------------------------------
    -- SCROLL
    --------------------------------------------------

    if y == UI.scroll then

        if x < W / 2 then

            scrollOffset = math.max(
                0,
                scrollOffset - 1
            )

        else

            scrollOffset = math.min(
                math.max(
                    0,
                    #catalogue - UI.visibleBooks
                ),
                scrollOffset + 1
            )

        end

        drawBooks()

        return

    end

    --------------------------------------------------
    -- QUANTITY
    --------------------------------------------------

    if y >= UI.quantityTitle and
        y <= UI.quantity then

        local buttonWidth = math.floor(W / 5)

        local quantity = math.floor(
            (x - 1) / buttonWidth
        ) + 1

        if quantity >= 1 and quantity <= 5 then

            selectedQuantity = quantity

            drawQuantity()

        end

        return

    end

    --------------------------------------------------
    -- START PRINTING
    --------------------------------------------------

    if y >= UI.print and y <= UI.print + 1 then

        if not selectedBook then
            showError("Select a book first")
            return
        end

        refreshCatalogue()

        local selected = nil

        for _, book in ipairs(catalogue) do

            if book.fingerprint == selectedBook then
                selected = book
                break
            end

        end

        if not selected then
            showError("Selected book unavailable")
            return
        end

        printBooks(selected, selectedQuantity)

        return

    end

end

--------------------------------------------------
-- INITIAL SCREEN
--------------------------------------------------

refreshCatalogue()

status = "READY"
message = "Select a book"

drawMonitor()

--------------------------------------------------
-- MAIN LOOP
--------------------------------------------------

local refreshTimer = os.startTimer(
    CONFIG.REFRESH_RATE
)

while true do

    local event, p1, p2, p3 = os.pullEvent()

    if event == "monitor_touch" then

        if p1 == peripheralName("monitor") then

            handleTouch(p2, p3)

        end

    elseif event == "monitor_resize" then

        W, H = monitor.getSize()

        drawMonitor()

    elseif event == "timer" and p1 == refreshTimer then

        if not busy then
            drawFluids()
        end

        refreshTimer = os.startTimer(
            CONFIG.REFRESH_RATE
        )

    end

end
