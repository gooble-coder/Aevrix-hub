-- ==========================================
-- AEVRIX KEY VERIFIER
-- DYNAMIC GITHUB LOADER + DEBUG
-- ==========================================

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

-- ==========================================
-- CONFIGURATION
-- ==========================================

local GITHUB_ROOT =
    "https://raw.githubusercontent.com/gooble-coder/Aevrix-hub/main/"

local CONFIG_URL =
    GITHUB_ROOT .. "games/games.json"

local GITHUB_BASE =
    GITHUB_ROOT .. "games/"

local WEBSITE =
    "https://aevrix-loader.auth-tracking.workers.dev/"

local VERIFY_URL =
    WEBSITE .. "v1/verify"

local GREEN = Color3.fromRGB(118, 255, 3)
local YELLOW = Color3.fromRGB(255, 230, 0)
local DARK = Color3.fromRGB(9, 13, 9)
local SURFACE = Color3.fromRGB(19, 27, 18)
local MUTED = Color3.fromRGB(165, 181, 157)
local WHITE = Color3.fromRGB(241, 247, 237)

-- ==========================================
-- DEBUG HELPERS
-- ==========================================

local function debugLog(...)
    print("[AEVRIX DEBUG]", ...)
end

local function debugWarn(...)
    warn("[AEVRIX DEBUG]", ...)
end

debugLog("Starting Aevrix...")
debugLog("Place ID:", game.PlaceId)
debugLog("Game ID:", game.GameId)

-- ==========================================
-- HTTP COMPATIBILITY
-- ==========================================

local function getRequestFunctions()
    local candidates = {}

    local function add(fn)
        if type(fn) == "function" then
            table.insert(candidates, fn)
        end
    end

    add(request)
    add(http_request)

    if type(syn) == "table" then
        add(syn.request)
    end

    if type(http) == "table" then
        add(http.request)
    end

    if type(fluxus) == "table" then
        add(fluxus.request)
    end

    if type(krnl) == "table" then
        add(krnl.request)
    end

    return candidates
end

-- ==========================================
-- DYNAMIC GAME CONFIGURATION
-- ==========================================

local function loadGameConfig()
    local url = CONFIG_URL
        .. "?t=" .. tostring(os.time())

    debugLog("Downloading game configuration...")
    debugLog("Config URL:", url)

    local success, response = pcall(function()
        return game:HttpGet(url)
    end)

    if not success then
        debugWarn("HTTP error:", response)
        return nil, "Could not download games.json"
    end

    if type(response) ~= "string"
        or response == "" then
        return nil, "Empty configuration response"
    end

    debugLog("Configuration downloaded")
    debugLog("Response length:", #response)

    local decoded, config = pcall(function()
        return HttpService:JSONDecode(response)
    end)

    if not decoded or type(config) ~= "table" then
        debugWarn("JSON decoding failed:", config)
        return nil, "Invalid games.json"
    end

    local games = config.games or config

    if type(games) ~= "table" then
        return nil, "Missing games table"
    end

    debugLog("Games found in configuration:")

    for id, entry in pairs(games) do
        if type(entry) == "table" then
            debugLog(
                "ID:", tostring(id),
                "Name:", tostring(entry.name),
                "Script:", tostring(entry.script)
            )
        end
    end

    return games
end

-- ==========================================
-- LOAD CONFIGURATION
-- ==========================================

local SUPPORTED_GAMES, configError =
    loadGameConfig()

if not SUPPORTED_GAMES then
    debugWarn("Config failed:", configError)
    return
end

-- ==========================================
-- GAME DETECTION DEBUG
-- ==========================================

local currentPlaceId = tostring(game.PlaceId)

debugLog("Current Place ID:", currentPlaceId)
debugLog("Config type:", type(SUPPORTED_GAMES))

local gameEntry =
    SUPPORTED_GAMES[currentPlaceId]

debugLog("Game entry type:", type(gameEntry))

if not gameEntry then
    debugWarn("NO MATCH FOUND!")
    debugWarn("Requested Place ID:", currentPlaceId)

    for id, entry in pairs(SUPPORTED_GAMES) do
        debugLog(
            "Available game:",
            tostring(id),
            type(entry) == "table"
                and tostring(entry.name)
                or "Invalid entry"
        )
    end
else
    debugLog("MATCH FOUND!")
    debugLog("Game:", gameEntry.name)
    debugLog("Script:", gameEntry.script)
end

local gameName =
    type(gameEntry) == "table"
    and gameEntry.name
    or nil

-- ==========================================
-- UI HELPERS
-- ==========================================

local function rounded(parent, radius)
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, radius)
    corner.Parent = parent
end

