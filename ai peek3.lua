-- vector library
local vector = require('vector')

-- text for the indicator, change it if u want
local indicator_text = 'A-PEEK'

local allowed_hitscan = {0, 2, 4, 5, 7, 8}
local hitscan = allowed_hitscan
local prev_data = {}
local tmp_pos, count = 1
local start_pos, cur_target, did_shoot
local should_return = false

local hitscan_to_hitboxes = {
	['head'] = {0}, -- neck=1 but we wont use it cuz aimbot wont shoot neck. at least not if i play on hs only servers
	['chest'] = {2, 3, 4},
	['stomach'] = {5, 6},
	['arms'] = {13, 14, 15, 16, 17, 18}, 
	['legs'] = {7, 8, 9, 10}, 
	['feet'] = {11, 12}
}

local hitgroup_data = {
	['Head'] = 1,
	['Neck'] = 8,
	['Pelvis'] = 2,
	['Spine 4'] = 3,
	['Spine 3'] = 3,
	['Spine 2'] = 3,
	['Spine 1'] = 3,
	['Leg Upper L'] = 6,
	['Leg Upper R'] = 7,
	['Leg Lower L'] = 6,
	['Leg Lower R'] = 7,
	['Foot L'] = 6,
	['Foot R'] = 7,
	['Hand L'] = 4,
	['Hand R'] = 5,
	['Arm Upper L'] = 4,
	['Arm Upper R'] = 5,
	['Arm Lower L'] = 4,
	['Arm Lower R'] = 5
}

local hitboxes_num2text = {
	[0] = 'Head',
	[1] = 'Neck',
	[2] = 'Pelvis',
	[3] = 'Spine 4',
	[4] = 'Spine 3',
	[5] = 'Spine 2',
	[6] = 'Spine 1',
	[7] = 'Leg Upper L',
	[8] = 'Leg Upper R',
	[9] = 'Leg Lower L',
	[10] = 'Leg Lower R',
	[11] = 'Foot L',
	[12] = 'Foot R',
	[13] = 'Hand L',
	[14] = 'Hand R',
	[15] = 'Arm Upper L',
	[16] = 'Arm Upper R',
	[17] = 'Arm Lower L',
	[18] = 'Arm Lower R',
}

-- ui referenceseses
local refs = {
	mindmg = ui.reference('RAGE', 'Aimbot', 'Minimum damage'),
	target_hitbox = ui.reference('RAGE', 'Aimbot', 'Target hitbox'),
	menu_color = ui.reference('MISC', 'Settings', 'Menu color')
}

-- options for the multiselect ui object
local options_t = {
	'Allow limbs',
	'Indicator',
	'Draw trace'
}

local menu_color = {ui.get(refs.menu_color)}

-- new ui objects or elemenst idk how u wanna call it
local enabled = ui.new_checkbox("RAGE", "Other", "\a0078FFFFMario\aFFFFFFFFLua\aCACACAFF Automatic Peek Minimal\a0078FFFF")
local ui_obj = {
	peek_key = ui.new_hotkey("RAGE", "Other", "On key", true),
	options = ui.new_multiselect("RAGE", "Other", "Options", options_t),
	max_dist = ui.new_slider("RAGE", "Other", "Max peek distance", 30, 300, 45, true, 'u'),
	steps = ui.new_slider("RAGE", "Other", "Trace steps", 1, 100, 10, true, 'u'),
	proc_speed = ui.new_slider("RAGE", "Other", "Process update rate", 0, 10, 0, true, 's', 0.01),
	color = ui.new_color_picker("RAGE", "Other", "Indicator color", menu_color[1], menu_color[2], menu_color[3])
}

-- Utility functions
local function table_contains(t, val)
	if not t or not val then
		return false
	end
	for i=1,#t do
		if t[i] == val then
			return true
		end
	end
	return false
end

local function table_queue( t, v, max )
	for i = max, 1, -1 do
		if( t[ i ] ~= nil ) then
			t[ i + 1 ] = t[ i ]
		end
	end

	t[ 1 ] = v
	return t
