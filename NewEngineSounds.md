# NewEngineSounds.md — fixing & finishing the semi diesel engine sound

Plan to fix the erroring engine-sound code and decide how the semi's diesel
engine sound should actually work. Scope: `SemiTruckMod` only, additive, no
vanilla sound replaced.

---

## 1. The bug (what's in the log)

Client log, every second:

```
bad argument #1 to 'playSoundEffectAtLocation' (number expected, got string)
```

**Root cause:** the engine-sound block in `semitruck.lua` (inside the cab's
`pushRenderInstance` hook) calls:

```lua
SH:playSoundEffectAtLocation(SEMI_ENGINE_SFX_TAG, base:getOrigin())
--                           ^ "SEMI_ENGINE_LOOP" (a STRING tag)
```

`SoundHandler:playSoundEffectAtLocation` wants a **numeric sfx id**, not the
string tag. (This matches how shipped code works: weapons/blocks always resolve
the tag to an id first via `SoundHandler:getSfxId("TAG")`, then pass the id.)
The earlier REFERENCE.md signature `playSoundEffectAtLocation(tag, pos)` was
misleading — "tag" there means the resolved id, not the string.

Result today: the diesel never plays, and the call throws ~once per render
frame → log spam. **Unrelated to the trailer issue** (server log is clean).

---

## 2. The fix (minimal, correct)

Resolve the tag to its numeric id **once** and reuse it — never resolve (or
error) every frame.

### Step 2a — cache the id
Add a module-level cache near the other `SEMI_ENGINE_*` constants:

```lua
SEMI_ENGINE_SFX_ID = nil   -- resolved lazily on the client (getSfxId)
```

### Step 2b — resolve lazily + guard, then play with the id
Replace the body of the engine block in `pushRenderInstance` with:

```lua
if (SEMI_ENGINE_SFX_ENABLE and not IS_SERVER) then
    if (st.engDist == nil) then st.engDist = SEMI_ENGINE_RETRIG_M; end
    if (math.abs(fwddist) > SEMI_ENGINE_MIN_MOVE) then
        st.engDist = st.engDist + math.abs(fwddist);
        if (st.engDist >= SEMI_ENGINE_RETRIG_M) then
            st.engDist = 0;
            local SH = turf.SoundHandler.getInstance();
            if (SH ~= nil) then
                -- resolve the string tag -> numeric id ONCE, then cache it
                if (SEMI_ENGINE_SFX_ID == nil) then
                    SEMI_ENGINE_SFX_ID = turf.SoundHandler.getInstanceC():getSfxId(SEMI_ENGINE_SFX_TAG);
                end
                if (SEMI_ENGINE_SFX_ID ~= nil and SEMI_ENGINE_SFX_ID >= 0) then
                    SH:playSoundEffectAtLocation(SEMI_ENGINE_SFX_ID, base:getOrigin());
                end
            end
        end
    end
end
```

Key changes vs current code:
- pass `SEMI_ENGINE_SFX_ID` (number) instead of `SEMI_ENGINE_SFX_TAG` (string)
- resolve via `getSfxId` once and cache → no per-frame work, no log spam
- guard `id >= 0` so a missing/typo'd tag fails silently instead of throwing

### Step 2c — verify the tag exists
`SemiTruckMod/sfx/sfx.txt` must define `SEMI_ENGINE_LOOP;semiengine.wav;0.7`
(additive — already present). If `getSfxId` returns -1, the sfx.txt didn't load
or the tag name is mismatched — check `logs/mod_load_client.log`.

---

## 3. Why the one-shot retrigger (Section 2) gaps — don't ship it as the engine

A one-shot plays its **full length** and is never cut off. The problem is
*pacing*: we'd retrigger by **distance travelled**, but the sample is a fixed
length in **time**. Those only line up at one speed:

- **Slow** → distance accrues slowly → next shot fires *after* the last ended →
  **silence gap**.
- **Fast** → next shot fires *before* the last ends → copies overlap → a
  **volume swell / flange**, not a clean engine.

To pace by *time* (fire every `sampleLen − overlap` s so it always overlaps
slightly and never gaps) we'd need a clock — and the client render hook gets no
`dt`/frame time, and counting frames is unreliable (FPS varies). **So the
one-shot cannot be made reliably gapless.** Keep Section 2 only as the immediate
error-killer / fallback, not the final engine.

Two facts that apply to *any* method here:
- **Layers over the stock engine drone.** The cab is a `BasicVehicleEntityType`,
  so the engine already plays the global `ENGINE_*` car loop for it. Our diesel
  ADDS on top. There is **no per-vehicle mute** (`VehicleParameters` exposes only
  `sirenSoundTag`). Diesel-only would mean overriding global `ENGINE_*` →
  changes every vanilla car → **off the table**. Keep diesel volume modest
  (0.5–0.7) so it complements.
- A **server** loop (`NetworkHandler:playSoundAt(name, pos, looping, 0, 0)`,
  the bank-vault alarm) pins the sound to a fixed point — wrong for a moving
  truck.

