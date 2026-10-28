# Air Alert (Strike Alert · Lite)

A second, much simpler game in the same project. Scene: `scenes/LiteMain.tscn`
(open it in the editor and press F6). All code is in `src/Lite/`; it shares only
the font and sound files in `assets/` with the main game.

## What it is
An air war on a live air-alert map in the style of map.ukrainealarm.com: a dark page,
flat grey regions with thin borders and white names, regions turning yellow under
air alert and light red under ballistic threat. Our country in the west, the enemy
(maroon) in the east, about as big as us or bigger. Both are jagged polygons, not
round blobs; regions are about the same size on both sides. Both capitals stand
equally far from the other country, so neither side starts closer. Every map is generated
from a seed; all names are fictional.

## The rules (the same for both sides)

### Economy and production
- Two kinds of building only: Factory and Air defence system.
- Factories earn money and production points (PP); a side earns a little of
  both with no factory at all. A factory whose region is under air alert works
  at half its pace: alerts cost the economy.
- Money pays for buildings and repairs. Every factory costs FactoryGrowth times
  the one before; every air defence system a fixed step more. Repairs run while
  switched on: damaged buildings get back a share of their health a second, at a
  price per share.
- Weapons are not bought: they are built from PP in one production queue that
  all factories work on, into a stockpile. Drone 5 PP, cruise missile 30, ballistic
  missile 80. With nothing queued the PP are lost; "Repeat" sends every finished
  weapon to the back of the queue again. Strikes launch from the stockpile, one
  by one or in salvos (1, 3, 6, all).
- Factories are built into a region, not a spot: the player picks a region with
  room and the factory goes to a free place in it. Front regions have room for
  2-3 factories, the middle 1-2, the deep rear 0-1, the capital's region one more;
  both sides get the same room in all. A destroyed factory leaves ruins that take
  its place for 3 minutes. Every 2 minutes industry shifts: on each side a region
  gains room, and half the time another loses a free place.
- A region holds at most 3 air defence systems, so air defence has to be spread
  and chosen, not piled up.
- A build tool stays in hand after each site, so several go down one click each;
  right-click, Esc or its button again puts it down.

### Targets, armor, damage
- Each capital has four key targets round it, each with its own health and
  armor: Headquarters, Command bunker, Energy centre, Government building.
  Destroying 3 of the 4 wins the war, for either side. They are always known to
  the other side.
- Factories and air defence are targets too, lightly armored.
- A hit deals max(MinDamage, warhead power − armor). Drones are weak (power 10),
  cruise missiles medium (60), ballistic missiles very strong (200): a swarm of
  drones does next to nothing to a bunker, a ballistic missile wrecks it. A
  site's tooltip shows its armor and what each weapon would do to it.

### Air defence
- A system sees and fires only inside its radar sector, a 120° cone out to its
  range. It faces the enemy capital when built; the owner drags from it to turn
  it, and it turns over a few seconds.
- It tracks at most 2 weapons at once; each channel fires an interceptor every
  1.6 seconds, with a chance to hit by weapon (drones easy, cruise medium,
  ballistic very hard). A weapon crossing the middle of the cone is shot at many
  times, one clipping its edge a few; many weapons from several directions at
  once are more than its channels can track. Shots cost nothing.
- So routes matter: around the cones, along their edges, from the side a system
  is not facing, or many at once.

### Weapons, routes, fog, alerts
- A click sends a salvo nearly straight (drones bend once, gently); dragging
  from our land to the target draws its route, which drones and cruise missiles
  follow (ballistic ones fly straight). A drone or missile whose site is
  destroyed before it arrives turns to another known site close by.
- The other side's sites are hidden until a drone or cruise missile flies near
  them or their air defence opens fire. Every 75 seconds each side's
  intelligence locates one hidden site of the other's (a factory if one is
  hidden); the player is told when the enemy has located one of our factories.
- The other side's drones and cruise missiles are hidden too, until they cross
  into our land or come within our air defence radar (half as far again as it
  shoots, all round); then they stay tracked. Ballistic launches are seen at once.
  Alerts sound only for what has been seen.
- Alerts follow what is in the air, not the routes: a region is under alert while
  a drone or cruise missile is over it or close by, or would reach it in a few
  seconds on its present heading. A ballistic launch alerts the target region
  and its neighbours (its fall is known). The all-clear comes a few seconds
  after the last threat.

### The enemy
- Production: it keeps a short queue topped up with what its stockpile lacks
  most, against a mix set by what it knows of us: drones for factories and air
  defence, cruise missiles where air defence stands, ballistic missiles for the
  key targets still standing.
- Raids: up to four known sites; for each, the weapons that do the most damage
  per PP after the losses it expects there, about as many as the site's health
  needs; routes round the air defence it knows of; a big group of drones splits
  and comes from two or three directions at once to saturate the defence;
  missiles timed to arrive with or after the drones. Scouts go to regions not yet
  flown over.
- Defence first: air defence round its capital (more as the war goes on), where
  our weapons came down, back where a system was destroyed, by its factories and
  key targets with spare money. Its systems turn towards where our weapons have
  been coming from. Factories go far from our capital, in regions with room.
- Massive strikes are a decision, not a schedule (Normal and Hard): it weighs
  what the sites it knows of are worth against the PP it would take to break
  through. When a strike is worth it and its stockpile can reach it within about
  four minutes, it starts massing; our intelligence notices (a feed warning, and
  the alert card says so until it comes).
- Difficulty: Easy raids go straight in rough numbers and never mass. Normal
  sizes and routes its raids and masses for strikes. Hard also sends cruise
  missiles ahead of a strike at the air defence that has shot down the most and
  feints with drones at the other end of the country. Enemy money and production:
  0.8 / 1.1 / 1.3 of ours, since its bigger country is harder to defend.

## How it looks
- The map is the screen; the right panel holds status (budget, both sides' key
  targets), BUILD, PRODUCTION with its queue, STRIKE with the stockpile, the
  feed and speed. An alert card sits on top of the map, the clock badge
  bottom-left.
- Flat, small icons; colour says whose: blue ours, red the enemy's.
- Air defence shows its radar sector as a faint cone and a tick for its facing;
  while it turns, a dashed line to where it will face.
- Weapons leave a track (drones dotted, missiles a fading line). Our own show the
  rest of their route dashed to a small cross at the target; the enemy's show only
  a short dashed heading as far as the alert reaches, a ballistic missile its whole
  fall.
- Fills ease between states; nothing blinks.
- A menu (Esc or the Menu chip) pauses the war: Continue, New war, Settings, Quit.
  Settings: sound, window/fullscreen, weapon routes, air defence ranges; kept in
  user://lite_settings.cfg with the last difficulty.

## Code
- `LiteRules.cs`: every tunable number. `LiteProduction.cs`: the queue and
  stockpile. `LiteDamage.cs`: armor and damage. `LiteAirDefence.cs`: sectors,
  tracking and fire. `LiteSim.cs`: the rest of the war. `LiteAi.cs`: the enemy.

## Rules for changes
- Keep it simple: every addition must create a decision for the player.
- Numbers live in `LiteRules` (LiteRules.cs).
- Checks: `--lite-sim=SECONDS --lite-seeds=N` (headless, AI against AI) and
  `--lite-shot=DIR` (self-closing screenshots; add `--lite-maps=N` for a picture
  of N maps first).
