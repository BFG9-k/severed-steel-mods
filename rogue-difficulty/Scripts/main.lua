local SCREEN_CLASS = "/Game/UI/MainMenuV3/Rogue/WBP_RogueMain.WBP_RogueMain_C"
local BUTTON_CLASS = "/Game/UI/AdamButton/WBP_AdamButton.WBP_AdamButton_C"
local CLICK_HANDLER = BUTTON_CLASS .. ":BndEvt__Button_45_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature"
local PICKER_CLASS = "/Game/UI/MainMenuV3/Difficulty/WBP_Difficulty.WBP_Difficulty_C"
local PICKER_ASSET = "/Game/UI/MainMenuV3/Difficulty/WBP_Difficulty"

local SETTINGS_FILE = "Mods/rogue-difficulty/settings.txt"

local DIFFICULTY_NAMES =
{
    [ 0 ] = "COLD STEEL",
    [ 1 ] = "TEMPERED STEEL",
    [ 2 ] = "SEVERED STEEL",
    [ 3 ] = "VERY HARD",
    [ 4 ] = "SHARPENED STEEL",
    [ 5 ] = "MOLTEN STEEL",
}
local PICKER_BUTTONS =
{
    { field = "ColdSteelButton", value = 0 },
    { field = "TemperedButton",  value = 1 },
    { field = "SeveredButton",   value = 2 },
    { field = "SharpenedButton", value = 4 },
    { field = "MoltenButton",    value = 5 },
}
local GAME_TYPE_ROGUE = 3
local ROGUE_DEFAULT_DIFFICULTY = 3

local chosen = nil

local function is_real_object( o )
    return o and o:IsValid( ) and not o:GetFName( ):ToString( ):find( "Default__", 1, true )
end

local function when_loaded( class_path, fn )
    local done = false
    LoopAsync( 200, function( )
        ExecuteInGameThread( function( )
            if done then return end
            local cls = StaticFindObject( class_path )
            if cls and cls:IsValid( ) then
                done = true
                fn( )
            end
        end )
        return done
    end )
end

local function load_settings( )
    local f = io.open( SETTINGS_FILE, "r" )
    if not f then return end
    local line = f:read( "l" )
    f:close( )
    local value = tonumber( line and line:match( "^diff=(%d+)$" ) )
    if value and DIFFICULTY_NAMES[ value ] then chosen = value end
end

local function save_settings( )
    local f = io.open( SETTINGS_FILE, "w" )
    if not f then return end
    f:write( "diff=" .. ( chosen ~= nil and tostring( chosen ) or "default" ) .. "\n" )
    f:close( )
end

local function chosen_name( )
    return chosen ~= nil and DIFFICULTY_NAMES[ chosen ] or "DEFAULT"
end

load_settings( )

local game_mode = nil

local function enforce_difficulty( )
    if chosen == nil then return end
    if not ( game_mode and game_mode:IsValid( ) ) then
        game_mode = FindFirstOf( "ThankYouVeryCoolGameMode" )
    end
    if not game_mode or not game_mode:IsValid( ) then return end

    if game_mode.CurrentGameType == GAME_TYPE_ROGUE and game_mode.Difficulty ~= chosen then
        game_mode:SetDifficult( chosen )
    end
end

LoopAsync( 1000, function( )
    ExecuteInGameThread( enforce_difficulty )
    return false
end )

local function set_button_texts( btn, top_text, main_text )
    pcall( function( ) btn.Text = FText( main_text ) end )
    btn.text_block_137:SetText( FText( main_text ) )
    btn.LevelTxt:SetText( FText( top_text ) )
    btn.LevelTextScaleBox:SetVisibility( 0 )
end

local function read_canvas_layout( w )
    local slot = w.Slot
    if not slot or not slot:IsValid( ) or slot:GetClass( ):GetFName( ):ToString( ) ~= "CanvasPanelSlot" then
        return nil
    end
    local ld = slot.LayoutData
    local o, a, al = ld.Offsets, ld.Anchors, ld.Alignment
    return
    {
        x = o.Left, y = o.Top,
        min_x = a.Minimum.X, min_y = a.Minimum.Y, max_x = a.Maximum.X, max_y = a.Maximum.Y,
        ay = al.Y, z = slot.ZOrder,
    }
end

local function find_canvas_anchor( widget )
    while widget and widget:IsValid( ) do
        local parent = widget:GetParent( )
        local layout = read_canvas_layout( widget )
        if layout and parent and parent:IsValid( ) then return widget, parent, layout end
        widget = parent
    end
end

local function branch_containing( a, b )
    local b_ancestors = { }
    local w = b
    while w and w:IsValid( ) do
        b_ancestors[ w:GetAddress( ) ] = true
        w = w:GetParent( )
    end
    local node = a
    while node and node:IsValid( ) do
        local parent = node:GetParent( )
        if not parent or not parent:IsValid( ) then return nil end
        if b_ancestors[ parent:GetAddress( ) ] then return node end
        node = parent
    end
end

local current = nil

local function screen_exists( screen )
    for _, w in ipairs( FindAllOf( "WBP_RogueMain_C" ) or { } ) do
        if w:GetAddress( ) == screen.address then return true end
    end
    return false
end

local function refresh_button( screen )
    set_button_texts( screen.button, chosen_name( ), "DIFFICULTY" )
end

local function close_panel( screen )
    if not screen.open then return end
    screen.open = false
    screen.panel:SetVisibility( 1 )
    for _, h in ipairs( screen.hidden ) do
        if h.widget:IsValid( ) then h.widget:SetVisibility( h.visibility ) end
    end
    screen.button:SetToggled( false )
