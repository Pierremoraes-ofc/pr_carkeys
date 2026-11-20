local REPO_OWNER = "Pierremoraes-ofc"
local REPO_NAME = "pr_carkeys"

if IsDuplicityVersion() then
    CreateThread(function()
        Wait(5000)
        if Config.VersionCheck then
            if pr_lib and pr_lib.versionCheck then
                pr_lib.versionCheck(("%s/%s"):format(REPO_OWNER, REPO_NAME))
            end
        end
    end)
end
