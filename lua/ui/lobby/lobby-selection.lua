
--******************************************************************************************************
--** Copyright (c) 2022  Willem 'Jip' Wijnia
--** 
--** Permission is hereby granted, free of charge, to any person obtaining a copy
--** of this software and associated documentation files (the "Software"), to deal
--** in the Software without restriction, including without limitation the rights
--** to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
--** copies of the Software, and to permit persons to whom the Software is
--** furnished to do so, subject to the following conditions:
--** 
--** The above copyright notice and this permission notice shall be included in all
--** copies or substantial portions of the Software.
--** 
--** THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
--** IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
--** FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
--** AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
--** LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
--** OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
--** SOFTWARE.
--******************************************************************************************************

local UIUtil = import("/lua/ui/uiutil.lua")
local LayoutHelpers = import("/lua/maui/layouthelpers.lua")
local Bitmap = import("/lua/maui/bitmap.lua").Bitmap
local Text = import("/lua/maui/text.lua").Text
local ItemList = import("/lua/maui/itemlist.lua").ItemList
local Edit = import("/lua/maui/edit.lua").Edit
local Button = import("/lua/maui/button.lua").Button
local Group = import("/lua/maui/group.lua").Group
local Scrollbar = import("/lua/maui/scrollbar.lua").Scrollbar
local MenuCommon = import("/lua/ui/menus/menucommon.lua")
local MultiLineText = import("/lua/maui/multilinetext.lua").MultiLineText
local MapPreview = import("/lua/ui/controls/mappreview.lua").MapPreview
local Prefs = import("/lua/user/prefs.lua")
local Tooltip = import("/lua/ui/game/tooltip.lua")
local Combo = import("/lua/ui/controls/combo.lua").Combo
local lobby = import("/lua/ui/lobby/lobby.lua")

local LobbySelectionRow = import("/lua/ui/lobby/lobby-selection-row.lua").LobbySelectionRow

local errorDialog = false

local editInFocus = nil

local MapUtil = import("/lua/ui/maputil.lua")
local scenarios = MapUtil.EnumerateSkirmishScenarios()
local gameOptions = {}
gameOptions[1] = import("/lua/ui/lobby/lobby-options.lua").teamOptions
gameOptions[2] = import("/lua/ui/lobby/lobby-options.lua").globalOpts

--- A noop for the purpose of the FAF binary not containing this definition
--
InternalStartSteamDiscoveryService = function() end

local tabData = {
    {
        name = '<LOC gamesel_0006>Map',
        width = 60,
        sortby = 'ScenarioName',
        isGameOption = true,
    },
    {
        name = '<LOC gamesel_0007>Name',
        width = 200,
        sortby = 'GameName',
        isGameOption = false,
    },
    {
        name = '<LOC gamesel_0008>Players',
        width = 120,
        sortby = 'MaxPlayers',
        isGameOption = false,
    },
    {
        name = '<LOC gamesel_0009>custom',
        width = 291,
        sortby = 'Custom',
        options = {
            {
                title = '<LOC gamesel_0010>Allow Observers',
                sortby = 'AllowObservers',
                isGameOption = false,
            },
            {
                title = '<LOC gamesel_0011>Cheats Enabled',
                sortby = 'CheatsEnabled',
                isGameOption = true,
            },
            {
                title = '<LOC gamesel_0012>Civilians',
                sortby = 'CivilianAlliance',
                isGameOption = true,
            },
            {
                title = '<LOC gamesel_0013>Fog Of War',
                sortby = 'FogOfWar',
                isGameOption = true,
            },
            {
                title = '<LOC gamesel_0014>Game Speed',
                sortby = 'GameSpeed',
                isGameOption = true,
            },
            {
                title = '<LOC gamesel_0015>No Rush',
                sortby = 'NoRushOption',
                isGameOption = true,
            },
            {
                title = '<LOC gamesel_0016>Prebuilt Units',
                sortby = 'PrebuiltUnits',
                isGameOption = true,
            },
            {
                title = '<LOC gamesel_0017>Teams Locked',
                sortby = 'TeamLock',
                isGameOption = true,
            },
            {
                title = '<LOC gamesel_0018>Team Spawn',
                sortby = 'TeamSpawn',
                isGameOption = true,
            },
            {
                title = '<LOC gamesel_0019>Timeouts',
                sortby = 'Timeouts',
                isGameOption = true,
            },
            {
                title = '<LOC gamesel_0020>Unit Cap',
                sortby = 'UnitCap',
                isGameOption = true,
            },
            {
                title = '<LOC gamesel_0021>Victory Conditions',
                sortby = 'Victory',
                isGameOption = true,
            },
        },
    }
}

local function IsNameOK(name)
    if name == nil then
        return false
    end

    if name == "" then
        return false
    end

    -- test for name consisting only of whitespace
    local nBegin, nEnd = string.find(name, "%s+")
    if nBegin and (nBegin == 1 and nEnd == string.len(name)) then
        return false
    end

    return true
end

function GetHostString(hostInfo)
    local playerstr = "<LOC GAMSEL_0000>player"
    if hostInfo.PlayerCount > 1 then
        playerstr = "<LOC GAMSEL_0001>players"
    end
    return LOCF("%s (%d %s)", hostInfo.GameName, hostInfo.PlayerCount, playerstr)
end

function CreateEditField(parent, width, maxChars)
    local control = Edit(parent)
    control:SetForegroundColor(UIUtil.fontColor)
    control:SetHighlightForegroundColor(UIUtil.highlightColor)
    control:SetHighlightBackgroundColor("880085EF")
    LayoutHelpers.SetDimensions(control, width, 19)
    control:SetFont(UIUtil.bodyFont, 16)
    if maxChars then control:SetMaxChars(maxChars) end
    return control
end