local function stroke(parent, color, transparency)
    local outline = Instance.new("UIStroke")
    outline.Color = color
    outline.Transparency = transparency or 0
    outline.Thickness = 1
    outline.Parent = parent
end

local function label(parent, name, text, size, color)
    local item = Instance.new("TextLabel")
    item.Name = name
    item.BackgroundTransparency = 1
    item.Text = text
    item.TextColor3 = color
    item.TextSize = size
    item.Font = Enum.Font.Gotham
    item.TextWrapped = true
    item.Parent = parent
    return item
end

local function makeButton(parent, name, text, color)
    local button = Instance.new("TextButton")
    button.Name = name
    button.BackgroundColor3 = color
    button.TextColor3 = DARK
    button.Text = text
    button.TextSize = 14
    button.Font = Enum.Font.GothamBold
    button.AutoButtonColor = true
    button.Parent = parent
    rounded(button, 10)
    return button
end

-- ==========================================
-- CREATE SCREEN GUI
-- ==========================================

local oldGui =
    playerGui:FindFirstChild("AevrixKeyVerifier")

if oldGui then
    oldGui:Destroy()
end

local gui = Instance.new("ScreenGui")
gui.Name = "AevrixKeyVerifier"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

-- ==========================================
-- NOTIFICATION SYSTEM
-- ==========================================

local notification = Instance.new("Frame")
notification.Name = "Notification"
notification.AnchorPoint = Vector2.new(1, 1)
notification.Position = UDim2.new(1, 340, 1, -24)
notification.Size = UDim2.fromOffset(310, 94)
notification.BackgroundColor3 = DARK
notification.Visible = false
notification.Parent = gui

rounded(notification, 13)
stroke(notification, YELLOW, 0.35)

local notificationTitle = label(
    notification, "Title", "", 15, YELLOW
)

notificationTitle.Font = Enum.Font.GothamBold
notificationTitle.TextXAlignment = Enum.TextXAlignment.Left
notificationTitle.Position = UDim2.fromOffset(16, 12)
notificationTitle.Size = UDim2.new(1, -32, 0, 24)

local notificationText = label(
    notification, "Message", "", 12, MUTED
)

notificationText.TextXAlignment = Enum.TextXAlignment.Left
notificationText.Position = UDim2.fromOffset(16, 39)
notificationText.Size = UDim2.new(1, -32, 0, 40)

local notificationId = 0

local function notify(titleText, messageText)
    notificationId += 1
    local id = notificationId

    notificationTitle.Text = titleText
    notificationText.Text = messageText
    notification.Visible = true

    notification.Position =
        UDim2.new(1, 340, 1, -24)

    TweenService:Create(
        notification,
        TweenInfo.new(
            0.32,
            Enum.EasingStyle.Quart,
            Enum.EasingDirection.Out
        ),
        {
            Position = UDim2.new(1, -24, 1, -24)
        }
    ):Play()

    task.delay(5, function()
        if notificationId ~= id then
            return
        end

        local tween = TweenService:Create(
            notification,
            TweenInfo.new(0.25),
            {
                Position = UDim2.new(1, 340, 1, -24)
            }
        )

        tween:Play()
        tween.Completed:Wait()

        if notificationId == id then
            notification.Visible = false
        end
    end)
end

-- ==========================================
-- CHECK SUPPORTED GAME
-- ==========================================

if type(gameName) ~= "string" then
    notify(
        "Game Not Supported",
        "Place ID: " .. currentPlaceId
    )

    debugWarn(
        "Game detection failed for:",
        currentPlaceId
    )

    return
end

debugLog("Game detection successful:", gameName)

-- ==========================================
-- BACKGROUND OVERLAY
-- ==========================================

local overlay = Instance.new("Frame")
overlay.Name = "Overlay"
overlay.Size = UDim2.fromScale(1, 1)
overlay.BackgroundColor3 = Color3.new(0, 0, 0)
overlay.BackgroundTransparency = 0.48
overlay.BorderSizePixel = 0
overlay.Parent = gui

-- ==========================================
-- MAIN VERIFIER WINDOW
-- ==========================================

local window = Instance.new("Frame")
window.Name = "VerifierWindow"
window.AnchorPoint = Vector2.new(0.5, 0.5)
window.Position = UDim2.fromScale(0.5, 0.5)
window.Size = UDim2.fromOffset(400, 300)
window.BackgroundColor3 = DARK
window.Parent = gui

rounded(window, 18)
stroke(window, GREEN, 0.7)

local windowScale = Instance.new("UIScale")
windowScale.Scale = 0.92
windowScale.Parent = window

TweenService:Create(
    windowScale,
    TweenInfo.new(0.25, Enum.EasingStyle.Back),
    {Scale = 1}
):Play()

