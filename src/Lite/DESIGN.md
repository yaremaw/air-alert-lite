# Air Alert (Strike Alert · Lite)

A small air-war game. Scene: `scenes/LiteMain.tscn` (the main scene; F5 in the
editor). All code is in `src/Lite/`; the font and sounds are in `assets/`.

## What it is
An air war on a live air-alert map in the style of map.ukrainealarm.com: a dark page,
flat grey regions with thin borders and white names, regions turning yellow under
air alert and light red under ballistic threat. Our country in the west, the enemy
(maroon) in the east, about as big as us or bigger. Both are jagged polygons, not
round blobs; regions are about the same size on both sides. Both capitals stand
equally far from the other country, so neither side starts closer. Every map is generated
from a seed; all names are fictional.

## The rules (the same for both sides)
- Money comes mostly from factories (the capital earns a little). Factories also
  repair their capital, so a capital cannot be worn down while its factories work:
  hit the factories, and the air defence guarding them, first. Each factory costs
  more than the last. A factory whose region is under air alert works at a third
  of its pace, for money and repair alike: alerts cost the economy.
- Factories are built into a region, not a spot: the player picks a region with
  room and the factory goes to a free place in it. Front regions have room for
  2-3 factories, the middle 1-2, the deep rear 0-1, the capital's region one more;
  both sides get the same room in all. A destroyed factory leaves ruins that take
  its place for 3 minutes. Every 2 minutes industry shifts: on each side a region
  gains room, and half the time another loses a free place.
- Build on your own territory: Factory, AA gun (cheap, short range, drones only,
  free shots), SAM (long range, hits everything, each interceptor costs money).
- Strike at the other side's territory: drones (cheap, slow, wandering, reveal
  sites they fly over), cruise missiles (fast, accurate), ballistic missiles (very
  fast, hard to intercept). A salvo size of 1, 3 or 6 is launched per click.
  A click sends the salvo nearly straight (drones bend once, gently); dragging
  from our land to the target draws its route, which drones and cruise missiles
  follow (ballistic ones fly straight). A drone or missile whose site is
  destroyed before it arrives turns to another known site close by.
- The other side's sites are hidden until a drone or cruise missile flies near
  them or their air defence opens fire. Capitals are always known.
- The other side's drones and cruise missiles are hidden too, until they cross
  into our land or come within our air defence radar (half as far again as it
  shoots); then they stay tracked. Ballistic launches are seen at once. Alerts
  sound only for what has been seen.
- Alerts follow what is in the air, not the routes: a region is under alert while
  a drone or cruise missile is over it or close by, or would reach it in a few
  seconds on its present heading. Drones zigzag and come at the target from a
  side of their own, so where the alert goes next cannot be read off the map.
  A ballistic launch alerts the target region and its neighbours (its fall is
  known). The all-clear comes a few seconds after the last threat.
- The enemy AI saves part of its income for raids, builds factories away from
  the front, puts air defence where it was hit, scouts with drones when it knows
  nothing (scouts go to regions not yet flown over), sends each target about as
  many weapons as its health needs after the losses it expects there, up to four
  targets a raid, routes each round the air defence it knows of, times drones
  and missiles to arrive together, goes for factories
  first, for air defence when its last raid was shot down, and for the capital
  when it knows of no factory left.
- Every 75 seconds each side's intelligence locates one hidden site of the
  other's: a factory if one is hidden, else air defence. The player is told
  when the enemy has located one of our factories.
- The enemy defends first: SAMs and guns round its capital (more as the war
  goes on, paid from its war fund when short), a gun by every factory, air
  defence where weapons came down.
- Massive strikes are a decision, not a schedule (Normal and Hard): the enemy
  weighs what the sites it knows of are worth against what it would take to
  overwhelm the defence round them. When a strike is worth it and affordable
  within about four minutes, it starts massing; our intelligence notices (a
  feed warning, and the alert card says so until it comes). It then keeps small
  raids small and launches once the money is there: drones from all sides
  arriving together to drain the air defence, missiles behind them.
- Difficulty: Easy raids go straight in rough numbers and never mass. Normal
  sizes and routes its raids and masses for strikes. Hard also sends cruise
  missiles ahead of a strike at the air defence that has shot down the most and
  feints with drones at the other end of the country. Enemy income: 0.8 / 1.1 /
  1.3, since its bigger country is harder to defend.
- Destroy the enemy capital to win; lose yours and the game is over.

## How it looks
- The map is the screen; the right panel holds status, BUILD, STRIKE, the feed
  and speed. An alert card sits on top of the map, the clock badge bottom-left.
- Flat, small icons; colour says whose: blue ours, red the enemy's.
- Weapons leave a track (drones dotted, missiles a fading line). Our own show the
  rest of their route dashed to a small cross at the target; the enemy's show only
  a short dashed heading as far as the alert reaches, a ballistic missile its whole
  fall.
- Fills ease between states; nothing blinks.
- A menu (Esc or the Menu chip) pauses the war: Continue, New war, Settings, Quit.
  Settings: sound, window/fullscreen, weapon routes, air defence ranges; kept in
  user://lite_settings.cfg with the last difficulty.

## Rules for changes
- Keep it simple: every addition must create a decision for the player.
- Numbers live in `LiteRules` (LiteRules.gd).
- Checks: `--lite-sim=SECONDS --lite-seeds=N` (headless, AI against AI) and
  `--lite-shot=DIR` (self-closing screenshots; add `--lite-maps=N` for a picture
  of N maps first).