function CreateUI(over, exitBehavior)
    local discovery = InternalCreateDiscoveryService(DiscoveryService)
    LOG('*** DISC CREATE: ', service)
	local parent = over
	-- panel and title
    local panel = Bitmap(parent, UIUtil.SkinnableFile('/scx_menu/gameselect/panel_bmp.dds'))
    LayoutHelpers.AtCenterIn(panel, parent)

    panel.brackets = UIUtil.CreateDialogBrackets(panel, 42, 32, 40, 30)

    local title = UIUtil.CreateText(panel, "<LOC GAMESEL_0000>LAN/IP Connect", 24)
    LayoutHelpers.AtHorizontalCenterIn(title, panel)
    LayoutHelpers.AtTopIn(title, panel, 26)

    local exitButton = UIUtil.CreateButtonStd(panel, '/scx_menu/small-btn/small', "<LOC _Back>", 14, 0, 0, "UI_Back_MouseDown")
    LayoutHelpers.AtLeftTopIn(exitButton, panel, 15, 645)

    local games = {}
	local serverList = {}

    exitButton.OnClick = function(self)
    	if exitBehavior then
        	exitBehavior()
        end
   		panel:Destroy()
		discovery:Destroy()
    	discovery = false
    end
    exitButton.HandleEvent = function(self, event)
        if event.Type == 'MouseEnter' then
            Tooltip.CreateMouseoverDisplay(self, "mpselect_exit", nil, true)
        elseif event.Type == 'MouseExit' then
            Tooltip.DestroyMouseoverDisplay()
        end
        Button.HandleEvent(self, event)
    end

    import("/lua/ui/uimain.lua").SetEscapeHandler(function() exitButton.OnClick() end)

    local createButton = UIUtil.CreateButtonStd(panel, '/scx_menu/large-no-bracket-btn/large', "<LOC _Create>Create", 18, 2)
    LayoutHelpers.AtRightTopIn(createButton, panel, -17, 645)
    createButton.HandleEvent = function(self, event)
        if event.Type == 'MouseEnter' then
            Tooltip.CreateMouseoverDisplay(self, "mpselect_create", nil, true)
        elseif event.Type == 'MouseExit' then
            Tooltip.DestroyMouseoverDisplay()
        end
        Button.HandleEvent(self, event)
    end

    gameList = Group(panel)
    LayoutHelpers.AtLeftTopIn(gameList, panel, 30, 152)
    gameList.Width:Set(panel.Width() - LayoutHelpers.ScaleNumber(90))
    LayoutHelpers.SetHeight(gameList, 432)
    gameList.top = 0

    local gamesTitle = UIUtil.CreateText(panel, '<LOC GAMESEL_0002>Server List', 18, UIUtil.bodyFont)
    LayoutHelpers.Above(gamesTitle, gameList, 6)

	-- name edit field
    local nameEdit = CreateEditField(panel, 375, 20)
    LayoutHelpers.AtLeftIn(nameEdit, panel, 30)
    LayoutHelpers.AtTopIn(nameEdit, panel, 92)
    nameEdit:SetText(Prefs.GetFromCurrentProfile('NetName') or Prefs.GetFromCurrentProfile('Name'))
    nameEdit:ShowBackground(false)
    nameEdit.HandleEvent = function(self, event)
        if event.Type == 'MouseEnter' then
            Tooltip.CreateMouseoverDisplay(self, "mpselect_name", nil, true)
        elseif event.Type == 'MouseExit' then
            Tooltip.DestroyMouseoverDisplay()
        end
        Edit.HandleEvent(self, event)
    end
    nameEdit.OnCharPressed = function(self, charcode)
        if charcode == UIUtil.VK_TAB then
            return true
        end
        local charlim = self:GetMaxChars()
        if STR_Utf8Len(self:GetText()) >= charlim then
            local sound = Sound({Cue = 'UI_Menu_Error_01', Bank = 'Interface',})
            PlaySound(sound)
        end
    end
    nameEdit.OnEnterPressed = function(self, text)
        nameEdit:AbandonFocus()
        return true
    end
    local nameLabel = UIUtil.CreateText(panel, "<LOC NICKNAME>Nickname", 18, UIUtil.bodyFont)
    LayoutHelpers.Above(nameLabel, nameEdit, 3)

    createButton.OnClick = function(self)
        local name = nameEdit:GetText()
        if IsNameOK(name) then
            Prefs.SetToCurrentProfile('NetName', name)
           	panel:Destroy()
            discovery:Destroy()
            discovery = false
            import("/lua/ui/lobby/gamecreate.lua").CreateUI(name, over, exitBehavior)
        else
            if errorDialog then errorDialog:Destroy() end
            errorDialog = UIUtil.ShowInfoDialog(parent, "<LOC GAMESEL_0003>Please fill in your nickname", "<LOC _OK>")
        end
    end

	-- ip address and port edit
	local ipaddressEdit = CreateEditField(panel, 290)
    LayoutHelpers.AtLeftTopIn(ipaddressEdit, panel, 28, 615)
    ipaddressEdit:SetText(Prefs.GetFromCurrentProfile('last_dc_ipaddress') or "")
    ipaddressEdit:ShowBackground(false)

    local portEdit = CreateEditField(panel, 79, 5)
    LayoutHelpers.RightOf(portEdit, ipaddressEdit, 15)
    portEdit:SetText(Prefs.GetFromCurrentProfile('last_dc_port') or "")
    portEdit:ShowBackground(false)

    ipaddressEdit.OnCharPressed = nameEdit.OnCharPressed
    ipaddressEdit.OnEnterPressed = function(self, text)
        ipaddressEdit:AbandonFocus()
        portEdit:AcquireFocus()
        return true
    end

    portEdit.OnCharPressed = nameEdit.OnCharPressed
    portEdit.OnEnterPressed = function(self, text)
        portEdit:AbandonFocus()
        ipaddressEdit:AcquireFocus()
        return true
    end

    local portLabel = UIUtil.CreateText(panel, "<LOC _Port>", 18, UIUtil.bodyFont)
    LayoutHelpers.Above(portLabel, portEdit, 2)

    local ipaddressLabel = UIUtil.CreateText(panel, "<LOC DIRCON_0001>IP Address/Hostname", 18, UIUtil.bodyFont)
    LayoutHelpers.Above(ipaddressLabel, ipaddressEdit, 2)

    local ipconnectBtn = UIUtil.CreateButtonStd(panel, '/scx_menu/small-btn/small', "<LOC _Connect>Connect", 14)
    Tooltip.AddButtonTooltip(ipconnectBtn, 'mainmenu_quickipconnect')
    LayoutHelpers.RightOf(ipconnectBtn, portEdit, 10)
    LayoutHelpers.AtVerticalCenterIn(ipconnectBtn, portEdit, -10)
    ipconnectBtn.OnClick = function(self, modifiers)
        local ipaddress = ipaddressEdit:GetText()
        local portstr = portEdit:GetText()
        local port = tonumber(portstr)

        if not port or math.floor(port) ~= port or port < 1 or port > 65535 then
            UIUtil.ShowInfoDialog(parent,
                                  LOCF('<LOC DIRCON_0003>Invalid port number: %s.  Must be an integer between 1 and 65535', portstr),
                                  "<LOC _OK>")
        else
            local name = nameEdit:GetText()
            if not IsNameOK(name) then
                if errorDialog then errorDialog:Destroy() end
                errorDialog = UIUtil.ShowInfoDialog(parent, "<LOC GAMESEL_0003>Please fill in your nickname", "<LOC _OK>")
                return
            end

            local valid = ipaddress ~= '' and ValidateIPAddress(ipaddress .. ':' .. port)
            if valid then
                Prefs.SetToCurrentProfile('last_dc_ipaddress', ipaddress)
                Prefs.SetToCurrentProfile('last_dc_port', tostring(port))

                lobby.CreateLobby("UDP", 0, name, nil, nil, over, function() CreateUI(over, exitBehavior) end)
               	panel:Destroy()
               	discovery:Destroy()
            	discovery = false
                lobby.JoinGame(valid, false)
            else
                UIUtil.ShowInfoDialog(parent,
                                      LOC("<LOC DIRCON_0004>Invalid/unknown IP address"),
                                      "<LOC _OK>")
            end
        end
    end

    gameList._tabs = {}
    gameList._sortby = {field = 'wrappedName', ascending = true, isOption = false, customField = 'AllowObservers', customFieldIsOption = false}

    local function CreateTab(data)
        local btn = Bitmap(panel, UIUtil.UIFile('/dialogs/sort_btn/sort_btn_up_m.dds'))

        btn.lcap = Bitmap(btn, UIUtil.UIFile('/dialogs/sort_btn/sort_btn_up_l.dds'))
        btn.lcap.Depth:Set(btn.Depth)
        LayoutHelpers.LeftOf(btn.lcap, btn)

        btn.rcap = Bitmap(btn, UIUtil.UIFile('/dialogs/sort_btn/sort_btn_up_r.dds'))
        btn.rcap.Depth:Set(btn.Depth)
        LayoutHelpers.RightOf(btn.rcap, btn)

        if data.options then
            btn.combo = Combo(btn, 14, 20, nil, nil, "UI_Tab_Click_01", "UI_Tab_Rollover_01")
            LayoutHelpers.SetWidth(btn.combo, 260)
            LayoutHelpers.AtLeftIn(btn.combo, btn, 38)
            LayoutHelpers.AtVerticalCenterIn(btn.combo, btn, -1)
            btn.combo.Depth:Set(function() return btn.Depth() + 20 end)

            local itemArray = {}
            btn.combo.keyMap = {}
            for index, val in data.options do
                itemArray[index] = LOC(val.title)
                btn.combo.keyMap[index] = {field = val.sortby, isOption = val.isGameOption}
            end
            btn.combo:AddItems(itemArray, 1)

            btn.combo.OnClick = function(self, index, text)
                gameList._sortby.customField = self.keyMap[index].field
                gameList._sortby.customFieldIsOption = self.keyMap[index].isOption
                formatData()
            end
        else
            btn.text = UIUtil.CreateText(btn, LOC(data.name), 16, UIUtil.bodyFont)
            btn.text:DisableHitTest()
            LayoutHelpers.AtLeftIn(btn.text, btn, 18)
            LayoutHelpers.AtVerticalCenterIn(btn.text, btn, -1)
        end

        btn.arrow = Bitmap(btn, UIUtil.UIFile('/dialogs/sort_btn/sort-arrow-down_bmp.dds'))
        btn.arrow:DisableHitTest()
        LayoutHelpers.AtLeftIn(btn.arrow, btn.lcap, 4)
        LayoutHelpers.AtVerticalCenterIn(btn.arrow, btn.lcap)
        btn.arrow:Hide()

        LayoutHelpers.SetWidth(btn, data.width)

        btn._checked = false

        return btn
    end

    for index, tabinfo in tabData do
        local i = index
        gameList._tabs[index] = CreateTab(tabinfo)
        gameList._tabs[index].tabinfo = tabinfo
        if index == 1 then
            LayoutHelpers.AtLeftTopIn(gameList._tabs[i], panel, 200, 125)
        else
            LayoutHelpers.RightOf(gameList._tabs[i], gameList._tabs[i-1], 18)
        end
        gameList._tabs[index].Uncheck = function(control)
            control._checked = false
            control:SetTexture(UIUtil.UIFile('/dialogs/sort_btn/sort_btn_up_m.dds'))
            control.lcap:SetTexture(UIUtil.UIFile('/dialogs/sort_btn/sort_btn_up_l.dds'))
            control.rcap:SetTexture(UIUtil.UIFile('/dialogs/sort_btn/sort_btn_up_r.dds'))
            control.arrow:Hide()
        end
        gameList._tabs[index]._sortKey = tabinfo.sortby
        gameList._tabs[index].OnClick = function(control, event)
            control.arrow:Show()
            if control._checked then
                gameList._sortby.ascending = not gameList._sortby.ascending
            end
            for index, tab in gameList._tabs do
                if index ~= i then
                    tab:Uncheck()
                end
            end
            control._checked = true
            if gameList._sortby.ascending then
                control.arrow:SetTexture(UIUtil.UIFile('/dialogs/sort_btn/sort-arrow-down_bmp.dds'))
            else
                control.arrow:SetTexture(UIUtil.UIFile('/dialogs/sort_btn/sort-arrow-up_bmp.dds'))
            end
            gameList._sortby.field = control._sortKey
            formatData()
        end
        gameList._tabs[index].HandleEvent = function(control, event)
            if event.Type == 'MouseEnter' then
                control:SetTexture(UIUtil.UIFile('/dialogs/sort_btn/sort_btn_over_m.dds'))
                control.lcap:SetTexture(UIUtil.UIFile('/dialogs/sort_btn/sort_btn_over_l.dds'))
                control.rcap:SetTexture(UIUtil.UIFile('/dialogs/sort_btn/sort_btn_over_r.dds'))
                if control.text then
                    control.text:SetColor('ff333333')
                end
            elseif event.Type == 'MouseExit' then
                control:SetTexture(UIUtil.UIFile('/dialogs/sort_btn/sort_btn_up_m.dds'))
                control.lcap:SetTexture(UIUtil.UIFile('/dialogs/sort_btn/sort_btn_up_l.dds'))
                control.rcap:SetTexture(UIUtil.UIFile('/dialogs/sort_btn/sort_btn_up_r.dds'))
                if control.text then
                    control.text:SetColor(UIUtil.fontColor)
                end
            elseif event.Type == 'ButtonPress' or event.Type == 'ButtonDClick' then
                control:OnClick()
            end
        end
    end

    gameListObjects = {}

    function CreateRollover(parent)
        local bg = Bitmap(parent, UIUtil.UIFile('/scx_menu/gameselect/map-panel_bmp.dds'))
        bg.Depth:Set(GetFrame(0):GetTopmostDepth() + 1)
        LayoutHelpers.RightOf(bg, parent.preview)
        LayoutHelpers.AtVerticalCenterIn(bg, parent.preview)

        bg.preview = MapPreview(bg)
        LayoutHelpers.AtLeftTopIn(bg.preview, bg, 44, 26)

        bg.mapglow = Bitmap(bg.preview, UIUtil.UIFile('/scx_menu/gameselect/map-panel-glow_bmp.dds'))
        LayoutHelpers.AtLeftTopIn(bg.mapglow, bg, 35, 17)
        bg.mapglow:DisableHitTest()

        if parent.data.ScenarioMap then
            bg.preview:SetTextureFromMap(parent.data.ScenarioMap)
            LayoutHelpers.SetDimensions(bg.preview, 240, 240)
        else
            bg.preview.Width:Set(0)
            bg.preview.Height:Set(0)
        end

        bg.textfields = {}

        bg.textfields.gamename = UIUtil.CreateText(bg, parent.data.GameName, 18, UIUtil.bodyFont)
        LayoutHelpers.AtLeftTopIn(bg.textfields.gamename, bg, 300, 17)

        bg.textfields.hostName = UIUtil.CreateText(bg, LOCF("<LOC gamesel_0000>Host: %s", parent.data.RolloverData.HostedBy), 14, UIUtil.bodyFont)
        LayoutHelpers.Below(bg.textfields.hostName, bg.textfields.gamename)

        bg.textfields.players = UIUtil.CreateText(bg, LOCF("<LOC gamesel_0001>Players: %d / %d", parent.data.PlayerCount, parent.data.MaxPlayers), 14, UIUtil.bodyFont)
        LayoutHelpers.Below(bg.textfields.players, bg.textfields.hostName)

        bg.textfields.mapname = UIUtil.CreateText(bg, LOCF("<LOC gamesel_0002>Map: %s", parent.data.RolloverData.scenario.name), 14, UIUtil.bodyFont)
        LayoutHelpers.Below(bg.textfields.mapname, bg.textfields.players)

        local prevcontrol = bg.textfields.mapname
        for i, v in parent.data.RolloverData.FormattedOptions do
            local index = i
            bg.textfields[index] = UIUtil.CreateText(bg, string.format("%s: %s", v.title, v.value), 14, UIUtil.bodyFont)
            LayoutHelpers.Below(bg.textfields[index], prevcontrol)
            prevcontrol = bg.textfields[index]
        end

        bg.RefreshData = function(self, data)
            if data.ScenarioMap then
                self.preview:SetTextureFromMap(data.ScenarioMap)
                LayoutHelpers.SetDimensions(self.preview, 240, 240)
            else
                self.preview.Width:Set(0)
                self.preview.Height:Set(0)
            end
            self.textfields.gamename:SetText(data.GameName)
            self.textfields.hostName:SetText(LOCF("<LOC gamesel_0003>Host: %s", data.RolloverData.HostedBy))
            self.textfields.players:SetText(LOCF("<LOC gamesel_0004>Players: %d / %d", data.PlayerCount, data.MaxPlayers))
            self.textfields.mapname:SetText(LOCF("<LOC gamesel_0005>Map: %s", data.RolloverData.scenario.name))
            for i, v in data.RolloverData.FormattedOptions do
                if self.textfields[i] then
                    self.textfields[i]:SetText(string.format("%s: %s", v.title, v.value))
                end
            end
        end

        bg:DisableHitTest(true)
        return bg
    end

    if not table.empty(gameListObjects) then
        for i, v in gameListObjects do
            v:Destroy()
        end
    end
    gameListObjects = {}
    local function CreateElement(index)
        gameListObjects[index] = Group(gameList)
        gameListObjects[index].Depth:Set(function() return gameList.Depth() + 10 end)

        gameListObjects[index].bg = Bitmap(gameListObjects[index], UIUtil.UIFile('/scx_menu/gameselect/slot_bmp.dds'))
        LayoutHelpers.AtLeftTopIn(gameListObjects[index].bg, gameListObjects[index], 235)
        gameListObjects[index].bg.Depth:Set(gameListObjects[index].Depth)

        gameListObjects[index].mapbg = Bitmap(gameListObjects[index], UIUtil.UIFile('/scx_menu/gameselect/map-slot_bmp.dds'))
        LayoutHelpers.AtLeftTopIn(gameListObjects[index].mapbg, gameListObjects[index], 163)
        gameListObjects[index].mapbg.Depth:Set(gameListObjects[index].Depth)

        gameListObjects[index].Width:Set(gameList.Width)
        gameListObjects[index].Height:Set(gameListObjects[index].bg.Height)

        gameListObjects[index].joinBtn = Button(gameListObjects[index],
            UIUtil.UIFile('/scx_menu/small-short-btn/small-btn_up.dds'),
            UIUtil.UIFile('/scx_menu/small-short-btn/small-btn_down.dds'),
            UIUtil.UIFile('/scx_menu/small-short-btn/small-btn_over.dds'),
            UIUtil.UIFile('/scx_menu/small-short-btn/small-btn_dis.dds'))
        gameListObjects[index].joinBtn.label = UIUtil.CreateText(gameListObjects[index].joinBtn, LOC("<LOC _Join>"), 14, UIUtil.bodyFont)
        LayoutHelpers.AtCenterIn(gameListObjects[index].joinBtn.label, gameListObjects[index].joinBtn)
        gameListObjects[index].joinBtn.label:DisableHitTest()
        LayoutHelpers.AtLeftTopIn(gameListObjects[index].joinBtn, gameListObjects[index], -5, -5)
        gameListObjects[index].joinBtn.OnClick = function(self, modifiers)
    	    if errorDialog then errorDialog:Destroy() end
            local name = nameEdit:GetText()
            if not IsNameOK(name) then
                errorDialog = UIUtil.ShowInfoDialog(parent, "<LOC GAMESEL_0003>Please fill in your nickname", "<LOC _OK>")
                return
            end

    		errorDialog = UIUtil.ShowInfoDialog(panel, "<LOC GAMESEL_0012>Attempting to Join")
            Prefs.SetToCurrentProfile('NetName', name)
            local hostInfo = games[self.GameID]
            lobby.CreateLobby(hostInfo.Protocol, 0, name, nil, nil, over, function() CreateUI(over, exitBehavior) end)
            panel:Destroy()
            discovery:Destroy()
            discovery = false
            --LOG('Joining ', repr(hostInfo))
            lobby.JoinGame(hostInfo.Address, false)
        end

        gameListObjects[index].obsBtn = Button(gameListObjects[index],
            UIUtil.UIFile('/scx_menu/small-short-btn/small-btn_up.dds'),
            UIUtil.UIFile('/scx_menu/small-short-btn/small-btn_down.dds'),
            UIUtil.UIFile('/scx_menu/small-short-btn/small-btn_over.dds'),
            UIUtil.UIFile('/scx_menu/small-short-btn/small-btn_dis.dds'))
        gameListObjects[index].obsBtn.label = UIUtil.CreateText(gameListObjects[index].obsBtn, LOC("<LOC _Observe>"), 14, UIUtil.bodyFont)
        LayoutHelpers.AtCenterIn(gameListObjects[index].obsBtn.label, gameListObjects[index].obsBtn)
        gameListObjects[index].obsBtn.label:DisableHitTest()
        LayoutHelpers.Below(gameListObjects[index].obsBtn, gameListObjects[index].joinBtn, -15)
        gameListObjects[index].obsBtn.OnClick = function(self, modifiers)
    	    if errorDialog then errorDialog:Destroy() end
            local name = nameEdit:GetText()
            if not IsNameOK(name) then
                errorDialog = UIUtil.ShowInfoDialog(parent, "<LOC GAMESEL_0003>Please fill in your nickname", "<LOC _OK>")
                return
            end
    		errorDialog = UIUtil.ShowInfoDialog(panel, "<LOC GAMESEL_0012>Attempting to Join")
            Prefs.SetToCurrentProfile('NetName', name)
            local hostInfo = games[self.GameID]
            lobby.CreateLobby(hostInfo.Protocol, 0, name, nil, nil, over, function() CreateUI(over, exitBehavior) end)
            panel:Destroy()
            discovery:Destroy()
            discovery = false
            --LOG('Joining ', repr(hostInfo))
            lobby.JoinGame(hostInfo.Address, true)
        end

        gameListObjects[index].preview = MapPreview(gameListObjects[index])
        LayoutHelpers.SetDimensions(gameListObjects[index].preview, 58, 58)
        LayoutHelpers.AtHorizontalCenterIn(gameListObjects[index].preview, gameList._tabs[1])
        LayoutHelpers.AtVerticalCenterIn(gameListObjects[index].preview, gameListObjects[index])
        gameListObjects[index].preview:DisableHitTest()

        gameListObjects[index].mapglow = Bitmap(gameListObjects[index].preview, UIUtil.UIFile('/scx_menu/gameselect/map-panel-glow_bmp.dds'))

        LayoutHelpers.FillParentFixedBorder(gameListObjects[index].mapglow, gameListObjects[index].preview, -3)
        gameListObjects[index].mapglow:DisableHitTest()

        gameListObjects[index].nopreview = UIUtil.CreateText(gameListObjects[index], '?', 60, UIUtil.bodyFont)
        LayoutHelpers.AtCenterIn(gameListObjects[index].nopreview, gameListObjects[index].preview)
        gameListObjects[index].nopreview:DisableHitTest()

        gameListObjects[index].name1 = UIUtil.CreateText(gameListObjects[index], '', 16)
        LayoutHelpers.AtLeftIn(gameListObjects[index].name1, gameList._tabs[2])
        LayoutHelpers.AtVerticalCenterIn(gameListObjects[index].name1, gameListObjects[index])
        gameListObjects[index].name1:DisableHitTest()

        gameListObjects[index].name2 = UIUtil.CreateText(gameListObjects[index], '', 16)
        LayoutHelpers.Below(gameListObjects[index].name2, gameListObjects[index].name1)
        LayoutHelpers.AtLeftIn(gameListObjects[index].name2, gameList._tabs[2])
        gameListObjects[index].name2:DisableHitTest()

        gameListObjects[index].players = UIUtil.CreateText(gameListObjects[index], '', 16)
        LayoutHelpers.AtHorizontalCenterIn(gameListObjects[index].players, gameList._tabs[3])
        LayoutHelpers.AtVerticalCenterIn(gameListObjects[index].players, gameListObjects[index])
        gameListObjects[index].players:DisableHitTest()

        gameListObjects[index].custom = UIUtil.CreateText(gameListObjects[index], 'custom', 16)
        LayoutHelpers.AtLeftIn(gameListObjects[index].custom, gameList._tabs[4])
        LayoutHelpers.AtVerticalCenterIn(gameListObjects[index].custom, gameListObjects[index])
        gameListObjects[index].custom:DisableHitTest()

        gameListObjects[index].roGroup = Group(gameListObjects[index])
        LayoutHelpers.FillParent(gameListObjects[index].roGroup, gameListObjects[index].mapbg)
        gameListObjects[index].roGroup.HandleEvent = function(self, event)
            if event.Type == 'MouseEnter' then
                if not gameListObjects[index].rollover then
                    gameListObjects[index].rollover = CreateRollover(gameListObjects[index])
                end
            elseif event.Type == 'MouseExit' then
                if gameListObjects[index].rollover then
                    gameListObjects[index].rollover:Destroy()
                    gameListObjects[index].rollover = false
                end
            end
        end
    end

    local formattedData = {}

    CreateElement(1)
    LayoutHelpers.AtLeftTopIn(gameListObjects[1], gameList, 0, 10)

    local index = 2
    while gameListObjects[table.getsize(gameListObjects)].Bottom() + gameListObjects[1].Height() < gameList.Bottom() do
        CreateElement(index)
        LayoutHelpers.Below(gameListObjects[index], gameListObjects[index-1], 5)
        index = index + 1
    end

    local numLines = function() return table.getsize(gameListObjects) end

    local function DataSize()
        return table.getsize(formattedData)
    end

    -- called when the scrollbar for the control requires data to size itself
    -- GetScrollValues must return 4 values in this order:
    -- rangeMin, rangeMax, visibleMin, visibleMax
    -- aixs can be "Vert" or "Horz"
    gameList.GetScrollValues = function(control, axis)
        local size = DataSize()
        --LOG(size, ":", self.top, ":", math.min(gameList.top + numLines(), size))
        return 0, size, gameList.top, math.min(gameList.top + numLines(), size)
    end

    -- called when the scrollbar wants to scroll a specific number of lines (negative indicates scroll up)
    gameList.ScrollLines = function(control, axis, delta)
        control:ScrollSetTop(axis, gameList.top + math.floor(delta))
    end

    -- called when the scrollbar wants to scroll a specific number of pages (negative indicates scroll up)
    gameList.ScrollPages = function(control, axis, delta)
        control:ScrollSetTop(axis, gameList.top + math.floor(delta) * numLines())
    end

    -- called when the scrollbar wants to set a new visible top line
    gameList.ScrollSetTop = function(control, axis, top)
        top = math.floor(top)
        if top == control.top then return end
        local size = DataSize()
        control.top = math.max(math.min(size - numLines() , top), 0)
        control:CalcVisible()
    end

    -- called to determine if the control is scrollable on a particular access. Must return true or false.
    gameList.IsScrollable = function(control, axis)
        return true
    end
    -- determines what controls should be visible or not
    gameList.CalcVisible = function(control)
        local function SetTextLine(line, data, lineID, index)
            if data.wrappedName[2] then
                line.name1:SetText(data.wrappedName[1])
                line.name2:SetText(data.wrappedName[2])
                LayoutHelpers.AtTopIn(line.name1, line, 10)
            else
                line.name1:SetText(data.wrappedName[1])
                line.name2:SetText('')
                LayoutHelpers.AtVerticalCenterIn(line.name1, line)
            end
            line.roGroup:Show()
            line.data = data
            if line.rollover then
                line.rollover:RefreshData(line.data)
            end
            line.joinBtn:Show()
            line.obsBtn:Show()
            line.bg:Show()
            line.mapbg:Show()
            line.joinBtn.GameID = data.GameIndex
            line.obsBtn.GameID = data.GameIndex
            line.custom:SetText(data.Custom)
            if data.AllowObservers then
                line.obsBtn:Show()
                LayoutHelpers.AtTopIn(line.joinBtn, line, -3)
            else
                line.obsBtn:Hide()
                LayoutHelpers.AtVerticalCenterIn(line.joinBtn, line)
            end
            if data.ScenarioMap then
                line.players:SetText(string.format('%d / %d', data.PlayerCount, data.MaxPlayers))
                if DiskGetFileInfo(data.ScenarioMap) then
                    line.preview:SetTextureFromMap(data.ScenarioMap)
                    line.preview:Show()
                    line.nopreview:Hide()
                else
                    line.preview:Hide()
                    line.nopreview:Show()
                end
            else
                local playerStr = LOC('<LOC _Player>Player')
                if data.PlayerCount > 1 then
                    playerStr = LOC('<LOC _Players>Players')
                end
                line.players:SetText(string.format('%d %s', data.PlayerCount, playerStr))
                line.preview:Hide()
                line.nopreview:Show()
            end
        end
        for i, v in gameListObjects do
            if formattedData[i + control.top] then
                SetTextLine(v, formattedData[i + control.top], i + control.top, i)
            else
                v.name1:SetText('')
                v.name2:SetText('')
                v.joinBtn:Hide()
                v.obsBtn:Hide()
                v.roGroup:Hide()
                v.preview:Hide()
                v.players:SetText('')
                v.custom:SetText('')
                v.nopreview:Hide()
                v.bg:Hide()
                v.mapbg:Hide()
            end
        end
    end
    gameList:CalcVisible()

    gameList.HandleEvent = function(control, event)
        if event.Type == 'WheelRotation' then
            local lines = 1
            if event.WheelRotation > 0 then
                lines = -1
            end
            control:ScrollLines(nil, lines)
        end
    end

    UIUtil.CreateVertScrollbarFor(gameList)

    function formatData()
        formattedData = {}
        for i, gameData in games do
            if gameData.ProductCode == nil or gameData.ProductCode ~= import("/lua/productcode.lua").productCode then continue end
            gameData.wrappedName = import("/lua/maui/text.lua").WrapText(gameData.GameName,
                gameList._tabs[2].Right() - gameList._tabs[2].Left(),
                function(curText) return gameListObjects[1].name1:GetStringAdvance(curText) end)

            for i, v in scenarios do
                if v.file == string.lower(gameData.Options.ScenarioFile) then
                    gameData.scenario = v
                    gameData.MaxPlayers = table.getsize(v.Configurations.standard.teams[1].armies)
                    break
                end
            end

            if not gameData.scenario then
                gameData.scenario = {name = 'Unknown Map'}
                gameData.MaxPlayers = 0
            end

            local custom = ''
            gameData.FormattedOptions = {}

            for i, v in gameOptions do
                for index, option in v do
                    for valIndex, value in option.values do
                        if option.key == gameList._sortby.customField and value.key == gameData.Options[gameList._sortby.customField] then
                            custom = LOC(value.text)
                        end
                        if value.key == gameData.Options[option.key] then
                            gameData.FormattedOptions[option.key] = {title = LOC(option.label), value = LOC(value.text)}
                        end
                    end
                end
            end
            if not gameList._sortby.customFieldIsOption then
                if type(gameData.Options[gameList._sortby.customField]) == 'string' then
                    custom = gameData.Options[gameList._sortby.customField]
                else
                    if gameData.Options[gameList._sortby.customField] then
                        custom = LOC("<LOC _Yes>")
                    else
                        custom = LOC("<LOC _No>")
                    end
                end
            end

            table.insert(formattedData, {
                PlayerCount = gameData.PlayerCount,
                GameName = gameData.GameName,
                wrappedName = gameData.wrappedName,
                MaxPlayers = gameData.MaxPlayers,
                AllowObservers = gameData.Options.AllowObservers,
                ScenarioMap = gameData.scenario.map,
                ScenarioName = gameData.scenario.name or '',
                Custom = custom,
                RolloverData = gameData,
                GameIndex = i,
            })
        end
        function sortFunc(a, b)
            if gameList._sortby.ascending then
                return a[gameList._sortby.field] > b[gameList._sortby.field]
            else
                return a[gameList._sortby.field] < b[gameList._sortby.field]
            end
        end
        table.sort(formattedData, sortFunc)
        --LOG(repr(formattedData))
        gameList:CalcVisible()
    end

