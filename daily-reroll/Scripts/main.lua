local BUTTON_LABEL = "RANDOM DAILY"

local DM_CLASS = "/Script/ThankYouVeryCool.DailyManager"
local SCREEN_CLASS = "/Game/UI/DailySteel/WBP_DailyMain.WBP_DailyMain_C"
local BUTTON_CLASS = "/Game/UI/AdamButton/WBP_AdamButton.WBP_AdamButton_C"
local CLICK_HANDLER = BUTTON_CLASS .. ":BndEvt__Button_45_K2Node_ComponentBoundEvent_0_OnButtonClickedEvent__DelegateSignature"

local TICKS_PER_SECOND = 10000000
local UNIX_EPOCH_TICKS = 621355968000000000
local DAY_SECONDS = 24 * 60 * 60
local MAX_OFFSET_DAYS = 1460

local function is_real_object( o )
    return o and o:IsValid( ) and not o:GetFName( ):ToString( ):find( "Default__", 1, true )
end

local function for_each_widget( short_class, fn )
    for _, w in ipairs( FindAllOf( short_class ) or { } ) do
        if is_real_object( w ) then fn( w ) end
    end
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

local TICKS_PROP = "DailyRerollTicks"
RegisterCustomProperty(
{
    Name = TICKS_PROP,
    Type = PropertyTypes.Int64Property,
    BelongsToClass = DM_CLASS,
    OffsetInternal = 0x238,
} )

math.randomseed( os.time( ) )

local function find_daily_manager( )
    local game_mode = FindFirstOf( "ThankYouVeryCoolGameMode" )
    local dm = game_mode and game_mode:IsValid( ) and game_mode.DailyManager
    if not dm or not dm:IsValid( ) then dm = FindFirstOf( "DailyManager" ) end
    if dm and dm:IsValid( ) then return dm end
    return nil
end