end

local function on_picked( screen, value )
    if value == chosen then
        chosen = nil
    else
        chosen = value
    end
    save_settings( )
    refresh_button( screen )
    close_panel( screen )
end

local function create_panel( screen )
    local cls = StaticFindObject( PICKER_CLASS )
    if not cls or not cls:IsValid( ) then
        LoadAsset( PICKER_ASSET )
        cls = StaticFindObject( PICKER_CLASS )
    end
    local lib = StaticFindObject( "/Script/UMG.Default__WidgetBlueprintLibrary" )
    local panel = lib:Create( screen.rogue, cls, FindFirstOf( "PlayerController" ) )

    local column, canvas, layout = find_canvas_anchor( screen.ref )
    local column_width = column:GetDesiredSize( ).X

    local slot = canvas:AddChild( panel )
    slot:SetAutoSize( true )
    slot:SetMinimum( { X = layout.min_x, Y = layout.min_y } )
    slot:SetMaximum( { X = layout.max_x, Y = layout.max_y } )
    slot:SetAlignment( { X = 0, Y = layout.ay } )
    slot:SetZOrder( ( layout.z or 0 ) + 10 )
    slot:SetPosition( { X = layout.x + column_width + 20, Y = layout.y } )

    local hide_list = { }
    local function hide( w )
        if w and w:IsValid( ) then table.insert( hide_list, w ) end
    end
    hide( branch_containing( screen.rogue.RC, screen.ref ) )
    for i = 0, canvas:GetChildrenCount( ) - 1 do
        local child = canvas:GetChildAt( i )
        if child:GetClass( ):GetFName( ):ToString( ) == "Border" then hide( child ) end
    end
    hide( screen.rogue.DifficultyDescription )

    screen.panel = panel
    screen.hide_list = hide_list
    screen.picker_buttons = { }
    for _, entry in ipairs( PICKER_BUTTONS ) do
        screen.picker_buttons[ panel[ entry.field ]:GetAddress( ) ] = entry.value
    end
end

local function open_panel( screen )
    if not screen.panel then create_panel( screen ) end
    screen.open = true
    screen.panel:SetVisibility( 0 )

    screen.hidden = { }
    for _, w in ipairs( screen.hide_list ) do
        table.insert( screen.hidden, { widget = w, visibility = w:GetVisibility( ) } )
        w:SetVisibility( 1 )
    end

    if chosen ~= nil then
        screen.panel:SetSelected( chosen )
    else
        screen.panel:UntoggleAll( )
    end

    local function show_description( )
        if screen.open and screen.panel:IsValid( ) then
            screen.panel:ShowDiffDesc( chosen ~= nil and chosen or ROGUE_DEFAULT_DIFFICULTY )
        end
    end
    show_description( )
    ExecuteWithDelay( 250, function( ) ExecuteInGameThread( show_description ) end )

    screen.button:SetToggled( true )
end

local function add_button( rogue )
    if not is_real_object( rogue ) then return true end
    if current and current.address == rogue:GetAddress( ) then return true end
    local ref = rogue.WorkshopBtn
    if not ref or not ref:IsValid( ) then return false end

    local lib = StaticFindObject( "/Script/UMG.Default__WidgetBlueprintLibrary" )
    local btn = lib:Create( rogue, ref:GetClass( ), FindFirstOf( "PlayerController" ) )

    pcall( function( ) btn.Size = ref.Size end )
    set_button_texts( btn, chosen_name( ), "DIFFICULTY" )
    btn:PreConstruct( false )
    set_button_texts( btn, chosen_name( ), "DIFFICULTY" )

    local slot = ref:GetParent( ):AddChild( btn )
    for _, property in ipairs( { "Padding", "HorizontalAlignment", "VerticalAlignment", "Size" } ) do
        pcall( function( ) slot[ property ] = ref.Slot[ property ] end )
    end
    btn:SetVisibility( 0 )

    current = { address = rogue:GetAddress( ), rogue = rogue, ref = ref, button = btn, button_address = btn:GetAddress( ) }
    return true
end

local function try_add_button( rogue, attempts_left )
    if not rogue:IsValid( ) then return end
    if add_button( rogue ) or attempts_left <= 0 then return end
    ExecuteWithDelay( 50, function( )
        ExecuteInGameThread( function( ) try_add_button( rogue, attempts_left - 1 ) end )
    end )
end

when_loaded( SCREEN_CLASS, function( )
    NotifyOnNewObject( SCREEN_CLASS, function( rogue )
        current = nil
        ExecuteWithDelay( 20, function( )
            ExecuteInGameThread( function( ) try_add_button( rogue, 40 ) end )
        end )
    end )
    for _, rogue in ipairs( FindAllOf( "WBP_RogueMain_C" ) or { } ) do try_add_button( rogue, 40 ) end
end )

when_loaded( BUTTON_CLASS, function( )
    RegisterHook( CLICK_HANDLER, function( self )
        local screen = current
        if not screen then return end
        local address = self:get( ):GetAddress( )
        local target_button = address == screen.button_address
        if not target_button and not screen.open then return end
        if not screen_exists( screen ) then
            current = nil
            return
        end
        if target_button then
            if screen.open then close_panel( screen ) else open_panel( screen ) end
        else
            local value = screen.picker_buttons[ address ]
            if value ~= nil then on_picked( screen, value ) else close_panel( screen ) end
        end
    end )
end )