-- discovery behaviors
    discovery.RemoveGame = function(self,index)
        games[index+1] = nil
        --LOG(repr(games))
        formatData()
    end

    discovery.GameFound = function(self,index,gameConfig)
        for i, v in games do
            if v.Address == gameConfig.Address and v.Hostname == gameConfig.Hostname then
                v = nil
            end
        end
        games[index+1] = gameConfig
        --LOG(repr(games))
        formatData()
    end

    discovery.GameUpdated = function(self,index,gameConfig)
        games[index+1] = gameConfig
        --LOG(repr(games))
        formatData()
    end

    ForkThread(function()
        gameList._tabs[2]:OnClick()
    end)
end

---@class UILobbySelection : Group
---@field LobbyDiscoveryService UILobbyDiscoveryService
---@field OnDestroyCallbacks table<string, fun()>
---@field OnExitCallbacks table<string, fun()>
---@field DebugUI Control
---@field Panel Bitmap
---@field PanelBrackets Group
---@field PanelTitle Text
---@field ButtonExit Button
---@field ButtonConnect Button
---@field ButtonCreate Button
---@field EditName Edit
---@field LobbySelectionRows UILobbySelectionRow[]
---@field DialogError Control
---@field EditAddress Edit
---@field EditPort Edit
---@field TextAddress Text
---@field TextPort Text
LobbySelection = Class(Group) {

    LobbyDiscoveryService = false,

    Games = { },
    GamesSorted = { },

    OnExitCallbacks = { },
    OnDestroyCallbacks = { },

    ---@param self UILobbySelection
    ---@param parent Control
    __init = function(self, parent)
        self:Debug(string.format("__init()"))

        Group.__init(self, parent, 'UILobbySelection')
        LayoutHelpers.FillParent(self, parent)

        -- can help us understand where various elements are
        self.DebugUI = Group(self)
        LayoutHelpers.FillParent(self.DebugUI, self)

        self.Panel = UIUtil.CreateBitmap(self, '/scx_menu/gameselect/panel_bmp.dds')
        LayoutHelpers.AtCenterIn(self.Panel, self)

        self.PanelBrackets = UIUtil.CreateDialogBrackets(self.Panel, 42, 32, 40, 30)

        self.PanelTitle = UIUtil.CreateText(self, "<LOC GAMESEL_0000>LAN/IP Connect", 24)
        LayoutHelpers.AtHorizontalCenterIn(self.PanelTitle, self.Panel)
        LayoutHelpers.AtTopIn(self.PanelTitle, self.Panel, 26)

        self.ButtonExit = UIUtil.CreateButtonStd(self, '/scx_menu/small-btn/small', "<LOC _Back>", 14, 0, 0, "UI_Back_MouseDown")
        LayoutHelpers.AtLeftTopIn(self.ButtonExit, self.Panel, 15, 645)
        LayoutHelpers.DepthOverParent(self.ButtonExit, self.Panel)

        self.ButtonCreate = UIUtil.CreateButtonStd(self, '/scx_menu/large-no-bracket-btn/large', "<LOC _Create>Create", 18, 2)
        LayoutHelpers.AtRightTopIn(self.ButtonCreate, self.Panel, -17, 645)
        LayoutHelpers.DepthOverParent(self.ButtonCreate, self.Panel)

        self.EditName = CreateEditField(self, 375, 20)
        LayoutHelpers.AtLeftIn(self.EditName, self.Panel, 30)
        LayoutHelpers.AtTopIn(self.EditName, self.Panel, 92)
        LayoutHelpers.DepthOverParent(self.EditName, self.Panel)

        self.ContentArea = Group(self.Panel)
        LayoutHelpers.AtLeftBottomIn(self.ContentArea, self.Panel, 24, 150)
        LayoutHelpers.AtRightTopIn(self.ContentArea, self.Panel, 28, 150)
        self.ContentArea:DisableHitTest()

        self.DebugContentArea = UIUtil.CreateBitmapColor(self.DebugUI, '44ffffff')
        LayoutHelpers.FillParent(self.DebugContentArea, self.ContentArea)

        -- ip address and port edit
        self.EditAddress = CreateEditField(self.Panel, 290)
        self.EditAddress:ShowBackground(false)
        LayoutHelpers.AtLeftTopIn(self.EditAddress, self.Panel, 28, 615)

        self.TextAddress = UIUtil.CreateText(self.Panel, "<LOC DIRCON_0001>IP Address/Hostname", 18, UIUtil.bodyFont)
        LayoutHelpers.Above(self.TextAddress, self.EditAddress, 2)

        self.EditPort = CreateEditField(self.Panel, 79, 5)
        self.EditPort:ShowBackground(false)
        LayoutHelpers.RightOf(self.EditPort, self.EditAddress, 15)

        self.TextPort = UIUtil.CreateText(self.Panel, "<LOC _Port>", 18, UIUtil.bodyFont)
        LayoutHelpers.Above(self.TextPort, self.EditPort, 2)

        self.ButtonConnect = UIUtil.CreateButtonStd(self.Panel, '/scx_menu/small-btn/small', "<LOC _Connect>Connect", 14)
        LayoutHelpers.RightOf(self.ButtonConnect, self.EditPort, 10)
        LayoutHelpers.AtVerticalCenterIn(self.ButtonConnect, self.EditPort, -10)
        Tooltip.AddButtonTooltip(self.ButtonConnect, 'mainmenu_quickipconnect')

        self.LobbySelectionRows = { }
        for k = 0, 4 do
            local lobbySelectionRow = LobbySelectionRow(self.ContentArea) --[[@as UILobbySelectionRow]]
            lobbySelectionRow.Height:Set(function() return 0.19 * self.ContentArea.Height() end)
            lobbySelectionRow.Width:Set(self.ContentArea.Width)
            LayoutHelpers.AtLeftTopIn(lobbySelectionRow, self.ContentArea, 0, 8 + 84 * k)

            lobbySelectionRow:AddOnJoinGameCallback(
                function (gameConfig)
                    reprsl(gameConfig)
                    self:JoinLobby(gameConfig.Address)
                end, 'JoinLobby'
            )

            self.LobbySelectionRows[k + 1] = lobbySelectionRow
        end
    end,

    ---@param self UILobbySelection
    ---@param parent Control
    __post_init = function(self, parent)
        self:Debug(string.format("__post_init()"))

        -- do not let the debug UI interfere with the usual UI
        self.DebugUI.Show = function(debugUI)
            if self.Debugging then
                Group.Show(debugUI)
            else
                Group.Hide(debugUI)
            end
        end

        self.DebugUI:DisableHitTest(true)
        if not self.Debugging then
            self.DebugUI:Hide()
        end

        -- escape handler event
        import("/lua/ui/uimain.lua").SetEscapeHandler(
            function()
                self.ButtonExit.OnClick()
            end
        )

        self.ButtonExit.OnClick = function(button)
            self:Debug(string.format("ButtonExit()"))

            for name, callback in self.OnExitCallbacks do
                local ok, msg = pcall(callback)
                if not ok then
                    self:Warn(string.format("Callback '%s' for 'ButtonExit' failed: \r\n %s", name, msg))
                end
            end

            self:Destroy()
        end

        self.ButtonConnect.OnClick = function(button)
            self:Debug(string.format("ButtonExit()"))
            local address = self.EditAddress:GetText()
            local port = self.EditPort:GetText()

            self:JoinLobby(string.format("%s:%s", tostring(address), (port)))
        end

        self.ButtonExit.HandleEvent = function(button, event)
            if event.Type == 'MouseEnter' then
                Tooltip.CreateMouseoverDisplay(button, "mpselect_exit", nil, true)
            elseif event.Type == 'MouseExit' then
                Tooltip.DestroyMouseoverDisplay()
            end
            Button.HandleEvent(button, event)
        end

        self.ButtonCreate.OnClick = function(button)
            local name = self.EditName:GetText()
            if IsNameOK(name) then
                Prefs.SetToCurrentProfile('NetName', name)
                if not self.DialogCreate then
                    self.DialogCreate = import("/lua/ui/lobby/lobby-creation-dialog.lua").CreateLobbyCreationDialog(self)
                    self.DialogCreate:AddOnCancelCallback(
                        function()
                            self.DialogCreate:Hide()
                        end,
                        'OnCancelHide'
                    )

                    self.DialogCreate:AddOnAcceptCallback(
                        function (name, port)
                            self:CreateLobby(name, port)
                            self:Destroy()
                        end, 'OnAcceptCreate'
                    )
                end

                self.DialogCreate:Show()
            else
                if self.DialogError then
                    self.DialogError:Destroy()
                end
                self.DialogError = UIUtil.ShowInfoDialog(parent, "<LOC GAMESEL_0003>Please fill in your nickname", "<LOC _OK>")
            end
        end

        self.ButtonCreate.HandleEvent = function(button, event)
            if event.Type == 'MouseEnter' then
                Tooltip.CreateMouseoverDisplay(button, "mpselect_create", nil, true)
            elseif event.Type == 'MouseExit' then
                Tooltip.DestroyMouseoverDisplay()
            end
            Button.HandleEvent(button, event)
        end

        self.EditName:SetText(Prefs.GetFromCurrentProfile('NetName') or Prefs.GetFromCurrentProfile('Name'))
        self.EditName:ShowBackground(false)
        self.EditName.HandleEvent = function(edit, event)
            if event.Type == 'MouseEnter' then
                Tooltip.CreateMouseoverDisplay(edit, "mpselect_name", nil, true)
            elseif event.Type == 'MouseExit' then
                Tooltip.DestroyMouseoverDisplay()
            end
            Edit.HandleEvent(edit, event)
        end

        self.EditName.OnCharPressed = function(edit, charcode)
            if charcode == UIUtil.VK_TAB then
                return true
            end
            local charlim = edit:GetMaxChars()
            if STR_Utf8Len(edit:GetText()) >= charlim then
                local sound = Sound({Cue = 'UI_Menu_Error_01', Bank = 'Interface',})
                PlaySound(sound)
            end
        end

        self.EditName.OnEnterPressed = function(edit, text)
            edit:AbandonFocus()
            return true
        end

        self.EditAddress:SetText(Prefs.GetFromCurrentProfile('last_dc_ipaddress') or "")
        self.EditAddress.OnCharPressed = self.EditName.OnCharPressed
        self.EditAddress.OnEnterPressed = function(edit, text)
            self.EditAddress:AbandonFocus()
            self.EditPort:AcquireFocus()
            return true
        end

        self.EditPort:SetText(Prefs.GetFromCurrentProfile('last_dc_port') or "")
        self.EditPort.OnCharPressed = self.EditName.OnCharPressed
        self.EditPort.OnEnterPressed = function(edit, text)
            self.EditPort:AbandonFocus()
            self.EditAddress:AcquireFocus()
            return true
        end

        self:SortGames()
        self:PopulateRows()
    end,

    SetupDiscoveryService = function(self)
        self.DiscoveryService = import("/lua/ui/lobby/lobby-discovery.lua").CreateDiscoveryService() --[[@as UILobbyDiscoveryService]]
        self:AddOnDestroyCallback(
            function()
                self.DiscoveryService:Destroy()
            end, 
            'DestroyDiscovery'
        )

        self.DiscoveryService:AddOnGameFoundCallback(
            ---@param index number
            ---@param configuration UILobbydDiscoveryInfo
            function (index, configuration)
                self.Games[index+1] = configuration
                self:SortGames()
                self:PopulateRows()
            end, 'LobbySelection'
        )

        self.DiscoveryService:AddOnGameUpdatedCallback(
            ---@param index number
            ---@param configuration UILobbydDiscoveryInfo
            function (index, configuration)
                self.Games[index + 1] = configuration
                self:SortGames()
                self:PopulateRows()
            end, 'LobbySelection'
        )

        self.DiscoveryService:AddOnRemoveGameCallback(
            ---@param index number
            function (index)
                self.Games[index + 1] = nil
                self:SortGames()
                self:PopulateRows()
            end, 'LobbySelection'
        )
    end,

    ---@param self UILobbySelection
    Destroy = function(self)
        self:Debug(string.format("Destroy()"))

        for name, callback in self.OnDestroyCallbacks do
            local ok, msg = pcall(callback)
            if not ok then
                self:Warn(string.format("Callback '%s' for 'RemoveGame' failed: \r\n %s", name, msg))
            end
        end

        Group.Destroy(self)
    end,

    ---@param self UILobbySelection
    SortGames = function(self)
        for k, v in self.GamesSorted do
            self.GamesSorted[k] = nil
        end

        local head = 1
        for k, config in self.Games do
            if not config then
                continue
            end

            self.GamesSorted[head] = config
            head = head + 1
        end
    end,

    ---@param self UILobbySelection
    PopulateRows = function(self)

        local gameCount = table.getn(self.GamesSorted)
        local rowCount = table.getn(self.LobbySelectionRows)

        for k = 1, gameCount do
            local lobbySelectionRow = self.LobbySelectionRows[k]
            if lobbySelectionRow then
                lobbySelectionRow:Populate(self.GamesSorted[k])
            end
        end

        for k = gameCount + 1, rowCount do
            local lobbySelectionRow = self.LobbySelectionRows[k]
            if lobbySelectionRow then
                lobbySelectionRow:Populate(nil)
            end
        end
    end,

    CreateErrorDialog = function(self, message)
        if self.DialogError then
            self.DialogError:Destroy()
        end

        self.DialogError = UIUtil.ShowInfoDialog(self, message, "<LOC _OK>")
    end,

    ---@param self UILobbySelection
    ---@param gameName string
    ---@param gamePort string
    CreateLobby = function(self, gameName, gamePort)

        -- validate name
        if (not gameName) or (gameName == "") then
            self:CreateErrorDialog("<LOC GAMECREATE_0000>Please choose a valid game name")
            return
        end

        -- validate name
        local gnBegin, gnEnd = string.find(gameName, "%s+")
        if gnBegin and (gnBegin == 1 and gnEnd == string.len(gameName)) then
            self:CreateErrorDialog("<LOC GAMECREATE_0004>Please choose a name that does not contain only whitespace characters")
            return
        end

        -- validate port
        local port = tonumber(gamePort) or 0  -- default of port 0 will cause engine to choose
        if not port or math.floor(port) ~= port or port < 0 or port > 65535 then
            self:CreateErrorDialog("<LOC GAMECREATE_0004>Please choose a name that does not contain only whitespace characters")
            return
        end

        -- validate name
        local playerName = self.EditName:GetText()
        if (not playerName) or (playerName == "") then
            self:CreateErrorDialog("<LOC GAMESEL_0003>Please fill in your nickname")
            return
        end

        local scenario = Prefs.GetFromCurrentProfile('LastScenario') or UIUtil.defaultScenario

        Prefs.SetToCurrentProfile('LastGameName', gameName)
        Prefs.SetToCurrentProfile('LastGamePort', port)

        local lobby = import("/lua/ui/lobby/lobby.lua").CreateLobby(port, playerName, nil)
        lobby:Host(gameName, scenario, false)

        self:Destroy()
    end,

    ---@param self UILobbySelection
    ---@param gameAddress string
    JoinLobby = function(self, gameAddress)
        -- validate name
        local playerName = self.EditName:GetText()
        if (not playerName) or (playerName == "") then
            self:CreateErrorDialog("<LOC GAMESEL_0003>Please fill in your nickname")
            return
        end

        -- validate address
        local address = ValidateIPAddress(gameAddress)
        if not address then
            self:CreateErrorDialog("<LOC DIRCON_0004>Invalid/unknown IP address")
            return
        end

        local lobby = import("/lua/ui/lobby/lobby.lua").CreateLobby(0, playerName, nil)
        lobby:Join(address)

        self:Destroy()
    end,

    ---------------------------------------------------------------------------
    --#region Callbacks

    ---@param self UILobbySelection
    ---@param callback fun()
    ---@param name string
    AddOnExitCallback = function(self, callback, name)
        if (not name) or type(name) != 'string' then
            self:Warn("Ignoring callback, 'name' parameter is invalid for  'AddOnExitCallback'")
            return
        end

        if (not callback) or type(callback) != 'function' then
            self:Warn("Ignoring callback, 'callback' parameter is invalid for 'AddOnExitCallback'")
            return
        end

        self.OnExitCallbacks[name] = callback
    end,

    ---@param self UILobbySelection
    ---@param callback fun()
    ---@param name string
    AddOnDestroyCallback = function(self, callback, name)
        if (not name) or type(name) != 'string' then
            self:Warn("Ignoring callback, 'name' parameter is invalid for  'AddOnDestroyCallback'")
            return
        end

        if (not callback) or type(callback) != 'function' then
            self:Warn("Ignoring callback, 'callback' parameter is invalid for 'AddOnDestroyCallback'")
            return
        end

        self.OnDestroyCallbacks[name] = callback
    end,

    ---------------------------------------------------------------------------
    --#region Debugging

    Debugging = true,

    ---@param self UILobbySelection
    ---@param message string
    Debug = function(self, message)
        if self.Debugging then
            SPEW(string.format("UILobbySelection: %s", message))
        end
    end,

    ---@param self UILobbySelection
    ---@param message string
    Log = function(self, message)
        LOG(string.format("UILobbySelection: %s", message))
    end,

    ---@param self UILobbySelection
    ---@param message string
    Warn = function(self, message)
        WARN(string.format("UILobbySelection: %s", message))
    end,
}

---@param parent Control
---@param exitBehavior fun()
---@return UILobbySelection
CreateLobbySelection = function(parent)
    local lobbySelection = LobbySelection(parent) --[[@as UILobbySelection]]
    lobbySelection:SetupDiscoveryService()
    return lobbySelection
end