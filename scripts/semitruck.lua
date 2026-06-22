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
SEMI_PAINT_MESH_ID       = 371  -- pristine v1.0.0 body (328 verts) for the PAINTED trailer
SEMI_EMPTY_WHEEL_MESH    = 364  -- tiny invisible mesh: hides the engine's physics wheels so only the model's own wheels show
SEMI_PAL_TEX_ID          = 0    -- overridden tex0: our own faithful palette (every model colour)
SEMI_ITEM_SEEK           = 13950 -- /give item (the cab, alone)

-- The trailer is its OWN separate entity (a wheeled VehicleEntity). It is spawned
-- INDEPENDENTLY via /give SemiTrailer -- never together with the cab. They only
-- connect later, by backing the cab under its nose (added once this stands solo).
SEMI_TRAILER_VEH_ID      = -1     -- the standalone trailer entity (-1 until its define succeeds)
SEMI_TRAILER_ITEM_SEEK   = 13951  -- /give item that places a trailer on its own
SEMI_TWHEEL_STATE        = {}     -- [client] trailerId -> { spin, px, pz } for its bogie wheels

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
-- TYPE to reuse (5 = TRL for +x side, 6 = TRR for -x side). y = 0.4 (dropped
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
SEMI_KINGPIN_LOCAL_Y   = 1.20  -- kingpin pivot height up the gooseneck. HIGHER = trailer hangs LOWER
                               -- from the fifth wheel (held at this point). Raised from 0.77 to drop
                               -- the nose ~0.5 (was sitting half a wheel too high at the hitch).
SEMI_KINGPIN_TO_CENTRE = 2.5   -- kingpin z in front of trailer origin. LOWER = trailer sits FORWARD (closer
                               -- to the cab). Was 2.9 (sat too far back vs the old painted version); 2.5 matches it.
SEMI_HITCH_LEN         = 6.4   -- kingpin -> trailer rear bogie centre (the trailing arm; longer = bends less)
-- PAINTED-trailer offsets (v1.0.0 body mesh 371) -- separate from the parked-entity detection above
SEMI_PAINT_KINGPIN_Y   = 1.6   -- v1.0.0 coupling height for the painted body
SEMI_PAINT_KINGPIN_Z   = 2.5   -- v1.0.0 kingpin in front of the painted body origin
SEMI_PAINT_TRIM_Y      = 0.0   -- v1.0.0 vertical trim for the painted body
SEMI_COUPLED_CABS      = {}    -- [cabId]=true once THAT cab is coupled (per-cab so multiple rigs work)
SEMI_COUPLED_TRAILERS  = {}    -- [trailerId]=true once THAT trailer is hitched (so another cab won't grab it)
SEMI_COLLIDER_E        = nil   -- the spawned invisible heavy collider entity
SEMI_COLLIDER_TYPE_ID  = -1    -- (unused now) old separate-collider type id
SEMI_PARKED_TRIM_Y     = -0.74 -- vertical nudge for the PARKED painted body so its wheels meet the ground
SEMI_TRAILER_VEH_TYPE  = nil   -- the trailer EntityType (so we can hide its mesh on couple)
SEMI_SRV_TRX           = nil   -- server-side trailing bogie x (to pose the collider, matches the painted bend)
SEMI_SRV_TRZ           = nil
SEMI_HINGE             = nil   -- the live btHingeConstraint
SEMI_COUPLE_DIST       = 1.5   -- fifth wheel within this (horizontal) of a kingpin -> swap to painted
SEMI_CAB_COM_Y         = 0.3   -- cab centreOfMass is (0,-0.3,0); add this to turn cab mesh-local Y into body-local
SEMI_TRAILER_TRIM_Y    = -0.27 -- vertical nudge so the painted trailer's wheels meet the ground

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
	-- btVector3 here has no :add method -- build the +1Y sample point directly.
	if (lc:isZero()) then lc = W:getLightAtLocationv(turf.btVector3(pos:x(), pos:y() + 1, pos:z())); end
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
	TR:setMeshId(SEMI_PAINT_MESH_ID);
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
	VP.maxEngineForce      = 2700;   -- grunt to haul the 2200 trailer (3000 was a touch much)
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
	VP.dragCoefficent      = 9;      -- raised with the force so top speed stays the same -- more pull, not more speed
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
		local cabId = E:getId();
		if (not SEMI_COUPLED_CABS[cabId]) then
			local trailerE = semi_find_trailer(E);
			if (trailerE ~= nil) then
				local EC2 = E:getEntityContainer();
				local cb2 = E:getBody();
				local fw2 = turf.cloneBtTransform(cb2:getWorldTransform()):multv(
					turf.btVector3(0, SEMI_HITCH_LOCAL_Y + SEMI_CAB_COM_Y, SEMI_HITCH_LOCAL_Z));
				-- The parked trailer IS the heavy collider: hinge IT to the cab (no despawn, no spawn).
				-- It's invisible (empty mesh) and its render hook stops once coupled; the cab paints it.
				SEMI_COLLIDER_E = trailerE;
				local tb = trailerE:getBody();
				if (tb ~= nil) then
					pcall(function () tb:setIgnoreCollisionCheck(cb2, true); end);  -- don't collide with its OWN cab (nose overhangs it); the trailer is still solid to the rest of the world
					pcall(semi_make_hinge, cb2, tb, fw2, EC2);
				end
				SEMI_COUPLED_CABS[cabId] = true;
				SEMI_COUPLED_TRAILERS[trailerE:getId()] = true;
			end
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
		if (math.abs(fwddist) > 0.02) then                 -- ignore crawl-speed noise (dividing by tiny fwddist amplifies jitter)
			local dyaw   = semi_atan2(st.hx * hz - st.hz * hx, st.hx * hx + st.hz * hz);
			local target = math.atan(SEMI_WHEELBASE * dyaw / fwddist);
			if (target >  SEMI_STEER_CLAMP) then target =  SEMI_STEER_CLAMP;
			elseif (target < -SEMI_STEER_CLAMP) then target = -SEMI_STEER_CLAMP; end
			st.steer = st.steer + (target - st.steer) * 0.18;  -- heavier smoothing = less front-wheel jitter
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
	end

	-- The standalone trailer: its OWN wheeled VehicleEntity, defined LAST and
	-- pcall-guarded so a failure here can never cost the cab. Mesh 361 (body, drawn
	-- by the engine) + hull 363 collision; raycast wheels at a front support axle
	-- and the rear bogie so it stands level on its own and rolls. NEVER spawned with
	-- the cab -- only via /give SemiTrailer.
	do   -- no pcall so a define error surfaces in lua_errors (the cab is already registered above)
		local tid = EntityTypes:getNEntityTypes();
		local TV  = turf.BasicVehicleEntityType.genNew(tid);
		TV:setMeshId(SEMI_EMPTY_WHEEL_MESH);    -- invisible: the render hook paints the trailer (body 371 + wheels)
		TV:setHitboxId(SEMI_TRAILER_MESH_ID);   -- 361 -> hull 363 collision
		TV:setTextureId(SEMI_PAL_TEX_ID);
		TV:setMass(2200);                       -- HEAVY: this body IS the towing collider once coupled
		TV:setMaxHp(450);
		TV:setAngularDamping(0.60);  -- damp the side-to-side wobble (rotational drag only; pull is unaffected)
		local TVP = TV:getVehicleParameters();
		TVP.maxEngineForce      = 0;       -- towed: no power of its own
		TVP.maxBreakingForce    = 60.0;
		TVP.breakingIncrement   = 10.0;
		TVP.steeringClamp       = 0;       -- no steering
		TVP.wheelRadius         = 0.5;
		TVP.wheelWidth          = 0.35;
		TVP.wheelFriction       = 1200;
		TVP.suspensionStiffness = 150.0;  -- hold the 2200 rear up (60 sagged once the hull cleared the ground)
		TVP.suspensionDamping   = 4.0;
		TVP.suspensionCompression = 4.4;
		TVP.suspensionRestLength  = 0.7;  -- raise the chassis so the back sits level, not sunk
		TVP.maxSuspensionForce  = 350000;
		TVP.rollInfluence       = 0.0;   -- no roll transferred from wheels -> less lean
		TVP.dragCoefficent      = 4;
		TVP.centreOfMass        = turf.btVector3(0, 0, 0);  -- pin physics origin to mesh origin so wheels line up with the body
		TVP.wheelType           = SEMI_WHEEL_TYPE;        -- invisible raycast wheels
		TVP.nWheels             = 4;                      -- front support axle + rear bogie axle
		TVP.axleXPos            = 1.00;  -- VERY wide track (near the hull edge 1.15): max static roll resistance so the rigid trailer stays level. Invisible wheels, visuals unchanged
		TVP.axleZPos            = 3.4;                    -- scalar (symmetric); the array form {} was the likely failure
		TVP.spawnRate           = 0.0;
		TVP.spawnType           = turf.VehicleParameters.SPAWN_TYPE_NORMAL;
		TV.hasCustomPushRenderInstance = true;
		EntityTypes:pushEntityType(TV);
		SEMI_TRAILER_VEH_ID = TV:getId();
		SEMI_TRAILER_VEH_TYPE = TV;

		-- Invisible HEAVY collider: a real physics trailer with no visible mesh. Spawned on couple
		-- and hinged to the cab, so it carries genuine mass + momentum (plows through trees, can't
		-- be shoved). The smooth painted trailer is drawn on top of it for the visuals.
		local CTV = turf.BasicVehicleEntityType.genNew(EntityTypes:getNEntityTypes());
		CTV:setMeshId(SEMI_EMPTY_WHEEL_MESH);     -- invisible
		CTV:setHitboxId(SEMI_TRAILER_MESH_ID);    -- 361 -> hull 363 collision
		CTV:setTextureId(SEMI_PAL_TEX_ID);
		CTV:setMass(2200);                        -- HEAVY (the old towed body was 800)
		CTV:setMaxHp(99999);
		local CVP = CTV:getVehicleParameters();
		CVP.maxEngineForce      = 0;
		CVP.maxBreakingForce    = 60.0;
		CVP.steeringClamp       = 0;
		CVP.wheelRadius         = 0.5;
		CVP.wheelWidth          = 0.35;
		CVP.wheelFriction       = 1500;
		CVP.suspensionStiffness = 60.0;
		CVP.suspensionDamping   = 4.0;
		CVP.suspensionCompression = 4.4;
		CVP.suspensionRestLength  = 0.5;
		CVP.maxSuspensionForce  = 200000;
		CVP.rollInfluence       = 0.1;
		CVP.dragCoefficent      = 2;
		CVP.centreOfMass        = turf.btVector3(0, 0, 0);
		CVP.wheelType           = SEMI_WHEEL_TYPE;
		CVP.nWheels             = 4;
		CVP.axleXPos            = 0.49;
		CVP.axleZPos            = 3.4;
		CVP.spawnRate           = 0.0;
		CVP.spawnType           = turf.VehicleParameters.SPAWN_TYPE_NORMAL;
		EntityTypes:pushEntityType(CTV);
		SEMI_COLLIDER_TYPE_ID = CTV:getId();
		ENTITY_TYPES[SEMI_TRAILER_VEH_ID] = {};
		ENTITY_TYPES[SEMI_TRAILER_VEH_ID].pushRenderInstance = function (E, W) semi_render_parked_trailer(E, W); end
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

-- Draw the standalone trailer's four bogie wheels (spinning with travel). Renders
-- only THIS entity's own wheels -- never iterates other entities, so it can't race
-- a despawn the way the old coupling code did.
function semi_render_trailer_wheels (E, W)
	local body = E:getBody();
	if (body == nil) then return; end
	-- Position off the BODY transform directly (NOT the hitbox/hull transform) -- the
	-- hull transform shifts when the collision shape changes, which dragged the wheels
	-- away from the axles. The body frame is the mesh frame (CoM is unset/0).
	local base = turf.cloneBtTransform(body:getWorldTransform());
	local id = E:getId();
	local st = SEMI_TWHEEL_STATE[id];
	local o  = base:getOrigin();
	local px, pz = o:x(), o:z();
	local hx, hz = semi_level_forward(body:getWorldTransform());
	if (st == nil) then st = { spin = 0, px = px, pz = pz }; SEMI_TWHEEL_STATE[id] = st; end
	local fwddist = (px - st.px) * hx + (pz - st.pz) * hz;
	st.spin = st.spin + fwddist / SEMI_WHEEL_RADIUS;
	if (st.spin >  6.2831853) then st.spin = st.spin - 6.2831853;
	elseif (st.spin < -6.2831853) then st.spin = st.spin + 6.2831853; end
	st.px, st.pz = px, pz;
	local spinRot = turf.btTransform(turf.btQuaternion(turf.btVector3(1, 0, 0), st.spin), turf.btVector3(0, 0, 0));
	local ETC = E:getEntityContainer():getEntityTypeContainer();
	for i = 1, #SEMI_TRAILER_WHEELS do
		local tw = SEMI_TRAILER_WHEELS[i];
		local wd = turf.cloneBtTransform(base):mult(
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

-- ---- /give item: the trailer, on its own -----------------------------------
function define_semi_trailer_item (BlockTypes, ItemTypes)
	if (SEMI_TRAILER_VEH_ID < 0) then return; end
	local ITEM = turf.EntitySpawningItem.genNew("SemiTrailer", SEMI_TRAILER_VEH_ID);
	local dx, dy, dz = 3, 4, 11;
	ITEM.dimensions = turf.iVec3(dx, dy, dz);
	ITEM.offset     = turf.btVector3(dx * 0.5, dy * 0.5 - 0.5, dz * 0.5);
	ITEM.basecost   = 50000;
	ITEM.isSecret   = false;
	ITEM:setDesc("A semi-trailer. Spawn it on its own; later you back a Semi Truck under its nose to hook up.");
	ItemTypes:pushItemType(ITEM, SEMI_TRAILER_ITEM_SEEK, turf.Item.NULL_MORPH_ROOT);
	local IC = ItemTypes:genNewItemCategory("Semi Trailer");
	IC:pushItem(SEMI_TRAILER_ITEM_SEEK);
	return SEMI_TRAILER_ITEM_SEEK;
end

-- ---- registration ----------------------------------------------------------
if (ENTITY_TYPES == nil) then ENTITY_TYPES = {}; end
if (defineEntityTypesUserCallback == nil) then defineEntityTypesUserCallback = {}; end
defineEntityTypesUserCallback[#defineEntityTypesUserCallback + 1] = { "SemiTruckMod|semi cab + trailer entities", define_semi_truck }
if (defineOtherItemsUserCallback == nil) then defineOtherItemsUserCallback = {}; end
defineOtherItemsUserCallback[#defineOtherItemsUserCallback + 1] = { "SemiTruckMod|semi spawn item", define_semi_truck_item }
defineOtherItemsUserCallback[#defineOtherItemsUserCallback + 1] = { "SemiTruckMod|standalone trailer spawn item", define_semi_trailer_item }

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

-- ===================== TRAILER COUPLING (despawn-and-paint) =====================
-- The physics-constrained trailer was floppy and floated. Instead: a PARKED trailer
-- entity you drive up to; when the cab fifth wheel comes within SEMI_COUPLE_DIST of its
-- kingpin the SERVER despawns the parked entity and the CLIENT paints the trailer onto
-- the cab (smooth, bends -- see the cab render hook). semi_find_trailer is the shared
-- proximity test (no side effects) used by both sides.
function semi_find_trailer (cab)
	if (SEMI_TRAILER_VEH_ID < 0) then return nil; end
	local cabBody = cab:getBody();
	if (cabBody == nil) then return nil; end
	local EC = cab:getEntityContainer();
	if (EC == nil) then return nil; end
	local fwW = turf.cloneBtTransform(cabBody:getWorldTransform()):multv(
		turf.btVector3(0, SEMI_HITCH_LOCAL_Y + SEMI_CAB_COM_Y, SEMI_HITCH_LOCAL_Z));
	local n = EC:getNEntities();
	for i = 0, n - 1 do
		local e = EC:get(i);
		if (e ~= nil) then
			local et = e:getEntityType();
			if (et ~= nil and et:getId() == SEMI_TRAILER_VEH_ID and not SEMI_COUPLED_TRAILERS[e:getId()]) then
				local trBody = e:getBody();
				if (trBody ~= nil) then
					local kpW = turf.cloneBtTransform(trBody:getWorldTransform()):multv(
						turf.btVector3(0, SEMI_KINGPIN_LOCAL_Y, SEMI_KINGPIN_TO_CENTRE));
					local dx = fwW:x() - kpW:x();
					local dz = fwW:z() - kpW:z();
					if (dx * dx + dz * dz < SEMI_COUPLE_DIST * SEMI_COUPLE_DIST) then
						return e;
					end
				end
			end
		end
	end
	return nil;
end

-- Paint the trailer (v1.0.0 body mesh 371 + spinning bogie wheels) directly on its OWN
-- physics body, every frame -- parked AND towed. The visual rides the real collider, so
-- what you see is exactly what has the hitbox: back into a tree and the trailer stops.
-- (The cab no longer paints a separate trailer, so there is no double and no visual/collider
-- split.) SEMI_PARKED_TRIM_Y drops the body so mesh 371 sits on its wheels.
function semi_render_parked_trailer (E, W)
	local body = E:getBody();
	if (body == nil) then return; end
	local bt = body:getWorldTransform();
	local drawT = turf.cloneBtTransform(bt):mult(
		turf.btTransform(turf.btQuaternion(turf.btVector3(0, 1, 0), 0), turf.btVector3(0, SEMI_PARKED_TRIM_Y, 0)));
	local ETC = E:getEntityContainer():getEntityTypeContainer();
	local tet = ETC:get(SEMI_TRAILER_RENDER_TYPE);
	if (tet) then tet:pushRenderInstance(turf.EntityRenderingInstance(drawT, semi_light_at(W, drawT:getOrigin()), 0)); end
	-- spin the bogie wheels from how far the body has travelled this frame
	local id = E:getId();
	local st = SEMI_TWHEEL_STATE[id];
	local o  = bt:getOrigin();
	local px, pz = o:x(), o:z();
	local hx, hz = semi_level_forward(bt);
	if (st == nil) then st = { spin = 0, px = px, pz = pz }; SEMI_TWHEEL_STATE[id] = st; end
	local fwddist = (px - st.px) * hx + (pz - st.pz) * hz;
	st.spin = st.spin + fwddist / SEMI_WHEEL_RADIUS;
	if (st.spin >  6.2831853) then st.spin = st.spin - 6.2831853;
	elseif (st.spin < -6.2831853) then st.spin = st.spin + 6.2831853; end
	st.px, st.pz = px, pz;
	local spinRot = turf.btTransform(turf.btQuaternion(turf.btVector3(1, 0, 0), st.spin), turf.btVector3(0, 0, 0));
	for i = 1, #SEMI_TRAILER_WHEELS do
		local tw = SEMI_TRAILER_WHEELS[i];
		local wd = turf.cloneBtTransform(drawT):mult(
			turf.btTransform(turf.btQuaternion(turf.btVector3(0, 1, 0), 0), turf.btVector3(tw.x, tw.y, tw.z)));
		wd = wd:mult(spinRot);
		local twet = ETC:get(SEMI_WHEELS[tw.wi].typeId);
		if (twet) then twet:pushRenderInstance(turf.EntityRenderingInstance(wd, semi_light_at(W, wd:getOrigin()), 0)); end
	end
end

function semi_make_hinge (cabBody, trBody, fwW, EC)
	cabBody:activate(true);
	trBody:activate(true);
	trBody:setActivationState(4);
	-- snap the collider so its kingpin sits at the fifth wheel, aligned behind the cab
	local Rcab    = turf.cloneBtTransform(cabBody:getWorldTransform()):getRotation();
	local rotOnly = turf.btTransform(Rcab, turf.btVector3(0, 0, 0));
	local kpOff   = rotOnly:multv(turf.btVector3(0, SEMI_KINGPIN_LOCAL_Y, SEMI_KINGPIN_TO_CENTRE));
	trBody:setCenterOfMassTransform(turf.btTransform(Rcab,
		turf.btVector3(fwW:x() - kpOff:x(), fwW:y() - kpOff:y(), fwW:z() - kpOff:z())));
	trBody:setLinearVelocity(turf.btVector3(0, 0, 0));
	trBody:setAngularVelocity(turf.btVector3(0, 0, 0));
	-- BALL JOINT (point2point) at the fifth wheel: frees all rotation so the rear settles
	-- onto its wheels (pitch) and the rig bends (yaw). Roll is also free (some lean), but the
	-- universal-joint attempt to lock roll BROKE towing (couldn't pull, bounced) -- so we keep
	-- the ball joint. pivots = the fifth-wheel world point in each body's local frame.
	local pivotA = turf.cloneBtTransform(cabBody:getWorldTransform()):inverse():multv(fwW);
	local pivotB = turf.cloneBtTransform(trBody:getWorldTransform()):inverse():multv(fwW);
	local c      = turf.btPoint2PointConstraint.newAB(cabBody, trBody, pivotA, pivotB);
	local PH = EC:getWorld():getPhysicsHandler();
	if (not pcall(function () PH:addConstraint(c, true); end)) then PH:addConstraint(c); end  -- true = cab<->trailer don't collide (attached pair)
	SEMI_HINGE = c;
end
if (customFunc == nil) then customFunc = {}; end
SEMI_PREV_POLL_EXTRA = customFunc.pollServerTick_extra;
customFunc.pollServerTick_extra = function (NH)
	if (SEMI_PREV_POLL_EXTRA ~= nil) then SEMI_PREV_POLL_EXTRA(NH); end
	semi_install_fire_guard();
end
