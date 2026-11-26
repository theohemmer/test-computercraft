
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
        raw_books = "raw_books",
        available_books = "available_books",
        input_raw_books = "input_raw_books",
        printed_books = "printed_books",
        output_books = "output_books",
        input_book = "input_book",

        fluid_tank = "fluid_tank",
        printer = "printer",

        monitor = "monitor",
        redstone_relay = "redstone_relay"
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

--------------------------------------------------
-- PERIPHERAL NAMES
--------------------------------------------------

local function peripheralName(configName)
    return CONFIG.PERIPHERALS[configName]
end

--------------------------------------------------
-- INITIALIZATION
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
-- REDSTONE CONTROL
--------------------------------------------------

local function machineOn()
    relay.setOutput(CONFIG.REDSTONE_SIDE, true)
end

local function machineOff()
    relay.setOutput(CONFIG.REDSTONE_SIDE, false)
end

-- Always turn ON at startup.
machineOn()

--------------------------------------------------
-- INVENTORY FUNCTIONS
--------------------------------------------------

local function countItems(inventory)

    local total = 0

    for _, item in pairs(inventory.list()) do
        total = total + item.count
    end

    return total
end

local function inventoryEmpty(inventory)
    return countItems(inventory) == 0
end

local function moveItems(source, destination, amount)

    local remaining = amount
    local moved = 0

    local destinationName = peripheralName(
        destination == rawBooks and "raw_books" or
        destination == availableBooks and "available_books" or
        destination == inputRawBooks and "input_raw_books" or
        destination == printedBooks and "printed_books" or
        destination == outputBooks and "output_books" or
        destination == inputBook and "input_book" or
        ""
    )

    if destinationName == "" then
        error("Unknown destination inventory")
    end

    for slot, item in pairs(source.list()) do

        if remaining <= 0 then
            break
        end

        local amountToMove = math.min(
            item.count,
            remaining
        )

        local transferred = source.pushItems(
            destinationName,
            slot,
            amountToMove
        )

        moved = moved + transferred
        remaining = remaining - transferred
    end

    return moved
end

--------------------------------------------------
-- FLUID FUNCTIONS
--------------------------------------------------