end
  
local function math_clamp(x, min, max)
	return math.min(math.max(min, x), max)
end

local function math_round(num, decimals)
	num = num or 0
	local mult = 10 ^ (decimals or 0)
	return math.floor(num * mult + 0.5) / mult
end

local function math_between(v, min, max)
	return (v and min and max) and (v > min and v < max) or false
end

local function degree_to_radian(degree)
	return (math.pi / 180) * degree
end

-- angle to vector calculation function i stole from my mom
local function AngleToVector (x, y)
	local pitch = degree_to_radian(x)
	local yaw = degree_to_radian(y)
	return math.cos(pitch) * math.cos(yaw), math.cos(pitch) * math.sin(yaw), -math.sin(pitch)
end

local client, o_trace_bullet, o_trace_line = client, client.trace_bullet, client.trace_line
local trace_cache = {
	bullet = {},
	line = {},
	line_cache = {},
	bullet_cache = {}
}

-- trace_line hook to crack luas
function client.trace_line(skip_entindex, from_x, from_y, from_z, to_x, to_y, to_z, name)
	-- for remembering and reusing trace results, which is stupit cuz trace_line drops close to 0 performance
	local cache_n = from_x..' '..from_y..' '..from_z..' '..to_x..' '..to_y..' '..to_z
	
	-- check if same trace was already made before and return the data in the table
	if trace_cache.line_cache[cache_n] then
		return trace_cache.line_cache[cache_n][1], trace_cache.line_cache[cache_n][2]
	end

	-- trace the line
	local frac, idx = o_trace_line(skip_entindex, from_x, from_y, from_z, to_x, to_y, to_z)
	
	-- store the trace data
	trace_cache.line_cache[cache_n] = {frac, idx}
	
	-- for drawing the trace lines 
	table_queue( trace_cache.line, {from = vector( from_x, from_y, from_z ), to = vector( to_x, to_y, to_z ), name = name or '', fraction = math_round(frac, 3)}, 1 )
	return frac, idx
end

function client.trace_bullet(from_player, from_x, from_y, from_z, to_x, to_y, to_z, skip_players, name)
	local idx, dmg = o_trace_bullet(from_player, from_x, from_y, from_z, to_x, to_y, to_z, skip_players)
	
	-- for drawing the damage traces 
	table_queue( trace_cache.bullet, {from = vector( from_x, from_y, from_z ), to = vector( to_x, to_y, to_z ), name = name or '', damage = dmg}, 1 )
	return idx, dmg
end

-- returns true if the entity is able to shoot, else it returns false
local function can_shoot(ent)
	ent = ent or entity.get_local_player()	
	local active_weapon = entity.get_prop(ent, "m_hActiveWeapon")
	local nextAttack = entity.get_prop(active_weapon, "m_flNextPrimaryAttack")
	return globals.curtime() >= nextAttack
end

-- make local player move to the given position
local function set_movement(cmd, desired_pos)
    local local_player = entity.get_local_player()
	local vec_angles = {
		vector(
			entity.get_origin( local_player )
		):to(
			desired_pos
		):angles()
	}

    local pitch, yaw = vec_angles[1], vec_angles[2]

    cmd.in_forward = 1
    cmd.in_back = 0
    cmd.in_moveleft = 0
    cmd.in_moveright = 0
    cmd.in_speed = 0
    cmd.forwardmove = 800
    cmd.sidemove = 0
    cmd.move_yaw = yaw
end


-- update the allowed hitscan if option allow limbs changed
local function update_allowed_hitscan(obj)
	local options = ui.get(obj)
	local limbs_allowed = table_contains(options, 'Allow limbs')

	-- i keep the commented out values just as an bridge of thought
	allowed_hitscan = (
		limbs_allowed and
		{0, --[[1, no neck. remember?]] 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18} or
		{0, --[[1, still no neck]] 2, --[[3,]] 4, 5, --[[6,]] 7, 8,--[[ 9, 10, 11, 12, 13, 14, 15, 16, 17, 18]]}
	)
