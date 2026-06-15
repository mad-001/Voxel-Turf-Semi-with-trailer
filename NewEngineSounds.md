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

## 3. Known limitations of this approach (decide before polishing)

These are inherent to driving engine audio from Lua and should be acknowledged
in the design, not "fixed" by guesswork:

1. **One-shot, not a true loop.** VoxelTurf exposes no per-entity *looping*
   sound handle to Lua (looping-start exists only on the `Item` class; the C++
   engine owns real vehicle engine audio). So "continuous engine" = re-firing
   the ~4s sample by distance travelled. Timing only lines up at one speed:
   too fast → overlapping copies (chorus-y); too slow → audible gaps.

2. **Layers over the stock engine drone.** The cab is a
   `BasicVehicleEntityType`, so the engine already plays the global
   `ENGINE_*` car loop for it. Our diesel ADDS on top → possible double engine
   sound. Making the diesel the *only* engine sound would require overriding the
   global `ENGINE_*` tags, which changes every vanilla car — **explicitly off
   the table**.

3. **No RPM reactivity.** Distance-paced, not throttle-paced. `setLooping...
   PlaybackSpeed` only works on a looping id we don't have.

---

## 4. Options going forward (pick one)

- **A. Ship the fixed one-shot version** (Section 2) as a best-effort diesel
  layer, toggle `SEMI_ENGINE_SFX_ENABLE` and tune `SEMI_ENGINE_RETRIG_M` by ear.
  Accept the layering with the stock drone. *Lowest effort, testable now.*

- **B. Horn only.** Set `SEMI_ENGINE_SFX_ENABLE = false`, keep the air-horn
  (`sirenSoundTag = "SEMI_HORN"`, which works cleanly), and leave the engine as
  the stock car drone. *Zero risk, no double-up, no log spam.* **Recommended
  unless the layered diesel sounds good in testing.**

- **C. Investigate a real looping handle.** Confirm in-game whether any
  `SoundHandler` call returns a usable looping id (the API table lists
  `setLoopingSoundEffectLocation`/`stopSoundEffectLooping`/`...PlaybackSpeed`
  that all take an id — something must return one). If a start-looping method
  exists, switch to a single positioned loop with `...PlaybackSpeed` scaled by
  speed → a proper engine. *Best result, needs verification, no guessing.*

---

## 5. Testing

1. Rebuild/redeploy `SemiTruckMod` to the game `mods/` folder.
2. `/give SemiTruck`, drive it.
3. Watch `logs/mod_load_client.log` — confirm `SEMI_ENGINE_LOOP` /
   `SEMI_HORN` loaded with no errors.
4. Watch the client log while driving — the `playSoundEffectAtLocation` error
   must be **gone**.
5. Judge by ear: does the diesel layer acceptably over the stock drone, or is it
   doubled/choruser? Decide A vs B vs C.

---

## 6. Coordination note (important)

`SemiTruckMod/scripts/semitruck.lua` is being edited by **two conversations at
once** (engine-sound work + trailer/spawn work). That caused the half-applied
state. Before applying Section 2:
- one conversation should own `semitruck.lua` edits at a time, OR
- isolate the engine-sound code so it doesn't overlap the trailer/spawn code.

The trailer/`spawnEntity` investigation is **separate** from this bug — server
log is clean; fixing the sound id will not affect the trailer.