local function getFluidAmount(peripheralObject)

    local total = 0
    local tanks = peripheralObject.tanks()

    if not tanks then
        return 0
    end

    for _, tank in pairs(tanks) do

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

    local capacity = CONFIG.FLUID_TANK_CAPACITY_MB

    if capacity <= 0 then
        return 0
    end

    return math.floor(
        getMainFluid() / capacity * 100
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
-- BOOK CATALOGUE
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
                    itemName = detail.name,
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

--------------------------------------------------
-- FIND SELECTED BOOK IN INVENTORY
--------------------------------------------------

local function findBook(fingerprint)

    for slot, item in pairs(availableBooks.list()) do

        local detail = availableBooks.getItemDetail(slot)

        if detail and getFingerprint(detail) == fingerprint then
            return slot, item.count
        end

    end

    return nil, 0
end

--------------------------------------------------
-- MONITOR DRAWING
--------------------------------------------------

local function clearScreen()

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()
end

local function writeAt(x, y, text, fg, bg)

    if y < 1 or y > H then
        return
    end

    text = tostring(text)

    if x < 1 then
        text = text:sub(2 - x)
        x = 1
    end

    if x > W then
        return
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
-- MONITOR LAYOUT
--------------------------------------------------

local UI = {}

local function calculateLayout()

    UI.eta = H
    UI.message = H - 1
    UI.status = H - 2
    UI.print = H - 3

    UI.quantity = H - 4
    UI.quantityTitle = H - 5

    UI.scroll = H - 7

    UI.bookStart = 7

    UI.visibleBooks = math.min(
        CONFIG.VISIBLE_BOOKS,
        UI.scroll - UI.bookStart
    )

    if UI.visibleBooks < 1 then
        error("Monitor resolution too small. Increase MONITOR_SCALE.")
    end

end

calculateLayout()

--------------------------------------------------
-- DRAW MONITOR
--------------------------------------------------

local function drawMonitor()

    W, H = monitor.getSize()

    calculateLayout()

    clearScreen()

    --------------------------------------------------
    -- HEADER
    --------------------------------------------------

    clearLine(1, colors.blue)

    centerText(
        1,
        "BOOK PRINTING STATION",
        colors.white,
        colors.blue
    )

    --------------------------------------------------
    -- FLUID MONITORING
    --------------------------------------------------

    local mainFluid = getMainFluid()
    local printerFluid = getPrinterFluid()
    local percentage = getMainPercentage()

    local mainColor = colors.lime
    local printerColor = colors.lime

    if mainFluid < CONFIG.MIN_MAIN_FLUID_MB then
        mainColor = colors.red
    end

    if printerFluid < CONFIG.MIN_PRINTER_FLUID_MB then
        printerColor = colors.red
    end

    writeAt(2, 3, "MAIN TANK:", colors.white)

    writeAt(
        14, 3,
        percentage .. "% (" ..
        mainFluid .. "/" ..
        CONFIG.FLUID_TANK_CAPACITY_MB .. " mB)",
        mainColor
    )

    writeAt(2, 4, "PRINTER:", colors.white)

    writeAt(
        14, 4,
        printerFluid .. " mB",
        printerColor
    )

    --------------------------------------------------
    -- BOOK CATALOGUE
    --------------------------------------------------

    centerText(6, "AVAILABLE BOOKS", colors.yellow)

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

            writeAt(
                2, y,
                prefix .. label,
                fg, bg
            )

            writeAt(
                W - 8, y,
                "x" .. book.count,
                fg, bg
            )

        end

    end

    --------------------------------------------------
    -- SCROLL CONTROLS
    --------------------------------------------------

    centerText(
        UI.scroll,
        "< PREVIOUS       NEXT >",
        colors.cyan
    )

    --------------------------------------------------
    -- QUANTITY SELECTOR
    --------------------------------------------------

    centerText(
        UI.quantityTitle,
        "QUANTITY",
        colors.yellow
    )

    local buttonWidth = math.floor(W / CONFIG.MAX_BOOKS)

    for i = 1, CONFIG.MAX_BOOKS do

        local x = (i - 1) * buttonWidth + 1

        local fg = colors.white
        local bg = colors.gray

        if selectedQuantity == i then
            fg = colors.black
            bg = colors.green
        end

        writeAt(
            x,
            UI.quantity,
            string.rep(" ", buttonWidth),
            fg,
            bg
        )

        local label = "[" .. i .. "]"

        writeAt(
            x + math.floor((buttonWidth - #label) / 2),
            UI.quantity,
            label,
            fg,
            bg
        )

    end

    --------------------------------------------------
    -- PRINT BUTTON
    --------------------------------------------------

    local printText = "[ START PRINTING ]"

    local printX = math.floor((W - #printText) / 2) + 1

    writeAt(
        printX,
        UI.print,
        printText,
        colors.black,
        colors.lime
    )

    --------------------------------------------------
    -- STATUS
    --------------------------------------------------

    local statusColor = colors.white

    if status == "READY" then
        statusColor = colors.lime
    elseif status == "ERROR" then
        statusColor = colors.red
    elseif status == "PRINTING" then
        statusColor = colors.yellow
    end

    centerText(
        UI.status,
        status,
        statusColor
    )

    centerText(
        UI.message,
        message,
        colors.white
    )

    --------------------------------------------------
    -- ETA
    --------------------------------------------------

    if busy then

        centerText(
            UI.eta,
            "ETA: " .. remainingTime .. "s",
            colors.orange
        )

    else

        centerText(
            UI.eta,
            " ",
            colors.white
        )

    end

    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)

end

--------------------------------------------------
-- FLUID SAFETY
--------------------------------------------------

local function checkFluids()

    local mainAmount = getMainFluid()
    local printerAmount = getPrinterFluid()

    if mainAmount < CONFIG.MIN_MAIN_FLUID_MB then

        return false,
            "Main tank below 10000 mB!"

    end

    if printerAmount < CONFIG.MIN_PRINTER_FLUID_MB then

        return false,
            "Printer below 500 mB!"

    end

    return true

end

--------------------------------------------------
-- ERROR HANDLING
--------------------------------------------------

local function showError(text)

    status = "ERROR"
    message = text

    busy = false
    remainingTime = 0

    drawMonitor()

end

--------------------------------------------------
-- RETURN PREVIOUS TEMPLATE
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

    if moved ~= amount then
        return false
    end

    return true

end

--------------------------------------------------
-- LOAD SELECTED TEMPLATE
--------------------------------------------------

local function loadSelectedTemplate(fingerprint)

    -- Return the previously selected template.

    if not returnPreviousTemplate() then

        return false,
            "Cannot return previous book"

    end

    -- Find the selected template again.
    -- Its slot may have changed.

    local slot = findBook(fingerprint)

    if not slot then

        return false,
            "Selected book unavailable"

    end

    local moved = availableBooks.pushItems(
        peripheralName("input_book"),
        slot,
        1
    )

    if moved ~= 1 then

        return false,
            "Cannot load selected book"

    end

    return true

end

--------------------------------------------------
-- PRINTING PROCESS
--------------------------------------------------

local function printBooks(book, quantity)

    busy = true

    --------------------------------------------------
    -- SAFETY CHECK
    --------------------------------------------------

    status = "CHECKING"
    message = "Checking machine..."

    drawMonitor()

    local fluidsOK, fluidError = checkFluids()

    if not fluidsOK then

        showError(fluidError)
        return

    end

    --------------------------------------------------
    -- CHECK INVENTORIES
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

    drawMonitor()

    local loaded, loadError = loadSelectedTemplate(
        book.fingerprint
    )

    if not loaded then

        showError(loadError)
        return

    end

    --------------------------------------------------
    -- LOAD RAW BOOKS
    --------------------------------------------------

    message = "Loading raw books..."

    drawMonitor()

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
    -- START MACHINE
    --------------------------------------------------

    machineOn()

    status = "PRINTING"
    message = "Printing in progress..."

    local expectedTime =
        quantity * CONFIG.SECONDS_PER_BOOK

    remainingTime = expectedTime

    local startTime = os.clock()

    drawMonitor()

    --------------------------------------------------
    -- WAIT FOR PRINTED BOOKS
    --------------------------------------------------

    while countItems(printedBooks) <
        initialPrinted + quantity do

        local elapsed = os.clock() - startTime

        remainingTime = math.max(
            0,
            math.ceil(expectedTime - elapsed)
        )

        -- Continuously monitor fluids.

        local fluidsOK = checkFluids()

        if not fluidsOK then

            showError("Fluid level too low!")
            return

        end

        drawMonitor()

        sleep(CONFIG.REFRESH_RATE)

    end

    --------------------------------------------------
    -- TRANSFER PRINTED BOOKS
    --------------------------------------------------

    status = "TRANSFERRING"
    message = "Transferring printed books..."

    drawMonitor()

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

    drawMonitor()

    sleep(CONFIG.RESET_DURATION)

    machineOn()

    --------------------------------------------------
    -- PRODUCTION COMPLETED
    --------------------------------------------------

    status = "READY"
    message = "Production completed!"

    remainingTime = 0
    busy = false

    refreshCatalogue()
    drawMonitor()

end

--------------------------------------------------
-- TOUCHSCREEN INPUT
--------------------------------------------------

local function handleTouch(x, y)

    if busy then
        return
    end

    refreshCatalogue()

    --------------------------------------------------
    -- BOOK SELECTION
    --------------------------------------------------

    local firstBookY = UI.bookStart
    local lastBookY = UI.bookStart + UI.visibleBooks - 1

    if y >= firstBookY and y <= lastBookY then

        local index = y - UI.bookStart + 1 + scrollOffset

        local book = catalogue[index]

        if book then

            selectedBook = book.fingerprint

            status = "READY"
            message = "Book selected"

            drawMonitor()

        end

        return

    end

    --------------------------------------------------
    -- SCROLLING
    --------------------------------------------------

    if y == UI.scroll then

        if x < W / 2 then

            scrollOffset = math.max(
                0,
                scrollOffset - 1
            )

        else

            scrollOffset = math.min(
                math.max(0, #catalogue - UI.visibleBooks),
                scrollOffset + 1
            )

        end

        drawMonitor()

        return

    end

    --------------------------------------------------
    -- QUANTITY SELECTION
    --------------------------------------------------

    if y == UI.quantity then

        local buttonWidth = math.floor(
            W / CONFIG.MAX_BOOKS
        )

        local quantity = math.floor(
            (x - 1) / buttonWidth
        ) + 1

        if quantity >= 1 and
            quantity <= CONFIG.MAX_BOOKS then

            selectedQuantity = quantity

            drawMonitor()

        end

        return

    end

    --------------------------------------------------
    -- START PRINTING
    --------------------------------------------------

    if y == UI.print then

        if not selectedBook then

            showError("Select a book first")
            return

        end

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

        printBooks(
            selected,
            selectedQuantity
        )

        return

    end

end

--------------------------------------------------
-- STARTUP DISPLAY
--------------------------------------------------

refreshCatalogue()

status = "READY"
message = "Select a book"

drawMonitor()

--------------------------------------------------
-- MAIN EVENT LOOP
--------------------------------------------------

local refreshTimer = os.startTimer(
    CONFIG.REFRESH_RATE
)

while true do

    local event, p1, p2, p3 = os.pullEvent()

    --------------------------------------------------
    -- MONITOR TOUCH
    --------------------------------------------------

    if event == "monitor_touch" then

        local side = p1
        local x = p2
        local y = p3

        if side == peripheralName("monitor") then

            handleTouch(x, y)

        end

    --------------------------------------------------
    -- MONITOR RESIZE
    --------------------------------------------------

    elseif event == "monitor_resize" then

        W, H = monitor.getSize()

        drawMonitor()

    --------------------------------------------------
    -- AUTOMATIC REFRESH
    --------------------------------------------------

    elseif event == "timer" and p1 == refreshTimer then

        if not busy then
            drawMonitor()
        end

        refreshTimer = os.startTimer(
            CONFIG.REFRESH_RATE
        )

    end

end