local function reroll_daily( )
    local dm = find_daily_manager( )
    if not dm then return end

    local noon = ( os.time( ) // DAY_SECONDS ) * DAY_SECONDS + DAY_SECONDS // 2
    local random_time = noon + math.random( -MAX_OFFSET_DAYS, MAX_OFFSET_DAYS ) * DAY_SECONDS
    local picked_ticks = random_time * TICKS_PER_SECOND + UNIX_EPOCH_TICKS
    dm[ TICKS_PROP ] = picked_ticks

    local pre_id, post_id = RegisterHook( DM_CLASS .. ":SetTodayAsDateTime", function( ) end, function( self )
        self:get( )[ TICKS_PROP ] = picked_ticks
    end )
    local ok, err = pcall( function( )
        for_each_widget( "WBP_DailyMain_C", function( w )
            w:OnChallengeRandomized_Event_0( )
            w:ShowString( )
            w:NotifyMenuShown( )
            w:ReRenderGun( )
        end )
        for_each_widget( "WBP_DailyDetail_C", function( w ) w:OnChallengeRandomized_Event_0( ) end )
    end )
    UnregisterHook( DM_CLASS .. ":SetTodayAsDateTime", pre_id, post_id )
    if not ok then error( err ) end

    dm[ TICKS_PROP ] = picked_ticks
    for_each_widget( "WBP_DailyMain_C", function( w ) w:ShowString( ) end )
end

local buttons = { }

local function read_canvas_layout( w )
    local slot = w.Slot
    if not slot or not slot:IsValid( ) or slot:GetClass( ):GetFName( ):ToString( ) ~= "CanvasPanelSlot" then
        return nil
    end
    local ld = slot.LayoutData
    local o, a, al = ld.Offsets, ld.Anchors, ld.Alignment
    local layout =
    {
        btn = w, slot = slot,
        x = o.Left, y = o.Top, width = o.Right,
        min_x = a.Minimum.X, min_y = a.Minimum.Y, max_x = a.Maximum.X, max_y = a.Maximum.Y,
        ax = al.X, ay = al.Y, z = slot.ZOrder,
    }
    layout.left = layout.x - layout.ax * layout.width
    return layout
end

local function plan_row( daily, leaderboard, new_btn, new_slot )
    local play = read_canvas_layout( daily.PlayBtn )
    local rewards = read_canvas_layout( daily.rwbtn )
    local lb = read_canvas_layout( leaderboard )
    if not ( play and rewards and lb ) then return nil end

    local items = { play, rewards, lb }
    for _, item in ipairs( items ) do
        if item.min_x ~= item.max_x or item.min_y ~= item.max_y
            or item.min_x ~= lb.min_x or item.min_y ~= lb.min_y then
            return nil
        end
    end

    table.sort( items, function( a, b ) return a.left < b.left end )
    local row_left = items[ 1 ].left
    local row_right = items[ 3 ].left + items[ 3 ].width
    local gap = 14
    local width = ( row_right - row_left - 3 * gap ) / 4
    if width < 80 then return nil end

    new_slot:SetAutoSize( true )
    new_slot:SetMinimum( { X = lb.min_x, Y = lb.min_y } )
    new_slot:SetMaximum( { X = lb.max_x, Y = lb.max_y } )
    new_slot:SetAlignment( { X = lb.ax, Y = lb.ay } )
    new_slot:SetZOrder( ( lb.z or 0 ) + 1 )

    local row = { items[ 1 ], items[ 2 ], items[ 3 ], { btn = new_btn, slot = new_slot, y = lb.y, ax = lb.ax } }
    for i, item in ipairs( row ) do
        item.left = row_left + ( i - 1 ) * ( width + gap )
    end
    return { row = row, width = width }
end

local function apply_plan( plan )
    for _, item in ipairs( plan.row ) do
        if item.btn:IsValid( ) then
            item.btn.SizeBox_0:SetWidthOverride( plan.width )
            item.slot:SetPosition( { X = item.left + item.ax * plan.width, Y = item.y } )
        end
    end
end

local function has_button( daily )
    local address = daily:GetAddress( )
    for _, entry in ipairs( buttons ) do
        if entry.btn:IsValid( ) and entry.owner:IsValid( ) and entry.owner:GetAddress( ) == address then
            return true
        end
    end
    return false
end

local function add_button( daily )
    if not is_real_object( daily ) then return true end
    if has_button( daily ) then return true end
    local leaderboard = daily.LBBtn
    if not leaderboard or not leaderboard:IsValid( ) then return false end

    local lib = StaticFindObject( "/Script/UMG.Default__WidgetBlueprintLibrary" )
    local btn = lib:Create( daily, leaderboard:GetClass( ), FindFirstOf( "PlayerController" ) )

    local function set_label( )
        local text = FText( BUTTON_LABEL )
        pcall( function( ) btn.Text = text end )
        btn.text_block_137:SetText( text )
        btn.LevelTxt:SetText( text )
    end
    pcall( function( ) btn.Size = leaderboard.Size end )
    set_label( )
    btn:PreConstruct( false )
    set_label( )

    local slot = leaderboard:GetParent( ):AddChild( btn )
    btn:SetVisibility( 0 )

    local plan = plan_row( daily, leaderboard, btn, slot )
    if plan then
        apply_plan( plan )
        ExecuteWithDelay( 500, function( ) ExecuteInGameThread( function( ) apply_plan( plan ) end ) end )
    end

    for i = #buttons, 1, -1 do
        if not buttons[ i ].btn:IsValid( ) then table.remove( buttons, i ) end
    end
    table.insert( buttons, { owner = daily, btn = btn } )
    return true
end

local function try_add_button( daily, attempts_left )
    if not daily:IsValid( ) then return end
    if add_button( daily ) or attempts_left <= 0 then return end
    ExecuteWithDelay( 50, function( )
        ExecuteInGameThread( function( ) try_add_button( daily, attempts_left - 1 ) end )
    end )
end

when_loaded( SCREEN_CLASS, function( )
    NotifyOnNewObject( SCREEN_CLASS, function( daily )
        ExecuteWithDelay( 20, function( )
            ExecuteInGameThread( function( ) try_add_button( daily, 40 ) end )
        end )
    end )
    for_each_widget( "WBP_DailyMain_C", function( w ) try_add_button( w, 40 ) end )
end )

when_loaded( BUTTON_CLASS, function( )
    RegisterHook( CLICK_HANDLER, function( self )
        local address = self:get( ):GetAddress( )
        for _, entry in ipairs( buttons ) do
            if entry.btn:IsValid( ) and entry.btn:GetAddress( ) == address then
                reroll_daily( )
                return
            end
        end
    end )
end )