end
ui.set_callback(ui_obj.options, update_allowed_hitscan)

-- update the hitscan if target hitbox settings changed
local function update_hitscan(obj)
	local t_hitscan = {}
	local target_hitboxes = ui.get(obj)

	-- loop through all enabled target hitboxes
	for i=1, #target_hitboxes do
		local hitbox_t = hitscan_to_hitboxes[target_hitboxes[i]:lower()]

		-- store all hitbox numbers in an temporary table
		for i2=1, #hitbox_t do
			local hitbox = hitbox_t[i2]

			if table_contains(allowed_hitscan, hitbox) then
				table.insert(t_hitscan, hitbox)
			end
		end
	end
	
	-- set the hitscan
	hitscan = t_hitscan
end
ui.set_callback(refs.target_hitbox, update_hitscan)

update_hitscan( refs.target_hitbox )

local function handle_trace(ent, left_x, left_y, right_x, right_x, right_y, lp_eye_pos, dist)
	dist = dist or 1
	count = count or 1

	local max_dist = ui.get(ui_obj.max_dist)

	-- stop if trace distance reached max distance and reset
	if dist > max_dist then
		tmp_pos = nil
	    prev_data = {}
		return
	end              
		
	local local_player = entity.get_local_player()

	-- currently traced hitbox
	local cur_hitbox = hitscan[count]
	
	-- target hitbox position
	local enemy_hitbox = vector( entity.hitbox_position( ent, cur_hitbox ) )
	
	-- set the next traced hitbox
	count = count < #hitscan and count + 1 or 1
	
	local eye_left = vector( left_x * dist + lp_eye_pos.x, left_y * dist + lp_eye_pos.y, lp_eye_pos.z )	-- calculation for the position to your left
	local eye_right = vector( right_x * dist + lp_eye_pos.x, right_y * dist + lp_eye_pos.y, lp_eye_pos.z )-- calculation for the position to your left

	-- trace the fraction of your left and right to prevent tracing points starting inside a wall
	local fraction_l, _entindex = client.trace_line( local_player, lp_eye_pos.x, lp_eye_pos.y, lp_eye_pos.z, eye_left.x, eye_left.y, eye_left.z )		-- fraction from your eye position to the left
	local fraction_r, _entindex2 = client.trace_line( local_player, lp_eye_pos.x, lp_eye_pos.y, lp_eye_pos.z, eye_right.x, eye_right.y, eye_right.z )	-- fraction from your eye position to the right
	
	-- there has to be an reason why i did this trace...
	-- oh god, alzheimer kicks in... what is this? where am i? hello? yes, this is hello... or is it? idk i am retarted
	local frac_l_to_ent, entindex = client.trace_line( local_player, eye_left.x, eye_left.y, eye_left.z, enemy_hitbox.x, enemy_hitbox.y, enemy_hitbox.z )		-- fraction from your left side to the target entity
	local frac_r_to_ent, entindex2 = client.trace_line( local_player, eye_right.x, eye_right.y, eye_right.z, enemy_hitbox.x, enemy_hitbox.y, enemy_hitbox.z )	-- fraction from your right side to the target entity

	-- get the possible damage from your left and right
	local _, dmg_l = client.trace_bullet( local_player, eye_left.x, eye_left.y, eye_left.z, enemy_hitbox.x, enemy_hitbox.y, enemy_hitbox.z )		-- damage from your left side to the target entity hitbox
	local _, dmg_r = client.trace_bullet( local_player, eye_right.x, eye_right.y, eye_right.z, enemy_hitbox.x, enemy_hitbox.y, enemy_hitbox.z )	-- damage from your right side to the target entity hitbox
	
	-- convert hitbox number to hitbox name
	local hitbox_name = hitboxes_num2text[cur_hitbox]

	-- get the hitgroup of the hitbox
	local hitgroup = hitgroup_data[hitbox_name]
	
	-- adjust the damage for the hitgroup
	dmg_l = client.scale_damage(ent, hitgroup, dmg_l)
	dmg_r = client.scale_damage(ent, hitgroup, dmg_r)
	
	local mindmg = ui.get(refs.mindmg)

	if fraction_l == 1 and dmg_l >= mindmg  then
		tmp_pos = eye_left
	    prev_data = {}
		return
	else
		prev_data.left = eye_left
	end

	if fraction_r == 1 and dmg_r >= mindmg then
	   tmp_pos = eye_right
	   prev_data = {}
	   return
	else
		prev_data.right = eye_right
	end
	
	-- check if it tracing should continue on the next distance
	if (fraction_l == 1 or fraction_r == 1) and (frac_l_to_ent < 1 and frac_r_to_ent < 1) and (entindex ~= ent and entindex2 ~= ent) and (dmg_r < mindmg and dmg_l < mindmg) then
		
		-- delay call for the next trace with and distance increase of default: 10 units
		-- less distance increment is finer but slower tracing and more increment is the opposite
		client.delay_call(ui.get( ui_obj.proc_speed ) / 100, handle_trace, ent, left_x, left_y, right_x, right_x, right_y, lp_eye_pos, dist + ui.get( ui_obj.steps ))
	else
		prev_data = {}
	end