---

## 4. Recommended: a real CLIENT loop (gapless, RPM-reactive)

A true looping sound has **zero** gaps by definition: start once, move it with
the cab, pitch it with speed, stop it when the cab is gone. The `SoundHandler`
loop methods (`setLoopingSoundEffectLocation(id,pos)`,
`setLoopingSoundEffectPlaybackSpeed(id,speed)`, `stopSoundEffectLooping(id)`)
all take an **id**, so a start-that-returns-an-id must exist — it's just not in
the documented table (the equivalent is shown only on the `Item` class as
`playSoundEffectLoopingAtLocation(tag, pos)`).

**Orphan cleanup without a despawn hook:** the render hook simply *stops being
called* for a cab once it despawns / leaves view. So stamp `st.lastSeen` each
frame and run a small sweep that stops any loop whose `lastSeen` is stale. No
client despawn callback needed.

Target design (apply only after the probe in §4.1 confirms the start method):

```lua
-- per cab, first render: start ONE loop and keep its id on st
if (st.engLoop == nil) then
    st.engLoop = <START LOOP at base:getOrigin()>   -- id from the probe-confirmed call
end
-- every frame while it exists:
SH:setLoopingSoundEffectLocation(st.engLoop, base:getOrigin());
local rev = 0.85 + math.min(0.6, math.abs(fwddist) * SEMI_ENGINE_REV_K);  -- speed → pitch
SH:setLoopingSoundEffectPlaybackSpeed(st.engLoop, rev);
st.lastSeen = <frame counter>;
-- periodic sweep: for each tracked st, if (now - st.lastSeen) > N then
--     SH:stopSoundEffectLooping(st.engLoop); st.engLoop = nil
```

### 4.1 In-game probe FIRST (no guessing in shipped code)

Before wiring the loop, confirm the start method and its return by wrapping the
likely call in `pcall` and reading the client log. Paste this **temporarily** at
the top of the engine block in `pushRenderInstance` (fires once via a guard):

```lua
if (not IS_SERVER and SEMI_ENGINE_PROBE ~= true) then
    SEMI_ENGINE_PROBE = true;
    local SH  = turf.SoundHandler.getInstance();
    local sid = turf.SoundHandler.getInstanceC():getSfxId("SEMI_ENGINE_LOOP");
    print("LOOP PROBE: sfxId=", tostring(sid));
    -- candidate start methods — whichever does NOT error and returns an id wins:
    local ok1, id1 = pcall(function() return SH:playSoundEffectLoopingAtLocation(sid, base:getOrigin()); end);
    print("LOOP PROBE: playSoundEffectLoopingAtLocation ok=", ok1, " id=", tostring(id1));
    local ok2, id2 = pcall(function() return SH:playSoundEffectLooping(sid); end);
    print("LOOP PROBE: playSoundEffectLooping ok=", ok2, " id=", tostring(id2));
end
```

Read `logs` (client) for the `LOOP PROBE:` lines:
- If a call shows `ok= true` and a numeric `id=` → that's our start method; build
  §4 around it (and immediately `stopSoundEffectLooping(id)` the probe's own id
  so it doesn't leak).
- If both `ok= false` → report the error text; next candidates to try are
  `playLoopingSoundEffectAtLocation` / a 2-return form. Still no guessing in the
  shipped block — only the probe explores.

### 4.2 Fallbacks if no client loop-start exists

- **B. Horn only.** Set `SEMI_ENGINE_SFX_ENABLE = false`; keep the working
  air-horn (`sirenSoundTag = "SEMI_HORN"`). Zero risk, no double-up, no spam.
- **A. Keep the fixed one-shot** (Section 2) accepting the gaps/swell. Lowest
  fidelity; only if a rough diesel layer is wanted.

---

## 5. Testing

1. Rebuild/redeploy `SemiTruckMod` to the game `mods/` folder.
2. `/give SemiTruck`, drive it.
3. Watch `logs/mod_load_client.log` — confirm `SEMI_ENGINE_LOOP` / `SEMI_HORN`
   loaded with no errors.
4. **Probe run (§4.1):** read the `LOOP PROBE:` lines, pick the start method.
5. Wire §4, drive: engine should be continuous (no gaps) and pitch up with
   speed. Confirm the old `playSoundEffectAtLocation` error is gone.
6. Park / despawn a cab and confirm its loop stops (staleness sweep works — no
   stuck droning).
7. Judge the diesel against the stock drone; tune volume (sfx.txt) / `REV_K`.

---

## 6. Coordination note (important)

`SemiTruckMod/scripts/semitruck.lua` is being edited by **two conversations at
once** (engine-sound work + trailer/spawn work). That caused the half-applied
state. Before applying Section 2:
- one conversation should own `semitruck.lua` edits at a time, OR
- isolate the engine-sound code so it doesn't overlap the trailer/spawn code.

The trailer/`spawnEntity` investigation is **separate** from this bug — server
log is clean; fixing the sound id will not affect the trailer.
