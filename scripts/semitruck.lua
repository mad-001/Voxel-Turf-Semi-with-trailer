-- SemiTruckMod -- driveable tractor + a bending semi-trailer
--
--   Cab     = BasicVehicleEntityType  (the Jura "Low Poly Red Semi Truck",
--             CC-BY, converted to mesh 360, coloured via palette texture 0).
--   Trailer = part of the cab's render (mesh 361). The cab's render hook draws
--             it the exact same way it draws the wheels: as an attached piece,
--             hinged at the fifth wheel so it trails and BENDS through turns.
--             Every client derives the trailer's pose from the cab's own
--             (already-synced) transform each frame, so it can't desync and
--             nothing has to be spawned. It is visual only (no separate
--             collision body) -- the version with a real hitbox needs a spawned
--             entity, which this engine wouldn't drive reliably for our cab.
--
-- Spawn for testing:   /give SemiTruck   (the trailer is drawn as part of the cab)

-- ---- ids / assets ----------------------------------------------------------
SEMI_CAB_ENTITY_ID       = -1
SEMI_TRAILER_RENDER_TYPE = -1   -- render-only component drawn with the cab (not a spawnable entity)
SEMI_WHEEL_TYPE          = -1
SEMI_CAB_MESH_ID         = 360  -- db/meshes.txt
SEMI_TRAILER_MESH_ID     = 361
SEMI_EMPTY_WHEEL_MESH    = 364  -- tiny invisible mesh: hides the engine's physics wheels so only the model's own wheels show
SEMI_PAL_TEX_ID          = 0    -- overridden tex0: our own faithful palette (every model colour)
SEMI_ITEM_SEEK           = 13950 -- /give item

