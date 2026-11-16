# Pictures: every one the game shows, with a prompt for each
Drop each picture into `assets/ui/story/` under its file name (`.jpg`, `.png` or `.webp`, 16:9, about 1920x1080), then open the project in the Godot editor once (or run it with `--import`) so it picks them up. A name ending in `_1`, `_2`, `_3` is one of that picture's variants: the game picks among the ones present, a different one for each operation of that kind. A name with `_desert_` or `_winter_` in it (`op_column_desert_1`) is only shown in a campaign on a desert or a winter map; the plain ones everywhere else (and on a desert or winter map that has none of its own). Until a new key has any picture of its own, the older shared picture stands in for it (`offensive`, `logistics`, `military`, `energy`, `ew`, `hold`, `industry`, `capital`, `taken`, `fallen`).
Each prompt below is complete with the house style: copy it as it is. The pictures can show people (the game's characters only appear in the story now).

## Operations: the loading screen

Shown full screen while an operation loads, its name in the middle and then CLICK TO BEGIN. Each kind of operation has its own pictures; give it two or three (`_1`, `_2`, `_3`) and the game shows a different one each time that kind comes up. One is enough to start with.

### `op_column` — Stop the armour (enemy armoured columns driving for our border)

**op_column_1** (dawn, mud)
```
A long enemy armoured column grinding along a muddy country road at dawn, seen from a low hill beside the road. Tracked tanks and armoured personnel carriers nose to tail, dark olive with mud up to their hulls, exhaust smoke hanging in the cold air; a self-propelled anti-aircraft gun with a radar dish rides in the middle of the column. Bare birch trees, puddles reflecting a pale orange sky, a burnt-out farmhouse by the road. Far ahead on the horizon, a thin line of smoke marks the border. Mood: a slow, heavy threat that must be stopped before it arrives. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with pale orange dawn light and small red tail lights, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_column_2** (winter night)
```
An enemy tank column driving through a snowy pine forest at night, headlights dimmed to narrow blue slits, snow kicked up by the tracks, one tank commander's head and shoulders out of the hatch looking at the sky. A tracked anti-aircraft gun with twin cannons and a radar dish follows the lead tanks. Moonlight on the snow, long tree shadows across the road, falling snow catching the light. Overhead, very small and high, the silhouette of one of our drones. Mood: cold, quiet, inevitable. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with cold blue moonlight and small amber hatch light, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_column_3** (desert, dust)
```
An enemy armoured column racing across a desert highway at sunset, a huge plume of golden dust rising behind it. Tanks and wheeled armoured vehicles in sand camouflage, a truck-mounted anti-aircraft gun among them, sun glinting on periscopes. Wind-blown sand ripples, a broken road sign leaning in the sand, distant rocky mesas. Seen from above and to the side, like from a drone. Mood: speed and menace. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with hot golden sunset light and small red accents, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `op_train` — Stop the ammunition train

**op_train_1** (steppe, night)
```
A long ammunition train pulled by a dark diesel locomotive crossing an open steppe at night, seen from slightly above beside the line. Covered wagons and flat wagons loaded with ammunition crates under tarpaulins; on one flat wagon an anti-aircraft gun with its crew. The locomotive's headlight cuts a cone through low mist; sparks from the wheels, the rails gleaming. Telegraph poles along the line, a faint station light far ahead on the horizon. Mood: a race against time. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with warm headlight amber and small red signal lights, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_train_2** (bridge, snow)
```
An ammunition train crossing a steel truss railway bridge over a frozen river in a snowstorm, seen from the river bank below. The locomotive leads a line of wagons dusted with snow; an armoured anti-aircraft wagon with twin cannons is coupled behind the engine. Ice floes, snow-covered riverbanks, the bridge's girders black against a grey-white sky. Mood: one chance to stop it. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with cold grey-white light and warm amber engine light, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_train_3** (desert, sunset)
```
An ammunition train crossing a desert at sunset, its long shadow stretching across the sand. A rusty diesel locomotive, tank wagons and covered wagons, an anti-aircraft gun mounted on a flat wagon, the crew scanning the sky with binoculars. A water tower and a small stone station far ahead, heat haze bending the air above the rails. Mood: the supply line that feeds their front. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with orange and violet sunset light and small red accents, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `op_hunt` — Hunt the launchers (mobile rocket launchers firing from cover)

**op_hunt_1** (forest salvo)
```
A truck-mounted multiple rocket launcher firing a salvo from a clearing in a dark pine forest at night: rockets leaving the tubes in a rippling line of bright flames and white smoke trails arcing up into the sky, the whole clearing lit orange for an instant. Crew in dark uniforms crouch away with their hands over their ears; a second launcher waits under camouflage netting between the trees. Mood: they shoot and run. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with blinding orange rocket flames and deep forest shadows, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_hunt_2** (barn hide)
```
A mobile missile launcher truck hidden inside a half-ruined farm barn at dusk, its launch tube lowered, only its front visible through the broken doors. Outside, a muddy farmyard, a rusty tractor, chickens, a dirt track leading to a misty field. A soldier pulls a camouflage net over the barn door while looking nervously at the sky. Mood: hiding in plain sight. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with warm dusk light through the planks and a cold blue sky, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_hunt_3** (on the move)
```
Two mobile rocket launcher trucks speeding away along a field track at twilight, their launch tubes still smoking from a salvo, dust trailing behind them. Behind them, high in the sky, the white curving trails of their rockets. Seen from a drone's point of view high above and behind, a faint targeting reticle shape suggested only by the framing. Mood: the moment to strike before they vanish. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with fading purple twilight and small orange smoke glow, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `op_port` — Close the port (oil terminal, docks and cargo ships)

**op_port_1** (night harbour)
```
An enemy oil port at night: a long concrete quay with huge cylindrical oil storage tanks, loading pipes and gantry cranes, and a big cargo tanker moored alongside with its deck lights on. Two more ships wait in the dark water of the harbour. Floodlights on tall masts, reflections rippling on the black water, a flare stack burning with a tall flame. A mobile SAM launcher and an anti-aircraft gun stand on the quay by the tanks. Mood: their export, their money, their weak point. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with orange flare light and cold harbour floodlights, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_port_2** (foggy dawn)
```
A loaded oil tanker leaving a harbour in thick fog at dawn, seen from the end of a breakwater, its bow pushing a white wave, a tugboat alongside. Behind it, the port's cranes and storage tanks fade into the fog; the lights of the terminal glow faintly. Seagulls, wet concrete, a mooring bollard in the foreground. Mood: every ship that gets away pays for another raid. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with soft grey fog and pale gold dawn light, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_port_3** (storm at sea)
```
Cargo ships at anchor off an enemy coast in a storm, waves breaking against a rocky breakwater, rain slanting across the frame. In the distance on the shore, the port's oil tanks and cranes lit by floodlights, a radar dish turning on a hill above the harbour. Lightning briefly lights the clouds. Mood: dramatic, dangerous, the sea itself on their side. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with cold blue storm light and a flash of white lightning, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `op_grid` — Black out the grid (two power stations, repair crews mending them)

**op_grid_1** (cooling towers)
```
A big thermal power station at night: two huge hourglass cooling towers releasing thick steam lit orange from below, a tall red-and-white striped chimney with blinking red lights, rows of high-voltage pylons leading away into the dark. A mobile SAM launcher stands by the perimeter fence. Snow on the ground. Mood: the heart of their air defence's power. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with warm orange floodlight and small red and blue accents, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_grid_2** (repair crew)
```
A repair crew working on a damaged electrical substation at night under the floodlights of their utility trucks: men in helmets and reflective vests on a cherry picker, a transformer still smoking, blue sparks from a broken insulator, cables lying on the ground. A soldier with a rifle stands guard by an armoured truck and looks up at the sky. Mood: whatever we break, they mend by morning. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with harsh white work lights and electric blue sparks, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_grid_3** (hydro dam)
```
A hydroelectric dam in a mountain gorge at dusk, water roaring through the spillways in white plumes, the long concrete wall lined with lamps, power lines strung across the gorge on tall pylons. Anti-aircraft guns sit in sandbagged positions on the dam crest; a radar dish on the cliff above. Mood: enormous, fortified, vital. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with dusky violet light and warm lamp light, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `op_depot` — Silence the jammers (a jammer covering the depot that supplies their front)

**op_depot_1** (jammer trucks)
```
An enemy electronic warfare station on a bare hilltop at night: two military trucks with tall folding antenna masts and box-shaped jammer arrays aimed at the sky, a command cabin glowing green and cyan from its screens. Ripples of distortion bend the stars around the antennas like heat haze. High above, a small drone tumbles out of control, trailing smoke. Mood: an invisible wall. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with cyan screen glow and small red accents, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_depot_2** (depot convoy)
```
A line of covered military supply trucks leaving a big depot at night, headlights dimmed, rolling out through a gate in a barbed-wire fence. Inside the depot: stacks of ammunition crates under camouflage nets, fuel tanks, a forklift. On a mast above the depot, a jammer antenna array. An anti-aircraft gun on a truck rides with the convoy. Mood: the artery feeding their front. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with dim amber headlights and cold blue night, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_depot_3** (antenna field, desert)
```
A field of electronic warfare antennas and dish arrays in a rocky desert at sunset, cables running to a camouflaged command bunker, a generator truck humming beside it. Beyond it, a supply depot of tents and crates, and a dusty road with trucks heading towards the front. Heat haze and long shadows. Mood: strange, technological, guarded. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with hot orange sunset light and cyan screen glow, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `op_assault` — Hold the region (enemy armour driving on one of our towns)

**op_assault_1** (trench, dusk)
```
Our soldiers in a trench at the edge of a small town at dusk, looking out across an open field where enemy tanks and armoured vehicles are approaching in a wide line, dust and exhaust behind them. Beside the trench, our gun truck with a heavy machine gun in its bed and a mobile SAM launcher raising its tubes. The town behind with lit windows and a church tower. Mood: they must not reach the town. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with orange sunset light and small red tracer accents, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_assault_2** (street, night)
```
A town street at night braced for an assault: sandbags across a crossroads, an armoured anti-aircraft gun parked by a shop with boarded windows, its twin cannons raised, a soldier on a radio in a doorway. At the end of the street, beyond the last houses, the glow of approaching enemy headlights and the flashes of distant artillery. Mood: tense waiting. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with warm streetlamp light and white artillery flashes, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_assault_3** (winter field)
```
A snowy field before a village, enemy armour advancing through falling snow, tracks churning the white ground, a self-propelled anti-aircraft gun among them. In the foreground, our soldiers in white camouflage behind a low stone wall, one pointing, another raising binoculars. Mood: stand and hold. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with cold blue-white light and small amber engine glow, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `op_evac` — Evacuate the town (our convoy getting out under drone raids)

**op_evac_1** (night road)
```
A long line of civilian buses and covered trucks leaving a town on a dark country road at night, headlights off, only small red tail lights showing. Our gun truck with a heavy machine gun in its bed rides beside the column, its gunner watching the sky. Behind them, the town with a few fires burning. Mood: get everyone out alive. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with small red tail lights and a dim orange fire glow, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_evac_2** (morning, drones)
```
An evacuation convoy of trucks and buses on a straight road through flat farmland in the grey morning, a gun truck firing a stream of tracers at three small attack drones diving at the column. One drone is already falling in flames into the field. Mood: desperate protection. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with grey morning light and bright yellow-orange tracer fire, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `op_protect` — Keep the lines running (our factories under heavy raids)

**op_protect_1** (night shift)
```
Inside one of our big factory halls during an air alert at night: workers in overalls keep the assembly line of drone airframes running under dimmed red emergency lights, sparks from welding, a siren light turning on the wall. Through the high windows, the beams of searchlights and the flashes of air defence fire in the sky. Mood: work goes on. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with red emergency light and white welding sparks, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_protect_2** (plant under fire)
```
One of our industrial plants at night seen from outside: smokestacks, saw-tooth roofs, a SAM launcher by the fence firing a missile into the sky with a bright trail, an anti-aircraft gun spraying tracers. A burning hangar on one side, firefighters spraying water. Mood: defend the industry. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with orange fire light and white missile trails, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `op_survive` — Weather the storm (a massive raid on our capital)

**op_survive_1** (sky full of drones)
```
Our capital at night under a massive raid, seen from a rooftop: dozens of small enemy drones with red lights crossing the sky, searchlights sweeping, streams of tracers from anti-aircraft guns, the bright trails of SAMs climbing to meet them, a few explosions blooming in the clouds. The city below with its parliament dome and a tall TV tower. Mood: the longest night. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with red drone lights, white searchlights and orange explosions, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_survive_2** (shelter)
```
People sheltering in a deep metro station during an air raid: families on blankets on the platform, children asleep, an old man reading a newspaper, a soldier standing by the stairs; a train stands still with its doors open and its lights on. Faint thuds from above make dust fall from the ceiling. Mood: endurance, quiet courage. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with warm yellow station light and soft shadows, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `op_capital` — Strike at the heart (the final attack on the enemy capital)

**op_capital_1** (dome of searchlights)
```
The enemy capital at night across a wide river: grey concrete towers, a red-walled fortress with onion domes and a tall spire on a hill. The city is ringed with air defence: missile launchers on the river banks, radar dishes on rooftops, tracers rising; searchlights meet high above the city in a dome of light. Mood: the final, best defended target. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with cold white searchlights and red warning lights, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**op_capital_2** (strike coming in)
```
The enemy capital at dawn seen from high above and far away, as our missiles and drones streak in from the edge of the frame in long white trails towards the fortress on the hill; the city's air defence fires back in a fountain of tracers and interceptor trails. Mood: the war ends here. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with pale dawn light, white contrails and orange flashes, 16:9, 1920x1080. The lower middle of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

## Operation results

Shown full screen after an operation, OPERATION COMPLETE or FAILED over it in big letters and three small buttons. Two or three variants each (`_1`, `_2`, `_3`); the same operation's result always shows the same one.

### `win_attack` — An attack won: the region taken

**win_attack_1** (liberated town)
```
Our soldiers riding into a liberated small town on an armoured vehicle at golden hour, townspeople coming out of their damaged houses to greet them, an old woman handing a soldier a loaf of bread, children running alongside. Broken windows, scorched walls, but sunlight breaking through the smoke. Mood: relief and joy. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with warm golden light and soft smoke, 16:9, 1920x1080. The lower left quarter of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**win_attack_2** (burnt column)
```
The morning after a won battle: a long line of burnt-out enemy tanks and trucks on a country road, still smoking, seen from a low hill where two of our soldiers stand looking down, one lighting a cigarette. Mist in the fields, crows on the wrecks. Mood: quiet, earned victory. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with pale morning light and thin grey smoke, 16:9, 1920x1080. The lower left quarter of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**win_attack_3** (dark port)
```
An enemy port or power station at dawn after our strike: its tanks and buildings burnt and black, cranes bent, smoke drifting out to sea, the lights out. A single seagull on a broken bollard in the foreground. Mood: their war machine stopped. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with cold dawn light and dying orange embers, 16:9, 1920x1080. The lower left quarter of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `win_defence` — A defence held

**win_defence_1** (the sky clears)
```
Morning over one of our towns after a night of raids: the sky clearing to pale blue, smoke drifting away, our gun truck crew sitting on the bed of their pickup drinking tea from tin mugs, empty shell cases around them, the town behind them still standing. Mood: we held. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with soft clear morning light and warm steam from the mugs, 16:9, 1920x1080. The lower left quarter of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**win_defence_2** (SAM crew)
```
A SAM launcher crew at dawn standing beside their vehicle with its empty launch tubes, exhausted, one of them laughing, another looking up at the sky where the last contrails fade. Behind them, a town with lit windows. Mood: tired, proud. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with pink dawn light and fading white contrails, 16:9, 1920x1080. The lower left quarter of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**win_defence_3** (factory lights on)
```
One of our factories at night after a raid: its windows lit again, workers walking back in through the gate, a firefighter rolling up a hose, the anti-aircraft gun by the fence quiet now. Mood: life goes on. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with warm window light and cold blue night, 16:9, 1920x1080. The lower left quarter of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `loss_attack` — An attack failed

**loss_attack_1** (pulling back)
```
Our soldiers pulling back along a muddy road in the rain at dusk, tired and silent, a damaged truck being towed, wrecked drones lying in a field beside the road. In the distance, enemy searchlights still sweep the sky. Mood: a setback, not the end. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with grey rain light and a faint red glow on the horizon, 16:9, 1920x1080. The lower left quarter of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**loss_attack_2** (long night)
```
An empty command bunker late at night after a failed operation: the map table with its markers knocked over, a cold cup of coffee, a radio hissing static, a single lamp still burning. A commander's jacket hangs on the chair. Mood: we will try again. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with a single warm lamp in deep blue darkness, 16:9, 1920x1080. The lower left quarter of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `loss_defence` — A region lost

**loss_defence_1** (leaving home)
```
People leaving a town on foot and in old cars along a road at dusk, carrying suitcases and bags, a child holding a cat, smoke rising from the town behind them where enemy armour is entering. Mood: loss, but not defeat; we will be back. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with dim orange dusk light and grey smoke, 16:9, 1920x1080. The lower left quarter of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

**loss_defence_2** (enemy in the streets)
```
Enemy tanks rolling through the empty, damaged main street of one of our towns at dawn, past a fallen street lamp and a burnt bus; a curtain moves in an upstairs window. Mood: heavy, silent loss. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with cold grey dawn light and small orange fires, 16:9, 1920x1080. The lower left quarter of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

## Campaign story

Shown once each: the campaign's opening slides and its end.

### `intro_1` — Campaign intro, slide 1: the night the sirens started (already in the game)

**intro_1**
```
A wide cinematic view from the dark window of a high-rise apartment at 4 a.m., looking out over a sleeping Eastern European city of concrete apartment blocks, a few church domes and factory chimneys. On the rooftop in the foreground, a tall pole with a cluster of grey air-raid siren horns in silhouette. A single searchlight beam rises from the outskirts into low clouds; a dull red glow of a distant fire on the horizon. Mood: quiet dread just before the alarm. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with warm amber window light and small red accents, 16:9, 1920x1080. The bottom third of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `intro_2` — Campaign intro, slide 2: the drones cross the border (already in the game)

**intro_2**
```
Early dawn over flat farmland at a border: dark ploughed fields, a river reflecting a pale orange sky, a line of poplars and a small village far away. A swarm of twenty small delta-wing attack drones with pusher propellers flies low towards the viewer, black against the brightening sky; columns of smoke rise on the horizon behind them. Mood: the moment the war arrives. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with warm orange dawn light and small red navigation lights, 16:9, 1920x1080. The bottom third of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `intro_3` — Campaign intro, slide 3: your war now (already in the game)

**intro_3**
```
An underground command bunker at night: a commander seen from behind with both hands on a large map table lit by a single green-shaded lamp, the map split by a jagged red and blue front line, pins and paper markers on it. Staff officers at old radio sets with glowing amber dials in the shadows around. Mood: the start of a long campaign. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with warm amber lamp light against cold blue darkness, 16:9, 1920x1080. The bottom third of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `victory` — The campaign won (already in the game)

**victory**
```
A city square at dawn after the war: people embracing, soldiers lowering their helmets, a woman crying with joy, confetti and torn leaflets in the air, damaged buildings around but the sun rising gold behind a church dome. Mood: the war is over. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with warm golden sunrise and soft pastel accents, 16:9, 1920x1080. The bottom third of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

### `defeat` — The campaign lost (already in the game)

**defeat**
```
A grey empty road out of a burnt town in the rain, a single abandoned truck, a dog sitting by it, smoke over the horizon. Mood: the war is lost, quiet and heavy. Detailed 16-bit pixel art like a modern indie strategy game, crisp pixels with fine dithering, deep navy and charcoal palette with cold grey rain light and a faint red ember glow, 16:9, 1920x1080. The bottom third of the picture is darker, simple and empty: plain ground or shadow with no important details. A single full-frame illustration with no borders, frames, panels, bars, buttons, user interface or overlays. No text, letters, numbers, logos, flags or insignia; no real landmarks or real military markings.
```

## Home screen (already in the game)

`assets/ui/home_bg.jpg` (the main menu), `assets/ui/home_campaign.jpg` (the Campaign screen) and `assets/ui/home_war.jpg` (the New war screen) stay as they are.

## Achievements

The medals in `assets/ui/achievements/<id>.png` are drawn by `tools/medal_art.py`; a picture of your own under the same name replaces one (see the README there).
