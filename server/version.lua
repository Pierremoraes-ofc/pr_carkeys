-- server/version.lua
local CURRENT_VERSION = "1.3.0"
local REPO_OWNER      = "Pierremoraes-ofc"
local REPO_NAME       = "pr_carkeys"

-- Só roda no server para não abrir requisição no client
if IsDuplicityVersion() then
    CreateThread(function()
        -- Aguarda o server subir completamente
        Wait(5000)

        local url = ("https://api.github.com/repos/%s/%s/releases/latest"):format(REPO_OWNER, REPO_NAME)

        PerformHttpRequest(url, function(statusCode, response, headers)
            -- FIX 1: Config.debug → Config.Debug (maiúsculo, igual ao resto do resource)
            -- FIX 2: Lang:t() removido — pr_carkeys não usa sistema de Lang
            if statusCode ~= 200 or not response then
                if Config.Debug then
                    Debug("WARNING", ("[Version] Falha ao checar atualizacao | HTTP %s"):format(tostring(statusCode)))
                end
                return
            end

            local data = json.decode(response)
            if not data or not data.tag_name then return end

            local latestVersion = data.tag_name:gsub("^v", "")
            local isUpToDate    = latestVersion == CURRENT_VERSION

            -- FIX 3: lógica corrigida
            -- Desatualizado → SEMPRE mostra (aviso importante)
            -- Atualizado + Debug = false → silencia para console limpo
            if isUpToDate and not Config.Debug then return end

            local status      = isUpToDate and "^2UP TO DATE^0" or "^1OUTDATED^0"
            local versionText = isUpToDate
                and ("VERSION %s"):format(CURRENT_VERSION)
                or  ("VERSION %s -> %s"):format(CURRENT_VERSION, latestVersion)

            local function center(text, width)
                local cleanText = text:gsub("%^%d", "")
                local spaces    = width - string.len(cleanText)
                local left      = math.floor(spaces / 2)
                local right     = spaces - left
                return string.rep(" ", left) .. text .. string.rep(" ", right)
            end

            local box = {
                "^8--------------------------------------------------^0",
                "^8|^0                                                ^8|^0",
                "^8|^0" .. center("^5PR CAR KEYS^0", 48) .. "^8|^0",
                "^8|^0" .. center("^7Vehicle Key System^0", 48) .. "^8|^0",
                "^8|^0                                                ^8|^0",
                "^8|^0" .. center(status, 48) .. "^8|^0",
                "^8|^0" .. center(versionText, 48) .. "^8|^0",
            }

            if not isUpToDate then
                table.insert(box, "^8|^0                                                ^8|^0")
                table.insert(box, "^8|^0" .. center("^3Please update your script!^0", 48) .. "^8|^0")
                table.insert(box, "^8|^0                                                ^8|^0")
                table.insert(box, "^8--------------------------------------------------^0")
                table.insert(box, "" .. center(("^3https://github.com/%s/%s/releases/latest^0"):format(REPO_OWNER, REPO_NAME), 48) .. "")
            else
                table.insert(box, "^8|^0                                                ^8|^0")
                table.insert(box, "^8--------------------------------------------------^0")
            end

            print("\n")
            for _, line in ipairs(box) do
                print(line)
            end
            print("\n")

        end, "GET", "", { ["User-Agent"] = "fivem_bridge" })
    end)
end