-- The six model wheels are split out of the cab mesh into their own meshes so
-- they can spin (and the front pair steer). hub = position in cab-mesh-local
-- space (matches semicab.obj); steer = part of the front steering pair.
SEMI_WHEEL_DEFS = {
	{ mesh = 365, hx =  0.5292, hy = 0.4488, hz =  2.6796, steer = true  }, -- front-left
	{ mesh = 366, hx = -0.5292, hy = 0.4488, hz =  2.6796, steer = true  }, -- front-right
	{ mesh = 367, hx =  0.4891, hy = 0.4488, hz = -2.1248, steer = false }, -- tandem-front-left
	{ mesh = 368, hx = -0.4891, hy = 0.4488, hz = -2.1248, steer = false }, -- tandem-front-right
	{ mesh = 369, hx =  0.4891, hy = 0.4488, hz = -3.2354, steer = false }, -- tandem-rear-left
	{ mesh = 370, hx = -0.4891, hy = 0.4488, hz = -3.2348, steer = false }, -- tandem-rear-right
}
SEMI_WHEELS        = {}     -- filled at define time: { typeId, hx,hy,hz, steer }
-- Trailer bogie wheels: rendered as separate pieces (so they SPIN like the cab's)
-- at these trailer-local positions. wi = index into SEMI_WHEELS for the wheel
-- TYPE to reuse (5 = TRL for +x side, 6 = TRR for -x side). y = 0.85 (dropped
-- 0.05 so they sit on the ground).
SEMI_TRAILER_WHEELS = {
	{ x =  0.49, y = 0.85, z = -3.4, wi = 5 },
	{ x = -0.49, y = 0.85, z = -3.4, wi = 6 },
	{ x =  0.49, y = 0.85, z = -4.4, wi = 5 },
	{ x = -0.49, y = 0.85, z = -4.4, wi = 6 },
}
SEMI_RSTATE        = {}     -- entityId -> render state { spin, steer, px,pz,hx,hz, trx,trz }
SEMI_WHEEL_RADIUS  = 0.51   -- model tyre radius (for roll rate)
SEMI_WHEELBASE     = 5.36   -- front axle -> tandem centre (for steer-from-yaw)
SEMI_STEER_CLAMP   = 0.7
SEMI_STEER_VISUAL  = 0.6    -- front wheels only LOOK like they turn this fraction (so they don't clip the body); driving is unchanged
SEMI_WHEEL_TRIM_Y  = -0.34  -- drop the wheels onto the axles (engine rests the chassis below the model's wheel-centre height)

-- ---- coupling geometry (matches the .obj meshes) ---------------------------
SEMI_HITCH_LOCAL_Y     = 0.9   -- fifth-wheel height on the cab (cab local; origin = wheel centre)
SEMI_HITCH_LOCAL_Z     = -2.0  -- fifth-wheel sits behind the cab, over the drive axle
SEMI_KINGPIN_LOCAL_Y   = 1.6   -- coupling height on the trailer (bigger = trailer rides lower)
SEMI_KINGPIN_TO_CENTRE = 2.5   -- kingpin pivot in front of the trailer origin (smaller = trailer further forward)
SEMI_HITCH_LEN         = 6.4   -- kingpin -> trailer rear bogie centre (the trailing arm; longer = bends less)
SEMI_TRAILER_TRIM_Y    = 0.0   -- vertical nudge for the trailer if it floats/sinks

-- ---- math helpers ----------------------------------------------------------
local function semi_atan2 (y, x)
	if x > 0 then return math.atan(y / x)
	elseif x < 0 and y >= 0 then return math.atan(y / x) + math.pi
	elseif x < 0 and y < 0 then return math.atan(y / x) - math.pi
	elseif x == 0 and y > 0 then return math.pi * 0.5
	elseif x == 0 and y < 0 then return -math.pi * 0.5
	else return 0 end
end
local function semi_light_at (W, pos)
	local lc = W:getLightAtLocationv(pos);
	if (lc:isZero()) then lc = W:getLightAtLocationv(pos:add(turf.btVector3(0, 1, 0))); end
	return lc;
end
local function semi_level_forward (T)
	local c = turf.cloneBtTransform(T); c:setOrigin(turf.btVector3(0, 0, 0));
	local r = c:multv(turf.btVector3(0, 0, 1));
	local x, z = r:x(), r:z(); local len = math.sqrt(x * x + z * z);
	if len < 0.0001 then return 0, 1 end
	return x / len, z / len;
end

-- ---- entity type definitions -----------------------------------------------
function define_semi_truck (EntityTypes)
	-- Trailer: a render-only component (a WheelEntityType, exactly like the
	-- wheels). The cab's render hook draws it; it is never spawned as an entity.
	SEMI_TRAILER_RENDER_TYPE = EntityTypes:getNEntityTypes();
	local TR = turf.WheelEntityType.genNew(SEMI_TRAILER_RENDER_TYPE);
	TR:setMeshId(SEMI_TRAILER_MESH_ID);
	TR:setTextureId(SEMI_PAL_TEX_ID);
	EntityTypes:pushEntityType(TR);
	SEMI_TRAILER_RENDER_TYPE = TR:getId();

	-- Invisible wheel type: the engine still needs raycast wheels to drive, but we
	-- render them with a near-zero mesh so only the model's own wheels are visible.
	SEMI_WHEEL_TYPE = EntityTypes:getNEntityTypes();
	local WT = turf.WheelEntityType.genNew(SEMI_WHEEL_TYPE);
	WT:setMeshId(SEMI_EMPTY_WHEEL_MESH);
	WT:setTextureId(20);
	EntityTypes:pushEntityType(WT);
	SEMI_WHEEL_TYPE = WT:getId();

	-- The six visible model wheels: each its own WheelEntityType (so we can give
	-- it an independent spin/steer transform when we render the cab). They carry
	-- the same palette texture as the body.
	SEMI_WHEELS = {};
	for i = 1, #SEMI_WHEEL_DEFS do
		local d = SEMI_WHEEL_DEFS[i];
		local wid = EntityTypes:getNEntityTypes();
		local VW = turf.WheelEntityType.genNew(wid);
		VW:setMeshId(d.mesh);
		VW:setTextureId(SEMI_PAL_TEX_ID);
		EntityTypes:pushEntityType(VW);
		SEMI_WHEELS[i] = { typeId = VW:getId(), hx = d.hx, hy = d.hy, hz = d.hz, steer = d.steer };
	end

	-- Cab: a normal driveable ground vehicle.
	SEMI_CAB_ENTITY_ID = EntityTypes:getNEntityTypes();
	local ET = turf.BasicVehicleEntityType.genNew(SEMI_CAB_ENTITY_ID);
	ET:setMeshId(SEMI_CAB_MESH_ID);
	ET:setHitboxId(SEMI_CAB_MESH_ID);
	ET:setTextureId(SEMI_PAL_TEX_ID);
	ET:setMass(4500);
	ET:setMaxHp(600);
	ET:setBaseArmourRating(0.6);

	local VP = ET:getVehicleParameters();
	VP.maxEngineForce      = 1600;   -- heavy semi: slow build-up
	VP.maxBreakingForce    = 350.0;
	VP.breakingIncrement   = 35.0;
	VP.steeringIncrement   = 0.03;
	VP.steeringClamp       = 0.7;
	VP.wheelRadius         = 0.5;
	VP.wheelWidth          = 0.35;
	VP.wheelFriction       = 1500;
	VP.suspensionStiffness = 80.0;
	VP.suspensionDamping   = 4.0;
	VP.suspensionCompression = 4.4;
	VP.suspensionRestLength  = 0.4;
	VP.maxSuspensionForce  = 300000;
	VP.rollInfluence       = 0.1;
	VP.damageForceScaling  = 0.2;
	VP.centreOfMass        = turf.btVector3(0, -0.3, 0);
	VP.dragCoefficent      = 6;      -- caps top speed lower
	VP.wheelType           = SEMI_WHEEL_TYPE;  -- invisible: the model draws its own wheels
	VP.nWheels             = 4;     -- front steer pair + rear drive pair
	VP.axleXPos            = 1.0;
	VP.axleZPos            = 2.68;  -- measured from the model's front/rear axles
	VP.sirenSoundTag       = "SEMI_HORN";   -- mod sfx (sfx/semihorn.wav)
	VP.spawnRate           = 0.0;   -- never in random traffic
	VP.spawnType           = turf.VehicleParameters.SPAWN_TYPE_NORMAL;

	ET.interiorCameraPos = turf.btVector3(0, 1.9, 2.0);
	-- 3rd-person chase camera pulled back so the whole rig (cab + trailer) fits
	-- (engine default end is (0, 4.5, -10)).
	ET.chaseCameraStart = turf.btVector3(0, 2.2, 0);
	ET.chaseCameraEnd   = turf.btVector3(0, 5.0, -15);

	ET.hasCustomPushRenderInstance = true;  -- we draw the wheels + the trailer ourselves
	ET.hasCustomPhysicsPrestep     = true;  -- feed trigger throttle into the engine's own drive input
	EntityTypes:pushEntityType(ET);
	SEMI_CAB_ENTITY_ID = ET:getId();

	ENTITY_TYPES[SEMI_CAB_ENTITY_ID] = {};

	-- Trigger drive -- NOTHING remapped. The right trigger is already bound to aim
	-- and the left trigger's pull already registers as fire, so we read those
	-- existing signals off the driver and write the engine's OWN throttle input,
	-- walkFB: right trigger -> forward, left trigger -> brake/reverse, neither ->
	-- coast. The native vehicle physics then drives with this cab's own
	-- VehicleParameters -- nothing is reimplemented. walkFB is overwritten every
	-- frame, so the stick no longer drives the cab forward (it still STEERS via
	-- walkLR, which we never touch). Runs server-side before the physics step.
	-- If forward/reverse come out swapped on your pad, swap the two reads below.
	ENTITY_TYPES[SEMI_CAB_ENTITY_ID].physicsPrestep = function (E, currentFrame)
		local P = E:wrangleDriver();
		if (P == nil) then return false; end
		local NH = turf.NetworkHandler;
		local rt = bit32.band(P:getRightClickMode(), bit32.bor(NH.RIGHT_MB_DOWN_FLAG, NH.RIGHT_MB_HOLD_FLAG)) ~= 0;
		local lt = bit32.band(P:getLeftClickMode(),  bit32.bor(NH.LEFT_MB_DOWN_FLAG,  NH.LEFT_MB_HOLD_FLAG))  ~= 0;
		if     (lt) then P.walkFB =  1;   -- right trigger (reports as left-click/aim path): drive forward
		elseif (rt) then P.walkFB = -1;   -- left trigger:  brake / reverse
		else             P.walkFB =  0;   -- neither:       coast (stick can't drive it)
		end
		return false;
	end

	-- Custom render: the engine already draws the cab BODY (overriding this hook
	-- ADDS to that render, it does not replace it). So here we add the six model
	-- wheels (spin + front steer) and the trailer (trails + bends). Runs on every
	-- client each render frame; visual only, no physics effect.
	ENTITY_TYPES[SEMI_CAB_ENTITY_ID].pushRenderInstance = function (E, W)
		local body = E:getBody();
		if (body == nil) then return; end
		-- Place parts in the same mesh-local frame the engine draws the body in
		-- (chassis world transform * mesh/hitbox offset).
		local ET   = E:getEntityType();
		local MTC  = turf.MeshTypeContainer.get();
		local base = turf.cloneBtTransform(body:getWorldTransform()):mult(
			turf.cloneBtTransform(MTC:getHitboxTransform(ET:getHitboxId())));

		-- Spin/steer/trailer-bend are derived from how the chassis MOVES between
		-- frames (getLinearVelocity reads ~0 on clients -- they interpolate
		-- position rather than simulate velocity).
		local id = E:getId();
		local st = SEMI_RSTATE[id];
		local px, pz = base:getOrigin():x(), base:getOrigin():z();
		local hx, hz = semi_level_forward(body:getWorldTransform());
		if (st == nil) then
			st = { spin = 0, steer = 0, px = px, pz = pz, hx = hx, hz = hz };
			SEMI_RSTATE[id] = st;
		end
		local mdx, mdz = px - st.px, pz - st.pz;          -- world move since last frame
		local fwddist  = mdx * st.hx + mdz * st.hz;        -- signed forward distance
		st.spin = st.spin + fwddist / SEMI_WHEEL_RADIUS;
		if (st.spin >  6.2831853) then st.spin = st.spin - 6.2831853;
		elseif (st.spin < -6.2831853) then st.spin = st.spin + 6.2831853; end
		if (math.abs(fwddist) > 0.001) then                -- the slightest movement steers
			local dyaw   = semi_atan2(st.hx * hz - st.hz * hx, st.hx * hx + st.hz * hz);
			local target = math.atan(SEMI_WHEELBASE * dyaw / fwddist);
			if (target >  SEMI_STEER_CLAMP) then target =  SEMI_STEER_CLAMP;
			elseif (target < -SEMI_STEER_CLAMP) then target = -SEMI_STEER_CLAMP; end
			st.steer = st.steer + (target - st.steer) * 0.35;
		end
		st.px, st.pz, st.hx, st.hz = px, pz, hx, hz;

		local spinRot  = turf.btTransform(turf.btQuaternion(turf.btVector3(1, 0, 0), st.spin),  turf.btVector3(0, 0, 0));
		local steerRot = turf.btTransform(turf.btQuaternion(turf.btVector3(0, 1, 0), -st.steer * SEMI_STEER_VISUAL), turf.btVector3(0, 0, 0));
		local ETC = E:getEntityContainer():getEntityTypeContainer();
		for i = 1, #SEMI_WHEELS do
			local w = SEMI_WHEELS[i];
			-- chassis * translate(hub) * (steer if front) * spin
			local d = turf.cloneBtTransform(base):mult(
				turf.btTransform(turf.btQuaternion(turf.btVector3(0, 1, 0), 0),
				                 turf.btVector3(w.hx, w.hy + SEMI_WHEEL_TRIM_Y, w.hz)));
			if (w.steer) then d = d:mult(steerRot); end
			d = d:mult(spinRot);
			local wet = ETC:get(w.typeId);
			if (wet) then
				wet:pushRenderInstance(turf.EntityRenderingInstance(
					d, semi_light_at(W, turf.cloneBtTransform(d):multv(turf.btVector3(0, 0, 0))), 0));
			end
		end

		-- Trailer: hinged at the fifth wheel and trailing behind. Its rear bogie
		-- lags; the body points from that bogie toward the kingpin, so it bends
		-- through turns. World transform (it has its own yaw, independent of cab).
		local kingW = turf.cloneBtTransform(base):multv(
			turf.btVector3(0, SEMI_HITCH_LOCAL_Y, SEMI_HITCH_LOCAL_Z));
		local kx, ky, kz = kingW:x(), kingW:y(), kingW:z();
		if (st.trx == nil) then                            -- first frame: straight back
			st.trx = kx - hx * SEMI_HITCH_LEN;
			st.trz = kz - hz * SEMI_HITCH_LEN;
		end
		local tdx, tdz = kx - st.trx, kz - st.trz;         -- bogie -> kingpin = trailer forward
		local tlen = math.sqrt(tdx * tdx + tdz * tdz);
		local dirx, dirz;
		if (tlen < 0.0001) then dirx, dirz = hx, hz; else dirx, dirz = tdx / tlen, tdz / tlen; end
		st.trx = kx - dirx * SEMI_HITCH_LEN;
		st.trz = kz - dirz * SEMI_HITCH_LEN;
		local tcentre = turf.btVector3(kx - dirx * SEMI_KINGPIN_TO_CENTRE,
		                               ky - SEMI_KINGPIN_LOCAL_Y + SEMI_TRAILER_TRIM_Y,
		                               kz - dirz * SEMI_KINGPIN_TO_CENTRE);
		local tdraw = turf.btTransform(turf.btQuaternion(turf.btVector3(0, 1, 0),
		                               semi_atan2(dirx, dirz)), tcentre);
		local tet = ETC:get(SEMI_TRAILER_RENDER_TYPE);
		if (tet) then
			tet:pushRenderInstance(turf.EntityRenderingInstance(
				tdraw, semi_light_at(W, tcentre), 0));
		end

		-- Trailer bogie wheels: separate pieces so they spin with travel (same
		-- spin as the cab's), placed in the trailer's frame and yawed with it.
		for i = 1, #SEMI_TRAILER_WHEELS do
			local tw = SEMI_TRAILER_WHEELS[i];
			local wd = turf.cloneBtTransform(tdraw):mult(
				turf.btTransform(turf.btQuaternion(turf.btVector3(0, 1, 0), 0),
				                 turf.btVector3(tw.x, tw.y, tw.z)));
			wd = wd:mult(spinRot);
			local twet = ETC:get(SEMI_WHEELS[tw.wi].typeId);
			if (twet) then
				twet:pushRenderInstance(turf.EntityRenderingInstance(
					wd, semi_light_at(W, turf.cloneBtTransform(wd):multv(turf.btVector3(0, 0, 0))), 0));
			end
		end
	end
end

-- ---- /give item (testing) --------------------------------------------------
function define_semi_truck_item (BlockTypes, ItemTypes)
	local ITEM = turf.EntitySpawningItem.genNew("SemiTruck", SEMI_CAB_ENTITY_ID);
	local dx, dy, dz = 3, 4, 8;
	ITEM.dimensions = turf.iVec3(dx, dy, dz);
	ITEM.offset     = turf.btVector3(dx * 0.5, dy * 0.5 - 0.5, dz * 0.5);
	ITEM.basecost   = 150000;
	ITEM.isSecret   = false;  -- visible in the buy menu under "Semi Truck" so you can purchase it
	ITEM:setDesc("An articulated semi. The trailer trails and bends behind the cab.");
	ItemTypes:pushItemType(ITEM, SEMI_ITEM_SEEK, turf.Item.NULL_MORPH_ROOT);
	local IC = ItemTypes:genNewItemCategory("Semi Truck");
	IC:pushItem(SEMI_ITEM_SEEK);
	return SEMI_ITEM_SEEK;
end

-- ---- registration ----------------------------------------------------------
if (ENTITY_TYPES == nil) then ENTITY_TYPES = {}; end
if (defineEntityTypesUserCallback == nil) then defineEntityTypesUserCallback = {}; end
defineEntityTypesUserCallback[#defineEntityTypesUserCallback + 1] = { "SemiTruckMod|semi cab + trailer entities", define_semi_truck }
if (defineOtherItemsUserCallback == nil) then defineOtherItemsUserCallback = {}; end
defineOtherItemsUserCallback[#defineOtherItemsUserCallback + 1] = { "SemiTruckMod|semi spawn item", define_semi_truck_item }

-- Because the drive triggers are the same ones bound to fire/aim (and we remap
-- NOTHING), pulling a trigger to drive would otherwise also fire the gun. The
-- fire decision is a Lua dispatch, onUseFunctions[IMT_Gun]; wrap it so a player
-- who is in a vehicle simply doesn't fire. Installed once from the server tick,
-- after the weapon scripts have set the dispatch. On-foot shooting is unaffected.
SEMI_FIRE_GUARD_DONE = false;
local function semi_install_fire_guard ()
	if (SEMI_FIRE_GUARD_DONE) then return; end
	if (onUseFunctions == nil or IMT_Gun == nil) then return; end
	local orig = onUseFunctions[IMT_Gun];
	if (orig == nil) then return; end
	onUseFunctions[IMT_Gun] = function (I, P, W, U, idx)
		if (P ~= nil and P:getBoundEntityObj() ~= nil) then return false; end  -- in a vehicle: don't fire
		return orig(I, P, W, U, idx);
	end
	SEMI_FIRE_GUARD_DONE = true;
end

if (customFunc == nil) then customFunc = {}; end
SEMI_PREV_POLL_EXTRA = customFunc.pollServerTick_extra;
customFunc.pollServerTick_extra = function (NH)
	if (SEMI_PREV_POLL_EXTRA ~= nil) then SEMI_PREV_POLL_EXTRA(NH); end
	semi_install_fire_guard();
end