end

local function do_return( cmd )
	-- check if player should return to start position
	if start_pos and should_return then
		local m_vecOrigin_lp = vector( entity.get_origin( entity.get_local_player() ) )
		if start_pos:dist2d( m_vecOrigin_lp ) > 5 then
			set_movement( cmd, start_pos )
		else
			should_return = false
		end
	end
end

local function on_setup_command(cmd)
	if not ui.get(enabled) or not ui.get(ui_obj.peek_key) then
		should_return = false
		tmp_pos = nil
		start_pos = nil
	    prev_data = {}
		return
	end

	local local_player = entity.get_local_player()

	-- check if local player is alive
	if not entity.is_alive(local_player) then
		prev_data = {}	
		tmp_pos = nil
	   return
	end

	-- i use current_threat so we wont need to loop through all players and calculate the best target
	local ent = client.current_threat()
	
	-- as an backup to prevent target switch while peeking
	cur_target = cur_target or ent

	-- check if the target can be switched and set to new target if so
	cur_target = cur_target ~= ent and ((not tmp_pos or should_return) and ent or cur_target) or cur_target
	
	-- set ent to cur_target just cuz i am to lazy to change ent to cur_target. which i could have done while writing this comment like an schizophrenic.
	ent = cur_target

	-- check if target exists and is alive
	if not ent or not entity.is_alive(ent) then
		-- return to start pos
		return do_return( cmd )
	end

	local m_vecOrigin_lp = vector(entity.get_origin( local_player ))
	local m_vecOrigin_enemy = vector(entity.get_origin( ent ))

	start_pos = start_pos or m_vecOrigin_lp

	local lp_eye_pos = vector( client.eye_position() )
	
	local vec2enemy_x, vec2enemy_y = lp_eye_pos.x - m_vecOrigin_enemy.x, lp_eye_pos.y - m_vecOrigin_enemy.y
	local ang2enemy = math.atan2( vec2enemy_y, vec2enemy_x ) * ( 180 / math.pi )
	
	local vec2enemy_x2, vec2enemy_y2 = lp_eye_pos.x - m_vecOrigin_enemy.x, lp_eye_pos.y - m_vecOrigin_enemy.y
	local ang2enemy2 = math.atan2( vec2enemy_y2, vec2enemy_x2 ) * ( 180 / math.pi )
	
	local left_x, left_y, left_z = AngleToVector( 0, ang2enemy - 90 )
	local right_x, right_y, right_z = AngleToVector( 0, ang2enemy + 90 )

	-- can u?
	local can_shit = can_shoot()

	should_return = can_shit and false or should_return

	-- check if trace handeling function should be called
	if not prev_data.left and not prev_data.right and not tmp_pos then	
		handle_trace( ent, left_x, left_y, right_x, right_x, right_y, lp_eye_pos )
	end

	-- if shot fired, the peek was successful and the player should return
	if did_shoot then
		should_return = true
		did_shoot = false
		prev_data = {}	
		tmp_pos = nil
	end
	
	if tmp_pos then
		local move_dist = tmp_pos:dist2d( m_vecOrigin_lp )

		-- as long the player can shoot and is far from the goal, the player should move to the goal
		if move_dist > 5 and can_shit then
			should_return = false
			set_movement( cmd, tmp_pos )
		else
			should_return = true
			tmp_pos = nil
		end
	end

	-- check if player should return to start position
	do_return( cmd )