local accent = Instance.new("Frame")
accent.Position = UDim2.fromOffset(24, 23)
accent.Size = UDim2.fromOffset(5, 35)
accent.BackgroundColor3 = GREEN
accent.BorderSizePixel = 0
accent.Parent = window

rounded(accent, 5)

local header = label(
    window, "Header", "AEVRIX", 25, GREEN
)

header.Font = Enum.Font.GothamBold
header.TextXAlignment = Enum.TextXAlignment.Left
header.Position = UDim2.fromOffset(42, 20)
header.Size = UDim2.fromOffset(280, 34)

local subtitle = label(
    window,
    "Subtitle",
    gameName .. "  •  Access Verification",
    12,
    MUTED
)

subtitle.TextXAlignment = Enum.TextXAlignment.Left
subtitle.Position = UDim2.fromOffset(24, 66)
subtitle.Size = UDim2.new(1, -48, 0, 24)

local divider = Instance.new("Frame")
divider.Position = UDim2.fromOffset(24, 104)
divider.Size = UDim2.new(1, -48, 0, 1)
divider.BorderSizePixel = 0
divider.BackgroundColor3 = Color3.fromRGB(45, 60, 40)
divider.Parent = window

local inputLabel = label(
    window,
    "InputLabel",
    "ACCESS KEY",
    11,
    MUTED
)

inputLabel.Font = Enum.Font.GothamBold
inputLabel.TextXAlignment = Enum.TextXAlignment.Left
inputLabel.Position = UDim2.fromOffset(24, 120)
inputLabel.Size = UDim2.new(1, -48, 0, 20)

-- ==========================================
-- KEY INPUT
-- ==========================================

local keyBox = Instance.new("TextBox")
keyBox.Name = "KeyInput"
keyBox.Position = UDim2.fromOffset(24, 148)
keyBox.Size = UDim2.new(1, -48, 0, 46)
keyBox.BackgroundColor3 = SURFACE
keyBox.TextColor3 = WHITE
keyBox.PlaceholderColor3 = MUTED
keyBox.PlaceholderText = "AEVRIX-XXXX..."
keyBox.Text = ""
keyBox.TextSize = 14
keyBox.Font = Enum.Font.Gotham
keyBox.ClearTextOnFocus = false
keyBox.Parent = window

rounded(keyBox, 10)
stroke(keyBox, Color3.fromRGB(55, 73, 48), 0)

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 13)
padding.PaddingRight = UDim.new(0, 13)
padding.Parent = keyBox

-- ==========================================
-- BUTTONS
-- ==========================================

local verifyButton = makeButton(
    window, "VerifyButton", "VERIFY KEY", GREEN
)

verifyButton.Position = UDim2.fromOffset(24, 211)
verifyButton.Size = UDim2.fromOffset(169, 43)

local getKeyButton = makeButton(
    window, "GetKeyButton", "GET KEY", YELLOW
)

getKeyButton.Position = UDim2.fromOffset(207, 211)
getKeyButton.Size = UDim2.fromOffset(169, 43)

local footer = label(
    window,
    "Footer",
    "AEVRIX  •  Secure Access",
    11,
    MUTED
)

footer.Position = UDim2.fromOffset(24, 268)
footer.Size = UDim2.new(1, -48, 0, 20)

-- ==========================================
-- CLOUDFLARE KEY VERIFICATION
-- ==========================================

local function verifyWithCloudflare(key)
    local functions = getRequestFunctions()

    if #functions == 0 then
        return {
            valid = false,
            status = "unsupported_http"
        }
    end

    local body = HttpService:JSONEncode({
        key = key
    })

    for _, sendRequest in ipairs(functions) do
        local success, response = pcall(function()
            return sendRequest({
                Url = VERIFY_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json",
                    ["Accept"] = "application/json"
                },
                Body = body
            })
        end)

        if success and type(response) == "table" then
            local responseBody =
                response.Body or response.body

            if type(responseBody) == "string" then
                local decoded, result = pcall(function()
                    return HttpService:JSONDecode(responseBody)
                end)

                if decoded and type(result) == "table" then
                    debugLog(
                        "Verification status:",
                        result.status
                    )

                    return {
                        valid = result.valid == true,
                        status = result.status or "error",
                        keyType = result.type,
                        expiresAt = result.expires_at
                    }
                end
            end
        end
    end

    return {
        valid = false,
        status = "connection_error"
    }
end

-- ==========================================
-- GITHUB SCRIPT LOADER
-- ==========================================

local scriptLoaded = false
local scriptLoading = false

