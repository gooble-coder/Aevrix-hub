


local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")



local WEBSITE =
    "https://aevrix-loader.auth-tracking.workers.dev/"

local VERIFY_URL =
    "https://aevrix-loader.auth-tracking.workers.dev/v1/verify"

local GITHUB_BASE =
    "https://raw.githubusercontent.com/gooble-coder/Aevrix-hub/main/games/"

local SUPPORTED_GAMES = {
    [2753915549] = "Blox Fruits - First Sea",
    [4442272183] = "Blox Fruits - Second Sea",
    [7449423635] = "Blox Fruits - Third Sea",
    [74102906764176] = "Greedy Growers"
}

local GAME_SCRIPTS = {
    [2753915549] = "bloxfruits.lua",
    [4442272183] = "bloxfruits.lua",
    [7449423635] = "bloxfruits.lua",
    [74102906764176] = "greedygrowers.lua"
}



local GREEN = Color3.fromRGB(118, 255, 3)
local YELLOW = Color3.fromRGB(255, 230, 0)
local DARK = Color3.fromRGB(9, 13, 9)
local SURFACE = Color3.fromRGB(19, 27, 18)
local MUTED = Color3.fromRGB(165, 181, 157)
local WHITE = Color3.fromRGB(241, 247, 237)



local function getRequestFunctions()
    local candidates = {}

    local function add(candidate)
        if type(candidate) == "function" then
            table.insert(candidates, candidate)
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



local function verifyWithCloudflare(key)
    local requestFunctions = getRequestFunctions()

    if #requestFunctions == 0 then
        return {
            valid = false,
            status = "unsupported_http"
        }
    end

    local body = HttpService:JSONEncode({
        key = key
    })

    for _, sendRequest in ipairs(requestFunctions) do
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
                    return HttpService:JSONDecode(
                        responseBody
                    )
                end)

                if decoded and type(result) == "table" then
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



local notification = Instance.new("Frame")
notification.Name = "Notification"
notification.AnchorPoint = Vector2.new(1, 1)
notification.Position =
    UDim2.new(1, 340, 1, -24)
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
-- GAME DETECTION
-- ==========================================

local gameName = SUPPORTED_GAMES[game.PlaceId]

if not gameName then
    notify(
        "Game Not Supported",
        "Aevrix does not currently support this experience."
    )
    return
end

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
-- VERIFIER WINDOW
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
    TweenInfo.new(
        0.25,
        Enum.EasingStyle.Back
    ),
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
divider.BackgroundColor3 =
    Color3.fromRGB(45, 60, 40)
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
stroke(
    keyBox,
    Color3.fromRGB(55, 73, 48),
    0
)

local padding = Instance.new("UIPadding")
padding.PaddingLeft = UDim.new(0, 13)
padding.PaddingRight = UDim.new(0, 13)
padding.Parent = keyBox

-- ==========================================
-- VERIFY BUTTON
-- ==========================================

local verifyButton = makeButton(
    window,
    "VerifyButton",
    "VERIFY KEY",
    GREEN
)

verifyButton.Position =
    UDim2.fromOffset(24, 211)
verifyButton.Size =
    UDim2.fromOffset(169, 43)

-- ==========================================
-- GET KEY BUTTON
-- ==========================================

local getKeyButton = makeButton(
    window,
    "GetKeyButton",
    "GET KEY",
    YELLOW
)

getKeyButton.Position =
    UDim2.fromOffset(207, 211)
getKeyButton.Size =
    UDim2.fromOffset(169, 43)

local footer = label(
    window,
    "Footer",
    "AEVRIX  •  Secure Access",
    11,
    MUTED
)

footer.Position =
    UDim2.fromOffset(24, 268)
footer.Size =
    UDim2.new(1, -48, 0, 20)

-- ==========================================
-- GITHUB SCRIPT LOADER
-- ==========================================

local scriptLoaded = false
local scriptLoading = false

local function loadGameScript()
    if scriptLoaded or scriptLoading then
        return false
    end

    local filename = GAME_SCRIPTS[game.PlaceId]

    if not filename then
        notify(
            "Unsupported Game",
            "No script is configured for this game."
        )
        return false
    end

    scriptLoading = true

    notify(
        "AEVRIX",
        "Downloading " .. filename .. "..."
    )

    local url = GITHUB_BASE .. filename

    local success, err = pcall(function()
        if type(loadstring) ~= "function" then
            error("loadstring is not available")
        end

        local source = game:HttpGet(url)

        if type(source) ~= "string" or source == "" then
            error("GitHub returned an empty script")
        end

        local execute, compileError = loadstring(source)

        if not execute then
            error(compileError)
        end

        execute()
    end)

    scriptLoading = false

    if not success then
        warn("[AEVRIX] Script load error:", err)

        notify(
            "Load Failed",
            "Unable to run " .. filename
        )

        return false
    end

    scriptLoaded = true

    notify(
        "AEVRIX",
        "Script started successfully!"
    )

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
            "The verification response was invalid."
        )
        return
    end

    if result.valid == true then
        verified = true

        verifyButton.Text = "VERIFIED"
        verifyButton.BackgroundColor3 = GREEN
        verifyButton.Active = false
        keyBox.TextEditable = false

        notify(
            "Key Verified",
            "Your Aevrix access key is valid!"
        )

        -- LOAD MATCHING GITHUB SCRIPT
        task.spawn(function()
            task.wait(0.5)

            local loaded = loadGameScript()

            if loaded then
                window.Visible = false
                overlay.Visible = false
            else
                verifyButton.Text = "LOAD FAILED"
            end
        end)

    elseif result.status == "expired" then
        notify(
            "Key Expired",
            "Your access key has expired."
        )

    elseif result.status == "revoked" then
        notify(
            "Key Revoked",
            "This key has been revoked."
        )

    elseif result.status == "invalid" then
        notify(
            "Invalid Key",
            "Please check your access key."
        )

    elseif result.status == "rate_limited" then
        notify(
            "Too Many Attempts",
            "Please wait before trying again."
        )

    elseif result.status == "unsupported_http" then
        notify(
            "HTTP Unsupported",
            "This environment does not support HTTP requests."
        )

    elseif result.status == "connection_error" then
        notify(
            "Connection Error",
            "Could not reach the verification service."
        )

    else
        notify(
            "Verification Failed",
            "Unable to verify your access key."
        )
    end
end

-- ==========================================
-- VERIFY KEY BUTTON
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
            "Please enter your Aevrix access key."
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
            notify(
                "Connection Error",
                "An unexpected verification error occurred."
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
                "Aevrix key website copied to clipboard."
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
-- AEVRIX LOADER READY
-- ==========================================

print("[AEVRIX] Key verifier initialized")
print("[AEVRIX] Detected game:", gameName)