end	

local function draw_trace_lines(color)
	if not ui.get(enabled) or not ui.get(ui_obj.peek_key) then
		return
	end

	local options = ui.get( ui_obj.options )
	
	if table_contains(options, 'Indicator') then
		local r, g, b, a = ui.get(ui_obj.color)
		renderer.indicator(r, g, b, a, indicator_text)
	end

	if not table_contains(options, 'Draw trace') then
		return
	end

	for i=1, #trace_cache.bullet do
		local from = trace_cache.bullet[i]['from']
		local to = trace_cache.bullet[i]['to']
		local name = trace_cache.bullet[i]['name']
		local dmg = trace_cache.bullet[i]['damage']
		
		local scr_from_x, scr_from_y = renderer.world_to_screen( from.x, from.y, from.z )
		local scr_to_x, scr_to_y = renderer.world_to_screen( to.x, to.y, to.z )

		if scr_from_x and scr_from_y and scr_to_x and scr_to_y then
			renderer.line( scr_from_x, scr_from_y, scr_to_x, scr_to_y, math_clamp( 200 + dmg, 0, 255 ), math_clamp( 255 - dmg, 0, 255 ), math_clamp( 100 - dmg, 0, 255 ), 255 )
			renderer.text( scr_from_x + 20, scr_from_y + 20, math_clamp( 200 + dmg, 0, 255 ), math_clamp( 255 - dmg, 0, 255 ), math_clamp( 100 - dmg, 0, 255 ), 255, 'c', 0, dmg )
		end
	end

end

-- set start position on key press
local key_pressed
ui.set_callback( ui_obj.peek_key, function(obj)
	local key_press = ui.get(obj)
	key_pressed = key_pressed and not key_press and false or key_pressed
	
	if key_pressed then
		return
	end

	key_pressed = true
	start_pos = vector( entity.get_origin( entity.get_local_player() ) )
	should_return = false
	did_shoot = false
	prev_data = {}	
	tmp_pos = nil
end )

-- do things if player spawned
local function on_player_spawn( e )
	local ent = client.userid_to_entindex( e.userid )
	local local_player = entity.get_local_player()
	
	
	if ent == local_player then
		-- update the hitscan if local player is spawned
		update_hitscan( refs.target_hitbox )
		
		-- reset the trace cache
		trace_cache = {
			bullet = {},
			line = {},
			line_cache = {},
			bullet_cache = {}
		}
	end
end

-- do things if an weapon is fired
local function on_weapon_fire( e )
	local ent = client.userid_to_entindex( e.userid )
	local local_player = entity.get_local_player()
	
	-- did the local player shoot?
	should_return = ent == local_player and true or should_return
	did_shoot = ent == local_player
	tmp_pos = nil
end

-- set ui object invisible/visible
local function ui_obj_visibility(param)
	local succ, val = pcall(ui.get, type(param) == 'boolean' and enabled or param)
	param = not succ and param or (val)
	
	-- set or unset the event callbacks depending on if the checkbox is enabled or disabled
	local handle_event_callback = param and client.set_event_callback or client.unset_event_callback
	
	-- gs events
	handle_event_callback( 'paint', draw_trace_lines )
	handle_event_callback( 'setup_command', on_setup_command )	
	
	-- game events
	handle_event_callback( "weapon_fire", on_weapon_fire )
	handle_event_callback( "player_spawn", on_player_spawn )
	
	for k, v in pairs(ui_obj) do
		ui.set_visible(v, param)
	end
end
ui_obj_visibility(false)
ui.set_callback(enabled, ui_obj_visibility)