local function loadGameScript()
    if scriptLoaded or scriptLoading then
        return false, "Already loaded or loading"
    end

    local filename = gameEntry.script

    if type(filename) ~= "string"
        or not filename:match("^[%w_%-]+%.lua$") then
        return false, "Invalid script filename"
    end

    if type(loadstring) ~= "function" then
        return false, "loadstring not supported"
    end

    scriptLoading = true

    local url = GITHUB_BASE .. filename

    debugLog("Loading script:", filename)
    debugLog("Script URL:", url)

    local fetched, source = pcall(function()
        return game:HttpGet(url)
    end)

    if not fetched or type(source) ~= "string"
        or source == "" then
        scriptLoading = false
        debugWarn("Script download failed:", source)
        return false, "Failed to download script"
    end

    debugLog("Script downloaded:", #source, "bytes")

    local compiled, runner = pcall(function()
        return loadstring(source)
    end)

    if not compiled or type(runner) ~= "function" then
        scriptLoading = false
        debugWarn("Compilation failed:", runner)
        return false, "Script compilation failed: "
            .. tostring(runner)
    end

    local success, err = pcall(runner)

    scriptLoading = false

    if not success then
        debugWarn("Execution error:", err)
        return false, tostring(err)
    end

    scriptLoaded = true
    debugLog("Game script executed successfully!")

    return true
end

-- ==========================================
-- VERIFICATION RESULT HANDLER
-- ==========================================

local verified = false
local verifying = false

local function handleVerificationResult(result)
    if verified then
        return
    end

    if type(result) ~= "table" then
        notify(
            "Verification Failed",
            "Invalid server response."
        )
        return
    end

    if result.valid == true then
        verified = true

        verifyButton.Text = "VERIFIED"
        verifyButton.BackgroundColor3 = GREEN
        verifyButton.Active = false
        keyBox.TextEditable = false

        debugLog("Key verified successfully!")

        notify(
            "Key Verified",
            "Your Aevrix access key is valid!"
        )

        verifyButton.Text = "LOADING..."

        task.spawn(function()
            local loaded, loadError = loadGameScript()

            if not gui.Parent then
                return
            end

            if loaded then
                verifyButton.Text = "VERIFIED"

                window.Visible = false
                overlay.Visible = false

                notify(
                    "AEVRIX",
                    "Game script started successfully!"
                )
            else
                verifyButton.Text = "LOAD FAILED"

                debugWarn("Loading error:", loadError)

                notify(
                    "Script Load Failed",
                    tostring(loadError):sub(1, 180)
                )
            end
        end)

    elseif result.status == "expired" then
        notify("Key Expired", "Your key has expired.")

    elseif result.status == "revoked" then
        notify("Key Revoked", "Your key was revoked.")

    elseif result.status == "invalid" then
        notify("Invalid Key", "Please check your key.")

    elseif result.status == "rate_limited" then
        notify(
            "Too Many Attempts",
            "Please wait before trying again."
        )

    elseif result.status == "unsupported_http" then
        notify(
            "HTTP Unsupported",
            "No compatible HTTP request function."
        )

    elseif result.status == "connection_error" then
        notify(
            "Connection Error",
            "Could not reach the verification service."
        )

    else
        notify(
            "Verification Failed",
            "Unable to verify your key."
        )
    end
end

-- ==========================================
-- VERIFY BUTTON
-- ==========================================

verifyButton.MouseButton1Click:Connect(function()
    if verified or verifying then
        return
    end

    local enteredKey =
        keyBox.Text:match("^%s*(.-)%s*$")

    if enteredKey == "" then
        notify(
            "Missing Key",
            "Please enter your access key."
        )
        return
    end

    verifying = true
    verifyButton.Text = "VERIFYING..."

    task.spawn(function()
        local success, result = pcall(function()
            return verifyWithCloudflare(enteredKey)
        end)

        verifying = false

        if not gui.Parent then
            return
        end

        if success then
            handleVerificationResult(result)
        else
            debugWarn("Verification error:", result)

            notify(
                "Connection Error",
                "An unexpected error occurred."
            )
        end

        if not verified then
            verifyButton.Text = "VERIFY KEY"
        end
    end)
end)

-- ==========================================
-- GET KEY BUTTON
-- ==========================================

getKeyButton.MouseButton1Click:Connect(function()
    if type(setclipboard) == "function" then
        local success = pcall(function()
            setclipboard(WEBSITE)
        end)

        if success then
            notify(
                "Link Copied!",
                "Aevrix website copied to clipboard."
            )
            return
        end
    end

    notify(
        "Get Your Key",
        "Visit: " .. WEBSITE
    )
end)

-- ==========================================
-- AEVRIX READY
-- ==========================================

debugLog("Dynamic loader initialized!")
debugLog("Detected game:", gameName)
debugLog("Ready for key verification.")
