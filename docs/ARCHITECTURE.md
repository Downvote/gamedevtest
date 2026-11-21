# Pixel Island: Architecture and Implementation Contract

The contract for the code in this repository (GitHub `Downvote/gamedevtest`). `docs/GAME_DESIGN.md` says what the game
does and why; this file says how the code is laid out, what each module offers and which data goes where. Where the
two disagree on an API, a type or a name, this file wins; on a number, `src/shared/Config/Tuning.luau` wins.

The build system, the conventions and much of the rendering code come from Random Bakery (`Downvote/test`, used
read-only as the reference: nothing there was changed). What was copied, and how it was changed, is listed in §12.

> The request (2026-11-14, GAME_DESIGN quotes it; its first two asks): "allow players to click on creatures to open up a
> menu seeing their details. also, there should a tip saying "New!" If the creature caught is new." (`WorldView`'s
> pick `palAt` and `openPal`, the `Pals` attribute's mutations, `Menus`' "pal" panel: §10.2, §10.4; `Tree.hatch`'s
> `new`, `Breed.turn`'s second list and Fx "turn" `fresh`, `HatchScene`'s `HatchNew` tag: §5, §10.11)
> The request (2026-11-14, GAME_DESIGN quotes it): "also, allow expansion up to level 20, you can make the previous
> levels of expansion a bit cheaper too. add decor, huts, work buildings, more egg rarities and creatures and other
> details as required for this" (twenty tiers: `Data/Street`'s `ISLES` and `Data/Office`'s plans to 20, every
> `Tuning` table by tier to 20 entries, `TierCost` a fifth lower up to tier 10, `LOT` north to z -232, piece
> coordinates -240 .. 64 (`Validate` `coord`, `Schema`), `index` to 8192, `Street.cellKey` with room for them; 39 new
> pieces in `Data/Buildings` with their models in `DecorModels`, `NatureModels`, `ThemeModels`, `ThemeMoreModels` and
> `FunModels`; the tree's stages 5 and 6; `BoostMax` 0.7; the `everdrift` preview, the Career's upgrades)

> The request (2026-11-14, GAME_DESIGN 4.5 quotes it): "also, add an inventory system to build mode, players can remove
> buildings to put them in their inventory. add a button to remove all buildings, remove all path/water etc, and a tool
> to quick remove buildings and paths" (`Profile.inv` and `ClientView.inv`, `Plot.store` / `unpaint` / `unfence` and a
> drawn look's swap into it, `Plot.place` / `paint` / `fence` from it first, `Plot.clear`, `Plot.sellHeld`,
> `Plot.cleanInv` in `Schema.reconcile`, the actions `plot.clear` and `inv.sell`; `BuildUI`'s Inventory tab, Sell,
> Remove all and Quick remove, the `mini_inv` and `mini_takeup` sprites; the `inventory` preview)

> The request (2026-11-21, GAME_DESIGN 4.7 quotes it): "Also, when placing things in build mode, allow the player to
> tap twice to place the building down. Also, add an undo button, selection tool and saving/loading of plots", and for
> computers "research on popular desktop tycoons and replicate their UIs" (`Logic/Undo`, `Logic/Layout`, the group
> actions in `Plot` (`moveMany`, `storeMany`, `copyMany`, `groupMoves`, `index`, `pricer`), `Profile.layouts` (save
> version 26), `ClientView.undo` and `layouts`, `Session.S.undo`, the actions `plot.undo`, `plot.moveMany`,
> `plot.storeMany`, `plot.copyMany`, `layout.save`, `layout.quote` and `layout.load` (§7.3); `BuildUI`'s tap twice,
> Undo button, Select tool, layouts' bar, tool tooltips and keys (§10.7), the `mini_undo`, `mini_select` and
> `mini_layouts` sprites; `tests/specs/Build.spec.luau`, `tools/sim/sim_build.luau`)

> The request (2026-11-13, GAME_DESIGN quotes it): "add a search button for the building ui." (`BuildUI`'s
> `SearchButton` and `focusSearch`, the `mini_search` sprite: §10.7)

> The request (2026-11-10, GAME_DESIGN quotes it with the choices made): "scrap this idea. could you make replicate
> beasty bay from kariosoft instead? still use the test repo as a reference" (an original island-village game in the
> genre: island building and farming, creature taming, expeditions and battles, villagers moving in, a shared sea)

> The request (2026-11-12, GAME_DESIGN quotes it with the choices made): "scrap the entire cave, fighting, level,
> skill and expedition system. instead, players start with a tree of life: it creates a creature every few seconds to
> be put into a pen. ..." (the expeditions' code is gone; the tree's pen, its levels and Equip best went on
> 2026-11-13, and the tree came back that day laying eggs, below)

> The request (2026-11-12, later): "remove villagers, only creatures should be enough" (no `Villager`, `folk`, homes,
> `folk.*` actions or Folk attribute; save version 11)

> The requests (2026-11-13, GAME_DESIGN quotes them with the talk before): "good idea, use the drifting in idea. you
> can remove the tree of life, there should now be a steady stream of driftlings, with rarities that players can pick
> up"; "also, make wood the main resource for building/expanding and shells the main resource of getting new
> driftlings. remove food as a resource"; later "make them float by just like a conveyer belt instead of drifting
> towards the island and stopping, with one every second" (what still holds: no `food`, eating or hunger; every piece
> priced in wood, `TierCost` in wood (its `TierCost[4]` was 150,000 then, 60,000 since the ten tiers), the Hatchery's
> feast in shells; the tide itself is gone again, below; its code is in this file's history up to commit 9d34e42)

> The request (2026-11-13, GAME_DESIGN 6): "never mind, bring back the tree of life and remove the
> converyer belt system. it now spawns eggs around it that the player can choose to hatch for some shells. ..."
> (`Logic/Tide` is `Logic/Tree` again: the tree a fixed 8 x 8 piece on every island (`Plot.isFixed`, ErrCode
> `fixed`), its eggs the profile's `clutch` (saved), mirrored as `ClientView.clutch` and the plot's `Eggs` attribute,
> drawn by `Controllers/EggView`; the action `egg.hatch` instead of `tide.take`; Fx "eggs" and "hatched"; no `Drift`,
> `s.tide`, `Street.TIDE`, `Tide` attribute, `TideView` or `Tide*` numbers; save version 13)

> And after it: "Also, make a limit of huts per island expansion level" (`Tuning.HutLimit`, `Plot.hutLimit`,
> `Plot.huts`, ErrCode `huts`)

> Then (2026-11-13, GAME_DESIGN 6): "Also, color each egg differently with different effects to allow players to
> distinguish easily between egg rarities" (`EggView.LOOK` and its sparks; the `egg_1` .. `egg_5` and `twinkle_*`
> sprites)

> The request (2026-11-13, the latest, GAME_DESIGN 4): "Make much, much more building options, like paths and fences.
> Polish the build ui more, just like the bakery game, and reference bloxburg. Also, add effects and polish when
> putting down decor and other amenities. There should be enough paths, fences and other detail to make a lot of
> vastly different themed islands. Also, add the ability to add water to make rivers. Make more island progression
> and allow the player to expand their land even more." (`Data/Buildings` with 245 pieces, their `tab`, `sub`, `water`
> and `feel` and the kinds `water` and `fence`; `Plot`'s tiles, water and fences with `plot.fence` and `plot.unfence`;
> ten tiers and `Tuning.FencePieces`; the model modules `Parts`, `GroundModels`, `FenceModels`, `NatureModels`,
> `ThemeModels`, `ThemeMoreModels` and `FunModels`; `BuildUI`'s catalog, `Controllers/BuildFx`, `Controllers/Puffs`
> and `UI/ThumbData`; save version 14)

> The requests (2026-11-13, GAME_DESIGN 2 and 6): "make the entire game feel more cozy, such as the pallette and other
> details to emphasize it. also, remove these, the eggs should be buyable only after the player clicks on the tree or
> enters the tree menu. also, make a cutscene for eggs hatching ..."; then "the egg hatching scene isnt detailed
> enough. add much much more detail to it, especially the egg. you are allowed to use 2d elements as well for the
> background"; then "There is no need to make things limited by squares and spheres, make everything more detailed
> with various shapes and textured objects. Also, like the bakery game, you can use 2d details ..." (no `EggHatch_`
> tags or `CardHatch_` buttons: `EggView.tapAt` and the HUD's `TreeCardTap` open the tree panel; `Tree.rise` and
> `Tuning.EggUp`, the result's `hr`; `Models/EggModels` (`build`, `hero`); `UI/HatchScene`, `UI/HatchBackdrop`;
> `Stage.clear` and the renderer's see-through sky; `Palette.modes.day` warm). Then "The creatures look blocky and
> unrealistic. Look at the cakes in the bakery game to reference how detailed they should be" and "could everything
> use a more pastelish colour pallette?" (`Models/DriftKit`, `Models/DriftPlansA..D`, `DriftModels.build`'s `lod`,
> `MicroModels.driftling(..., lod)`; the pastel `Data/Palette` colours and UI colours, `gen_art.py`'s `PAL`). Then
> "Can you use different eyes for each? Also, apply texture to each of them" (`Data/Creatures` eye, iris, tex, tex2;
> DriftKit's eye styles and `tuck`; `Render/DynTex`; Raster's `Shade` gets `t`; the renderer's `shadeTex`;
> `MicroModels.species`). Then (2026-11-14) "when i meant pastel color, i didnt mean desaturated it, i meant use more
> cozy colors. saturate the game back more. also, no need to use so much grass on the floor, it just looks noisy"
> (`Data/Palette` and `gen_art.py`'s `PAL` back from pastel and 15% fuller; `Shading.grassMark` and AmbientView's tufts
> thinned), and "could you also remove the transition that happens when clicking to hatch an egg? you can simply render
> the floating egg in a 2d background. also, make the player click to hatch the egg, each click revealing a mutation or
> a tier up upgrade if there is any, otherwise it just hatches" (`Stage.empty` and the renderer's empty stage, no bake;
> `UI/HatchScene` without the islet, the blinds or the timeline: a queue of reveals, one a tap; `Tuning.HatchSceneWait`
> and `HatchSceneHold` gone; `HatchScene.setWait` gone). Then, asked together: "make sounds when cracking the egg. also,
> make the egg rise up into view when it is being opened. also, there is a bug where the player snaps above buildings
> while walking over them. also, while the rare one quest is active or any rarity related quests, make it such that an
> egg of that rarity will always spawn in the tree of life. also, make the pallette more pinkish, changing the sand
> pink and the rest of the pallette to match. also, right now, the models simply move by rotating or moving parts of the
> mesh around. please use bones and rigging to make more realistic and detailed movement. follow and use as many
> animation principles when animating as well." (Audio `crack`, `crack_open`; HatchScene's `DROP` and `liftOf`;
> AvatarView's ground ray `RespectCanCollide`; `Tree.wanted` and `Tree.ensure`; `Data/Palette` with pink sand, then
> "not that pink, i meant a light pink, close to the color of actual sand"; `Models/DriftRig` and `Models/DriftMotion`) Then "also, expanding the island dosent have a good
> transition, it simply make the new land appear out of nowhere. could you make a transition such that it feels like the
> island grows out the new land smoothly?" (`Pixel/Grow`; `PixelRenderer.growNext`, `growing`, `growFront`, `afterGrow`,
> `growStats`; `Controllers/GrowFx`; `Tuning.GrowSecs`, `GrowArmSecs`; the `grow_surf` and `grow_sand` sounds; EggView's
> eggs waiting for the land) and "also, in build mode, make the camera still follow the player as they walk around, even
> though it is displaced downwards abit" (CameraController's Build mode follow and drag offset, `buildDrag`,
> `Tuning.CamBuildRecenter`; BuildUI's ghost following a still mouse)
> Then (with a picture of Random Bakery's HUD) "make the ui appear like this instead, with a black transparent background and make it neater. also, zoom into the
> island more such that there isnt too much sea in the screen"
> (`UIKit.glass`, `UIKit.row`, `GLASS_ALPHA`, `PANEL_ALPHA`, `ROW_ALPHA`, `DARK_ALPHA`, `PAD`; `Palette.ui` glass, veil,
> rule, xp; ghost and dark buttons; Hud's top bar, status panel and `Hud.statusLine`; `Tuning.CamFrame`)

## 1. Layout and tooling

```
default.project.json   Rojo: Shared -> ReplicatedStorage, Server -> ServerScriptService, Client -> StarterPlayerScripts;
                       characters on (the founder walks and jumps on the islands: JumpHeight 7.2)
src/shared/            Types, Net, Config (Tuning, Monetization), Data (content), Logic (pure rules), Render (pure pixel
                       maths, copied; Fx, the effects in the pixel layer), Models (procedural models), Locale (Lang and the nine generated language tables: docs/LOCALIZATION.md)
src/server/            Main.server.luau, Services/* (DataService, Session, Router, IslandService, PlotService)
src/client/            Main.client.luau, Controllers/* (StateClient, CameraController, WorldView, EggView,
                       AvatarView, StreetLife, AmbientView, Audio, DayLight, BuildFx, Puffs), Pixel/* (PixelRenderer, BakeCast, PixelText, Snapshot, ImageMemory), UI/* (UIKit, Hud,
                       Menus, BuildUI, StoreUI, FounderUI, SkyBackdrop, VisitUI, PixelSprites, ArtData and ThumbData (generated),
                       Words, PalTip)
src/first/             ReplicatedFirst.Loading (with Render/PixelFont and PixelFontData mapped beside it): Boot.client
                       (puts the loading card up first), LoadingCard, LoadingArt (generated: tools/preview/loading_art.sh)
src/RbxCharacterSounds.client.luau  an empty LocalScript in StarterPlayerScripts under the name Roblox would give its own
                       character sounds, so Roblox doesn't insert them (the founder's feet: Audio's step events)
tests/                 run.luau (spec runner), TestKit.luau, Career.luau (the Economy spec's player), career.luau (prints
                       its runs), specs/*.spec.luau
scripts/check.sh       the gate every change passes (§11)
scripts/gen_pixelfont.py  the pixel font's glyph tables (copied; README "Fonts and licences")
scripts/locale_strings.py the words the game can show, for the Lang spec (docs/LOCALIZATION.md 6; locale/ignore.txt,
                       locale/extra.txt)
scripts/gen_locale.py  locale/<code>.json -> src/shared/Locale/<code>.luau (the language tables; do not edit those)
scripts/gen_art.py     every interface sprite as a text mask -> UI/ArtData.luau (outline, anti-aliasing, shading;
                       `--png <file>` writes a contact sheet; GAME_DESIGN 2's rules; §10.10), and the build catalog's
                       pictures (scripts/thumbs.txt, drawn by tools/preview/thumbs.sh) -> UI/ThumbData.luau
tools/                 setup.sh (installs rojo, luau, luau-lsp), defs/ (Roblox API types), sim/ (the fake engine and
                       this game's scenarios), preview/ (PNG renders of the real game); tools/README.md
```

Rojo 7.4.4 (`rokit.toml`), luau-lsp 1.70.1 with `tools/defs/globalTypes.d.luau`, the plain Luau CLI for the specs.
Every file is `--!strict` (`.luaurc`). `X.server.luau` is a Script, `X.client.luau` a LocalScript, everything else a
ModuleScript; there are no `init.luau` files. (The Rojo project keeps its old name `byte-size-studio`; the place file
is `PixelIsland-<short hash>.rbxl`.)

## 2. Rules for the code

- Require by instance path only (`require(script.Parent.X)`, `require(ReplicatedStorage.Shared.Logic.X)`), never by
  string. Pure modules (`Types`, `Config/*`, `Data/*`, `Logic/*`, `Render/*`, `Locale/*`) use only the three forms
  `script.Parent.X`, `script.Parent.Parent.X`, `script.Parent.Parent.Folder.X`, because `scripts/check.sh` rewrites
  exactly those into string requires for the CLI copy the specs run on; they require only other pure modules and
  touch no Roblox API.
- The server decides everything. A client action is one Router request (a name and a payload) checked by
  `Logic/Validate`, answered `{ ok = true, data }` or `{ ok = false, err = ErrCode }`.
- Every number is in `Config/Tuning.luau`; every Roblox id is in `Config/Monetization.luau` (0 = not made yet). Each
  pass's and product's icon to upload is `art/products/<key>.png` (512 x 512 pixel art drawn from the game's models by
  `tools/preview/product_icons.sh`: a round badge for a pass, a rounded square for a product; the money on them is
  gold coins drawn in `product_icons.py`, `coin(cv, cx, cy, R, star?)`: two on Double Income, a heap of five in front
  of the Starter Pack's eggs). The game's own
  thumbnails (1920 x 1080) and icon (512 x 512) are `art/thumbnails/thumb_<n>_<name>.png` and `art/thumbnails/icon.png`
  (`tools/preview/game_thumbs.sh`: frames of the game drawn by its pixel filter with the HUD off and no founder in them
  and driftlings and eggs drawn alone through Pixel/Snapshot, laid out as pixel illustrations by
  `tools/preview/game_thumbs.py`, `genre_thumbs.py` and `illustrate.py`, every word lettered on its picture's own grid;
  `thumb_0_days.png` leads, the genre's before and after on a 2x grid; `thumb_1_rarity` .. `thumb_5_rich` are the
  genre's other frames, the close-up and the egg on the 4x grid, the ladder, the meadow and the big number on the 2x
  one; the icon is on a 256 x 256 grid; GAME_DESIGN 11.1).
  Every outline in these and in the loading card's art is a darker step of the colour beside it, never flat ink
  (GAME_DESIGN 2): `product_icons.py`'s `Canvas.edge` and `outline` draw a shape's outline in ink and `Canvas.finish`
  gives each pixel still showing `ink_of` the colours it rings; a word's outline and depth are `ink_of(face, 0.3,
  0.3)`; `gen_thumbs.py` (`fit_colours`) and `gen_loading_art.py` merge a picture's closest colours when its outline
  steps take it past the colours a character can name.
- One function stays under 200 locals and upvalues (luau-compile checks it).
- Player-visible text goes through `Locale/Lang.t` (ten languages since 2026-11-20: docs/LOCALIZATION.md). A sentence
  built in code is a whole template (`Lang.f`, `Lang.fmt`, `Lang.an` for "a" / "an"), never English pieces glued
  together; new words go into every `locale/<code>.json` in the same change (`scripts/check.sh` fails otherwise).
- Some modules keep the names of the games before this one (the plots along a "street", the island's tiers an
  "office"): `Data/Street` is the islands in the sky (no sea since 2026-11-20), `Data/Office` the island's tiers (their names),
  `Models/DecorModels` builds every building, `Models/StreetModels` the floating islands,
  `Models/MicroModels` the driftlings and the island's small moving things.

## 3. Types (`src/shared/Types.luau`)

`Look` (`{ skin, hair, style, shirt }` indices into Data/Looks, and `hat? face? neck? back? hand? top?`: a Data/Cosmetics id
worn in that slot, only an owned one of that slot (`Schema.reconcile`, `Store.wear`); 2026-11-14; since 2026-11-20, the
bakery's customization screen, `bangs? hair2? eye? eye2? apron? turn?` and `hatTint? faceTint? neckTint? backTint?
handTint? topTint? apronTint?`, more indices into Data/Looks, kept only when not their default), `Profile.outfits` and
`ClientView.outfits` (`{ string }`: up to `Tuning.MaxOutfits` saved looks, each `Looks.encode`), `Bagged` (an egg held
in the bag, `{ id, r }`: Logic/Store's products and rewards, hatched for nothing by `Tree.hatchBag`), `Track` (the pass
track: `{ s (the season these points are for), xp, got, gotP (the levels whose free / premium reward was claimed) }`),
`Piece` (`{ uid, id, x, z, rot, lvl }`: anything standing on the island; `uid` stays while it stands; `lvl` a
level kept from an older save, else 1; (x, z) its footprint's north-west corner, plot-local, -240 .. 64; a path or water
tile's on even studs at rot 0; a fence length's an even grid corner and `rot` its way, 0 east or 90 south), `PlotSave`
(`{ placed }`), `Pal` (a driftling: `{ id, sp, home (a hut's Piece uid; 0: no hut, as when its hut was cleared away or
made smaller: it waits for room, `Tree.settle`), work (a Piece uid, 0 resting; only one in a hut works), muts? (its
mutations, Data/Traits ids), pin? (true: the player placed it by hand, so `Island.arrange` leaves it; kept in the save
only while it lives in a hut; 2026-11-14) }`; no `held` since the pen went), `Laid` (an egg the Tree of Life laid: `{ id (its own id,
not a Pal id), r (its rarity, 1 .. 9 (`Traits.RMAX`): its look, `EggView.LOOK`), cost? (only on the client's copy: `Tree.cost` on this
island now), ss? (the season it was laid in, a Data/Weather season id), wx? (the weather that touched it, a
Data/Weather kind id with a mutation family), wt? (that touch's tier, 1 .. 4) }`; what hatches is rolled when it is
hatched; ss, wx and wt are kept by `Schema.reconcile` only when known, wt only with wx (GAME_DESIGN 13)), `Clutch` (the tree's eggs, saved: `{ left (seconds till the
next lot), list: { Laid }, next (the next egg's id) }`), `Settings` (`{ pixel, music?, sfx?, zoom?, screen?, lang?, text? }`: music and sfx "on" | "off"; lang "auto" or a
`Lang.LIST` code, text "pixel" | "smooth" (2026-11-20, docs/LOCALIZATION.md: reconcile makes anything else "auto" and
"pixel"); the Settings panel), `Stats`
(`{ days, built, earned, taken (eggs hatched from the tree; the driftlings taken in off the tide and the ones the old
tree grew before version 13), sold (driftlings sold), best (the rarest had), hatched (the Hatcheries' eggs hatched) }`),
`Egg` (a Hatchery's: `{ uid (its Hatchery), a, b (the parents' ids), sp, muts, left (turns) }`, one a Hatchery),
`Profile` (the save, version 26 (Build mode's saved layouts, 2026-11-21: `layouts` (`{ LayoutSave }`, always
`Tuning.LayoutSlots` of them: `LayoutSave { at (os.time when saved, 0 empty), tier (the island's then), n (its pieces,
the tree apart), code (`Layout.pack`'s string, "" empty) }`); an older save gets every slot empty, `Layout.clean`
cleans them on every load); 25 (the tips in a new order, 2026-11-21: `tut` 1 a hut, 2 an egg, 3 a workplace, 4 the last (they were 1 a camp, 2 a farm, 3 a hut, 4 an egg, 5 a shop, 6 the last: 1, 2, 3 -> 1; 4 -> 2; 5 -> 3; 6 -> 4), and the questline opening on four huts with Build another hut gone: a save on the questline (`tut` 0, or a quest past the first) keeps its quest, the first four one place later, the fifth on to the sixth); 24 (the leaderboards and friends, 2026-11-21: `social` (`Social`: `referredBy` (the inviter's user id, 0 for none), `refPaid` (the inviter's reward went out), `refPlay` (seconds played toward it, up to `ReferralMinPlaySec`), `invited` and `refDay` / `refToday` (the inviter's friends rewarded, in all and on that UTC day), `here` (Roblox friends on this server: never kept, 0 at every load, `Schema.social`)); an older save gets it fresh); 23 (the View slider's default moved to the seventh notch, 2026-11-20, "also, make the default view here": a save still on the sixth, the default every save wrote since 18, loses it and reconcile gives it the new one; `settings.zoom`); 20 (the rewards for coming back and playing, 2026-11-19: `rewards` (`RewardsSave`:
`daily { last (UTC day), streak, best, miles }`, `play { day, secs, got }`, `tasks { day, list { TaskSave { id, n, at } },
got, bonus }`, `spin { day, extra, total }`, `codes` (code -> true), `index { got }`) and `boosts` (timed boost id ->
seconds left); an older save gets them fresh); 19 (the questline lost its fourth quest, Another camp, 2026-11-18: `quest` past it moves
back one, so a save stays on the quest it was on); 18 (the View slider's default moved to the sixth notch, 2026-11-18: a save still on
the eighth, the first default, loses it and reconcile gives it the new one; `settings.zoom`); 17 (offline earnings and the group, 2026-11-14: `seenAt` (the sea's clock when the island
was last open, set every second while it is; 0 unknown: an older save earns nothing for its time away), `group`
(`Group = { member, gift }`: in the group at the last check, its gift given)); 16 (the store, 2026-11-14: `passes` (pass key -> true, checked again at every join),
`receipts` (the last 50 developer product PurchaseIds paid), `gifts` (`starter`, `vip`: the one-time gifts given),
`vipDay` (the UTC day VIP's daily gift was claimed), `bag` ({ Bagged }), `owned` (cosmetic id -> true), `titles` (title
id -> true; everyone has `newcomer`), `title` (worn, "" none), `shop` (`{ at, n }`: the rotation the refreshes bought
count for), `track`); before that 15: `shells` (the one store since 2026-11-14: eggs, building, growing; no `wood`), `day`,
`tier`, `founder`,
`pals`, `plot`, `seen` (species -> 2 had one, the Index; 1, seen on the tide, only in a save from then), `eggs` (the
Hatcheries'), `clutch` (the tree's), `inv` (Build mode's inventory since 2026-11-14: a piece id -> how many wait there,
1 .. `Plot.INV_MAX`; never the tree; no version bump: `Schema.reconcile` gives an old save `{}`), `nextId` (driftlings
and pieces share it), `tut` (1 .. 4, `Plot.TIP_HUT` .. `TIP_LAST`, 0 done), `quest` (the
questline's quest on the go, Data/Quests; one past the last: all done), `stats`, `settings`, `createdAt`; no `food` or
`tree` levels), `ClientView` (the profile's fields, `inv` among them, `undo` (the steps Build mode's Undo can take back this session:
`#Session.S.undo`), `layouts` (each slot's `{ at, tier, n }`: `Layout.view`, never the codes), `social` (`Social.view`: `{ invited, todayLeft, here, boost, referred }`), plus `dayFrac`, `plot` (the plot index), `pieces`, `rates` (`{ shells
}` a turn, the charm bonus in), `charm`, `charmBonus` (`Island.charmBonus` of it: 0.25 = +25%), `nests` (the huts'
room); no `wood`, no `visitors`; `pals` is every driftling; `clutch` the tree's eggs
now (`{ Laid }`, each with its `cost`), `clutchLeft` the seconds till the next lot, `clutchSecs` the seconds between two
(`Tree.secs`: 360, 180 with the Quick Tree pass), `turnIn` the seconds to the island's next turn (the Hatcheries'
timers; an `Egg` with `left` 0 is ready and waits for `breed.hatch`); the store's (`passes gifts vipDay bag owned titles title track` as saved,
`shopList` (the rotating shop's pieces now), `shopLeft` (seconds till it turns over), `shopRefresh` (refreshes bought in
this rotation), `trackLevel`, `trackInto`, `trackNeed` (`Store.level`), `trackLeft` (seconds left in the season),
`minuteShells` (`Store.perMinute`: what a minutes-of-shells reward pays a minute), `incomeMult` (`Island.passMult`: the passes and the group), `offline` (`OfflineReport = { away, secs, shells }` waiting to
be collected, else false), `offlineHours`, `offlinePct` (`Store.offlineCap` / 3600, `Store.offlinePct`), `offlineDouble`
(`Store.offlineDouble`: Collect x2 free), `group`, `groupOn` (`Monetization.Group.Id` set)); `clock` the sea's clock (`WorldClock.now`) when the view was made (the season and the weather: also
patched by every tick); no `tide` or `tideSecs`), `ErrCode` (with `hatcheries`: the island has all the Hatcheries its tier allows, 2026-11-14; `boosts`: the island has two of that boost building already, 2026-11-20; `no_hut`: no hut built to hatch into; `full`: no room in that
hut, every hut full for an `egg.hatch` with no swap, or the island's piece, tile or fence limit reached; `fixed`: the
Tree of Life can't be cleared away; `huts`: the island's huts' limit reached; `work`: its work cap reached (a
workplace whose places won't fit, 2026-11-18); `money`: not enough shells; no `food`, no
`wood` since 2026-11-14),
`Response`, and the utility types `Connection`, `Signal<T...>`, `Rng`, `PixelTier`. The file is the reference for
every field.

## 4. Config

- `Config/Tuning.luau`: persistence (`DataStoreName = "BSS_Profile_v1"`, never renamed), the island (`BuildingPrice`
  (0.3: the Work and Huts tabs' buildings cost this share of their listed price, Data/Buildings `priceOf`: "make it
  much cheaper to buy work and hut buildings"), `WoodShells` (5), `WoodTierUp` (1.8) and `WoodTierTop` (7: a price that
  was wood is WoodShells shells a wood, times WoodTierUp for each tier past the second up to WoodTierTop, to two
  figures: every piece's,
  `Buildings.shellsFor`, and growing the island's, `Island.expandCost`; GAME_DESIGN 4, 10), `StartShells` (600: the
  tips' buildings, 405, and two eggs for the first hut, a rare and a common, so no tip waits on shells; `StartWood` went with the wood), `TurnSeconds` (the island's pace),
  `DaySeconds` (the sea's day: hours), `SkyDaySecs` (1200: the sky's own day round the floating islands, midnight to
  midnight, UI/SkyBackdrop; only the sky follows it), `IdleOutput` (a building's work with nobody at it), `PalWork` (a common
  driftling's), `RarityWork` (a driftling's work by its rarity), `WorkRoom` (the driftlings a workplace takes by the tier it opens at: 2 on the first island, then since 2026-11-19 as
many as that tier's newest hut holds, 8, 10, 12, 16, 18 (tiers 6 to 10), 22, 26, 30, 34; Data/Buildings' `jobs`; it was
`HelpMax`, 2 everywhere, until 2026-11-18, then 6, 8, 10, 12, 16, 20 to 32), `CharmMax` (1) and
  `CharmHalf` (200: charm's bonus to every shell, `Island.charmBonus`; the visitors' numbers went on 2026-11-14),
  `DecorCharm` (by island tier, 1, 1, 1, 2, 2, 3, 4 ... 15, 17, 19: every decor piece's charm for each tile of its footprint, `Buildings.charmOf`),
  `Refund` (0.5: Replace's share of the old piece's price, and what an inventory piece sells for; nothing taken off the
  island is paid back since 2026-11-14: it goes into the inventory), `UpgradeMult` (a level from an older save; no
  upgrades since 2026-11-11), `TierCost` (the wood to grow to
  each of the twenty tiers, paid in shells at `WoodShells` (5), `WoodTierUp` (1.8) and `WoodTierTop` (7: the growth
  stops there): 0, 480, 7,200, 48,000, 128,000, 300,000, 640,000, 1,280,000, 2,400,000, 4,000,000, then 5,000,000,
  6,000,000, 7,200,000, 8,600,000, 10,200,000, 12,000,000, 14,000,000, 16,500,000, 19,500,000, 23,000,000; every table
  by tier has twenty entries, and the top tier is `#TierCost`, GAME_DESIGN 4.4), `ComfortLvl`, `BoostMax` (0.7); no `StartFood`,
  `EatPal` or `Hungry` since food went), the Tree of Life's eggs (GAME_DESIGN 6: `EggSecs` (360: seconds between two
  lots, six minutes since 2026-11-17: "make the default time for egg refresh 6 minutes, and 3 minutes with gamepass";
  `EggSecsPass` 180 with the Quick Tree pass), `EggCount` (eggs a lot by the island's tier: 7, 8, 9, 10, 11, 12 from tier 6, 13 from 13, 14 from 17; two more on every tier since 2026-11-14), `EggPrice`
  (shells by rarity, seven of them: 8, 36, 160, 800, 4,000, 24,000, 160,000), `EggTier` (the price's multiplier by the
  island's tier: 1, 2, 5, 12, 27, 54, 96, 160, 250, 380, then 460, 540, 640, 750, 880, 1,040, 1,220, 1,440, 1,700,
  2,000; about a quarter of the old prices since 2026-11-14, "make eggs much cheaper"), `EggLuck` (the luck by tier: 0, 0.25, 0.5, 0.75, 1, 1.3, 1.6, 1.9, 2.2, 2.6, then 2.8 up by 0.2 a tier
  to 4.6), `EggMutTier` (2: tiers for a hatchling's mutation roll one rarity up), `EggUp` (an egg's chance a step to turn
  rarer as it hatches, by rarity: 0.12, 0.08, 0.05, 0.025, 0.012, 0.006, twice the old since 2026-11-14), `TreeStage` (the tree model's stage by tier:
  1, 2, 2, 3, 3, 4 from tier 6, 5 from 11, 6 from 16), `HutTree`,
  `HutLuck`, `HutCost` (the huts' tree, luck and cost shares at most: 0.5 each), `SellPrice` (by rarity), `SellTier` (a
  mutation tier's share on a price); none of the tide's `TideSecs`, `TideLife`, `TidePrice`, `TideTier`, `TideRare`,
  `TideLuck`, `TideMutTier` or `HutTide`, and none of the old tree's `TreeSecs`, `TreeLuck`, `TreeMutLuck`,
  `TreeSpeedCost`, `TreeLuckCost`, `PenSafe`, `PenShown` or `TreeStages`), breeding (`BreedShells` (an egg's price by the
  child's rarity), `BreedTurns`, `BreedKeep`, `BreedTierUp`, `BreedNew`), the island's lean (`MutLean`, `MutLeanFloor`),
  the founders' doze (`DozeSecs` 40), the boost buildings' stacking (`BoostStack` 0.5), the server's step and rate limit, the sea
  (`MaxPlots`, `PlotSpacing` (170 since 2026-11-20: the islands are whole and round from the start, so a channel of
  sea stays between two), `PlotPieces` (buildings and decor by tier: 36, 60, 90, 130, 180, 240, 300, 370, 450, 540,
  then 60 more a tier to 1,140), `HousingLimit` (the driftlings an island's huts may house together by its tier, however many huts: since 2026-11-19
  ("buying 2 huts and 2 work buildings of the highest tier is enough to fill the cap") each tier adds two of its newest
  hut's `slots`: 8, 24, 44, 68, 100, 136, 172, 208, 244, 280, 324, 368, 412, 464, 516, 568, 628, 688, 748, 816 (it was 8,
  24, 40, 60, 96, 168 .. 840; `Plot.spec` holds the rule for huts and workplaces both); 2026-11-14, it was `HutLimit`, a
  count of huts), `HatcheryLimit` (Hatcheries by tier: 0, 0, then 1 from tier 3, 2 from 6, 3 from 10, 4 from 14, 5 from 18), `PathPieces` (path and
  water tiles together: 80, 150, 240, 340, 460, 600, 750, 900, 1,050, 1,200, then 120 more a tier to 2,400),
  `FencePieces` (fence lengths: 40, 80, 130, 180, 240, 300, 370, 440, 520, 600, then 60 more a tier to 1,200),
  `HomeCooldown`, `WalkSpeed`, `JumpHeight`; no `SwimSpeed` since the islands took to the sky), and the camera and pixel filter values (Random Bakery's `CamYaw` 45,
  `CamPitch` 30, `PixelTiers`, `PixelScaleMin` / `PixelScaleSides`; this game's `CamRayBack`, `PixelMaxRayDist`,
  `CamFollowBox`, `CamFollowSecs` (0.2: the follow's smooth time), `CamBuildPan`, `CamBuildRecenter` (0.12: the share of Build mode's drag given back each
  frame the founder walks), `PixelPanRays`, `PixelPanCacheTiles` (768: the pan cache's tiles at most, 0 off),
`PixelInvalidateRaysFrame`, `PixelInvalidateMs` (8: the re-casts' time a frame at most, besides their rays), `PixelPreCastMs` (2: the time a frame given to casting the next tier ahead, 0 off), `PixelMaxDyn` (80: models drawn afresh a tick at most), `PixelDynMs` (8: ms a tick of
  drawing models afresh), `PixelIncCompose` (1: the incremental compose, 9.3; 0: every pan composes whole)). (`GrowSecs`
  and `GrowArmSecs` went with the island's growth on the picture, 2026-11-19.)
  The seasons and the weather (GAME_DESIGN 13): `WeatherEpoch` (0: the sea's clock time the first spring starts),
  `SeasonSecs` (9000: a season, a whole number of spells), `WeatherSecs` (600: a spell), `WeatherTouch` (the chance an
  egg laid in a kind is touched: rain, snow, blossom, leaves 0.35; haze, fog 0.3; storm 0.2), `WeatherTierW` (52, 30,
  13, 5: the touch's tier weights before the rarity's shift), `WeatherLuck` (`{ storm = 0.25 }`: rarity luck a kind
  adds to the eggs laid in it), `SeasonFavour` (3: a season's islets' kinds that many times as likely).
- `Config/Tuning.luau`, the leaderboards and friends (GAME_DESIGN 16, 2026-11-21): `BoardStores` (`coins`, `charm`,
  `hatched`, `driftlings` -> `PI_Board_*_v1`, never renamed), `BoardRarityPoints` (10 20 35 55 80 110 150 200 260, by
  rarity), `BoardStarPoints` (10 a mutation star), `BoardRows` (50), `BoardCacheSec` (120), `BoardWriteSec` (300),
  `ReferralStoreName` (`PI_Referral_v1`, never renamed), `ReferralMaxAgeSec` (86400: a save that young takes an
  invite), `ReferralMinPlaySec` (600), `ReferralDailyCap` (10), `FriendsBoostEach` (0.1), `FriendsBoostMax` (0.4).
  `Data/Rewards.REFERRAL` { invitee (a rare egg, 10 min of coins), inviter (an epic egg, 20 min, a 30 min Lucky Hour) }.
- `Config/Monetization.luau`: `GamePasses` (OfflinePass among them since 2026-11-14), `DevProducts` (RefreshEggs among them since 2026-11-14), `Group = { Id }` (the Roblox group for the group gift: 255554513; 0 none), `Badges` (empty or 0), `Sounds` (the Creator Store
  library ids `Controllers/Audio` plays: Roblox's free licensed ProSoundEffects clips and APM Music stingers, none of
  Random Bakery's, each named in a comment; the weather's `RainLight` 9112852671, `RainHeavy` 9112858162, `WindGusts`
  9114057104 and `Thunder` 9120017047, measured with ffprobe) and `Music` (`{ day, night }`: lists of `{ id, gain }`, APM Music
  tracks, each named; `gain` evens their loudness out).

## 5. Data (pure content tables)

| Module | Holds |
|---|---|
| `Data/Palette` | the LUT colours (`order`, `colors`), the shore's `shallow`, `foam`, `rock` and `rock_dark`, the older rooms' floor and wall themes (`themes`, still in the LUT), the build catalog's 16 theme colours (`moss maple bamboo clay slate snow ice lava basalt crystal cherry teal swamp coral straw brick`, in `order` and so in the LUT), the light modes (`modes.day` warm with a faint blush, 1.033, 0.995, 0.955: GAME_DESIGN 2's cozy light), and the UI's colours (`ui`, `axis`, `match`: driftwood plates, warm plank frames, turquoise buttons). Rich and warm (GAME_DESIGN 2's pink sand: a light pink sand close to real sand, a fresh green lawn, a turquoise sea, the rest near the cozy colours with a faint blush; the renderer's `WATER_CREST` and `WATER_DEEP` turquoise to match) |
| `Data/Buildings` | the 284 pieces (GAME_DESIGN 4; 39 of them for tiers 11 to 20 since 2026-11-14) and the Tree of Life `{ id, name, kind (farm wood shop nest breed gen path water fence decor tree), shells (the price, since 2026-11-14 the only one: the listed price, which was wood (the old shells and wood added up), a Work or Huts tab building's, kinds farm wood shop gen nest breed, times `Tuning.BuildingPrice` to two figures, 5 at least, `priceOf`, then in shells at `Tuning.WoodShells` a wood times `WoodTierUp` for each tier past the second, to two figures, `shellsFor(wood, tier)`, also exported for `Island.expandCost`; no `wood` field), w, d (a path or water tile 2 x 2; a fence length w 2, d 0: a line along the grid), rate (the shells a turn with one common driftling at it, every kind that makes something; the wood buildings' raised to about a farm's of the same price on 2026-11-14), knack, slots (a hut's room), jobs (a workplace's places: `Tuning.WorkRoom` at its tier, 0 for the rest; a workplace's
listed price times jobs / 2, so a place costs what it did at 2), charm (a path's, water's or fence's may be a fraction; a decor piece's is 0: on an island it is `Tuning.DecorCharm[tier]` x w x d, `charmOf(def, tier)`, since 2026-11-19 the same for its size whatever the piece and growing with the island), comfort (a hut's share), boost ("farm" "wood" "shop" "all": a "gen" piece's knack; the Smokehouse's "fish" became "farm" on 2026-11-14), boostBy, tier (1 .. 20), blurb, tab (Build mode's tab: `work nest path fence water nature decor fun`; from the kind when not given: farm, wood, shop and gen "work", nest and breed "nest", path, water and fence their own, decor "decor"), sub (its row of chips: a Decor piece's theme `beach garden farm harbour town jungle frost autumn desert fairy zen volcano grand`, Nature's `trees plants rocks`, Fun's `seats lights play treats fountains`, Water's `tiles bridge float`, Work's the kind `farm wood shop gen`; "" for the huts, paths and fences), water ("" none; "over": may stand over water tiles as well as grass, the bridges, the dock, the waterwheel and the little waterfall; "on": only on water tiles, lily pads, reeds, stepping stones, the duck decoy, the rowboat, lotus flowers, floating lanterns), feel (what putting it down throws up and sounds like, `Controllers/BuildFx`: `wood stone plant water metal magic sand snow cloth fire`; from the kind when not given: path stone, water water, farm plant, else wood) }`; kind "farm" (the old "food": it sells what it grows or catches for shells), "nest" the huts (Driftling Hut .. Driftling Citadel), "path" and "water" the drawn tiles, "fence" the drawn lengths, "decor" everything for charm on the Nature, Decor, Fun and Water tabs (the bridges and floating pieces among them), "tree" the Tree of Life (`tree`: 8 x 8, charm 6, no price, tier 99 so no tab of the tray shows it; every island's, `Logic/Tree`); no `eats`, and no one-piece `fence` or `hedge` since save version 14; `list`, `byId`, `charmOf(def, tier)` (a piece's charm on an island of that tier: a decor piece's tiles times `Tuning.DecorCharm[tier]`, any other its `charm`), `EYES` (the twenty eye styles). The looks come from its `LOOKS` table (GAME_DESIGN 6; since the request of 2026-11-16, "Make all of their eyes small beads instead", every eye style there is "bead", the DataIntegrity spec) |
| `Data/Weather` | the seasons and the weather (GAME_DESIGN 13): `KINDS` (9 `Kind`s `{ id, name, laid ("Laid in the rain": the Tree panel), starts (the notice when it turns), family? (its Data/Traits weather family: only these touch eggs), icon (a `mini_` sprite), grade? (`{ mr, mg, mb, lift, sat }`: its light over DayLight's BRIGHT), mark (a palette colour: the status line's tone) }`: sunny, breezy, rain, storm, fog, snow, blossom, haze, leaves), `SEASONS` (4 `Season`s `{ id, name, icon, odds ({ kind, w }), favour (islet ids whose kinds come more often), blurb }`, in order spring, summer, autumn, winter), `byId`, `seasonById` |
| `Data/Creatures` | the 73 driftlings (GAME_DESIGN 6; 18 of them on the kinds past the capital, islets 10 .. 12) `{ id, name, islet (its kind, Data/Islets), rarity (1 common .. 7 celestial: 6 mythic), hp, atk, def, spd (kept only for `power`), knack ("farm", "wood" or "shop": the Work tab's groups; the twelve "fish" ones moved on 2026-11-14), shape (its MicroModels body plan), body, accent, eye (its DriftKit eye style, one of `EYES`), iris (palette key?), tex (its body colour's Render/DynTex texture), tex2 (its accent's, where that is a big surface?), blurb, passive ({ name, fx }: its own, Data/Traits effects), power (its stats weighted, +12% a rarity step: the breeding rank) }`; `list`, `byId` |
| `Data/Traits` | what makes one driftling unlike another (GAME_DESIGN 6): `MAX` (4 mutations), `KEYS` (the effects: work farm wood shop (shares at work; no fish since 2026-11-14), cost (the eggs' price: below 0 cheaper), sell (the price), charm (whole points), luck (luckier eggs); cost and luck count from a driftling in a hut, for the whole island (no `tree`, the next eggs sooner, since 2026-11-14: the tree keeps its 10 minutes; `renamed` turns a saved "swift<t>", Leafy, into "bright<t>", Lucky, and each passive's tree share became egg luck); 0.1 = +10%; `cost` was `eat` before the tide and the driftling's own price on it, `tree` was `tide` on it), `RARITY` (`{ name, color, weight }` x 7: Common .. Legendary, Mythic (UI colour `mythic`), Celestial (`celestial`); the tree's weights before luck, 100 45 16 5 1.2 0.02 0.002), `RMAX` (7: every table by rarity has this many entries; the bounds of the saves, payloads and clamps), `TIER_COLOR` (a tier's colour; its stars are `star_t<tier>` sprites, `UI/TierStars`, since 2026-11-14), `list`, `byId` (mutations `{ id ("sturdy3"), family, tier (1 .. 4; 0 a flaw), name, blurb, fx }`: nine families x four tiers and five flaws (the Angler family went on 2026-11-14: `renamed(id)` turns a saved "angler<t>" into "grower<t>", and `clean` uses it); the families keep their old ids, "sturdy" now Thrifty .. Selfless (cost) and "swift" Leafy .. Evergreen (tree), so older saves read them), `families`, `at(family, tier)`, `roll(rng, rarity, lean?) -> { id }` (0 .. 3, no family twice, a rarer one rolls fewer flaws and higher tiers; each family by `pickFamily`), `pickFamily(rng, families, lean?) -> family` (all alike with no lean or an empty one, the draws the same as before the lean; else weighted by `lean[family]`, 1 when absent; 2026-11-15), `sum(passive?, muts?) -> Fx`, `workAt(fx, knack)` (work + the knack's share, at least -0.5), `clean(muts)` (known ids, a family once, at most MAX), `describe(fx)` ("+24% at farms, eggs cost 30% less, +2 charm", "+5% egg luck"); `weather` (the seven weather families `{ family, weather, key, names, values }`: rainy (farm), frosty (work: fish until 2026-11-14), sunny (shop), bloomy (charm), autumn (wood), misty (sell: tree until 2026-11-14), stormy (luck), four tiers each in `list` and `byId` like the rest but not in `families`, so `roll` and breeding never give them; only an egg the weather touched does, GAME_DESIGN 13) |
| `Data/Quests` | the questline (GAME_DESIGN 9) `{ id, title, text (what to do and where), goal { kind, n, of? }, reward { shells? } (wood rewards became shells, one for one, on 2026-11-14), go (its Go: a panel "pals" "index" "hatch" "tree", or "build" / "build:<tab>"), icon (a `mini_` sprite) }`, twenty in order; `list`, `byId`. Goal kinds: helpers (driftlings at work) housed (in huts) built (of a building kind) paths decor taken (eggs hatched from the tree) sold best (the rarest had) tier seen hatched; the tree's `luck`, `speed` and `grown` are gone |
| `Data/Islets` | the 12 kinds of land the driftlings come from (GAME_DESIGN 6) `{ id, name ("Beach"), plural, tier (the island tier its driftlings start hatching at: Beach, Meadow 1; Snowfield, Mangrove 2; Volcano, Grotto 3; Reef 4; Bluffs 5; Ruins 6; Moonwood 11; Cloudtop 14; Starfall 17), wild (every driftling of its kind, from Data/Creatures, the commonest first), color, blurb }`; `list` |
| `Data/Looks` | skin (11), hair colour (17), hair style (19: short long bun spiky curly pony twintails mohawk bob braid pigtails afro sideswept spacebuns wavy pixie sidepony mullet bald) and shirt colour (18) lists, eye colours (13), `bangs` (10, "auto" the style's own), `aprons` (16, "none" first: `{ id, name, color, accent, pattern }`), `tints` (21, Original then 20: `{ id, name, color, shade, code }`), `turns` (5: degrees forward), all free (`Types.Look` indexes them; new entries only on the end), `names.<list>`, `worn` (the six cosmetic slots in the attribute's order), `extra` / `extraDefault` (the six fields after the first four), `tintFields` / `tintField` (slot -> field), `encode(look)` / `decode(s)` (the "Founder" attribute and a saved outfit: "skin.hair.style.shirt", then ".bangs.hair2.eye.eye2.apron.turn" when one is not its default, "|hat|face|neck|back|hand|top" when anything is worn or tinted, "|<a tint code a slot>" when anything is tinted; GAME_DESIGN 14), `tinted(c, a, t) -> (c, a)` (a piece's two colours under a tint), `tintOf(look, slot) -> key?`, `turnOf(look) -> degrees` |
| `Data/Cosmetics` | the 276 pieces a founder can wear (GAME_DESIGN 14) `{ id, slot (hat face neck back hand top), name, rarity (1 .. 7), src ("shop": the rotating shop's pool; "track", "trackp": the pass track's free and premium sides; "vip"; "starter"; "free": always owned), kind?, color?, accent?, covers?, bottom?, head?, rainbow? }` (the 193 with a `kind` are Random Bakery's, drawn by `Models/AccessoryModels` / `AccessoryBasics`; `color` and `accent` their two palette keys); `SLOTS` (`{ id, name }` x 6), `list`, `byId`, `bySlot`, `from(src) -> { id }`, `owns(owned, id)`. `Models/WearModels` draws each on the founder |
| `Data/Titles` | the 34 titles (GAME_DESIGN 14) `{ id, name, how ("start" "tier" "taken" "best" "seen" "earned" "hatched" "days" "owned" "vip" "starter" "track"), n, color (a UIKit / Palette key) }`; `list`, `byId` |
| `Data/Track` | the pass track (GAME_DESIGN 14): `LEVELS` (30), `list` (`{ free, prem }` a level, each a `Reward` `{ kind ("shells" with `mins`, "egg" with `r`, "look" or "title" with `id`) }`), `extra` (the last level's second reward each side: a legendary, a mythic egg) |
| `Data/Office` | the island's twenty tiers (`plans[tier]`: `{ tier, name }`, Castaway Cay, Palm Isle, Grand Isle, Harbor Town, Coral City, Sunspire Capital, Moonlit Bay, Evergreen Isle, Skyreach Isle, Driftling Haven, Lantern Cove, Saltwind Reach, Kelpwood Isle, Pearlstone Port, Cloudberry Isle, Amberfield, Starfall Atoll, Tidecrown, Farshore, Everdrift: the island card's title and Expand's cheer; as many as `Tuning.TierCost`), `plan(tier)`, `origin(plot)` (Data/Street's). The island has no house (GAME_DESIGN 8) |
| `Data/Street` | the islands in the sky (GAME_DESIGN 8; the request of 2026-11-20: "Never mind, make it a floating island instead, with a 2d skybox. Expanding makes the island bigger."): `warm(tier)` (works a tier's cells out now: tens of ms, so never at an expansion), `MAX`, `SPACING`; `LAWN_Y` (-0.5: the top of the grass, where pieces stand); the cell layers `GRASS` and `AIR`; `REACH` (3: how far past the edge a cell's coast distance is kept, for the bevels and the wall), `WALL` (1.5: the invisible wall's cells past the edge); `LOT` (a plot's lot: x +-85, z -72 .. 86, room for the top tier's island and its wall), `CENTER` (the island's heart, where a new island's Tree of Life stands: `Tree.SPOT`); `TOP` (20). `isle(tier)` (a tier's shape round the heart, centre (0, 6), radii and wobble phases; `ISLES` has twenty, each adding the ground the tiers always added: the first an oval 15 by 12, then circles of radius 19.1 up to 60.1, so the island grows outward evenly ("make expansion expand outwards evenly instead of resulting in one long stretch", 2026-11-20)), `coast(tier, x, z)` (studs from the island's edge, below 0 on the grass: the shape's radius times a wobble of four sines, joined to every smaller tier's (the least distance) so the island only grows), and per whole-stud cell (cached per tier, each tier worked from its own shape and the tier below's cells; `cellKey`, room for x and z of +-1024): `layer(tier, x, z)` (`GRASS` or `AIR`), `cellDist(tier, x, z)` (the coast distance, huge past `REACH`), `cellBounds(tier)` (every cell the drawing looks at), `buildable(tier, x, z)` (a stud or more in from the edge), `walkable(tier, x, z)` (the grass), `plot(tier)` (the island's box); `origin(i)` (plot i's world origin: a row along X centred on 0), `plotAt(x, z)` (the lot a world point is in, 0 off the row), `bounds()` (every lot), `spawn()` (just south of a new island's tree), `sign(tier)` (the south rim's last grass cell west of the tree). (The sea round the islands, its beach, wet sand, foam and shallows, the seabed the founders swam on, the darkness over land not open yet and the rock before it went on 2026-11-20.) |

Coordinates in `Data/Street` are studs, plot-local, +Y up. The camera looks from the south-east (+X, +Z), so an
island's back is its north-west. A piece's `rot` turns its model (built facing +Z: south, toward the viewer).

## 6. Logic and models

Pure rules (`src/shared/Logic`), all specced in `tests/specs`; every action returns `(true, data?)` or `(false,
ErrCode)` and changes the profile only on success:

| Module | API |
|---|---|
| `Util` | copied from Random Bakery: `hash32`, `newRng(seed)` (xorshift32: `next int range chance weighted`), `stir(rng, n)` (n XORed into its state: `Session.stir`), `pick`, `shuffle`, `Signal`, `round clamp lerp isFinite sig2 deepCopy count` |
| `Island` | the turn and the day (GAME_DESIGN 3): `piece(p, uid)`, `nests` (the huts' room), `fxOf(pal) -> Fx` (its passive and mutations, `Traits.sum`), `charm` (every piece's, a decor piece's at the island's tier (`Buildings.charmOf`), and each driftling in a hut: 1 + its charm share), `charmBonus(charm)` (`CharmMax` x charm / (charm + `CharmHalf`), never below nothing: what charm adds to every shell; `visitors` went on 2026-11-14), `works(id)` (a building that makes something: kind farm, wood or shop), `jobPlaces(pieces) -> number` (every workplace's `jobs` together: the island card's Working line, 2026-11-17), `homes(p) -> { [key]: { uid, comfort } }` (each hut driftling's hut and its comfort (the hut's plus `ComfortLvl` by level), "p<id>", none for one with no hut), `boosts(p) -> { farm wood shop all }` (every boost building, the k-th of a kind `boostShare(id, k)`: its `boostBy` x `Tuning.BoostStack`^(k-1), 2026-11-15), `boostInfo(p, id) -> { knack, count, raw, total, more }` (a boost building's card: its knack, the boost buildings counting there (an "all" one: the "all" ones), their boost before and after `BoostMax`, what one more of its kind adds), `boostAt(b, knack)` (its own and "all", `BoostMax` at most), `palWork(p, pal) -> number` (its work share at its building's knack, `Traits.workAt`), `palBoost(p, pal, comfort?)` (`PalWork` x `RarityWork[rarity]` x max(0, 1 + `palWork` + the hut's comfort): what a driftling puts in), `output(p) -> { [uid]: shells }` (each workplace a turn before the charm bonus and the passes: rate x level x workers or `IdleOutput` x (1 + boosts); the building cards' earnings), `rates(p, steady?) -> Rates` (`{ shells }` a turn: `output` summed in `placed` order; `steady`: without a timed boost, the pace the time away and the rewards counted in minutes go by; a farm, wood building or shop makes its rate times its driftlings' `palBoost` summed (`IdleOutput` with nobody), times 1 + `boostAt`, times `UpgradeMult` by level, all in shells; the whole times 1 + `charmBonus(charm)`; nothing eats), `step(p, dt) -> Rates` (the shells; counted in `stats.earned`), `randomLook(rng)` (the founder's first look), `freeJob(p, knack, fx?) -> uid` (a workplace with fewer driftlings than its `jobs`: one of that knack first, else the one where `fx` works fastest (`Traits.workAt`), then the emptiest, farms before wood before shops, the first built; 0 none), `newDay(p)`, `arrange(p)` (the automatic arrangement, 2026-11-14: every hut driftling not `pin`ned to the free place where its output is highest, the best workers first (their best speed at any knack, then the lower id); a workplace's output is its rate x `UpgradeMult` x (1 + `boostAt`), a driftling's speed `PalWork` x `RarityWork` x max(0, 1 + `Traits.workAt` + its hut's comfort); ties: its own knack, then farm, wood, shop, then the first built; a pinned one keeps its place while it stands (gone: unpinned, arranged); one with no hut rests; run by `Tree.fillJobs`, `settle`, `add`, `hatch`, `expand`, `setHelp`, `autoWork`, so on every building change, hatch, sale, move, growth and load), `setHelp` (by the player's hand: only a driftling in a hut, at any workplace whatever its knack, or rest; `pin` set; its `jobs` a building, the first there unpinned and sent back to the arrangement; then `arrange`; bad_payload for one with no hut or a building that makes nothing), `autoWork(p, id)` (unpinned and `arrange`d; data `{ work }`; not_found), `expandCost(tier) -> { shells }?` (`TierCost[tier + 1]` in shells, `Buildings.shellsFor(wood, tier + 1)`; nil at the top), `expand(p)` (max, money; data `{ tier, moved, cleared }`: `Plot.refit`), `setFounder` |
| `Store` | the store (GAME_DESIGN 14): `PASSES`, `PRODUCTS`, `owns`, `setPass`, `vipDaily`, `perMinute` / `minutes`, `product`, `shopNow` / `buy`, `wear`, `setTitle`, `earn`, the track (`season sync addXp level claim`), `paid` / `remember`; offline earnings and the group (GAME_DESIGN 14.3, 2026-11-14): `offlineCap(p)` (seconds: `OfflineHours`, `OfflinePassHours` with the Offline Pass), `offlinePct(p)`, `offline(p, now) -> OfflineReport?` (from `seenAt` to now, capped, at that share of `Island.rates(p, true)` now (no timed boost: it runs down only while the player is here, and a banked one multiplied every return's report; the server review of 2026-11-19), whole shells; nil when `seenAt` is 0, under `OfflineMinSec` or nothing earned), `offlineDouble(p, now)` (an island's first `OfflineDoubleDays`), `collect(p, report, mult) -> shells` (the shells and `stats.earned`), `setGroup(p, member) -> (changed, gift?)` (`group.member`; the first time in it `group.gift` and a `GroupEgg` egg with `GroupMins` of shells); `Island.passMult` adds 1 + `GroupBoost` while `group.member` |
| `Social` | the leaderboards and friends (GAME_DESIGN 16): `BOARDS` (`coins charm hatched driftlings`), `score(p, board)` / `scores(p)` (whole numbers: `floor(stats.earned)`, `floor(Island.charm)` of the island, `stats.taken + stats.hatched`, and the best driftling's `points x KIND_CODES + kindCode(sp)`), the Driftlings board (2026-11-21): `stars(pal)` (its mutations' tiers, a flaw 0), `palPoints(pal)` (`BoardRarityPoints[rarity] + BoardStarPoints x stars`), `bestPal(p) -> (points, pal?)`, `KIND_CODES` (1e6), `kindCode(sp)` (`Util.hash32(sp) % KIND_CODES`; the spec checks every kind has its own), `decode(value) -> (points, sp?)`, `isBoard`, `fresh()`; a friend invited: `canJoin(p, inviter, selfId, now)` (a whole positive id, not the player's, none taken yet, a save younger than `ReferralMaxAgeSec`), `join(p, inviter) -> given` (`REFERRAL.invitee` through `Rewards.give`), `play(p, dt) -> becameDue`, `due(p)`, `todayLeft(p, now)` (UTC days), `reward(p, now) -> (ok, given?)` (`REFERRAL.inviter`, false past `ReferralDailyCap`); `view(p, now)`. `Island.friendsMult(p)` = 1 + min(`FriendsBoostMax`, `social.here` x `FriendsBoostEach`), in `Island.rates` with the timed boosts (not the steady pace) |
| `Plot` | building (GAME_DESIGN 4): `ROTS`, the limits by tier `limit(tier)` (`PlotPieces`), `housingLimit(tier)` (`HousingLimit`: the room its huts may have together) and `housing(placed)` (the room its huts have), `workLimit(tier)` (the work cap: its places at work together, the driftling limit `housingLimit`; 2026-11-18) and `work(placed)` (its workplaces' `jobs` together), `hatcheryLimit(tier)` (`HatcheryLimit`) and `hatcheries(placed)`, `pathLimit(tier)` (`PathPieces`: path and water tiles together), `fenceLimit(tier)` (`FencePieces`); `huts(placed)` (the huts standing); what a piece is: `isPath(id)`, `isWater(id)`, `isTile(id)` (a path or water: 2 x 2, drawn on the even studs), `isFence(id)`, `isDrawn(id)` (a tile or a fence: Build mode's draw bar, never placed one at a time from a card), `isFixed(id)` (the Tree of Life: moved, never bought, cleared away or replaced), `onPaths(id)` (any piece but the tree, a fence, a tile and a piece with a `water` mark: decor, plants, fun pieces, huts and workplaces may stand on path tiles, and paths may be drawn under them; 2026-11-14), `group(id)` ("tile", "fence", "fixed" (the tree: never counted) or "piece": the limit it counts toward), `groupLimit(group, tier)`, `used(p, id) -> (n, limit)` (the pieces of its group and that group's limit); `footprint(id, rot)`, `rect`, `blockers(tier)` (none since 2026-11-20: the campfire's plaza went, the Tree of Life in its place a piece like the rest; the path to the jetty went with the docks), `spawn(tier, placed) -> (x, z)` (where a founder appears: a stud and a half south of the tree's footprint where it stands, else the nearest spot round there no piece but a path tile covers; `Street.spawn` with no tree; PlotService.spawnCFrame), `fits(tier, placed, id, x, z, rot, skip?) -> (ok, "outside" (a footprint cell not `Street.buildable`, a tile off the even studs, a fence off the grid, a piece marked "on" not wholly on water tiles) / "blocked" / "overlap" / "unknown")` (one piece never on another but: a piece marked `water` "over" or "on" on water tiles, and water dug under one; an `onPaths` piece (a hut or a workplace too) on path tiles, and paths drawn under one; tiles and fences never in each other's way; a fence length (`fenceFits`: from an even corner, rot 0 east or 90 south, each of its two studs with buildable grass on one side or the other, not through a piece's footprint but free to run along its side, not on another length) never inside a piece's footprint, so no piece goes down across a fence), `spot(tier, placed, id, x, z, rot) -> (x?, z?, rot?)` (the free spot nearest x, z: `Tree.plant` plants with it, `refit` moves with it; ties to the turn asked, then the lower z, then x; tried ring by ring out from x, z until no farther ring can come nearer, a floater only where every cell under it is water: it tried every cell of the island against every piece, seconds for a lily pad on a big island), `unhouse(p, uid, keep?)` (a hut's driftlings past its first `keep` left with no hut, resting, unpinned; `Tree.settle` moves them in again; was `toPen`; a workplace taken away (`store`, `clear`, `unpaint`, `unfence`, `refit`, `Tree.plant`) sends its workers back to the arrangement unpinned: pinned with no work reads as resting by hand, and they rested for good; the server review of 2026-11-19), `place` (bad_payload (an unknown piece, a home of the old saves, the tree), locked, full (its group's limit), huts (a hut whose room `housing` + its slots would pass `housingLimit`), hatcheries (a Hatchery at `hatcheryLimit`), money (short of the shells), blocked; one waiting in the inventory goes down
for nothing, else it's paid; data `{ i, uid, free }`), `move` (the tree too; blocked for the spot; no upgrades: taken out 2026-11-11; a level from an older save stays and counts), `replaceCost(q, id)` (the new price less `Refund` of the old, never below nothing), `replacements(q, tier)` (the others of its kind open at the tier, a decor piece's only from its own row: the same `tab` and `sub`, a tree for a tree, a bench for a bench; none for the tree or a drawn piece, which is drawn over instead), `replace(p, i, id)` (bad_payload (another kind, the same piece, the tree), locked, huts (a bigger hut whose extra room the housing limit hasn't), money, blocked (the new footprint where the old stands); a smaller hut keeps the driftlings it has room for, the rest left with no hut; the uid kept, the level 1, its driftlings staying (any driftling works anywhere); bad_payload too for a drawn piece or a decor piece from another row, the same rows `replacements` offers), `store` (fixed (the tree), egg; into the inventory, data `{ id }`; a hut's driftlings left with no
hut); the inventory (2026-11-14): `INV_MAX` (9999 of a piece), `held(p, id)`, `clear(p, what) -> (ok, { removed })`
(Remove all: "pieces" every piece but the tree and a Hatchery warming an egg, "tiles" every path and water tile with
what floats, "fences" every length, all into the inventory; not_found when none, bad_payload for another group),
`sellHeld(p, id, n) -> (ok, { sold, shells })` (up to n of those waiting sold for `Refund` of the price each; not_found,
bad_payload), `cleanInv(v)` (a save's inventory: known pieces, never the tree, whole counts 1 .. `INV_MAX`), `refit(p) -> (moved, cleared)` (each piece tried against the kept pieces in the 8-cell blocks round it alone, which
is all `fits` looks at; the tree first, keeping its place, then the water tiles, so what floats on them finds them kept whatever order it was laid in (a lily pad moved onto a pond painted after it once failed on every load and was looked for a spot all over the island: 9.5 s at tier 6, 79 s at tier 10, freezing the whole server on each join and expansion; the server review of 2026-11-19); pieces that do not fit move to the nearest free spot, or are cleared with their whole price back; a tile or a fence is never moved, only cleared; never the tree: after the island grew and when a save loads); huts housing past `housingLimit` and Hatcheries past `hatcheryLimit` in a save are kept; drawing (GAME_DESIGN 4: Build mode's draw bar): `PATH_STEP` (2: a tile's cell and a fence's length, on the even studs), `PAINT_MAX` (40 cells or edges a request), `cells(s) -> { {x, z} }` and `cellString(cells)` (the payload's "x,z;x,z": tiles' north-west corners), `edges(s) -> { {x, z, rot} }` and `edgeString(edges)` ("x,z,r;...": a length's corner and its way), `paint(p, id, cells) -> (ok, { placed, swapped, skipped })` (a path or water piece only; the cells in order: one with a tile of the same look passed over (skipped), one with a tile of another look of the same kind swapped for it (the old one into the inventory, the new one from it or paid, the uid kept, `stats.built`), a free cell that fits given a tile at rotation 0 (from the inventory first, for nothing), one that doesn't fit skipped; it stops at the tile limit or when the stores run out; bad_payload, locked, or full / money / blocked when none changed), `unpaint(p, cells, kind?) -> (ok, { removed, floated })` (every tile of `kind` ("path", "water" or "all") covering one of the cells' studs comes up into the inventory; anything marked "on" no longer wholly on water comes up with it, into the inventory too; a piece on path tiles stays where it stands; not_found), `fence(p, id, edges) -> (ok, { placed, swapped, skipped })` (a fence piece only; `paint`'s rules along the edges: another fence on an edge swapped, a new length where `fenceFits`, the fence limit; an edge turned other than 0 or 90 skipped), `unfence(p, edges) -> (ok, { removed })` (the lengths on those edges down, each into the inventory; not_found). Many pieces at once (GAME_DESIGN 4.7, 2026-11-21): `MANY_MAX` (300), `uids(s)` / `uidString(list)` ("12,40,41"), `spanOf(q)` (a piece's rect; a fence length's zero-width segment), `index(list) -> { add, remove, near(rect, skip) }` (pieces in blocks of 8 cells), `fitsNear(tier, idx, id, x, z, rot, skip)`, `roomFor(tier, placed, ids) -> (ok, err)` (every limit for pieces added), `pick(placed, uids)`, `groupMoves(group, dx, dz, rot) -> { Move { q, x, z, rot } }` (quarter turns about the group's box, half a stud (a stud with tiles or fences, kept on the even studs) toward its longer side when the middle falls between, so four turns come back; tiles stay rot 0, fences run east or south), `groupRank(id)` (tree, water, paths, fences, pieces, floats), `movesFit(tier, rest, moves)`, `without(placed, group)`, `moveMany(p, uids, dx, dz, rot)` (data `{ moved }`), `storeMany(p, uids)` (the tree and a warming Hatchery stay; data `{ removed, kept }`), `copyCost(p | view, uids) -> { shells, held, bought }`, `copyMany(p, uids, dx, dz, rot)` (the inventory's first; data `{ placed, shells }`), `limitsOk(tier, placed, before)`, `pricer(p)` (Plot.price with the tips' free workplace free once), and `stow`, `takeHeld`, `freeWorkers`, `clearOut` for Logic/Undo and Logic/Layout |
| `Undo` | Build mode's Undo (GAME_DESIGN 4.7): `capture(p) -> Snap` (every piece as it stood, the inventory, the coins, the build count, each driftling's hut and work), `diff(snap, p, what) -> Step?` (`{ what, gone, added, moved, inv, shells, built, pals, size }`: what the action changed, nil when nothing did), `push(stack, step)` (the oldest dropped past `Tuning.UndoSteps` steps or `Tuning.UndoRecords` records, the newest always kept), `can(p, step)`, `apply(p, step) -> (ok, data | err)` (all or nothing: not_found (a piece it put down or moved is gone, or the inventory no longer holds what it put away), egg (a Hatchery it put down warms an egg), money (a sale's coins spent), blocked (a piece would not fit where it stood, against the whole island after), full / huts / work / hatcheries / boosts (`Plot.limitsOk`); the coins back by what the action cost, the driftlings back in their huts and work where those have room) |
| `Layout` | saved layouts (GAME_DESIGN 4.7): `SLOTS` (`Tuning.LayoutSlots`), `MAX_PIECES` (every limit of the top tier and the tree), `CODE_MAX`, `pack(placed) -> string` (the ids joined by ",", ";", then seven characters a piece: the id's place in two base-36 digits, x + 240 and z + 240 in two each, the quarter turn), `unpack(code) -> { Entry { id, x, z, rot } }?` (nil when it doesn't read), `clean(v) -> { LayoutSave }` (exactly SLOTS, empty where one doesn't read; `Schema`), `view(p)` (`{ at, tier, n }` a slot), `save(p, slot, now)` (data `{ slot, n }`), `plan(p, slot) -> Plan { placed, held, bought, shells, locked, limit, blocked, away, tree }` (changes nothing), `load(p, slot)` (all or nothing: the island's own pieces first, keeping their uids, then the inventory's, then bought (`Plot.pricer`); money when the coins don't cover it; the tree to its saved spot when that fits; a warming Hatchery stays; the pieces not used into the inventory) |
| `Weather` | the seasons and the weather from the sea's clock, pure (GAME_DESIGN 13): `season(t) -> (id, left, index)`, `kindOf(spell) -> id` (the season's odds by `Util.hash32("weather:" .. spell)`; a storm after a storm gives the season's first kind), `at(t) -> State` (`{ season, seasonLeft, kind, kindLeft, spell, year }`), `luck(state?)` (`WeatherLuck[kind]` or 0), `touch(rng, state?, rarity) -> (kind?, tier?)` (with `WeatherTouch[kind]` when the kind has a family; the tier from `WeatherTierW`, the first weight down 8 and the top two up 3 and 2 a rarity step; a storm's one better, 2 .. 4), `mutation(kind?, tier?) -> id?`, `known(kind)`, `knownSeason(id)`, `left(secs) -> string` ("2 h 10 min", "45 min"). `Logic/Tree` takes the weather as an optional last argument: `fill(p, rng, wx?)`, `lay(p, rng, wx?)`, `step(p, dt, rng, wx?)` (each new egg gets `ss` and maybe `wx`/`wt` from `Weather.touch`; the tips' two commons none; nil weather lays plain eggs, as the Career did before), `odds(p, tier?, extra?)` (`extra` the weather's luck), `roll(p, rng, rarity, knack?, season?)` (the season's favoured islets' kinds `SeasonFavour` times as likely when no knack is asked), `weatherMut(egg) -> id?`; `hatch` rolls with the egg's season and adds its weather mutation (replacing one of its family, else appended, else replacing the lowest tier when MAX are held), data also `{ wx, wm }` |
| `Tree` | the Tree of Life, its eggs and the huts (GAME_DESIGN 6; `Logic/Tide` for a few hours on 2026-11-13): `ID` ("tree"), `SPOT` (-4, 2: the 8 x 8 tree centred on the island's heart, `Street.CENTER`, since the request of 2026-11-20 "Remove the campfire in the middle and put the tree in the middle instead"; `OLD_SPOT` (-4, -6: behind the campfire, before), `hutFx(p) -> (tree, luck, cost)` (the huts' driftlings' shares, at most `HutTree` / `HutLuck` / `HutCost`; cost as a share off, 0 .. `HutCost`), `secs(p)` (`EggSecs` / (1 + the tree share): seconds between two lots), `count(tier)` (`EggCount[tier]`: eggs a lot), `stage(tier)` (`TreeStage[tier]`: the tree model's stage), `luck(p, tier?)` (1 + `EggLuck[tier]` + the luck share), `pool(tier) -> { { sp } }` (by rarity, the kinds open at the tier), `odds(p, tier?) -> { share }` (each rarity's weight x luck^(r - 1), a rarity the pool lacks given to the next commoner one), `worth(pal)` (`RarityWork` x (1 + its share at its knack): the lists' order and the weakest in a swap, kept per driftling table in a weak table, its kind and mutations never changing), `worthAt(pal, knack)` (the same at a building of `knack`: the work picker's speed at each workplace), `better(a, b)` (the better worker first, then the older), `price(pal)` (what it sells for: `SellPrice` x (1 + `SellTier` x its mutation tiers) x max(0.2, 1 + its sell share), whole shells, at least 1), `cost(p, r)` (an egg of rarity r: `EggPrice[r]` x `EggTier[tier]` x (1 - the cost share), whole shells, at least 1), `huts(p) -> { Hut }` (`{ uid, room, comfort, n }`, the comfiest first, then the first built), `room(p)` (the huts' free places), `settle(p) -> { id }` (the driftlings with no hut, the best first, into the huts with room, the comfiest first, each taking a free job, its knack's first (`Island.freeJob` with its effects): who moved), `fillJobs(p)` (resting hut driftlings to free jobs), `add(p, sp, muts) -> Pal` (a Hatchery's hatchling: the comfiest hut with room, or none; a free job; `seen` 2, `stats.best`), `roll(p, rng, rarity, knack?) -> (sp, muts)` (a kind of that rarity open at the tier, a commoner rarity when none is; of `knack` when asked and it has one; `Traits.roll` at the rarity + (tier - 1) // `EggMutTier`, that boost stopping at legendary, a mythic or celestial one rolling as itself, with `lean(p)`), `lean(p) -> { [family]: weight }` (never shown, 2026-11-15: each knack's family (grower, chopper, trader) 1 + `MutLean` x that knack's work buildings / max(all the work buildings, `MutLeanFloor`); empty with no work buildings), `fill(p, rng, wx?) -> { Laid }` (eggs up to `count(tier)`, each rarity by `odds`; on a new island (`stats.taken` 0, no driftling) the lot's first two commons; then `ensure(p, wx)`; the new ones), `wanted(p) -> number` (the rarity the quest on the go asks for (`Quest.current`, a "best" goal: the uncommon, rare and epic quests) while `stats.best` is under it and `pool(tier)` has that rarity; else 0), `ensure(p, wx?) -> Laid?` (with `wanted` above 0, no new island and no egg of that rarity in the lot, the commonest egg commoner than it (the first of those in the list) turns into one, its id and place kept; with none to turn (the lot hatched out, or every egg rarer), a new egg of that rarity is laid (`clutch.next`, the season of `wx` when given, no weather touch), even past `count(tier)`: the egg that turned or was laid, else nil; the request of 2026-11-14, "also, while the rare one quest is active or any rarity related quests, make it such that an egg of that rarity will always spawn in the tree of life.", and the bug report of 2026-11-16, "there is a bug, the tree dosent have the rare egg in this quest"), `lay(p, rng) -> { Laid }` (a new lot: the list cleared, `left` = `secs(p)`, then `fill`), `step(p, dt, rng) -> { Laid }?` (`left` - dt; at 0 or below, `lay`; nil when nothing was laid), `view(p) -> { Laid }` (the client's copy, each egg with its `cost`), `rise(p, rng, r) -> number` (the rarity an egg of rarity r hatches as: up one with `Tuning.EggUp[r]` and on while the rolls hold, never to a rarity `pool(tier)` lacks), `hatch(p, id, swap, rng)` (not_found (no such egg: a new lot came), no_hut (no hut built), money, full (every hut full and swap 0), bad_payload (a swap that isn't in a hut); the shells paid, the egg gone, a swapped one sold (`price`, `stats.sold`, `stats.earned`) and its hut taken, else the comfiest with room; `rise` (not for the first two on a new island), then `roll` at that rarity (the first two of the knack "wood", then "farm"); a free job; `seen` 2, `stats.taken`, `stats.best`; data `{ id, sp, muts, egg, r, hr, cost, sold, swapped, wx, wm, new }`: `r` the rarity laid, `hr` the one it hatched as, `new` true when the kind was never had before, `seen` under 2 before the hatch: the hatch scene's "New!"), `sell(p, id)` (not_found; its price, `stats.sold`, `stats.earned`, then `settle` and `fillJobs`; data `{ shells, sold }`), `house(p, id, uid, swap)` (to another hut and a free job there, its knack's first; a full hut only in a swap with `swap` (one living there), which goes where this one was; not_found, bad_payload (not a hut, a swap not living there), full; then `settle` and `fillJobs`; data `{ moved }`), `piece(p) -> Piece?` (the tree's), `plant(p) -> Piece?` (an island with no tree gets one at the free spot nearest `SPOT`; on one built full the pieces nearest it make room, paths first, then decor, then the rest that houses nobody, each cleared with its whole price back). None of the tide's `State`, `new`, `start`, `drift`, `life`, `along`, `entry` or `take`, nor the old tree's pen, levels and `equipBest` |
| `Breed` | the Hatchery (GAME_DESIGN 6.1): `child(a, b, tier?) -> sp` (a pair of one kind its kind, else the kind of power nearest their average, legendary and up no rarer than the commoner parent (a legend only from two legends or rarer, a mythic one from two mythic or rarer, a celestial one from two celestial); with `tier` only kinds of land open there, or the parents' own; the commoner, then the first id, on a tie), `cost(sp, p?) -> (shells, turns)` (`BreedShells`, `BreedTurns` by its rarity; with `p` the turns times `Island.isle(p).hatch`, at least one), `inherit(ma, mb) -> muts` (since 2026-11-19 decided, no chance: every family either parent carries at the better tier, one both carry a tier above it (at most 4; a wondrous one stays itself; a shared flaw its family's first tier, a lone flaw left behind), the highest tiers first, four at most), `preview(p, a, b) -> Preview?` (`{ sp, muts, price, turns }`: what the pair of the island's driftlings `a`, `b` would lay; nil when either isn't the island's; the Hatchery panel shows it on the client from the view as a profile), `eggAt(p, uid)`, `start(p, uid, a, b)` (not_found, egg, bad_payload, money; lays `preview`'s egg, `p.eggs` + 1), `turn(p) -> { Ready }` (each warming egg a turn nearer; the ones reaching 0 this turn, `{ uid, sp }`: ready, they wait at their Hatchery, nothing hatches by itself since the request of 2026-11-20: "the hatchery should have the timer above its building, and show ready! once the egg is ready. clicking it while ready shows the hatching screen just like hatching an egg normally, but with the resultant creature"), `finish(p) -> n` (every warming egg ready now: Finish Hatcheries), `hatch(p, uid) -> (ok, Hatched | err)` (the ready egg at Hatchery `uid` into a hut with room, or none (`Tree.add`), `stats.hatched`, the egg gone; not_found (no egg there), egg (still warming); `Hatched` `{ uid, sp, muts, r (its kind's rarity), id, home, new (a kind never had before: the hatch scene's "New!") }`) |
| `Quest` | the questline's rules (GAME_DESIGN 9): `Facts` (`{ pals, pieces, tier, seen, stats }`: a profile's, `facts(p)`, or the client view's, same names), `count(facts, goal)` (how far: driftlings at work (`helpers`), path tiles, decor, pieces of a kind, driftlings in huts (`housed`), the stats' counts (`taken`, `sold`, `hatched`), the rarest had (`best`), the tier, kinds in the Index), `current(tut, i) -> (Quest?, i)` (none while the tips are on, or past the last), `progress(facts, q) -> (have, need)`, `done(facts, q)`, `claim(p)` (not_found, not_done; the reward paid in shells and wood, `p.quest` + 1; data `{ id, shells, wood, next }`) |
| `Schema` | `VERSION` (22 now: 21 -> 22 moves a tree still at `Tree.OLD_SPOT` to `Tree.SPOT`, the campfire's plaza, always free since no piece could stand there; one moved elsewhere stays; 15: one store), `default(now, seed)` (`StartShells`, no driftling, `clutch` `{ left 0, list {}, next 1 }` (the first lot laid on the first step), then `Tree.plant`), `migrate(raw)` (1 -> 2: a founder; 2..4 -> 5: the studio gone, the founder, settings and start kept; 5 -> 6: the tips' steps moved (3 -> 5, 4 -> 6); 6 -> 7: each driftling rolls its mutations once, seeded by its kind and id; 7 -> 8: the questline; 8 -> 9: `boat` and `chart` gone; 9 -> 10: `cap`, `islets`, `sea`, `wilds` and `pouch` gone, a Training Yard refunded (450 shells, 50 wood), the driftlings put in the nests (now huts) in the old order (the comfiest first, in the order they came), the rest to the pen (sold at 11 -> 12), `tut` past 5 back to 5, `quest` 1, `stats.grown` from the old `befriended`, `stats.best` the rarest kept; 10 -> 11: `folk` gone, every home (Tent .. Manor) taken down with its whole price back, `tut` past 4 back one, `stats.movedIn` gone; 11 -> 12: `tree` and `food` gone, the tree's piece taken off the plot, every driftling with no hut (the pen's) sold for `Tree.price` (shells, `stats.sold`, `stats.earned`), `held` dropped, `stats.grown` renamed `stats.taken`; the tips keep their numbers; 12 -> 13: `clutch` dropped (reconcile makes it: the tree planted, its first lot laid when the player arrives); 13 -> 14: the old one-piece fence and hedge (ids `fence` and `hedge`, now drawn: Picket Fence, Hedgerow) taken off the plot with their whole price back in wood (25 and 120 each); 14 -> 15: the wood (a number above nothing) added to the shells, one for one, at most 1e12, and `wood` dropped), `reconcile(raw, now, seed)` (any table -> a valid Profile: pieces that exist with unique uids, each group to its own limit (`Plot.group`: the pieces, the tiles, the fences, one tree), `inv` through `Plot.cleanInv` (`{}` in a save without one), x and z clamped to -160 .. 64, valid turns (a fence's 0 or 90 from an even corner, any other dropped; a tile off the even studs is cleared by `Plot.refit` below, its whole price back), driftlings with unique ids (at most `MAX_PALS`, 5000) (a driftling's `home` a standing hut with room or 0, `work` only from a hut at a workplace (a farm, wood or shop building, any knack), `muts` through `Traits.clean`), the Index's species, `nextId` past every id, `tut` 0 .. 6; then `Plot.refit`, `Tree.plant`, the clutch (rarities 1 .. `Traits.RMAX`, ids unique, at most `Tree.count(tier)` eggs, `left` 0 .. `EggSecs`, `next` past every egg id) and `Tree.settle`) |
| `Validate` | `ACTIONS` (the action catalogue, §7.3: `egg.hatch` `{ id = int, swap = int }` in place of `tide.take`; `plot.fence` and `plot.unfence`; `plot.unpaint` with its `kind`; `plot.clear` `{ what = group }` and `inv.sell` `{ id, n = int }` since 2026-11-14), `request(action, payload) -> (ok, err?)`: exact schemas, unknown and missing fields refused. Field kinds of the building actions: `coord` a whole number in [-240, 160] (a plot-local stud: the whole island reaches that far north and south), `index` [1, 8192] (a placed piece: pieces, tiles and fences), `rarity` [1, `Traits.RMAX`], `cells` 1 to 40 cells "x,z" joined by ";" (each a coord), `edges` 1 to 40 edges "x,z,r" (each a coord, r 0 or 90), `tiles` "path", "water" or "all" (which tiles an eraser takes up), `group` "pieces", "tiles" or "fences" (what Remove all takes) |
| `Numbers` | `int`, `short`, `coins`, `rate`, `perMin` ("+57/min"), `oneIn`, `duration(secs)` ("2 h 10 min", "45 min", "1 min": whole minutes rounded up; the weather's lines (`Weather.left`) and the Hatchery's eggs, 2026-11-14), `clock(secs)` ("4:05", "1:02:09": whole seconds rounded up; the Hatchery's tag, 2026-11-20) |

Models (`src/shared/Models`, Roblox modules):

- `Blocks` (copied): `part(parent, spec)` (anchored, SmoothPlastic or Neon, sizes on the 0.25-stud grid, palette
  colours), `cylY`, `model`, `color`, `snap`. `pace(fn?, every?)`: from the thread that calls it, `part` calls `fn` (a
  `task.wait`) after every `every` (60) parts, so a big build spreads over frames; other threads are never paced;
  `pace(nil)` ends it (PlotService's next islands).
- `CharacterModels.build(look, name, seed) -> Rig` (a seated chibi, the portraits'; the head's parts with a glint in
  each eye, brows, a mouth and ears, sizes exact to the eighth of a stud), `buildStanding(look, name, seed)` (a
  standing chibi: the founders and the visitors: soles, shoes, bare shins under shorts, a shirt with a belt and buckle,
  a collar and two buttons, sleeves, bare forearms and fists, the head raised a stud), `posePose(rig, base, Pose)`
  (`Pose { lean, twist, crouch (the knees bend to keep the feet down), lift, hipL/R, kneeL/R, armL/R (CFrames about
  the shoulders), elbowL/R, head, roll (the body tipped about the waist), mood }`; moods `calm fierce shout hurt happy
  ko blink sleep snore yawn hum` move the brows, open the eyes (a thin upright line, 0.125 x 0.375: the request of
  2026-11-15, "can they be 2 vertical lines instead?"; no glints) or shut them (a flat line, 0.25 x 0.125) and size
  the mouth, all at the rig's scale), `poseStanding(rig, base, t, speed)` (the walk: knees and elbows bending, or the
  stand: breathing, the weight shifting, the head wandering and glancing round; a blink, `blinking(seed, t)`: 0.12 s
  somewhere in each 3.3 s, now and then a second just after), `poseFounder(rig, base, t, speed, idle, dozing, quiet,
  squash?)` (the stand plus a fidget, `fidgetAt(rig, t, idle) -> (name?, u)`: one of `FIDGETS` (look, tap, yawn,
  scratch, hum, rock, stretch, look) for `FIDGET_LEN` 2.4 s at the start of each `FIDGET_SEC` 6.5 s slot, picked by
  the slot and the seed, none begun before the rig stood still; or the doze: the head nodding down over 85% of
  `NOD_SEC` 3.05 s and back up, the body sagging, the arms hanging, "sleep" and at the bottom "snore"; a landing's
  crouch by `squash`),
  `poseAction(rig, base, t, speed, action, k?)` (`cheer hurt swing reach pet cast jump sneak dance`, `swim` (nobody swims since the sea went on
  2026-11-20; kept: a crawl when `speed` > 1, the arms turning over in turn and the legs kicking, leaning 30°; else treading
  water, the arms sweeping out and back with a slow bob), the
  fights' `windup strike guard throw run victory ko` (nothing plays them now), and the island's work, each a loop with `k` the beat's phase:
  `dig pick fish chop saw sell serve hammer train tend`), `WORK_HIT` (where in a beat a work's blows land:
  `{ [action]: { phase } }`), `STAND_TOP`, `topOf(rig)` (the top of the head and its hat as drawn: the name tag's
  height), `preview(look) -> Model` (the standing rig at rest for pictures: the customization screen's stage and
  thumbnails). The hair styles are Data/Looks' nineteen (each a few head parts, "bald" none), the eyes in the look's
  colours (EyeR in `eye2`'s when set), a `Streak` down the fringe in `hair2`; the pieces worn, the apron and the bangs
  (GAME_DESIGN 14.1) come from `Models/WearModels.build(look)` onto the rig, `Rig.extra = { head, body, hand, handL }`
  (their part names by the bone they move with: `posePose` moves the head ones with the head, the body ones with the
  torso, the hand ones with each forearm (`limb` returns the forearm's frame); the seated rig keeps the head and body
  ones, moved down to its head and torso, and holds nothing) and `Rig.moves` (`{ [part]: { CFrame } }`: a moving
  piece's loop, rig space, stepped 7 a second by `Pose.t`, which `walkPose` sets: still pictures rest); a hat's `covers`
  hides the hair it covers ("top": what sticks up, the afro and space buns among it; "hood": all the hair but the
  Fringe), a covering bakery hat's `bottom` stops the HairCap at its edge, a hat that is the head (`head`) hides the
  head's own parts, bangs take the Fringe's place, an apron hides the shirt's buttons and buckle; a top (in its tint,
  `WearModels.top`) recolours the Torso, the sleeves and the trim and hides the shirt's parts it lists.
- `WearModels` (2026-11-20): `build(look) -> { specs, headHat, hatBottom?, covers?, apron, bangs }` (every part worn:
  this game's pieces from `CosmeticModels`, recoloured by the slot's tint (the colour most of the piece is in takes it,
  the second its accent: `Looks.tinted`), the bakery's drawn by `AccessoryModels` / `AccessoryBasics` through their
  Api in the bakery's body space and fitted onto the founder per bone: 0.75 about the anchor, the bakery's head middle
  (0, 3.5, 0) to (0, 3.125, -0.1), torso (0, 1.75, 0) to (0, 1.875, 0), fists (+-1, 1.25, 0) to (+-0.8125, 1.39, 0),
  a loop m fitted as A m A^-1; the held piece turned forward about the fist (`AccessoryModels.grip(kind)` for the
  bakery's) by `Looks.turnOf`, clear of the ground), `piece(id, look?) -> { Spec }` (one piece alone: the cosmetic
  pictures), `top(look) -> Recolor?`, `covers(id)`.
- `AccessoryModels` (Random Bakery's file whole, its comments made ours): `build(api, slot, kind, c, a, ctx) ->
  boolean`, `KINDS`, `grip(kind)`, the `Api` (`add ball cyl glow count anim HEAD ROOT ARM_R ARM_L`). `AccessoryBasics`:
  the bakery's own free hats, faces and wings (`b_<id>` kinds), `apron(api, option, tint)`, `bangs(api, id, color,
  streak, top)`, `BOTTOM` (the covering ones' lower edges).
- `CosmeticModels.parts(id) -> { Spec }` (each of this game's 83 own pieces: `{ name ("<id>_WearN"), size, at (the
  standing rig's space), color, shape?, rot?, bone ("head" | "body" | "hand" | "handL"), neon?, moves? }`, a few parts
  each, cached; the module asserts every piece without a `kind` has its model), `top(id) -> { torso?, arms?, trim?, hide? }?`, `covers(id) -> "top" |
  "hood" | nil`, the anchors `HEAD` (0, 3.125, 0), `BODY` (0, 1.875, 0), `HAND` (0.8125, 1.39, 0).
- (`Blocks.windy(root)`, the wind's `PixelWind` tags on leaves and flags, went on 2026-11-20 with the wind itself.)
- `BoatSpec` (the boat's plan: only the loading card's art draws a boat now; the ambient sailboats went with the sea on
  2026-11-20, the pier's boat and `moor` with the docks on 2026-11-13): `MAX` (6), `dims(level) -> { L, W, H }`,
  `deck(level)` (the four places on deck, founder first: deck-top coordinates, +Z the bow), `deckOverWater(level)`, `parts(level) -> { { name, shape ("Block" "Wedge" "CylY"), size, cf (from the
  deck top's centre; the `Bow` wedge turned over: tall at the hull, its keel sloping up to the point), color, neon?,
  wind? } }` (the hull and every detail of GAME_DESIGN 8 by level; flags named `Flag...`). Every user applies `cf`'s
  rotation (MicroModels.ship, StreetModels.boat).
- `StreetModels` (the floating islands since 2026-11-20: "Never mind, make it a floating island instead, with a 2d
  skybox. Expanding makes the island bigger."; no sea, beach, seabed, palms, shells or driftwood any more):
  `land(parent, origin, tier)` (the island, the model "Land": its chunks, its wall and the sign), `landPlan(tier) -> {
  chunks = { { name, rect } }, sign, walls }` (the island's chunks of `CHUNK` (8) x 8 cells on a grid from the plot's
  origin and clipped to the lot, each with any of the island in it; a chunk's name is `Chunk_<cx>_<cz>_<signature>`,
  two 26-bit hashes of every cell's code (`cellCode`: 0 the open air, else which of `BANDS` its coast distance is in:
  the wall's, the lawn's edge and rim, and every course's wobbling edges from `cutsOf`)
  in it and `LAND_MARGIN` (3) cells round it, and of the sign's place when it is near; a cell further in than the
  deepest course's inner edge reads the same on every tier, so an expansion changes only the chunks along the old and
  the new edge), `landChunk(parent, origin, tier, chunk)` (one chunk's `layers` and `scatterIn`),
  `wallsName(tier)` ("Walls_<tier>") and `landWalls(parent, origin, tier)` (the invisible wall round the tier's grass,
  one model of its own: out of the chunks, so a chunk's box (what the pixel filter draws again or ahead when it comes
  or goes) is only as big as what shows of it), `landSign(parent, origin, tier)` (the model `signName(tier)`,
  "Sign_<2x>_<2z>", holding the `PlotSign` with its `SignBoard` on the south rim, `Street.sign`), `emptyLot(parent,
  origin, opts?)` (an unclaimed plot: a little islet built the same way, 14 by 11, with a sign; `opts` `{ rx, rz,
  sign }` gives other half sizes in studs and `sign = false` none, for the rarity ladder thumbnail's islets), `LIP_BOT` (-3) and
  `BOTTOM` (-16.75: the deepest course's underside). Since 2026-11-20 ("for the floating island, detail the rocks and
  below like this too", with a picture) the edge is boulders: `layers(m, o, b, dist)` builds the `Lawn` (`LAWN_H` 0.5
  thick, top at `Street.LAWN_Y`, the founders stand on it; tone 2 dark along its rim and in patches, 1 light
  elsewhere) on every cell with a coast distance of 0 or less, then `COURSES`, nine rings of boulders, each `{ hi, w,
  top, bot, off, cols, foot, core, gap }`.
  - **Bands and depths:** a course's stones stand on cells whose coast distance lies between its inner edge and `hi`.
    The rim's band runs from the grass's edge (0) to 1.5; the other courses' `hi` values are 0.75, -0.25, -1.5, -3,
    -4.75, -6.75, -9 and -11.5. Heights run from -0.5 .. -3 for the rim down to -16.75.
  - **`cutsOf(x, z)`:** cached per cell, plot-local and the same on every tier. It wobbles each course's edge (always at
    least half a stud in from the course above) and lists every threshold the drawing compares a cell with: [k] course
    k's outer edge, [NC + k] its inner edge, [2 NC + 1] the inner edge of the deepest stones' band.
  - **Cores:** each course's core is a dark `bevelled` skin (`shell`: only cells with an east, south or south-east
    neighbour outside it), named "Lip" for the rim's soil and "Rock" below.
  - **`stones`:** one "Boulder" per 2-cell block of the course's grid (offset `off`, so courses are staggered), built by
    the chunk holding the block's first cell. Each stone is the block's band cells less `gap`, at least 0.75 across,
    with a jittered top and bottom; below the rim it steps out up to half a stud. Rim stones get a cap and on some a
    "Turf" with a tuft; seen stones on courses 1 to 5 get a darker foot. Stones below the rim are built only where
    their face shows (the camera's fixed angle never sees the north-west underside or anything behind an outer
    face); rim stones go all the way round, their tops show from above.
  - **`scatterIn(m, o, b, dist, sx?, sz?)`:** picks each kind's thing in its own block of the grid (`block` cells a
    side, the chunk's size a whole number of them): the block's cell with the lowest `hash01(x, z, salt)` among those
    in the kind's band, kept when a second hash is under its share `p`, never within 3 studs of the sign: tufts,
    pebbles and bushes on the rim (-0.95 .. 0), vines under the rim stones, `hanger`s under courses 4 to 9; none of
    the small things collide, so a chunk's things depend on its own cells alone.
  - **`cellCode`:** 0 past `REACH_CODE` (2.25), otherwise 1 plus how many of `BANDS` (0, -0.9, -0.95) and the cell's
    `cutsOf` the distance is at or under; a chunk's signature covers every threshold a cell is compared with, so
    chunks stay the same across tiers where the island did not change.
  - `bevelled` gained `shell`, and `quarters` an air-only mode in which only the outline is bevelled. The palette
    keys `cliff`, `cliff_dark`, `cliff_deep` and `cliff_base` (Data/Palette, in `Palette.order` and Shading's
    `TEX_STONE`) carry the stone from a light warm beige to a dusky violet. Land parts: 1019 on a first island, 4868
    at tier 10, 7129 at tier 20 (the sims hold them under 3000 and 12000). `walls(m, o, b, dist)`: the cells with a coast distance over 0 and up to `Street.WALL`, merged into boxes
  `WALL_H` (14) high from a stud under the lawn, invisible, in the collision group `Bounds` (the pixel filter's rays,
  group `PixelRays`, pass through them, and its redraws leave them out). The layers are bevelled (2026-11-13,
  GAME_DESIGN 8: "could you bevel these to make them smoother, with rounded corners?"; `bevelled(m, o, b, lv, lab,
  keep?)`): each layer is a region of cells with a label (the lawn's and the rock's tones), and a cell is four quarters
  (`quarters`): where both sides of a corner border another label the half at that corner takes it, a higher label
  filling a notch, a lower one cutting a square corner only where no notch beside it is filled (so the edge never
  zigzags). With `keep`, only the cells it says yes to are drawn (a ring along the outline: the lip, each ring of
  rock), the outline bevelled as the whole region's, so it meets the layer above with no seam. Whole cells are merged
  into boxes (`greedy`: by rows or by columns, whichever makes fewer); a half cell is a `WedgePart` lying on its side
  (`flat`), a run of half cells along a diagonal one big wedge where the cells it also covers are the layer's own in
  that label, a lone quarter two half-stud wedges. Only the lawn collides: a filled notch never does, a cell still
  wholly covered does, and a cut cell keeps an invisible part where it stood (in `Bounds`, named as its layer). Land
  parts: a first island about 600, a top tier one about 4,500 (the rocks' first island had 8,479). (The palms, the
  plaza with its campfire, the beach's shells, starfish and driftwood, the sea's water, seabed and shelves and the
  world's walls went: the plaza on 2026-11-20 with the campfire, the rest the same day with the sea.)
- `DecorModels.build(id, at, lvl?) -> Model` (its `Decor` attribute the id and `At` the frame it was built at, for
  Controllers/Spinners; every piece in `Data/Buildings`; `lvl` goes to the builder: a level
  kept from an older save, the tree's stage, or a water tile's neighbour mask plus 1; `at`: the footprint's centre on
  the grass, turned; each building with its doors, windows, ridged roofs with eaves and its own props (crates, barrels,
  sacks, pots, fences, lamps); a pennant (`PennantPole` at the back-left corner, which every builder keeps below 0.5
  studs; red at lvl 2, gold at 3 with a second flag and a lit `LampLight` lantern under a `LampCap` on the pole's top
  in place of its knob: since 2026-11-15, the front corner where the lamp stood holding the reworked buildings' props),
  only on a building (never on the tree, a path, a water tile or a fence, whose `lvl` means something else or nothing); the
  pier's pond and the fountain's water `PixelWater` 2; parts don't collide), `has`. It holds the
  builders of the old pieces and the tree (64), the 18 huts, workplaces and boosts of tiers 11 to 20 (2026-11-14:
  `shroomcellar` .. `citadel`, with `span` (a box between two points), `roundDoor`, `cap` (a mushroom cap) and `spire`
  (a tower roof in narrowing rings)), and takes the rest from the catalog's model modules below, by id (a builder of
  its own wins). The homes (Tent .. Manor) went with the villagers.
  The 50 buildings' builders live in five group modules, each `B: { [id]: Builder }` merged into DecorModels' table
  before the catalog's: `Models/FarmBuildings` (patch, pier, orchard, greenhouse, paddy, kelpfarm, skygarden,
  shroomcellar, pearlbeds, honeyterrace, vineyard), `Models/WoodBuildings` (lumber, sawmill, timber, bamboo,
  grandmill, logflume, ironwood, canopymill), `Models/ShopBuildings` (stall, cafe, inn, bakery, bazaar, hotel,
  nightmarket, theatre, skytram), `Models/HomeBuildings` (nest, burrow, den, roost, grotto, palace, loft, coralmanor,
  cloudkeep, citadel, hatchery) and `Models/BoostBuildings` (toolshed, windmill, smokehouse, market, watertower,
  townhall, beacon, seedvault, guildhall, tradehall, tidebell). The request of 2026-11-15 ("could you rework and detail
  every building even more? look at the bakery game for reference") rebuilt all 50 at two to four times the parts
  (60 to 175 each), each with its own small helpers (shingled roofs in rows, windows with frames and flower boxes,
  lanterns, crates and barrels with proud straps) inside its footprint and its pennant corner, every size a multiple
  of 0.25 (`Blocks` snaps them) so no two faces of different colours lie in one plane. The spinners keep their names
  and hubs (the windmill's `SailArm` and `Sail` round (0, 3.4, 0.9), the grand mill's 13 `Paddle`s round
  (1.6, 1.5, -0.6)); water keeps `PixelWater` (2 still, 3 foam, 4 falling); smoke rises from parts named `Chimney` or
  `Vent`; birds perch on `Ridge`. Their shared helpers are `Models/BuildKit` (`BuildKit.box`, `ball`, `cyl`, `log`,
  `tube`, `palmTrunk`, `wedge`, `roof`, `window`, `sideWindow`, `door`, `crate`, `barrel`, `sack`, `pot`, `footing`,
  `fence`, `fenceZ`, `lamp`, `fruitTree`, `awning`, `storey`, `flatRoof`, `streetLamp`, `blades`, `pennant`, `span`,
  `roundDoor`, `cap`, `spire`); since that rework `roundDoor` faces +Z (a quarter turn round Y: the old turn round X
  left the disc facing the side), `storey`'s walls stand on its band instead of around it, and `crate`'s strap and
  `barrel`'s hoops stand a whole grid step proud (snapped, the old ones shared the body's faces and flickered).
  `tube(m, f, pts, dia, color, name,
  cap?)`: a round trunk or strand through points, a cylinder between each two and a ball at each joint as wide as the
  segment below (widths on the 1/8-stud grid, lengths exact, so it bends with no gap or step); the Palm Tree's trunk is
  one (the catalog's Palm Tree, `B.palm`, is StreetModels' palm a little fuller since 2026-11-15: eight fronds, five
  coconuts, its crown where it was, a two-step sand mound at its foot with a fallen coconut, a split one showing its
  white and a tuft of beach grass; about 77 parts). The Tree of Life
  (`tree`, 8 x 8; GAME_DESIGN 6 has the references it was drawn after): an `EggLawn` (7.8 studs across: its eggs lie
  on it), a `Lawn` and `Moss`; a ring of standing `Stone`s at radius 2.3 (1.25 and 0.75 tall, times 1.2 from stage
  4; `StoneMoss` tufts, gold from stage 4, moss down the face, `Lichen`, a gap at the front);
  `Root`s flaring from about 1.8 studs up the trunk, the big ones dipping into the ground and coming up again past the
  stones, with rootlets (simpler behind the trunk); a `Trunk` core and three braided `Strand`s (each a `tube`, one
  facing the camera, the other two ending either side of the doorway), `Knot`s with dark hearts and `BarkMoss` on the
  camera's side (no `Rune`s or `Glyph`s since 2026-11-20: they drew as blue rectangles); the `Hollow` at the front
  with its glowing `Pod` (Neon) in an arched frame (`Lintel`, `Jamb`s), a stone `Step` and a `Lantern` on a `Post` either side (from stage 1); a
  `BirdHouse` (`BirdRoof`, `BirdHole`, `Perch`) on the trunk; round `Branch` limbs (tubes) out to the leaf clouds,
  each one `Leaves` ball with `LeafPuff` lobes, `LeafLit` patches on the sunny side and `LeavesUnder` beneath (the
  clouds at the back darker), `Blossom`, swaying `Vine`s (chalk, so they don't rustle) with `VineFlower`s and a
  `VineTip`, and Neon gold `Fruit` on a `Stalk` under it; a `Ring` of gold Neon dashes on the ground,
  mushrooms (`Stem`, `Cap` and `Spot` balls), `Flower`s and `Fallen` blossom; the ground, the stones and
  the roots inside the inner 6 x 6, nothing standing between 3.05 and 3.85 studs out all the way round (the eggs).
  About 435 parts at stage 1 and 817 at stage 6 (269 and 623 before the rebuild of 2026-11-15). Its stage (`lvl` 1 .. 6,
  `Tree.stage`) scales it above that ground: the trunk's girth, the limbs' and the ring of clouds' height, the top
  cloud's height (12.2 studs x 1, 1.18, 1.36, 1.55, 1.68, 1.8), the crown's spread and each cloud's size; more `Blossom`; `Lantern`s (Neon) from stage 2; eight ring clouds, four more above them and three
  `Fruit` a cloud from stage 3; from stage 4 blossom on every cloud, a `Halo` of gold Neon over the crown, gold caps on
  the stones and a second ring of light; from stage 5 a `Lantern` under every limb, a second, wider `Halo` and three
  `Floating` stones round the trunk (`FloatingMoss`, a `Pebble`); at stage 6 `GoldLeaves` in the crown,
  a third ring of light and two low `OuterStone`s with `OuterCap`s in each corner of the lawn (radius 4.7 to 4.95,
  off the eggs' ring, inside the 8 x 8); no Lv 3
  pennant (its `lvl` is a stage). `DecorModels.HOLLOW` (the hollow's
  foot in the model's frame: where a hatchling steps out when its egg's place is unknown, `EggView.hatchPoint`) and
  `DecorModels.EGG_RING` (3.45: the studs from its middle to the eggs' circle, `EggView`).
- The build catalog's model modules (GAME_DESIGN 4), each a table of builders `(m, f, lvl)` by piece id (`f` the
  footprint's centre on the grass, turned; +Z faces the view before the turn), merged into `DecorModels`:
  `GroundModels` (the 18 new paths: each tile covers its square or keeps the same gap at every edge, so tiles side by
  side join with no seam, its small things moved about by `Parts.hash` so a long run never repeats, at most 8 parts a
  tile; and the 7 waters: `lvl` - 1 is the tile's neighbour mask (north 1, east 2, south 4, west 8,
  `PlotService.waterMasks`), the water over the whole tile, a bank only along the sides with no water next to it and
  a block rounding the corner where two banks meet), `FenceModels` (the 17 fences: one length along X from -1 to +1
  at z = 0 with a post at each end that the next length shares, within about 0.35 of its line and at most 8 parts; six
  of the bridges, along Z, landing on the grass at z -3 and +3 (the Canal Bridge is DecorModels' own); the 8 pieces for
  the water, floating at its surface), `NatureModels` (37 trees, plants and rocks, four of them for tiers 11 to 20; the Palm Tree, Round Bush and
  Flower Bed are DecorModels' own; blossom, maple leaves, snow and grass marked to sway as leaves do; no trunk is a
  stack of steps: one column from the ground (on a flat plate of `Root` at most), or a `tube` through its bends (the
  Bare Tree, the Bonsai), as DecorModels' `tube`; nothing reaches lower into the ground than before, since the
  catalog's pictures and the loading card stand a model on its box), `ThemeModels`
  (42 pieces of the beach, garden, farm, harbour, town and jungle rows, six for tiers 11 to 20) and `ThemeMoreModels`
  (35 of frost, autumn, desert, fairy, zen and volcano, six for tiers 11 to 20), each theme in its own colours, its lights Neon so they glow at night, and
  `FunModels` (the 24 seats, lights, play pieces, treats and fountains not modelled before, the Big Wheel, the four
  grand pieces of tiers 7 to 10 and the four of tiers 12 to 20). Since the request of 2026-11-19 ("detail all decor
  more, some having animations, as much as in the bakery game and as much as the work/hut/ main buildings") every
  decor builder in these modules and in `DecorModels` is about twice as detailed (20 to about 130 parts a piece), its
  moving parts marked with `Parts.move` (Controllers/Spinners) and its flames, jets and gems named `Flame`, `Spray`
  and `Sparkle` for the ambient layer; each module keeps its own small helpers for it (FenceModels `lap`, `tuft`,
  `fern`, `ride`, `hangLantern`, `pad`; FunModels `mover`, `fall`, `tuft`, `bloom`; ThemeMoreModels `cone`, `swing`,
  `snowpine`, `porthole`; DecorModels `at`, `discZ`, `discX`, `bar`, `onBall`, `ringOf`, `flower`, `tuft`, `lantern`,
  `crystal`, `moveAll`). The waterwheel still turns by its parts' names (`Rim`, `Spoke`, `Paddle`). They build through `Parts` (the same shapes `DecorModels` uses, through `Blocks`: anchored, no
  collision, palette colours, the 0.25-stud grid, never thinner than 0.25, in the piece's frame: `box`, `turned`, `at`,
  `ball`, `cyl`, `log`, `logZ`, `wedge`, `glow` (Neon), `water` (a flat water part with `PixelWater` 2, moving like the
  shallows), `hash(f, k?)` (a number 0 .. 1 from the tile's place), `move(part, kind, hub, axis, speed, amp?, phase?)`
  (a part that moves in the client, Controllers/Spinners: "spin" round `axis` "X" | "Y" | "Z" of the piece's frame
  through `hub` at `speed` rad/s, "swing" `amp` rad either way at that pace, "bob" `amp` studs up and down with a
  little rock; its `Move*` attributes; also `BuildKit.move`; 2026-11-19)).
- `MicroModels` (the driftlings and the island's small things): `build(kind, opts?) -> Thing` (`{ model, parts, rest, sizes,
  baseRest, baseSize, colors, h, r, kind }`, a few palette parts round the origin, facing +Z), `driftling(shape, body,
  accent)` (the 37 body plans of `DriftModels`), `sailboat`,
  `ship` (a boat from `BoatSpec` at `opts.level`: its origin on the waterline; StreetLife's boats), `flutter(thing, t)` (a
  thing's `Flag...` parts ripple: their depth and height step through four frames), ambient kinds (`bird
  butterfly light flame crab ...`), `slab`, `grid`, `hoop`, and the fights' `aim`, `aimpath` and `aimring` (nothing
  builds them now), `place(t, cf)`, `scale(t, k)`,
  `recolor(t, color?)`, `show(t, on)`, `has`. `place` moves a thing's parts with one `Workspace:BulkMoveTo` (its part
  list kept per thing; part by part while the model is outside Workspace). Parts keep their sizes to the eighth of a stud (about an art px), not
  Blocks' quarter. `species(id, lod?)` builds a species (Data/Creatures) with its look (and its id, for its plan's form; an unknown id
  is a steel armadillo); `driftling(shape, body, accent, lod?, look?)` is `DriftModels.build` (below; WorldView builds "world",
  everything else the default "full"); `animate(t, time, mood, k?)` hands
  a driftling (`t.rig`) to `DriftModels.animate` with the squash of `scale` (its clock must run on smoothly: the
  springs and blends use it; WorldView places a driftling on the ground and the rig lifts it), and moves the other
  things' limbs by name
  (`Wing*` flap, `Tail*` wag, `Eye*` blink...; `flap(t, cf, phase, glide?)`). WorldView and StreetLife call
  it every frame (WorldView poses a driftling more than `FAR_POSE` 40 studs from the view's centre every fourth frame
  only, staggered by its id). The driftlings' parts are on the kit's 0.05 grid (DriftKit, below).
- `DriftKit` (GAME_DESIGN 6, "Look at the cakes in the bakery game to reference how detailed they should be"): the
  driftlings' building kit, after Random Bakery's FoodKit. Builder state (the thing being built, its current joint):
  `new(shape, h, r, gait)`, `J(name, parent?, pivot, kind, side?, phase?)`, `on(joint)`, `finish()`, `setFull(on)`,
  `full()`. Parts on the 0.05-stud grid (a Ball's diameter its smallest side): `part(name, shape, size, cf, color,
  neon?)`, `P` (centre and turn), `D` (full only), `keep`. Round shapes: `ball`, `disc(name, at, normal, d, th, color,
  detail?, onR?)` (flat, sunk onto a ball of radius onR so its rim meets the surface), `rod(a, b, d)`, `blade(base,
  tip, w, th, normal)` (a flat pointed triangle: two mirrored half wedges), `tube(name, pts, radii, color, step?)` (a
  capsule chain along a Catmull-Rom curve: cylinders between points with a ball at each joint, the joints' balls 0.86
  of their links so no two surfaces lie flush, the ends round), `strip(pts, widths, normal)` (overlapping coplanar
  discs), `pillow(center, R, h, up)` (a disc with a ring of balls round its rim), `ovoid(center, half, color, rot?)`
  (an ellipsoid of balls along its longest axis, two or three rows where it is much wider than deep), `tuft`,
  `toes`, `whiskers`, `onBall(c, r, dir) -> (point, normal)`, `along(at, dir)`, `curveAt(pts, u)`. The face:
  `eye(side, hc, hr, dir, d, iris?, dark?)` / `eyes(hc, hr, dir, spread, lift, d, iris?, dark?)` (two dark discs for
  an oval, an iris disc, two shines, a lid of small balls), `blush`, `mouth(at, n, w)` (a smile of two rods, an open
  mouth disc and tongue). Face parts are listed in the thing's `face` table: "eye" (tucked in while shut), "lid" (out
  only while shut), "open" (out only while the mouth is open), "closed" (out only while it is shut); a tucked part
  sits `TUCK` (0.14) studs in along its local +X, its normal. `detail` arguments and `D` drop a piece from the "world"
  level of detail. `Thing` adds `face` and `lod` ("full" | "world") to DriftModels' old fields.
  Looks (2026-11-14, "Can you use different eyes for each?"): `setLook({ eye?, iris?, body?, accent? })` (DriftModels.build
  sets it) picks `eye`'s style: sparkle, lashes, button, bead, dot, star, heart, round, wide, specs, slit, bar, ringed,
  sleepy, fierce, happy, glow, gem, visor, compound. Since the request of 2026-11-15 ("the eyes still do not look
  detailed or accurate and are mostly just simple discs") `Kit.eye` makes each eye an **eyeball**: an "Ell" solid
  (`EYE_SIZE` by style, 1.15 x `d`; its depth 0.3 of its width, sunk so it meets the head at `EyeTex.EDGE` 0.9 of its
  radius) in a frame whose +Z is the head's normal there, its "PixelEye" attribute the style and "PixelEyeIris",
  "PixelEyeDark", "PixelEyeLid" (Color3s) and "PixelEyeSide" (-1 left, 1 right) what `Render/EyeTex` paints on it; a
  face part "eye". Every style but happy also gets its blink lid: the same eyeball shape 1.08 x 1.1 x 1.15 as big in
  the body colour, painted "closed", standing 0.04 studs over the eyeball's front, a face part "lid". Extras in 3D:
  lashes (three tapered limbs at the outer top, full only), fierce's brow (a tapered limb slanting inward), specs' rim
  (a ring of limbs, and the bridge's half, in the iris colour). The renderer (`registerDynamic`: `DynPart.eye`;
  `SG.shadeEye`) and Snapshot (`Picture.Solid.eye`, the dominant layer's colour into the G-buffer, a lift as a step
  toward white or black) paint an eyeball per pixel: the hit point in its frame gives (u, v) on its face,
  `EyeTex.sample` the layers there, each lit by `Shading.toonAt` as its own palette colour (a catchlight or a lit eye
  glowing), an edge layer mixed over its share (`Shading.softMix`). Each face part records `tuck[name]`, its sink
  against the normal it was made on in its own frame (a rod or a blade hides as a disc does); a part without one sinks
  along its -X.
- `DriftAnatomy` (GAME_DESIGN 6, the request of 2026-11-15: "can you redo all the creatures and eggs and add alot more
  extra ones with more variation to them? currently, all of them are modelled using blobs, which is unnatural.
  reference other models online to see how you should model them"): the body parts the plans are sculpted from, on the
  kit's smooth solids (`Kit.ell`, `Kit.egg`, `Kit.limb` (a tapered limb from a to b, radii ra and rb, `flat` squashing
  its cross-section toward `flatN`), `Kit.limbs` (a chain along a Catmull-Rom curve; on the islands half the links, at
  least two), `Kit.tri(name, a, b, c, th, color, neon?, ja?, jb?, jc?)` (a flat triangle as two right wedges onto its
  longest side, `Kit.wedgeFrame(sharp, corner, top, th, snap)` each; with a joint for each corner it is a `Membrane` on
  `Rig.mem`, `{ a, b, c, ja, jb, jc, w1, w2, th }`, stretched by DriftRig as the joints move: the bats' and the drakes'
  wing membranes, the request of 2026-11-18, "scorchwing and other bat type creatures have their wing parts seperated
  instead of being one whole wing while they are flapping"), `Kit.faceOn` / `faceOff` / `onEll` / `onFace`: the face's surface an ellipsoid). `A.body(name, c, d, len,
  wide, tall, split, color) -> (part, Mass)` (an egg lying along d, the hips its narrow end), `A.blob`, `A.patch(name,
  mass, d, shrink, out, color)` (a smaller copy pushed out toward d: a cap of colour curved with the body), `A.on`,
  `A.reach`; `A.leg(n, side, phase, hip, opts)` (its joint and a "fore" leg down to a wrist, a "hind" one forward to
  the knee and back to a hock, a "post", a "bird" leg with a feathered thigh and a bare shank, a "frog" leg folded;
  feet "paw", "hoof", "claw", "pad", "bird", "web", "frog"), `A.paw`, `A.hoof`, `A.claws`, `A.birdFoot`; `A.head(opts)
  -> Head` (the "head" and "jaw" joints, a cranium, a muzzle "fox" "dog" "cat" "bear" "deer" "pig" "beak" "duck"
  "lizard" "frog" or "none", the nose, cheeks, the eyes on the cranium, blush and the mouth), `A.ears(head, opts)`
  ("fox" "cat" "round" "long" "droop" "leaf" "tuft" "fin" "big"; an inside and a tip standing 0.04 studs proud),
  `A.horns` ("nubs" "spike" "goat" "ram" "antler" "stag" "drake"), `A.tail(base, opts)` ("brush" "whip" "lizard"
  "stub" "puff" "curl" "flat" "fluke" "plume" "club"), `A.wings` ("bird" folded or open, "bat", "insect"); colour
  helpers `A.shade`, `A.under`, `A.ink`, `A.iris`, `A.isDark`, `A.isPale` (the palette's "chalk" is a dark board green,
  0x2A5F3D, not white); `A.dir`, `A.lie`, `A.mx`, `A.lerp`. The plans add their own local helpers where these fall
  short (DriftPlansE's `dot` and `eggOn`, DriftPlansF's `birdLeg`, DriftPlansB's camera-facing wings).
- `DriftPlansA..F` (the same request): every body plan rebuilt on the smooth solids, sculpted the way a modeller
  blocks a creature out over its skeleton, and each module's `forms` (Data/Creatures id -> the options its plan reads:
  ears, tails, horns, manes, crests, props, proportions, markings), so no two species of a plan are recolours. Each
  module returns `{ plans, forms }`; a plan is `(b, a, form?) -> Thing` facing +Z with its feet at y 0 (a form may set
  `gait`: the cloud whale and Cloudpip fly). A: pup (foxes and the wolf), cat (lynxes, the kitten, lions, the temple
  cat), bear, otter (Kelpup sits up and holds its shell: biped, arms), monkey (the lemur), yeti. B: deer (fawns, stags,
  the goats, the unicorn, the kirin), ram (wool of soft puffs), elephant (the trunk on two "tendril" joints), griffin,
  drake (a "neck" joint now). C: bun, mole, hedgehog, armadillo, turtle (tortoises on pillars, sea turtles on
  flippers, props on the shells: a cloud farm, a reef, a temple), golem (stone, wood, ice and basalt from blocks,
  wedges and hexagonal columns marked "PixelOwn"). D: lizard (the gecko, the axolotl, the chameleon, the crocodile),
  frog, crab (Rubblet in a brick), beetle, snail, wyrm. E: seal (and the cloud whale), fish, ray, seahorse, octo, jelly,
  shroom, sprite (legs and ears now). F: bird (the heron, the phoenix, the swift...), owl, penguin, duck, bat, moth (the
  butterflies and the bee). Full about 40 to 120 parts, the islands' level about 26 to 60 (most of an old face's parts
  went with the painted eyes). The old ball-built plans (DriftOldA..D) are gone. Up close the body is one blended
  surface (9.1): `DriftModels.build` marks every smooth solid but the face, the lit bits and the thin details (under
  `BLEND_MIN` 0.07 studs across its middle size) with "PixelBlend" (`BLEND` 0.07 x the height, as a share of the part's
  largest size); `A.ears` and the elephant give each ear a thick root ("EarRoot", full level only) so the head runs
  on into the ear. Faces (the request of 2026-11-16, "Detail the faces of the creatures even more. Add more details based on
  the shape and details of the creature's bodies"), full level only: `Kit.look()` (the species' look, its textures
  `tex`/`tex2` among it), `Kit.faceRec()` (the eyes and mouth just built: `EyeRec`, `MouthRec`), `Kit.faceClear()`,
  `Kit.joint()`; `A.face(o: FaceOpts)` (brows shaped by the eye style and the texture, a line from the nose to the
  mouth, whisker dots, beak nostrils and gape line, lip scales, cheek tufts, feather or scale edges, freckles, glowing
  freckles on ember, cracks on stone, a crown: a crest, a gem, a leaf, a frost star, a plate; `A.head` calls it, custom
  heads call it themselves), `A.more(plan, species)` (a species' `faceDetail` form over the plan's: marks blaze, star,
  spots, freckles, kohl, glow, crack, gem, leaf), `A.markC(c)`. Blushes are painted on (the request of 2026-11-16, "make the blushes drawn on instead
  of discs too"): `Kit.blush` still builds its disc (Roblox's own view) but marks it "PixelPaint" with the oval it
  paints, "PixelPaintA" and "PixelPaintB" (across and up the face, over their radii: a little wider than tall) and
  "PixelPaintN" (along the normal, over its reach), in the disc's frame. The pixel filter never draws such a part:
  `registerDynamic` keeps it as `DynPart.paint`, `drawModel` turns each mark's oval into world space a frame
  (`SG.paints`), and every part near one (`SG.paintOn`, per blend member `SG.blendPaint`) is shaded through
  `SG.paintAt` (inside the oval the mark's colour, the head's light kept; on its edge one step between the two; a
  plain lit part near a mark takes `SG.shadePaint`, the per-pixel form of `shadeLit`). `Snapshot` reads the oval into
  `Picture.Solid.paint` and `Picture` paints its G-buffer the same way (`job.paints`); the blended body's members cast
  the picture's shadows as the opaque solids do.
- `DriftModels` (GAME_DESIGN 6, "more detailed ... look more like the animals", "different moving parts"): the 37
  body plans (`PLANS`, from `DriftPlansA..F`: `pup cat bear otter monkey yeti deer ram elephant griffin drake bun mole
  hedgehog armadillo turtle golem lizard frog crab beetle snail wyrm seal fish ray seahorse octo jelly shroom sprite
  bird owl penguin duck bat moth`; an unknown shape builds the armadillo) in its species' body and accent colours and
  its form (`FORMS[look.id]`, or `look.form`), built on a skeleton: `Rig { joints (name -> { parent?, pivot, kind, side, phase }), order (parents first), of
  (part -> joint), gait ("quad" | "biped" | "hop" | "scuttle" | "slither" | "fly"), world }`. Joint kinds: `body` (the
  root), `head`, `neck`, `jaw`, `ear`, `arm`, `leg`, `tail` (segments in a chain, `phase` their order), `wing` (an
  outer segment as a child), `fin`, `stalk` (eye stalks), `pincer`, `tendril` (two segments), `antenna`, `shell`.
  `build(shape, body, accent, lod?, look?) -> Thing` (with `rig`; `lod` "full", the default, or "world"; `look` `{ id?, eye?,
  iris?, tex?, tex2?, form? }`: the eyes, and a "PixelTex" attribute on every non-face, non-Neon part of the body colour
  (`tex`) or the accent (`tex2`)), `has(shape)`, `animate(t, time, mood, k?, squash)`: hands it to `DriftRig.animate`
  (below). The kit's `Rig` also carries `skel` and `anim` (DriftRig's skeleton and motion state, made when first
  posed) and `placed` (the CFrame `MicroModels.place` last put it at: the springs feel it move).
- `DriftRig` (GAME_DESIGN 6, the request of 2026-11-14: "please use bones and rigging to make more realistic and
  detailed movement. follow and use as many animation principles when animating as well"): the skeleton and skin.
  Roblox's `Bone` instances bend only skinned MeshParts (uploaded meshes); a driftling is plain parts drawn by the pixel
  filter, so the rig is in code. `skeleton(t) -> Skel { bones, skins, root, ground, tempo, seed, full }` (kept on the
  rig): a `Bone { name, parent (index, 0 the root), pivot, kind, side, phase, axis, len, spring?, children }` per joint,
  its tail the farthest of its parts' centres and its children's pivots; a `Skin { name, part, r0, b1, b2, w, face?,
  tuck?, shine, blink?, size }` per part: on its bone `b1`, and a small part (no side over 0.55 studs, not a face part)
  within a third of a bone's length of a joint (0.12 .. 0.32 studs) shared with the bone across it, `w` 0.5 at the
  pivot down to 0 (`BLEND` kinds: neck head tail ear arm leg wing fin tendril stalk antenna; the jaw and pincers
  hinge). `tempo` (1.9 / height)^0.35 in 0.82 .. 1.18 (a bigger one is slower); `seed` its own phase. `animate(t, time,
  mood, k?, sc)`: the mood's program (DriftMotion) and each bone's pose, blended from the last mood's over `BLEND_T`
  0.28 s; forward kinematics (`world[i] = world[parent] * T(pivot + shift) * turn * T(-pivot)`, a stretched parent
  carrying the child's pivot with it); `SPRINGS` (ear, tail, antenna, tendril, stalk, fin, and a wing's outer
  segment: stiffness k, damping z, max turn) as a point mass at the bone's tip in world space (with `placed`), up to
  four substeps a frame, the bone turned toward it (at most `max`), reset on the first pose, a jump in the clock or a
  move of more than `TELEPORT` 3 studs in a frame; then the skin: each part at `world[b1] * r0` (lerped toward
  `world[b2] * r0` by `w`), stretched with its bone along its axis (volume kept), and everything squashed by the body
  bone's stretch from the ground (y 0; a flyer about its body's pivot), x and z by 1 / sqrt. Up close (`full`) the
  parts' sizes follow the body's squash in `SIZE_STEP` 0.05 steps, written only when they change; on the islands
  ("world") only positions squash. Face parts tuck as before. Then the membranes (`Skel.mem`): each corner where its
  joint's bone puts it (stretched and squashed as a part's centre is), the triangle's foot on its longest side found
  again, and its two wedges' frames and sizes written afresh (their skins marked `mem`, left out of the size step), so
  a wing's panels on the arm, the hand and the body stay joined edge to edge however the wrist bends. Before, each
  panel rode one bone whole and the ones crossing the wrist parted from the hand's. `stretchAt(p, o, axis, s)`, `stats(t) -> { bones,
  springs, parts, shared }`, `debugSprings(t)` (each spring's turn, degrees: the previews).
- `DriftMotion` (pure, no instances; tests/specs/DriftMotion.spec.luau): `ease(id, x)` (`LINEAR SMOOTH OUT IN BACK
  HOLD`), `track(keys, u)` (keys `{ u, value, ease }`), the key sets `JUMP` (ty, sq, rx, leg: crouch, push off, the
  arc, the fall, the landing squash, the settle), `WALK` (`duty` 0.6, `amp` 0.55, `lift` 0.1, `bob` 0.035, `sq` 0.02,
  `roll` 0.035, `twist` 0.05, `rate` 1.9 strides a second), `LOOK`, `WEIGHT`, `YAWN`, `PECK`, `DIP`, `LUNGE`, `TWITCH`;
  `newProg()`, `program(mood, t, age, k, gait, tempo, seed, out) -> Prog` (the shared values of a frame: the body's
  turns, shift and stretch `brx bry brz btx bty btz bsq`, the head's `hrx hry hrz htz hsq`, `jaw`, the ears, arm and
  leg modes, the stride or jump phase `u`, the tail, wing and fin waves, `shut`, `open`), `bone(prog, kind, side,
  phase) -> (rx, ry, rz, tx, ty, tz, sq)`. Moods: idle (breathing, the weight shifting every 8 s, a look about every
  6 s with a counter-turn first and an overshoot, a yawn every 11 s, ear twitches one at a time, blinks and double
  blinks), walk by gait (since the request of 2026-11-15, "most creatures seem to walk around by bouncing instead of
  actually walking. could you animate them to walk instead of bouncing?", a walk with no hop for two and four legs and
  the hoppers too: each leg planted `duty` of the stride, sweeping back evenly, then lifted `lift` and swung forward
  eased, legMode 1 by each leg's phase (four legs in diagonal pairs, two in turn) and legMode 7 for a hopper, whose legs
  are built in step, by side; the body `bob` studs higher passing over a planted leg and `sq` squashed as the other
  lands, rolling onto the planted side, the hips twisting, the head nodding a beat late and keeping level, the arms
  swinging a beat behind the legs; a slither's sway; a scuttle; flight; hoppers still jump in cheer and hop),
  cheer and hop (jumps: cheer higher, arms up, mouth open), hooray (one jump from the mood's start, then the cheer's
  pose held; since 2026-11-16 nothing just hatched plays it: the hatch scene and WorldView keep it idle), rest (the pose as built, eyes open: the portraits), attack (the `LUNGE` over k), hurt (by its age: a hard
  squash wobbling back, flung back, ears folded back), ko, and the work moods peck, push, dip, wave and nap. `PITCH`
  scales how far a long body (four legs, a serpent) tips.
  Since the request of 2026-11-16 ("Pose and animate them in ways that make them look natural and lively and bring
  out what they are more") each driftling has a manner: `program(..., style)` takes the rig's `style` (its plan's
  name, or its form's `style`: `DriftModels.build` sets `rig.style`), `style(name)` gives `STYLE[name]` (one for each
  of the 37 plans, fifteen for species: lion, horse, goat, chameleon, croc, axolotl, seaturtle, seaotter, whale, heron,
  skybird, toad, hermit, bee, treant; and `default`, the old manner). A style is a flat table: `acts` (names in
  `ACTS`) and `every` (seconds between them, 3 to 8); the carriage every frame (`lean head ear twitch tail tip sway
  swayF wag breath breathT weight arm armOut wing wingAmp wingF hover hoverF finAmp finF small fluke`); the looks
  (`look tilt snap lookBody reach`); the walk (`bob nod walkWag walkTail roll bend heavy hump pulse flyWing flyWingF`);
  and `cheer` (jump, flap, leap, splash, claws, wave, wag, trumpet, clap, bounce, flutter, pound, binky). `ACTS[name] =
  { dur, fn }` (about ninety: wag, sniff, shake, bow, groom, stretch, knead, howl, pounce, thump, situp, swivel,
  graze, trunk, earflap, stomp, peck, preen, ruffle, flap, waddle, throat, pushup, tongue, snap, antennae, stalks,
  retract, coil, drift, dart, pulse, wave, bounce, flutter, clap, chest, curl, dig, butt, oneleg, strike and more):
  each eases in and out, starting and ending at rest, and scales a beat of fixed speed so nothing skips. Idle time is
  cut into windows of `every` seconds offset by the seed; most windows play one act at a seeded moment (never the
  window before's), the rest nothing (`actAt(style, t, seed, tempo)`, `act(prog, name, u, t, side, style)`). New
  program fields (reset each frame): ears `earL earR earYL earYR`, arms `armL armR armLz armRz`, legs `legF legH
  liftLeg legLift legUp plant free shuffle`, `tailRy tailTip wag`, `wingL wingR`, `finY finZ`, stalks `stalkSq stalkX
  stalkZ stalkTurn`, tendrils and antennae `tendrilAmp tendrilRx tendrilTip tendrilRz flare antAmp antRx`.
  `bone(prog, kind, side, phase, dx?, dz?)`: `dx, dz` the bone's pivot from the root's (`DriftRig`'s `Bone.dx/dz`), so
  planted feet stay put while the body leans or rises and tendrils spread from the middle. The leg's sign: + rx swings
  a hanging foot back, so a walk plants each foot ahead of the hip and sweeps it back (it used to slide), and `JUMP.leg`
  is + forward. Pure arithmetic, nothing allocated a frame.

### 6.x One kind of work, the wondrous mutations, every egg everywhere, the rewards (2026-11-19)

The request: "Look at the bakery game and see its menu. Make a similarly polished and themed menu for different tabs.
Also, add rewards for playtime, daily rewards, streak rewards, codes, and as many retention features you can think of.
Also, remove work building types. ..." (GAME_DESIGN, the top). What changed in the contract:

- **`Data/Buildings`**: farms, lumber camps and shops are `kind = "work"`, with `act` ("farm", "wood" or "shop": only
  what the driftlings at it look like doing, `Controllers/WorldView`, and its `feel`); TAB `work` for work and gen, SUB
  `work` / `gen` (Build mode's Work tab: All, Workplaces, Boosts). A boost building has no `boost` field: its `boostBy`
  counts at every workplace. `Data/Creatures` has no `knack`.
- **`Data/Traits`**: `TOP` 5; `KEYS` work aura all hatch boost charmPct charm luck skip eggs away cost sell; `ISLE` (the
  effects a hut's driftling gives the whole island); families sturdy (cost), fierce (sell), armor (charm, flat), bright
  (luck), busy (work), grower (hatch), chopper (boost), trader (charmPct); the weather's seven; `wonders` (six, tier 5,
  ids `<family>5`: golden all, maestro aura, twin eggs, prism skip, dream away, heart charmPct and charm);
  `TIER_COLOR[5]` "mythic", `TIER_NAME[5]` "Wondrous"; `at(family, tier)` (a wondrous family's own id); `roll(rng,
  rarity)` (no lean); `work(fx)` (a share at work); `RENAMED` (`angler` -> busy, `swift` -> bright).
- **`Logic/Island`**: `isle(p) -> Isle` (`{ luck, cost, hatch, boost, charmPct, all, aura, eggs, skip, away }` from the
  huts' driftlings, each to `Tuning.IsleCap`; `hatch` a multiplier: each share takes its part off what is left, down to
  `HatchMin`); `charm(p, isle?)` (flat charm times 1 + charmPct); `boostShare(id, k)`, `boostRaw(p)` (every boost
  building, stacking by `BoostStack` within a kind, at most `BoostMax`), `boost(p, isle?)` (raw times 1 + isle.boost),
  `boostInfo(p, id) -> { count, raw, total, mult, more }` (the hover card's); `works(id)` (kind "work");
  `palWork(p, pal)`, `palBoost(p, pal, comfort?, aura?)`; `output(p, isle?)`; `rates` (times 1 + isle.all and
  `timedMult`); `timedMult(p)` (1 + `TimedShells` while a Busy Day runs); `passMult`; `step` (the timed boosts run down);
  `freeJob(p)`; `arrange` (one list, the fastest driftlings to the best workplaces).
- **`Logic/Tree`**: `lot(p)` (the tier's count and `isle.eggs`); `luck(p, tier?)` (the huts' luck and a Lucky Hour's
  `TimedLuck`); `odds` (a rarity no open kind has weighs `EggEarly` of its weight); `roll(p, rng, rarity, season?,
  tier?)` (a kind not open yet with `FarKind`, or always when no open kind has that rarity); `rise` (`isle.skip` added to
  each `EggUp` step); `MAKE_ROOM` ranks "work"; no `lean`.
- **`Logic/Rewards`** (pure; GAME_DESIGN 15) over **`Data/Rewards`** (`DAILY`, `MILESTONES`, `PLAY`, `TASKS`,
  `TASK_COUNT`, `BONUS`, `SPIN`, `INDEX`, `BOOSTS`, `BOOST_MAX`): `day(now)`, `fresh()`, `give(p, r) -> Given` (spins and
  timed boosts here, the rest through `Store.give`), `daily(p, now) -> Daily`, `claimDaily`, `sync(p, now) -> changed`
  (the day turning: playtime reset, three tasks dealt), `tick(p, now, dt)`, `claimPlay`, `taskState`, `claimTask`,
  `claimBonus`, `spins`, `spin(p, rng, now)`, `norm(code)`, `redeem(p, code, defs, now)`, `kinds`, `claimIndex`,
  `view(p, now) -> View` (`{ daily, play, playGot, tasks, bonus, spins, kinds, indexGot, ready }`). Days are compared
  in order (today later than the last claim's, never just another day: a server whose clock runs behind gave the day's
  daily, free spin, playtime and tasks again, and `Store.vipDaily` its gift; the server review of 2026-11-19).
  **`src/server/Config/Codes`**: the codes (server only). `IslandService` runs `Rewards.sync` and `tick` every second
  (the tick's Fx carries `play`); `Session.view` adds `rewards` (`Rewards.view`) and `boosts`. `Logic/Store.offline`
  pays `1 + isle.away` times as much.

### 6.y Two of each boost building, the fabled mutations, Ancient and Eternal (2026-11-20)

The request: "make the max of each boosts building to be 2. also, add another tier of mutations, which are the
strongest and rarest. also, make more higher tier eggs, about 2 more tiers" (GAME_DESIGN, the top). No save shape
changed: `Schema.VERSION` stays, every older save loads as it is (a rarity past the rarest is clamped to `RMAX`). What
changed in the contract:

- **`Config/Tuning`**: `BoostEach` 2 (each boost building on an island at most). Every table by rarity has nine
  entries: `RarityWork` (.. 17, 26, 40), `EggPrice` (.. 160,000, 1,000,000, 6,000,000), `SellPrice` (.. 5,500, 24,000,
  100,000), `BreedShells` (.. 90,000, 380,000, 1,600,000), `BreedTurns` (.. 28, 38, 50), `ShopWeight` (.. 0.4, 0.15,
  0.05) and `CosmeticPrice` (.. 150,000, 400,000, 1,000,000; no cosmetic has rarity 8 or 9 yet); `EggUp` eight (..
  0.006, 0.003, 0.0015). `IsleCap` unchanged: the fabled effects fit under it.
- **`Logic/Plot`**: `isBoost(id)` (kind "gen"), `boostLimit()` (`BoostEach`), `boosts(placed, id)` (how many of that
  id stand), `boostFull(placed, id)` (one more would pass the limit; false for anything that isn't a boost building).
  `place` refuses `boosts` before the price (also a piece out of the inventory); `replace` refuses `boosts` for a new
  id the island already has two of. **`Types.ErrCode`** adds `boosts`; `UI/Words`: "Two of each boost building is the
  most." `tests/Career.luau`'s `build` checks `boostFull` too.
- **`Logic/Island`**: `boostInfo(p, id) -> { count, raw, total, mult, more, same }`: `same` the copies of its id,
  `more` 0 once `same` reaches `Plot.boostLimit()` (`Controllers/BuildingTags` says "<same> of 2 built" then). An
  older save's third still counts (`boostShare(id, 3)`).
- **`UI/BuildUI`**: a boost building's card counts its copies in the corner ("1/2", `BoostCount`; the accent while
  there is room, dim at two) and at two is greyed with "Max" (`noRoom`, `roomErr` "boosts"); the Inventory tab's card
  likewise; the replace list greys an id the island has two of with "Max 2" and refuses it on a tap; the tip says "A
  second adds 50% of it. Two at most."
- **`Data/Traits`**: `TOP` 6; `RARITY` nine (`Ancient` colour "ancient", weight 0.00006; `Eternal` "eternal",
  0.0000015), `RMAX` 9; `TIER_COLOR[6]` "eternal", `TIER_NAME[6]` "Fabled"; `fabled` (six, tier 6, ids `<family>6`:
  crown all 0.3, rally aura 0.2, bounty eggs 2, fate skip 0.12, timeless away 1, adored charmPct 0.6 and charm 16);
  `at(family, tier)` returns a wondrous or fabled family's own id; `roll` has a seventh tier weight (`TIER_W` 0.03,
  `FABLED_UP` 0.04 more a rarity step). `Data/Palette.ui`: `ancient` 0xFF7B3A, `eternal` 0xE98CFF.
- **`Logic/Breed`**: `inherit` keeps a wondrous or fabled one as itself when both parents carry it (tier 5 and up), the
  highest tiers first (a fabled one before a wondrous one); `child` keeps "no rarer than the commoner parent" for every
  rarity past legendary (an eternal one only from two eternal ones).
- **`Data/Creatures`**: 154 kinds; Skyelder, Stormstag and Islebearer (ancient, Cloudtop, islet 11), Firstflame and
  Craterwarden (ancient, Starfall, islet 12), Everwyrm, Nightwhale, Starmane and Dawnwing (eternal, Starfall), each
  with its look in `LOOKS` and its form in `Models/DriftPlansA..F` (`FORMS.<id>`). So `Tree.pool(t)[8]` is empty below
  tier 14 and `[9]` below 17, and `Tree.odds` keeps every rarity rarer than the one before at every tier (the Tree
  spec checks it). Their portraits are in `scripts/portraits.txt` (`tools/preview/portraits.sh`).
- **`Data/Titles`**: `relickeeper` ("Relic Keeper", best 8, "ancient"), `timekeeper` ("Timekeeper", best 9, "eternal").
- **`Models/EggModels`**: `SIZE` and `LOOK` nine each (8 `basalt` with "veins" of `lava`, lawn `lava`; 9 `plate_white`
  with a "rainbow" belt, lawn `crystal`); `TRIM` 8 (ash nest, "embers" by it) and 9 (white and lilac wisps, "prism");
  `build` gives an ancient egg three "orbit" embers (k 3, 6, 9) and an eternal egg nine "orbit" and nine "orbit2"
  beads; `hero` an ancient egg's lava cracks (lit spots), runes, foot embers, three "orbit" embers and three motes, an
  eternal egg's rainbow belt, stars, pearls, a halo of 14, 21 "orbit" and 14 "orbit2" lights and three motes. The fx
  kind **"orbit2"** is a second ring the other way round, tilted against the first: `Controllers/EggView` and
  `UI/HatchScene` move it. **`Render/DynTex`**: `NAMES` adds "magma" (23) and "prism" (24); `EGG` nine.
- **`Controllers/EggView`**: `EVERY` nine (0.07, 0.06); an ancient egg's sparks are embers (`ember_1..3`), an eternal
  egg's motes of every rarity's colour and `prism_1..3` glints. The hatch notice says "an" before a rarity starting
  with a vowel (also `UI/Hud`'s "An ancient egg waits at the tree.", `UI/StoreUI`, `UI/Menus`).
- **`UI/HatchScene`**: `EGG_H`, `GLORY`, `GRADE`, `RAY`, `SHINE` and `TWINKLE` nine each; `fireflies` adds embers
  (8) and motes of every colour (9); a tier 6 plate blinks twice, adds a white starburst and its dots in every
  rarity's colour (`FABLED_DOTS`). **`UI/HatchBackdrop`**: `SKIES`, `BASES` and `INK` nine; `Sky.body` adds "eclipse"
  (`bodyC`: fire, the dark disc, its rim) and "halosun" (its fill, its ring, its slanting rays' colour); `Sky.rainbow`
  draws a rainbow over the hills; the pedestal's flecks show from rarity 7 up.
- **`UI/TierStars`**: up to `Traits.TOP` stars. **`scripts/gen_art.py`**: ramps `V` (orchid), `L` (pearl), `J` (ash);
  `star_t6`; `egg_8`, `egg_9`, `mini_egg_8`, `mini_egg_9` (`hand_egg` marks `o` and `h`: lava and its hot points;
  `R O Y G B U`: the rainbow, light on the lit side); `ember_1..3`, `prism_1..3`.

## 7. Server

### 7.1 Remotes (`Net`)
`ReplicatedStorage.Remotes`: `Request` (RemoteFunction, C->S `(action, payload) -> Response`), `Signal` (RemoteEvent,
C->S `(kind, payload)`; no handlers in this version), `State` (RemoteEvent, S->C the whole `ClientView` when it
changed), `Fx` (RemoteEvent, S->C `{ kind = "tick", shells, dayFrac, clutchLeft (`p.clutch.left`), clutchSecs
(`Tree.secs`), turnIn (seconds to the island's next turn: `TurnSeconds` - the session's `turnClock`) }` every second, `{ kind = "eggs", laid (`Tree.view`: every egg now, each with its cost), more (0: a
new lot; n: the eggs added when the island grew), turned? (an egg of the lot turned into this rarity, or laid in it, for the
quest on the go: `Tree.ensure`) }` when the tree lays or an egg turns (the session is marked dirty with it, so the whole
view follows), `{ kind = "hatched", data }` (`egg.hatch`'s data) when an egg is hatched, `{ kind = "turn",
ready? (the Hatchery eggs ready this turn, `{ uid, sp }`: Breed.turn) }` at each turn's end (`hatched` and `fresh` till
2026-11-20, when eggs hatched by themselves), `{ kind = "day", day }` at each of the sea's days,
`{ kind = "quest", data }` on a claim; no "tide" or "taken" since the tide went, and none of the old tree's "tree" or
"treegrew"). `Net.serverInit()` creates them; `Net.clientInit()` waits for them.

### 7.2 `Session`
`create(player, profile, plot) -> S` (`{ player, profile, plot, rng, ready, turnClock, dayIndex, tickClock, dirty,
saveAt, reqTimes, undo }`; no `tide` or `tideDirty`: the tree's eggs are the profile's; `undo`: Build mode's Undo
stack, `{ Undo.Step }` newest last, never saved, emptied when the island grows (GAME_DESIGN 4.7)), `get`, `remove`, `all`, `view(s)
-> ClientView` (every driftling, `clutch` from `Tree.view`, `clutchLeft`, `clutchSecs`), `markDirty`, `flush` (sends
State when dirty), `fx(s, msg)`, `allow(s, now)` (the rate limit), `stir(s)`. The session's generator (`Util.newRng`,
the shared xorshift the client has too) is seeded from the server's own `Random.new()` and takes more of it before
each request (`stir`: `Util.stir(rng, n)` XORs a whole number into its state). It was seeded from the player's id and
the join's second, so a scripted client could find the seed and mirror every draw (the server review of 2026-11-19).

### 7.3 `Router` and the action catalogue
`Router.on(action, fn(s, payload) -> (ok, data|err))`, `Router.onSignal(kind, fn)`, `Router.handle(player, action,
payload) -> Response` (not ready -> `not_ready`; over `Tuning.RateLimitPerSec` -> `rate`; `Validate.request`;
`Session.stir`; the handler under pcall; success marks the session dirty).

| Action | Payload | Rule | Errors |
|---|---|---|---|
| `plot.place` | `id x z rot` (coords whole studs in [-240, 64], rot a quarter turn) | `Plot.place` (from the inventory for nothing, else paid in shells; data `{ i, uid, free }`), the buildings rebuilt by difference, then `Tree.settle` and `Tree.fillJobs`, the tips | locked, full (its group's limit), huts (the huts' limit), work (the work cap, a workplace whose places won't fit), money, blocked, bad_payload (the tree, an unknown piece) |
| `plot.move` | `i x z rot` | `Plot.move` (the tree too) | blocked, bad_payload |
| `plot.paint` | `id cells` (a path or water piece; "x,z;x,z": 1 .. 40 cells, whole studs in [-240, 64]) | `Plot.paint` (data `{ placed, swapped, skipped }`; the inventory's tiles first, a swapped one's old look into it), the buildings rebuilt | bad_payload, locked, full, money, blocked |
| `plot.unpaint` | `cells kind` (kind "path", "water" or "all") | `Plot.unpaint` (data `{ removed, floated }`), the buildings rebuilt | not_found |
| `plot.fence` | `id edges` (a fence piece; "x,z,r;...": 1 .. 40 edges, r 0 or 90) | `Plot.fence` (data `{ placed, swapped, skipped }`), the buildings rebuilt | bad_payload, locked, full, money, blocked |
| `plot.unfence` | `edges` | `Plot.unfence` (data `{ removed }`), the buildings rebuilt | not_found |
| `plot.replace` | `i`, `id` | `Plot.replace` (data `{ i, uid, id }`; the island's pieces rebuilt; a smaller workplace keeps its first `jobs` workers, the rest to the arrangement) | bad_payload (the tree), locked, huts (a bigger hut past the huts' limit), work (a bigger workplace past the work cap), money, blocked |
| `plot.store` | `i` | `Plot.store` (put away into the inventory, data `{ id }`; a hut's driftlings left with no hut, then into any hut with room) | fixed (the tree), egg (a Hatchery holding an egg), bad_payload |
| `plot.clear` | `what` ("pieces", "tiles" or "fences") | `Plot.clear` (Remove all: the whole group into the inventory, never the tree or a Hatchery warming an egg; data `{ removed }`), through `rebuilt` (`Tree.settle`, `Tree.fillJobs`, the buildings rebuilt) | not_found (none to take), bad_payload |
| `inv.sell` | `id n` (n a whole number) | `Plot.sellHeld` (up to n of those waiting in the inventory, `Refund` of the price each; data `{ sold, shells }`), an Undo step (through `recorded`) | not_found (none waiting), bad_payload |
| `plot.undo` | - | `Undo.apply` of the session's last step (popped when it goes; data `{ what }`), through `rebuilt` (not recorded itself) | not_found (nothing left, or a piece it put down is gone), egg, money (a sale's coins spent), blocked, full, huts, work, hatcheries, boosts |
| `plot.moveMany` | `uids dx dz rot` (uids "u,u,...": 1 .. 300 uids of 1 .. 9 digits, none twice; dx, dz whole numbers in [-400, 400]; rot a quarter turn) | `Plot.moveMany` (all or nothing; data `{ moved }`) | bad_payload (a uid not on the island, an odd offset under tiles or fences), blocked |
| `plot.storeMany` | `uids` | `Plot.storeMany` (the tree and a warming Hatchery stay; what floats on water taken up goes too; data `{ removed, kept }`) | fixed (nothing but those), bad_payload |
| `plot.copyMany` | `uids dx dz rot` | `Plot.copyMany` (the inventory's first, the rest bought; data `{ placed, shells }`) | fixed (the tree), locked, full, huts, work, hatcheries, boosts, money, blocked, bad_payload |
| `layout.save` | `slot` (1 .. `Tuning.LayoutSlots`) | `Layout.save` (the island as it stands, `os.time()`; data `{ slot, n }`; not an Undo step) | bad_payload |
| `layout.quote` | `slot` | `Layout.plan` (data `Plan`: what loading it would do; changes nothing) | not_found (an empty slot), bad_payload |
| `layout.load` | `slot` | `Layout.load` (data `Plan`), through `rebuilt`: one Undo step | not_found, money, bad_payload |
| `breed.start` | `uid`, `a`, `b` | `Breed.start` (an egg at the Hatchery `uid` from driftlings `a` and `b`; its price in shells) | not_found, egg, money, bad_payload |
| `breed.hatch` | `uid` | `Breed.hatch` (the ready egg at the Hatchery `uid`; the pass track's breed points; data `Breed.Hatched`, the client plays the hatch scene with it: 2026-11-20) | not_found (no egg there), egg (still warming), bad_payload |
| `island.expand` | - | `Island.expand` (paid in shells), `Tree.fill` (the bigger island's extra eggs, Fx eggs with `more`), the island rebuilt (data `{ tier, moved, cleared }`) | max, money |
| `pal.work` | `id uid` (0: rest) | `Island.setHelp` (the pick kept: `pin`) | not_found, bad_payload |
| `pal.auto` | `id` | `Island.autoWork` (back to the arrangement) | not_found |
| `pal.house` | `id uid swap` (swap 0: none) | `Tree.house` | not_found, bad_payload, full |
| `pal.sell` | `id` | `Tree.sell` (data `{ shells, sold }`) | not_found |
| `egg.hatch` | `id swap` (an egg id under the tree; swap 0: none, else a hut driftling sold to make room) | `Tree.hatch`, the tips, Fx hatched (data `{ id, sp, muts, egg, r, hr, cost, sold, swapped, wx, wm, new }`) | not_found (a new lot replaced it), no_hut, money, full (every hut full and no swap: the client opens the swap picker), bad_payload |
| `founder.set` | `skin hair style shirt` | `Island.setFounder` (the `Founder` attribute follows on the next sync) | bad_payload |
| `look.set` | `look` (a `Looks.encode` string, at most 200 characters) | `Store.setLook` (`checkLook`: every index in range, every piece owned and of its slot; the whole look replaces the founder's; the `Founder` attribute follows) | bad_payload, locked |
| `outfit.set` | `i` (1 .. #outfits + 1), `look` ("" deletes outfit i) | `Store.setOutfit` (saves the look's canonical code as outfit i; returns `{ outfits }`) | bad_payload, locked, dup, full |
| `settings.set` | `k` ("pixel", "music", "sfx", "zoom", "screen", "lang" or "text"), `v` | the pixel tier (high, medium, low, off), the music or the sounds (on, off), the View slider's notch (a whole number 1 to 10), the screen's scale (a key of `Tuning.ScreenScales`: auto, 100, 125, 150, 175, 200), the language ("auto" or a code of `Lang.LIST`), the text (pixel, smooth) | bad_payload |
| `tut.next` | - | the tips go away for good, then the quest's egg (`Tree.ensure`) | - |
| `quest.claim` | - | `Quest.claim` (data `{ id, shells, next }`), then the next quest's egg (`Tree.ensure`) | not_found, not_done |
| `char.home` | - | PlotService puts the founder in front of their own tree | cooldown (`Tuning.HomeCooldown`), not_ready |
| `char.visit` | plot (small) | PlotService puts the founder in front of that island's tree (the islands float apart since 2026-11-20); data `{ plot }` | not_found (empty, or the own plot), cooldown (shared with Home), not_ready |
| `look.wear` | `slot id` (a cosmetics slot; id "" takes it off) | `Store.wear` (the `Founder` attribute follows on the next sync) | bad_payload, locked (not owned) |
| `title.set` | `id` ("" none) | `Store.setTitle` (the `Title` attribute follows) | not_found, locked |
| `shop.buy` | `id` | `Store.buy` (a piece on sale in the player's rotating shop now, for shells; data `{ id, cost }`) | not_found (not on sale now), full (owned), money |
| `track.claim` | `lvl prem` (1 .. 30, a boolean) | `Store.claim` (data `{ lvl, prem, given }`; Fx rewards) | locked (not reached, or no Premium Track pass), full (claimed), bad_payload |
| `bag.hatch` | `id swap` | `Tree.hatchBag` (a bag egg, no shells; Fx hatched with `bag = true`) | not_found, no_hut, full, bad_payload |
| `vip.daily` | - | `Store.vipDaily` (data `{ given }`; Fx rewards) | locked (no VIP), cooldown (claimed this UTC day) |
| `reward.daily` | - | `Rewards.claimDaily` (data `{ given, streak, round, miles }`; Fx rewards from "daily") | cooldown |
| `reward.play` | `i` (1 .. 8) | `Rewards.claimPlay` (a gift for playing whose minutes are in) | not_done, used, bad_payload |
| `reward.task` | `i` (1 .. 3) | `Rewards.claimTask` (today's task `i`, done) | not_done, used, bad_payload |
| `reward.bonus` | - | `Rewards.claimBonus` (all three claimed) | not_done, used |
| `reward.spin` | - | `Rewards.spin` (data `{ slice, given }`; Fx rewards from "spin", which the client tells once its light stops) | not_done |
| `reward.index` | `i` | `Rewards.claimIndex` (an Index milestone) | not_done, used, bad_payload |
| `code.redeem` | `code` (1 .. 32 letters, digits, spaces, - and _) | `Rewards.redeem` against `Config/Codes` | not_found, used |
| `offline.collect` | `mode` ("free" or "double") | `Store.collect` of the session's `offline` report, x2 for "double" (data `{ shells }`) | not_found (nothing waiting), locked ("double" after `Store.offlineDouble`) |
| `lb.get` | `board` (`coins`, `charm`, `hatched` or `driftlings`) | `SocialService`'s cached board (yields on a read: data `{ board, rows { BoardRow { rank, userId, name } , value }, you { value, rank? } }`, `name` "" when Roblox gave none) | bad_payload |
| `group.check` | - | `MonetizationService.checkGroup` (yields: `IsInGroupAsync`; data `{ member }`; Fx rewards from "group" the first time in it) | not_ready (no `Monetization.Group.Id`) |

The building actions and `island.expand` still check shells (`money`) for a price in shells, which no piece or tier
has now. The expedition actions (`exp.*`, `pouch.upgrade`) and `pal.release` are gone (2026-11-12), the villagers'
`folk.work` and `folk.dismiss` with them later that day, the tree's `pen.sell`, `pen.best` and `tree.upgrade` on
2026-11-13, and the tide's `tide.take` later that day: `Validate` answers them `unknown_action`.

### 7.4 `IslandService`
Registers the actions above (the building ones, `plot.fence`, `plot.unfence` and `plot.clear` among them, through
`rebuilt`; `inv.sell` through `recorded`, nothing on the island changing). Build mode's Undo (GAME_DESIGN 4.7): `rebuilt`
takes `Undo.capture` before the action and, once it went and the huts and work have settled round it (`Tree.settle`,
`Tree.fillJobs`), pushes `Undo.diff` onto `s.undo` (`Undo.push`); `recorded` does the same without rebuilding the
island. `plot.undo` applies the last step through `rebuilt` without recording itself, and pops it only when it went.
`island.expand` empties the stack. The group actions and `layout.load` are `rebuilt` actions like the rest: one step
each.
`step(dt)` (Main's fixed 10 Hz step), for every ready session: `Island.step` (the shells), `Tree.step(p, dt,
s.rng, Weather.at(WorldClock.now()))` (a new lot when its time comes, laid in the sea's weather: the session marked
dirty and Fx "eggs" with `more` 0; when the spell's kind or the season changes, Fx `{ kind = "weather", wx, season,
newSeason, clock }` to everyone), a turn every
`TurnSeconds` (`Breed.turn`: Fx "turn"), a day each time the sea's clock passes a day's end (`WorldClock.dayIndex` past
the session's `dayIndex`: `Island.newDay`, Fx "day"), the stores every second (Fx "tick" with `WorldClock.dayFrac`,
`clutchLeft`, `clutchSecs` and `clock`: the whole view is not sent for them). `island.expand`'s `Tree.fill` lays in the
weather too. PlotService's `Eggs` attribute: "id.r" per egg, "id.r.kind" for a touched one, ";" between. `WorldClock` (server): the sea's clock, `os.time()`
at start advanced by every step (`now`, `advance`, `shift(seconds)` for the sims and previews, `dayIndex`, `dayFrac`); a
day is `Tuning.DaySeconds` (4 hours). The tips (`tips(s)`; GAME_DESIGN 9, the request of 2026-11-21): 1
(`Plot.TIP_HUT`) moves on when a hut stands, 2 (`TIP_HATCH`) when an egg has hatched (`stats.taken` above 0 or any
driftling), 3 (`TIP_WORK`) when a workplace stands, 4 (`TIP_LAST`) on OK (`tut.next`); a step whose task is already
done moves on at once, several in a row if need be (an older save); `join` runs them too. Every building change
(`rebuilt`) runs `Tree.settle` and `Tree.fillJobs` before the island's models are rebuilt; `egg.hatch` runs the tips and
sends Fx "hatched"; `island.expand` runs `Tree.fill` and, when it laid any, sends Fx "eggs" with `more` the count. The quest's egg (`questEgg`: `Tree.ensure`) runs after `quest.claim` and `tut.next` and once a second on the clock's tick; when an egg turned it marks the session dirty and sends Fx "eggs" with `more` 0 and `turned` (the rarity), so the HUD says "A rare egg waits at the tree." and EggView, seeing the same egg id with another rarity on the plot's `Eggs` attribute, rebuilds its shell and lets it rise again.
Nothing happens while the player is away: the tree's clock runs only in a ready session.

### 7.5 `PlotService` (the islands)
`init()` registers the collision groups `Bounds` (the invisible walls round the islands' grass) and `PixelRays` (the
pixel filter's rays), not colliding with each other, and `Staged`, `StagedBounds` (the next island built ahead, below:
colliding with nothing) and `PreCast` (the pixel filter's rays that draw it ahead: meeting `Staged` and `Default`, not
`Bounds` or `StagedBounds`), puts a little empty islet on every plot (`Plot_<i>.Static.Land` = `EmptyLot`, attribute
`Owner` 0; no sea since 2026-11-20: "Never mind, make it a floating island instead, with a 2d skybox. Expanding makes
the island bigger."), and starts the fall check: every 0.5 s a ready player's character whose root is more than
`FALL_DEPTH` (30) studs under the grass (fallen off past the wall in a glitch) is put back home (`placeCharacter`).
`claim(player) -> plot` (the lowest free index, 0 when the server is full: Main kicks), `release(i)` (back to an empty
islet, every attribute cleared).
`build(s)`: `Plot_<i>` gets `Owner`, `OwnerName`, `StudioName` ("Name's Isle"); its `Static` gets
`Land` for the island's tier (rebuilt only when `Static`'s `Built` attribute differs: the island for that tier built
ahead is swapped in when it is ready, else it is built there and then) and `Decor` by difference
(`buildDecor(s, ahead?)`: one model a piece, named `uid:id:x:z:rot:lvl`; models whose key is unchanged stay (the
models there are put in a table by name once, not looked up one `FindFirstChild` a piece); the Tree of
Life's `lvl` is its stage, `Tree.stage(tier)`, so a new stage builds it again, unless `ahead` holds it by that name
(the next island's job builds the tree at its next stage when the next tier grows one: `nextLand[i].tree`, from the
tree's place when the job was queued); a water tile's is 1 plus its neighbour
mask, `waterMasks(placed) -> { [Street.cellKey(x, z)]: number }` (a bit for each side with a water tile next to it on
the even grid: north 1, east 2, south 4, west 8), so a tile is built again when water is dug or taken up beside it),
then `sync(s)`: the attributes `Tier`,
`Day`, `Charm`, `Pals` (the hut driftlings, `;`-separated `id.species.work.home`, then `.mut,mut` for one with
mutations, so a tap on a neighbour's driftling shows them; one with no hut is left out until it moves in; no `Folk` since the villagers went), `Eggs` (the tree's eggs, `;`-separated `id.rarity`, in the order
they were laid: every client draws every island's, `Controllers/EggView`; no `Tide` or `syncTide` since the tide
went), and the player's `Founder` (`skin.hair.style.shirt`) and `Plot` (Main syncs every dirty session before sending
its view; only changed values replicate). A player leaving clears every attribute, `Eggs` with them, so their eggs
go from every client. The founder: `watchCharacters(player)`,
`placeCharacter(s)`, `spawnCFrame(s)`, `home(s)` (`char.home`, once every `Tuning.HomeCooldown`), `visit(s, i)`
(`char.visit`: the founder to plot i's island, `spawnCFrame` of its owner's session 2.5 studs aside; not_found for an
empty plot or the player's own, cooldown with Home, not_ready; data `{ plot }`).
**The next island, built ahead** (GAME_DESIGN 4: the lag before an expansion; the request of 2026-11-19, "Expansion
is very slow and laggy, especially at higher levels"): the land is `StreetModels.landPlan(tier)`'s 8x8-cell chunks,
each named for its cells (a chunk whose cells and margin did not change keeps its name from one tier to the next: only
those along the old and the new edge change).
After each `build` a plot that can still grow queues its next tier; one background thread builds only the chunks the
current land lacks (`landModelOf(i)`, `Static.Land.Land`), paced by `Blocks.pace` (60 parts a frame), each out of the
world, then staged (`stageParts`: every part's group `Staged`, or `StagedBounds` for a `Bounds` one) and put in the
hold, `workspace.Staged.Plot_<i>` (since 2026-11-20, GAME_DESIGN 4: "Is there a way to make island expansion seamless,
with no lag? Could you pre render max expansion floors so that expanding simply switches to that expansion level?"), so
every client receives the next island a chunk at a time long before it is wanted; the hold's `Tier` attribute is set
once all of it is there (`nextLand[i] = { tier, chunks, tree, hold, gen }`, the tree when the next tier grows it a
stage; a newer plan or `release` destroys the hold). The swap `unstage`s each prebuilt chunk (and the tree) before it
moves it over.
`planOf(tier)` caches each plan. The expansion's `build` then diffs the land in place: the new chunks go in first
(prebuilt ones moved over, any missing built then), the sign and the wall (`landWalls`, its model named for the
tier) if their names changed, and only then the chunks, the sign and the wall the new plan no longer has are
destroyed, so the island never shows a hole and the founder is never unwalled. A plot with no land model yet builds
the whole `StreetModels.land`. Grand Isle to Harbor Town: 55 chunks in over 43 out. `init` works out every tier's cells first (`Street.warm`). `debugNext(i) -> (tier?, ready, swaps)` (the sims'
check: `ready` is the hold's chunks built).

### 7.7 `MonetizationService` (GAME_DESIGN 14)
Every id from `Config/Monetization` (`GamePasses`, `DevProducts`, `SuggestedRobux`; `isEnabled(id)`: 0 is not on sale and
is never sent to Roblox). `init()` maps the enabled ids to their keys, sets `MarketplaceService.ProcessReceipt` and
listens to `PromptGamePassPurchaseFinished` (a pass bought: `Store.setPass`, Fx `pass` { key, bought }, and Fx `rewards`
{ from, given } for VIP's welcome gift). `join(s)` (Main, once the session is ready) checks each enabled pass in
parallel (`UserOwnsGamePassAsync` under pcall; a failed check keeps what the save had; a pass the save had and Roblox
says isn't owned is taken off: a refund). `grant(s, key, purchaseId) -> (paid, saved)` pays a product once
(`Store.paid` / `Store.remember`, `Store.product`, Fx `rewards`, then `DataService.save`); ProcessReceipt waits up to
10 s for the buyer's session and answers PurchaseGranted only when the save holds the purchase (else NotProcessedYet:
Roblox tries again, and the kept PurchaseId stops a second payment). IslandService's second tick also runs
`Store.earn` (Fx `titles` { ids }), `Store.sync` (a new season), a minute's track points and marks the session dirty
when the rotating shop turns over; the hatches, Hatchery eggs, quests and expansions add their track points.
The group (GAME_DESIGN 14.3; `Monetization.Group = { Id }`, a table so the sims can set it): `checkGroup(s) -> member`
(yields) asks `IsInGroupAsync` under pcall (no id or a failed check: nothing changes, false), then `Store.setGroup`
(Fx `rewards` { from = "group" } with the gift the first time); `join` runs it in the background, the route
`group.check` on the Store's Join. Offline earnings (GAME_DESIGN 14.3; IslandService): `IslandService.join(s)` (Main,
right after `Session.create`, before the island is built) sets the session's `offline` from `Store.offline(profile,
WorldClock.now())` and `seenAt` to now; the second tick keeps `seenAt` at now; `IslandService.leave(s)` (Main's leave
and BindToClose, before the save) pays a report not collected (`Store.collect` x1) and sets `seenAt`.

### 7.6 Persistence (`DataService`, `Logic/Schema`)
One key per player (`u_<userId>`) in `Tuning.DataStoreName`, a record `{ data = Profile, lock = { job, t }? }`.
`load(userId) -> (raw?, ok)` takes the lock: while another server holds a lock younger than `Tuning.LockTTL` it
waits and retries, and on the last of `Tuning.LoadRetries` attempts (about 10 s) takes it over. `save(userId, profile,
release?) -> boolean` never overwrites a record whose lock another server holds, and says whether the record now holds
the profile (false: the store failed, another server's lock, or a save after the player's leaving one). A leaving save
(`release`) is tried `Tuning.SaveRetries` times (2 s, then 4 s between); after it, this server never writes or locks
that player's record again until they load here anew (an autosave that started before they left is dropped inside
the update). `unlock(userId)` drops this server's lock without saving; `pending()` counts the saves and unlocks going.
Main: join -> claim a plot, load (kick on failure; the player gone meanwhile: unlock), a record newer than
`Schema.VERSION` -> unlock and kick ("This server is out of date. Rejoin to play.": an older server drops the fields it
does not know on its first save), `Schema.reconcile`, build the island, ready, send the view; leave -> save with the
lock released, free the plot; autosave every `Tuning.AutosaveSec`; BindToClose runs leave for everyone still here and
waits until `pending()` is 0 (up to 25 s). Each frame `WorldClock.keepUp(os.time())`: the sea's clock gains at most a
second a frame through the fixed step, and a stall left it behind for good (it jumps up to the real clock when more
than 5 s behind, never back). `MonetizationService.grant` answers a purchase id it has seen by saving again (it said
"saved" without saving). The server review of 2026-11-19 found each of these. Without DataStores (Studio without API
access) saves live in memory and a warning says so. A new save shape needs a `Schema.VERSION` step in `migrate` and a
spec that an older profile still loads.
The leaderboards and friends (GAME_DESIGN 16): `writeBoards(userId, scores, last)` sets each board's
OrderedDataStore entry (`Tuning.BoardStores`, key `u_<id>`, a whole score) where it changed since `last` (updated as
each write lands; counted in `pending`); `readBoard(board, n) -> { { userId, value } }?` (`GetSortedAsync`, best first,
nil on a failure); `queueReferral(inviterId, inviteeId) -> ok` and `takeReferrals(userId, max) -> { { invitee, at } }`
keep the friends waiting for an inviter who wasn't on the server (`Tuning.ReferralStoreName`, key `u_<id>`, a list of
at most 100, one entry a friend; `UpdateAsync`). Without DataStores both live in memory too.

### 7.8 `SocialService` (GAME_DESIGN 16)
`init()` registers `lb.get`: the board's top `Tuning.BoardRows` from a cache read again at most every
`BoardCacheSec` (a failed read tried again in 15 s; a second asker waits for the first's read), the names through
`Players:GetNameFromUserIdAsync` in parallel (cached, 5 s at most), and the asker's score now and place. `join(s)` (Main
spawns it once the session is ready; yields): the player list's `leaderstats` (`Island` = tier, `Earned` =
`Social.score(p, "coins")`, kept up every 5 s), each new pair of players checked once with `IsFriendsWithAsync` (three
tries on failures, again every 30 s) and every player's `social.here` counted again; the inviter from
`Player:GetJoinData()` (`ReferredByPlayerId`, else `LaunchData` `{"r": id}` or a bare id; asked three times a second
apart) taken by `Social.canJoin` / `join` (Fx `rewards` from "invited"); then the friends waiting in the referral
queue, as many as `Social.todayLeft` allows, each `Social.reward` (Fx `rewards` from "friend"; one that can't be paid
goes back). `step(dt)` (Main's fixed step): each second `Social.play` for every session and, once due, the inviter's
reward: on this server `Social.reward` there and `refPaid` set, else `DataService.queueReferral` (`refPaid` once it
lands; a failed write tried again in 30 s); each player's scores written every `BoardWriteSec`. `leave(s)` (Main's
leave, before the save): the scores written once more (spawned; BindToClose waits for it through `pending`), the
others' friends here counted again. Every web call is pcall'd.

## 8. Client bootstrap and the mirror

`Main.client`: the loading card's `show()` (ReplicatedFirst's, nothing when Boot put it up), `StateClient.init`
(remotes), `PixelRenderer.init` (lighting), `CameraController.init`, the card's phase "island", wait for the first
view, `CameraController.start`, `PixelRenderer.start`, `DayLight.start`, `UIKit.init`, `WorldView.start`,
`AvatarView.start`, `StreetLife.start`, `AmbientView.start`, `Hud.start` (which starts `Menus`), then the card's phase
"picture": `PixelRenderer.firstPicture()`'s progress every 0.05 s until it is on screen (or 30 s), then `finish()`.

### 8.0 The loading card (`src/first`, ReplicatedFirst.Loading)
`Boot.client`: ReplicatedFirst's one script, run before the rest of the game has arrived: `LoadingCard.show()`, then
`ReplicatedFirst:RemoveDefaultLoadingScreen()` once the card is up. Nothing in it touches ReplicatedStorage (not
there yet): the palette's colours are written out and `PixelFont` / `PixelFontData` are mapped beside it.
`LoadingCard` (GAME_DESIGN 11): `show()` (once: a `LoadingCard` ScreenGui, DisplayOrder 300, no inset; a canvas of
`ceil(screen / K)` UI px under a UIScale K, the game's pixel size (`PixelScaleMin` 2 plus one per `PixelScaleSides`
entry the screen's short side exceeds; fitted to a whole number of the screen's own pixels when the screen's size, in
units, says it is scaled by a fraction: Pixel/DisplayScale's rule on the two sides alone); Roblox's touch buttons off while it is up), `phase(name)` ("island",
"picture"; it starts in "start"), `progress(f)`, `finish()` (the bar fills, `FADE_STEPS` (5) steps over `FADE_SEC`
(0.45) to clear, destroyed, touch buttons back; by itself after `SAFETY_SEC` (45)), `state() -> { up, phase, bar,
finished, fading, painted, fallback, actors, ticks, K, size, title (the title's block rect), island, isle, bob,
bobMoves, mode, cover, covered, bank, clip, status, waiting, lang }`; `cover(opts?) -> boolean` (2026-11-20, "make a transition for expansion, hiding the game
with a loading transition": the card again, for Build mode's expansion; `opts { title?, status?, onCovered?, onOpened?
}`; false while the card is up), `status(text)` (a cover's words), `useLang(Lang, smooth?)` (Main, once UIKit has set the player's language: the status,
the tip and a cover's title show in it from then on, in the pixel font or smooth, a TextLabel in Builder Sans bold with
a soft stroke, as `smooth()` and the language want; a player whose Roblox language is another of the game's sees the
dots alone until then, `WAIT_WORDS` 8 s at most; the game's name stays as it is; docs/LOCALIZATION.md 4), `reword()`
(every line again: `UIKit.LanguageChanged`). A cover mounts the same card with its root
see-through (`mode` "cover"); `bandShapes(W, H)` lays a bank of cloud for the canvas (per column: where its three
layers start, `top`, `l1`, `l2`, from rows of round domes, `domes(W, rng, r0, r1, k)`, and where it ends, `bot`, with
shallow domes hanging under it; sizes for a 360 px tall canvas scaled to it, seed 11; `base0` the bank's top line
wholly under the screen, `base1` wholly over it), and `Cover { state ("closing" | "held" | "opening"), t0, base, lo, hi,
coveredAt, onCovered, onOpened }` moves the top line from `base0` to `base1` over `CLOSE_SEC` (0.7) with a smoothstep
(`bankBase`). Every Heartbeat `drawBand()` writes the rows the bank crossed since the last frame (`lo`, `hi`: one
`WritePixelsBuffer` of exactly those rows): each pixel the painting's (`paintBuf`, kept for the next cover of the same
canvas size, `paintKey`) under the bank while it closes and over it while it opens, the bank's flat `BANK` colours
(0x5B5084, 0x776A9E, 0x9A90C2, back to front: the card's moonlit clouds), or clear; `placeClip()` sizes the `Clip` frame (ClipsDescendants) that
holds the sprites, words and bar (`S.layer`, the `Over` frame inside it, under the `Painting`'s `Scene`) to the rows
the card wholly covers. Covered: `onCovered` runs. `finish()` on a cover waits `HOLD_MIN` (0.9 s) after it covered and
for the bar to fill, then the bank rises again over `OPEN_SEC` (0.8), the card over it; `onOpened` runs once it is
destroyed. A cover's bar follows `progress(f)` (1.2 a second); it opens by itself after `COVER_SAFETY` (20 s).
Without EditableImages only the clip moves: the plain card behind a straight edge. Laid out from
the canvas's size (`layoutFor`: the title, status, bar and tip rows; the island's picture, `still` "big" when it fits
between the bar and the tip (and the width), else "small" with its foot allowed down behind the tip, centred under the
bar at `ix`, `iy` (`iw` x `ih`); the horizon, the top of the sea of clouds, seven tenths of the way down the island;
the moon, `moonX`, `moonY`, `moonR`, high on the right beside the island) and built again 0.15 s after the camera's
ViewportSize changes. Since 2026-11-20 ("make the island loading screen like this view, but render it as a still
image, then polish it like a pixel art illustration") it is the night sky with the island's still picture over it.
`paint(L)` writes the sky into one EditableImage of the canvas's size: `SKY`'s bands through `bandAt(list, u, x, y,
zone?)` / `band(list, t, ...)` (flat, then three dither steps of `stepOn(x, y, s)`: a quarter, a half, three
quarters), the galaxy's faint band (`MILKY` on a dither across a diagonal), stars (fewer toward the horizon, a few
bright ones with four points), the moon (`MOON`, `MOON_CRATER`, its lower right rim `MOON_RIM`, its edge mixed half
into the sky, a halo of `MOON_HALO` in two dithered rings), four far islets (silhouettes in `FAR`, the edge toward the
moon `FAR_LIT`, a tree on the two big ones) and the sea of clouds (`CLOUDS`, five layers of `domes`, flat, a pixel of
`CLOUD_RIM` along each top). Every `put` rounds to whole pixels (a fraction would write across two pixels' bytes: on a
phone the far islets once came out shifted and blue). The island is `decodeStill(ART[L.still])` (decoded once a
size, `S.stills`) in an `Island` ImageLabel in the `Over` layer (ZIndex 3, under the words), at one UI px an art px.
Nothing moves on the card but the bar, the status's dots and the tips; `S.ticks` counts its Heartbeats. `state()`
adds `still` ({ name, x0, y0, w, h }) and `moon` ({ x, y, r }).
The words: `textImage` rasterises a line with `PixelFont.mask`
(the title in `BIG` with the "title" under layer and `PixelFont.smooth`'s anti-aliasing steps, the status and the tip
in `SMALL` with a drop shadow) into an EditableImage, centred on the canvas; the status's dots and the bar are Frames.
Without EditableImages (`fallback`): Frames and an Arcade TextLabel. `LoadingArt` (generated by
`tools/preview/loading_art.sh`: the preview scenario `ploadingart` draws the island and `gen_loading_art.py` polishes
and packs it) is `{ big: Still, small: Still }`, `Still = { w, h, pal (0xRRGGBB), alpha (255, or 128: an
anti-aliasing pixel the card's sky shows through), px }`: one line of run-length codes over the 91 printable
characters from '#' to '~' without the backslash (with NS = 1 + #pal, a code below NS a symbol, 0 clear and 1 + i the
palette's i + 1; the codes from NS up the digits of the run's length, bijective base 91 - NS, least significant
first). The big picture is the View slider's farthest notch (5 art px a stud, 222 x 234), the small one 3 art px a
stud (134 x 143).
The card's own outlines are darker steps of what they ring (`C.title_ink` the gold title's, 0.3 and 0.3; `C.bar_ink`
the bar frame's, `ROCK_INK` and `LOG_INK`, 0.45 and 0.3), never `C.ink`, which stays for the words' drop shadow and the
tip's plate.

### 8.1 `StateClient`
`init`, `view() -> ClientView?`, `waitView`, `Changed: Signal<ClientView>`, `Fx: Signal<msg>`, `Tick:
Signal<ClientView>` (Fx "tick": the view's `shells`, `dayFrac`, `clutchLeft` and `clutchSecs` are patched in
place after a check (numbers, not NaN), no whole view comes), `clutchLeft() -> (left, secs)` (the seconds till the
tree's next lot, the server's last word (a tick or a view) run down by the client's clock, and the seconds between two
lots), `turnIn() -> number` (seconds to the island's next turn: the view's or the last tick's `turnIn` run down by the
client's clock), `eggLeft(egg) -> number` (seconds till a Hatchery egg is ready: its turns left less one, times
`TurnSeconds`, plus `turnIn()`; 0 once ready), `seaClock() -> number` (the sea's clock: the view's or the last tick's `clock` run on by the client's clock; 0
before the first view), `request(action, payload) -> Response` (never errors), `signal(kind, payload)`. (No `TideChanged`, `tideNow`
or `along` since the tide went; `treeFrac` went with the old tree.)

### 8.2 `DayLight` (the light: one bright day; the sky's own day)
The request of 2026-11-14, "remove the day night cycle, and make everything brighter": `start()` sets
`PixelRenderer.setGrade(hold or BRIGHT)` every frame (with the filter off, `Lighting.ClockTime` 13.5), sets the
crickets to `0.12 x night()` (the surf at 0 since the sea went on 2026-11-20; WeatherView keeps a soft wind) and plays
the birds every `BIRDS_EVERY` 80 s while `night()` is under a half.
The sky's day (the request of 2026-11-20: "polish the skybox more. it should be of the same quality as the ones in the
egg hatching screen, with day and night cycles with moon and sun rising"): `skyHour() -> 0 .. 1` (the sea's clock,
`StateClient.seaClock`, round `Tuning.SkyDaySecs`: the same hour on every client of a server; 0 midnight, about 0.23
sunrise, 0.5 noon, about 0.77 sunset; os.clock before the first view), `skyNight()` (which night: the clock in sky days
plus a half, so it turns at noon; the moon's phase), `night(h?) -> 0 .. 1` (0 from 0.25 to 0.75, 1 before 0.17 and after
0.83, straight ramps between), `debugSky(h?, night?)` (hold the hour and the night for the previews and sims; nil lets
them run). Only the sky and the sounds follow it: the island's grade stays `BRIGHT`. `BRIGHT` = `{ mr
1.035, mg 1.035, mb 1.025, lift 3, sat 1.02, lamps 0 }`. `at(frac) -> Grade` (`BRIGHT` at any time), `frac()` (always
0.35, the day's middle: AmbientView's birds and butterflies are always about, its fireflies never), `hold(grade?)`
(the hatch scene's rarity grades over the day's; nil lets go), `setWeather(grade?)` (WeatherView: the weather's
`Data/Weather` grade multiplied onto BRIGHT's colours and saturation, its lift added; nil back to BRIGHT; a hold still
wins), `debugSet(frac?)` (kept for the previews' day, dusk,
night and dawn scenarios: it changes nothing now, so they all show the same day), `debugState() -> { frac, grade,
clock }`. The view's `dayFrac` still moves (the HUD's calendar bar); nothing lights by it.

### 8.3 `Audio`
`play(name, opts?) -> boolean` (opts `{ volume, pitch }` times the event's; a voice not loaded yet is asked to load
so the next play is on time), `preload(names)` (every voice of those events made and loaded now, on its own thread;
nothing calls it since the fights went), `has(name)`, `EVENTS`: every sound by name (`click open close deny notice
ding coin coins combo sparkle cheer tick flip pop`; the happy moments, each its own library sound: `newcomer`
(`DoorChime`; nothing plays it since the villagers went), `grow` (the island has grown, or the tree lays an epic or legendary egg: `BellTreeRun`), `grow_surf` (the island growing: `Waves` from 0.4 s, 2.1 s long, its last 0.7 s faded), `grow_sand` (its sand settling: `StepSand1`, `StepSand2` or `LandSand`, pitched 0.7 to 0.85), `friend`
(a Hatchery's egg hatched: `ChimeCluster`), `level_up` (a piece replaced: `SparkleTones`), `reward` (a quest claimed:
`Triangle`), `egg` (`MusicBoxWind`), `rare` (a new lot of eggs, or one rare or better hatched: `SparklePass`; a common or uncommon one hatched plays `pop`); the hatch scene's egg: `crack` (a tap that cracks it: `CrackEgg1..3`, ProSoundEffects' "Crack Egg Crunchy", the crunch cut out, `ids`) and `crack_open` (the hatch: `EggBreak`, "Eggs Break 15"); the founder's feet (AvatarView):
`step_grass step_sand step_wood` (two or three takes each, `ids`), `step_water` (wading through a river: `Pop`
pitched low), `jump`, `land`; putting a piece down in Build mode (`Controllers/BuildFx`, by its `feel`, cut from
the clips above): `place_wood` (the hammer's taps), `place_stone` (`CoinsMany`, pebbles, low), `place_plant`
(`StepGrass` takes), `place_water` (`Pop`), `place_metal` (`Notice`'s clinks, high), `place_magic` (`Sparkle`),
`place_sand` and `place_snow` (`StepSand` takes, the snow higher), `place_cloth` (`Hop`, a cloth flap) and
`place_fire` (`Combo`, a shaker, low); the world's `hammer gull birds` (nothing plays `hammer` since `place_wood` took
its clip); the fights' sounds and their ids went on 2026-11-12), each one `Monetization.Sounds` id (0 =
silent), or a few takes (`ids`: one voice each, picked at random, never the same twice running), with a volume, a
pitch range, a cooldown (a repeat inside it is dropped), a few voices and maybe a stretch of the clip (`from`, `len`:
the hammer's first two taps, the door chime's first ding-dong; its last `fade` seconds tweened down, a fade still
running cancelled when the voice plays again; the voice stops when it is over) (Sounds in `SoundService.UISounds`,
reused). `playCount(name)`: how many times an event has played on this client (the sims: the footsteps). `ambience(name, volume)`: a looped sound (`waves`, `crickets`, `rain`, `downpour`, `wind`) faded toward a volume
(DayLight: the crickets at night by the sky's day, the surf no longer since the sea went; WeatherView: the rain and the
wind). `music(mood?)`: the background music, a mood's playlist of
`Monetization.Music` ("day", "night"; nil: quiet) shuffled once and played round, track after track
(`Music_<mood>` Sounds at `MUSIC_VOL` (0.4, twice the 0.2 it was since "make the music louder", 2026-11-14) times the track's `gain`); a change of mood and each track's last `MUSIC_FADE` seconds crossfade (a track
that ends early hands on at `Ended`); a mood still fading out fades back in when asked again. `setMusicOn(on)` fades
it all away or back; `musicState() -> { mood, on, tracks }`. The HUD sets the mood every frame (night from 0.74 of the day to the dawn, else day) and `on` from
`settings.music`.

## 9. The pixel filter and the camera

### 9.1 Principle (Random Bakery's, cut down: one fitted scale, pans, no Actors)
One EditableImage, shown full screen through an ImageLabel with `ResampleMode = Pixelated` from the screen's top-left
corner: one art pixel is K × K screen px. K is the game's one pixel size (2 on phones and 768p, 3 at 1080p, 4 at
1440p; a tier only makes it coarser), in Roblox's units. On a screen scaled by a fraction (125%, 150%, 175%: Roblox
lays the interface out in density-independent units and draws them at the display's scale) `Pixel/DisplayScale`
fits it to a whole number of the screen's own pixels, so K may be a fraction of a unit (2.4, 3.2): `DisplayScale.start()`
(CameraController.start) watches mouse and touch positions and the camera's ViewportSize; `DisplayScale.observe(v)`
keeps the last 32 distinct values with a fraction (a whole one fits any screen and is dropped: Roblox may round a
mouse position to whole units); the scale is the smallest of `1.25, 1.5, 1.75, 2, 2.25, 2.5, 2.625, 2.75, 3, 3.5, 4`
that makes every one a whole number of pixels (within 0.02), 1 with fewer than 2 or none fitting, or the
Settings choice (`setChoice(c)`, `Tuning.ScreenScales`: "auto" 0, "100" 1 .. "200" 2); `factor()`; `fit(K)` = K at a
whole scale, else `round(K * s) / s`; `Changed` (the camera refits: `CameraController.pixelK` returns `fit` of
`Raster.pixelScale`); `found()` (what Auto found, whatever the choice: Settings shows it); `debugState()`,
`debugReset()`. Roblox keeps a UDim Offset whole, so nothing puts K into an offset: the layer's `Image` is W x H
offset units with a UIScale child `PixelSize` of K, SkyBackdrop lays everything on a `Canvas` frame (W x H) with a
UIScale of K, HatchBackdrop's `Image` has a `PixelSize` UIScale and its life `Layer` (W x H) a UIScale of K, the
pieces on them placed and sized in art px; UIKit's canvases have their UIScale of K and sit on the K grid from the
screen's corner (`top % K` with a tolerance), a fractional shift given as a share of the root's height (a UDim Scale
keeps its fraction); the view's key formats K `%g`. (The jolts, `PixelRenderer.setOffset` and
`HatchBackdrop.offset`, still move by whole art px times K in offsets: both lose the same fraction.) The report of 2026-11-20 ("the tree still looks like this": screenshots
whose every pixel was 2.5 of the screen's). The **static layer** is a raycast G-buffer of the view: progressive passes (one
ray per 4×4 block, per 2×2, then every pixel; `Pixel/BakeCast`: each ray starts where it comes down through `Tuning.PixelRayTop`, 80 studs up, not at the ray plane 500 studs back, and its depth still counts from the plane: Roblox's single-precision ball test from 500 studs off blurred the edges of small balls, 2026-11-20), time-sliced (`Tuning.PixelBakeMsPerFrame`, more
behind the first curtain), sun visibility cast at each 2×2 block's even-even anchor and shared by the other three
pixels when they show the same part and normal (their own shadow ray otherwise; then every shared pixel lit unlike a
neighbour casts its own, `refineShadows`, so shadow edges step one pixel: GAME_DESIGN 2), shaded with `Render/Shading`'s three
toon bands and the palette LUT (the indoor tint inside the room) with each material's surface texture (9.3), then the
outline (`Shading.outline`) and the contact shade at the foot of upright faces. The outline is selective (GAME_DESIGN
2, the request of 2026-11-20: "For outlines everywhere, no longer use pure black, but a darker version of suitable
neighbouring pixels instead"): each edge pixel becomes `Shading.inkOf(p)`, 0.45 of its own colour plus 0.3 of the
palette's ink (cached per colour), or on a picture's outer rim (alpha 0) that of its first coloured 4-neighbour, or
the flat ink `Shading.INK_PIXEL` where it has none. `Shading.isInk(p)` says whether a pixel is one of those edge
colours (the wind pass tells an edge from a leaf by it; a pixel already an edge is never darkened twice).
`Shading.setFlatInk(on)` draws every edge in the flat ink instead: only the picture scenarios set it
(`portraits.luau`, `thumbs.luau`, `cosmetic_thumbs.luau`, `product_icons.luau`), so `tools/preview/gen_portraits.py`
can find the outline and the creases by colour before it gives each its darker step. The **dynamic layer** is the islanders (the hut driftlings), the tree's eggs and the founders: every tick (the tier's Hz) their parts
are drawn analytically with `Raster.drawPart` and the same orthographic camera, depth-tested against the static
layer and outlined; only the tiles where something changed are drawn again and uploaded (9.3, the incremental
compose). Besides Roblox's shapes, Raster draws
three smooth solids (the request of 2026-11-15: "currently, all of them are modelled using blobs, which is unnatural";
`Raster.drawSolid`, `Raster.hitSolid`, `Raster.SOLID_KIND`): "Ell" (the ellipsoid in the part's box), "Egg" (two half
ellipsoids along its Y joined at an equator, the top `prm` of the height), "Cone" (a tapered limb along its X: two
balls and the cone touching both, the -X end's radius sy/2 and the +X end's `prm` times it, its cross-section squashed
to sz/sy) and "EggBot" / "EggTop" (an egg cut across, its part below or above the cut; `prm` = 10 x the cut's height
in thousandths of the box from its bottom + the split). Per pixel the ray is taken into the part's frame (squashed
round) and the quadratic solved; a row's columns are bounded by the roots of the silhouette's own quadratic. A part
says it is one with its "PixelShape" attribute (and "PixelK" for `prm`): `registerDynamic` (`DynPart.prm`),
`Snapshot`'s solids (`Picture.solid`'s `prm`, its shadow rays through `hitSolid`), `DynTex.uv` and `SmoothParts.role`
read them; with the pixel filter off an ellipsoid or an egg shows through a sphere `SpecialMesh` and a limb as a
cylinder. A driftling's body is drawn as one blended surface (the request of 2026-11-16: "You should not be able to
see the shapes that the creatures consist of ... make them all look like one connected mesh"; `Raster.blendMember`,
`Raster.drawBlend`, `Raster.blendWorth`, `Raster.blendField`): its body solids (parts with a "PixelBlend" attribute,
the blend radius as a share of the part's largest size; `DriftModels.build` sets it, `registerDynamic` reads it into
`DynPart.blend`, `Snapshot` into `Picture.Solid.blend`) are the smooth union of their distance fields, a polynomial
smooth minimum folded over them thickest first, each member's own radius the model's or 0.6 x its smallest size if
less (a thin antler or a flat ear meets the head in a small fillet). Each member is first drawn over its own
silhouette (its exact hit, normal and member kept per pixel, and how many members cover it); only near pixels covered
by two members does the union count: there the member's neighbours (members whose bounding balls come within the
pair's radius, listed once a frame, and only those the pixel's ray passes near) give the field, and where it dips
below the hit Newton steps along the ray move to the union's surface (a shift under a pixel keeps the hit), lit by
the members' gradients mixed by the minimum's weights and coloured by the nearest member; the pixels just outside the
silhouettes between two different members march the union for a fillet. With no step in depth at a join, the outline
pass draws no ink along it. The details (eyes, claws, whiskers, teeth, lit bits) are drawn first as plain parts, so
the body must be truly in front to cover them. Below `BLEND_MIN_PX` (3 art pixels of blend radius: the islands, where
a driftling is a small figure among dozens) the members draw as plain solids; a still picture (`Picture`, the
portraits) blends at any size. The **effect layers** (9.3,
`Render/Fx`) draw over both every tick: 2D sprites and pixels in the world (the islands' small lives,
`AmbientView`), depth-tested, colour only. Without EditableImages (or with Classic picked) the layer hides and the
Roblox camera shows the 3D world.

### 9.2 `CameraController`
`View = { rot12, center, look, viewH, grid: Raster.Grid, key, fullX, fullY, K, tier, plot, room, box }`.
Orthographic yaw 45° pitch 30°: floor edges step 2:1. A fixed box round the island's heart (`FRAME`, the same on every
tier, shrunk about its middle by `Tuning.CamFrame`: 0.75, about 11 art px a stud on a desktop (a phone, the screen's short side 500 px or less, `Tuning.CamFramePhone`: 0.6, a step closer); it was 1 (8 px), then 0.7 (12 px)
after "zoom into the island more such that there isnt too much sea in the screen", then 0.95 (9 px) after "zoom out abit
more. the whole island should still be visible", then 0.75 (the phone's 0.75 to 0.6) after "zoom in into the island
more. it should fit like this, with the playable island as big as the bakery", all 2026-11-14) is placed on screen clear of the HUD's blocks (`setHudRects`, `Raster.place`; the screen's middle when it doesn't fit): that placement is the **home** pan (`view().grid.px/py`).
The zoom is the same on every screen since 2026-11-18 ("make it such that smaller windows or smaller devices will still
receive the same amount of detail as bigger ones"): it was the largest clean grid scale whose placement of the box was
clear, so it followed the screen (11.25 on a 1080p desktop, 12 on a laptop, 5 to 6.25 on phones). It is the Settings
panel's View slider (the same day: "make a view slider for zooming the camera in and out, with 10 notches"):
`setZoom(n)` picks notch n of `Tuning.CamZoomNotches` (5, 6, 7, 8, 9, 10, 11, 12, 14, 16 art px a stud, each a clean
`Raster.gridScale`), `zoom()` reads it; `CamZoomDefault` 7 (11 a stud: the user's pick on 2026-11-20, "also, make the
default view here"; it was 8, 12 a stud, then 6, 10 a stud, "default view should be here"; Schema's 17 -> 18 step moves
a save still on 8 to the new default and its 22 -> 23 step one still on 6). A new notch is a new key: `refit` puts the pan
on the founder and fires `ViewChanged`, and the renderer bakes the island again at the new scale (the old picture
stays up meanwhile); Build mode's drag is scaled to keep its studs. `start` applies `settings.zoom` from the view when
the saved value changes (the join, another device), so a tap still waiting on the server is not undone. A stage's view (`Stage`) still fits its own points that way. The grid's ray plane `l` is fixed per plot (`CamRayBack` behind the plot's origin), so the
key (`plot|a|phase|l|screen|K`) only changes with the plot, the screen or K: anything else (the HUD's blocks, the
island's tier) only moves the home pan.
The **pan now** (`pan() -> (px, py)`, whole art px) follows the founder every frame (`RenderStepped`): the target puts
the founder's ground point in the middle of the screen across and halfway between the HUD's top and bottom strips
(and the tips banner), on any island. The target is not rounded; the follow's own place
(`camX, camY`, art px) chases it on a critically damped spring (Unity's SmoothDamp, smooth time `CamFollowSecs` 0.2 s,
the frame's dt counted) since 2026-11-18 ("make the camera a smooth lerp follow the player like most top down games
instead of sharply cutting to the player"): it sets off gently, trails a steady walk by the founder's speed times
`CamFollowSecs` (3.2 studs), and settles on them about half a second after they stop, never past them. (Before, the pan
moved `CamGlide` 0.18 of the way a 60th of a second, at least an art px a frame, and stopped dead.) The pan is the
target's pixel less the gap's (`round(t) - round(t - cam)` on each axis), so through a steady walk it steps with the
founder pixel for pixel and they keep still on the screen; it moves at most what the renderer can scroll in a frame
(`panCaps`: `PixelPanRays` over 1.5 rays a pixel of a strip), so its picture never falls behind into a re-bake. In the
classic style the Roblox camera stands on the unrounded place. A target more than three quarters of the screen away
snaps (one bake instead of a scroll that would bake several times). A new character is ignored until it has stood on its own lot once or 3 s have passed
(Roblox drops it mid-street before the server moves it home). Build mode (GAME_DESIGN 4.5: "make the camera still follow
the player as they walk around, even though it is displaced downwards abit"): `setFree(true, down?)` keeps the follow,
the target lowered by half of `down` art px (Build mode's tray height) plus a drag offset; `panBy(dx, dy)` (full-screen
px) moves the offset and the follow's place with it at once (no spring between the pointer and the world), the target's
centre kept within `CamBuildPan` studs of the plot (`clampBuild`); while the
founder stands the offset holds, and each frame their follow target moves the offset shrinks by `CamBuildRecenter` of
itself (at least an art px) until the view is back on them; with no founder to follow the view stays.
`setFree(false)` drops the lowering and the offset; `isFree()`; `buildDrag() -> (dx, dy)` (the offset, art px: sims).
`setFocus(p?, snap?)`: a cutscene's world point the pan keeps in the middle instead of the founder (unused since the walk in went), nil gives the
founder back; `snap` jumps there at once (behind the blinds) instead of gliding. `settled()`: the pan is on its
target's pixel. `refit` on a new key starts the pan on the target (the founder or the focus), not on the island's middle.
A new tier's cells and the next one's are worked out 3 s after the view's tier changes (`Street.warm`).
`gridAt(px, py)` (the grid at a pan), `centerWorld()` (the view's ground centre now), `view()`, `refit()`,
`ViewChanged` (a new key: a new bake), `pixelK(size?)`, `setPixelLimit(h, classic)`. The Roblox camera is posed on the
pan now: far away at `CamFov` with the filter on, at `CamOffFov` in the classic style.
**Stage mode** (the hatch scene's, `UI/HatchScene`): `setStage(Stage?)` with `Stage = { name, origin, pts, tight?, top, bottom, clear?, empty? }` fits the
stage's points (`tight` instead on a screen under 600 px tall: a phone held sideways, the action's band drawn at a
bigger scale) full screen clear of the play overlay's top and bottom strips (art px), the ray plane at the stage's origin,
the key `stage:<name>|...`, no indoor room; the view holds still (`view().stage` true; `view().clear` when the stage's
sky is see-through, `Stage.clear`: the renderer leaves what its rays miss empty; `view().empty` when it is also
`Stage.empty`, a stage with nothing static on it: the renderer casts no rays for it and has its empty picture at once,
so only the moving things show, over whatever is behind the layer); `setStage(nil)` goes back
to the street; `stage()`. `setStageShift(shift, snap?)`: an endless islet's camera, the stage's framing moved by
`shift` studs (the target is the home pan plus the shift's grid px); on a stage the view glides, so the renderer
scrolls to the next area and never re-bakes (reset by `setStage`); `snap` puts it there at once (behind the curtain,
before the first picture: only the boat arrival, unused now, asked for it).

### 9.3 `PixelRenderer`
`init`, `start`, `setTier(t)`, `tier`, `isActive`, `unavailableReason`, `pixelScale` (K), `firstPicture() -> (shown,
progress)`, `hideStatic(part)` (Controllers/Spinners: a static part leaves the picture, Transparency 1 so BakeCast
looks through it, the rect it and its shadow cover cast again, or the stash marked dirty on a stage),
`registerDynamic(model, outline?)` (outline "self" or "player": a founder, outlined in white, GAME_DESIGN
14.1: Random Bakery's rim. Once every model and its ink edge is drawn, each founder's whole silhouette, hidden parts too,
is drawn again flat into a scratch window of its parts' rect (`Raster.window`, a buffer grown on demand and never
shrunk) and `Shading.rim` lays white on its edge pixels, dotted on the global grid where something nearer hides that
part (x-ray); at most `Rims.max` (8) a tick, the own one ("self") first, then the nearest to the layer's middle; the
rim state is one table, `Rims`, since the main chunk sits at Luau's 200 registers), `hasRim(model)`, `debugRims() ->
{ drawn, px, ms, registered }` (the last tick's rims, their white pixels and ms), `unregisterDynamic`,
`refreshDynamic`, `rebake`, `setPaused`,
On a view with `clear` the pixels its rays miss are 0 (alpha 0) and the grade and dim pass them by, so a picture behind
the layer shows round the stage (`UI/HatchBackdrop`, a ScreenGui at `PixelDisplayOrder` - 2, its sky life at - 1).
On a view with `empty` (`Stage.empty`, the hatch scene's) nothing is cast: the static picture is cleared (no colour,
far depth, no ids) and finished at once, so the first picture is there on the next frame with only the moving things.
When a stage takes the view, the island's finished picture is kept (the stash: its buffers, its id tables and the rects
still to cast again on it) and comes back the moment the island's view does. One kept while a re-bake ran behind it or
was due, or with a part come or gone since (`dirty`), still comes back at once and is baked again behind itself. (The report of 2026-11-18: "a glitch happens when expanding and
then immediately hatching somthing after, which causes the filter to be disabled". Such a picture used to be dropped,
so the island came back to a bake from nothing with the hatch scene's last frame left over the 3D world meanwhile.)
Back from a stage with nothing kept (the screen changed size), the layer stays hidden until its bake fades in.
`watchStage(root)` (unused now: a stage's static parts that come or go while it is in view re-cast their rects; a rect over one
already queued joins it while their box is no bigger than the two apart, so an endless islet's area landing in view,
hundreds of boxes, re-casts its union once instead of re-baking the whole picture over their overlaps),
`afterBake(fn)` (fn runs once the picture shows the world as it is now: after the pending or running bake, at once
when none is coming or the filter is off), `busy()` (a bake under way or due, or rects queued to cast again; false in
the classic style: Build mode's expansion holds the loading card up until it is false), `setHidden(on)` (while the
loading card hides the game a bake may take `Tuning.PixelHiddenMs` (40) of each frame, and a re-cast as long with 8
times the rays; kept on the module table),
`casting(model) -> boolean` (whether the picture has still to catch up with
`model` where it stands: a whole bake running or due, or a re-cast queued or under way over the rect of any of its
parts with their shadows; false in the classic style; Build mode's landed stand-in waits on it), a moving model's
"PixelLead" attribute (studs nearer than it stands when its picture is put down on the frame, `Dyn.lead`, read at
`registerDynamic`: a model standing where a static one is being cast wins the ties, so the static pixels cast under it
so far never show through),
(the island growing into its next tier on the picture, `Pixel/Grow` with `growNext`, `growing`, `growFront`,
`afterGrow` and `growStats`, went on 2026-11-19: "Expansion is very slow and laggy, especially at higher levels. Is it
possible to optimize and speed it up? No need for the transition anymore". The land's chunks that an expansion swaps
(StreetModels.landPlan) come and go like any part: their rects are re-cast where they show, the whole layer re-baked
behind the picture only when they cover more than `REBAKE_SHARE` of it.) The water's wave phase is
`waterPhase(wx, wz)`, shared with the bake. `project(world) -> (Vector2 full-screen px, on)`, `projectPixel(world) -> (i, j, on)`, `pixelAt(pos) -> (i, j)` (the
art pixel under an InputObject's Position, as `projectPixel` gives them), `screenRay(pos) -> (origin,
direction * length)` (pos = an InputObject's Position: the pick ray through what the layer shows), `nearScreen(world,
pad) -> boolean` (whether a world point lies on the layer or within `pad` art px of it: Controllers/WorldView dresses
and undresses the driftlings by it, Controllers/Spinners turns only the sails near the screen), `debugStatic()`
(CLI checks: layer, pan, bakes, ticks, `baking` and `behind` (a bake behind the picture), `scrolls`, `scrollRays`, `recasts`, `queued`),
`debugStaticIds(root?) -> (Raster.Frame?, { [id]: BasePart }, isInk)` (previews: the static picture's buffers (its
colour as shown, depth and part ids; nil before a bake), the ids the parts under `root` got (every id with no root),
and `Shading.isInk` to tell an outline's pixel; the preview `treeink` counts the Tree of Life's loose pixels with it),
`glide(model, now?, posed?)` (Controllers/WorldView every frame: where a driftling stands and where its parts were
posed; its kept picture slides between them), `debugShown(model) -> (x?, y?)` (where its picture went down last,
layer px), `debugShadowCheck() -> { high, darkened, ground, shadows }` (the blob shadows' pixels on raised surfaces,
those darkened, and the ground ones darkened), `Changed: Signal<PixelTier>`,
`addFxLayer(name, draw) -> remove` and `fxStats()` (below).
- **Pans** (every frame): when `CameraController.pan()` differs from the layer's, every static buffer shifts by whole
  art px (`buffer.copy`, overlapping rows) and the uncovered strips are cast by the bake's last pass (each 2x2 block's
  even-even anchor first with its sun ray, then the pixels sharing it), their shadow edges refined once all of them are
  in (`castRect(..., noRefine)`, then `refineShadows` over each strip and a pixel round it), re-outlined with a pixel
  round them and their water set to the frame now (`SG.waterFix`); at most `Tuning.PixelPanRays` rays a frame (a
  longer pan catches up over frames); a pan of half the layer or more re-bakes at the new pan behind the old picture.
  Composing incrementally, the finished frame, its base, the image's graded copy and last tick's effect pixels shift
  with the layer (`SG.panShift`; the sticky pixels come off first, `SG.unstickFrame`, as the pan drops them) and the
  strips, with 3 px round them, go in as the static picture alone (`SG.strips`); otherwise the next compose copies the
  whole static layer and uploads the whole image.
- **The see-through sky round the islands** (the request of 2026-11-20: "Never mind, make it a floating island instead,
  with a 2d skybox. Expanding makes the island bigger."): the islands' view is `clear` (CameraController), so a pixel
  whose ray meets nothing is left empty (alpha 0, never graded), like the hatch scene's stage, and `UI/SkyBackdrop`'s
  painted sky shows through behind the pixel layer (10.19; hidden whenever the filter isn't drawing, so the classic
  style shows the world). An island's invisible wall and the parts that keep a bevel's cut
  corner solid (group `Bounds`, `StagedBounds`, or wholly transparent) are never in the picture, so their coming and
  going casts nothing (`watchStatic`'s `poke`). The rect a part and its shadow cover runs down to `Street.LAWN_Y` - 0.6
  (`SG.boxRect`). (The darkness over the land not open yet, `SG.DK` with its `sDark` keys, ran for part of the same
  day.)
- **The pan cache** (`Pixel/PanCache`, `SG.Tiles`; the request of 2026-11-16: "is there any way to optimize the camera
  movement? it is still very laggy when moving around"): the view is orthographic and pans by whole art px, so a static
  pixel at a global art px is the same wherever the view stands. The strips a pan is about to scroll off are kept in
  tiles of `PanCache.TILE` (32) x 32 global art px (`save(bufs, gx0, gy0, x0, y0, x1, y1)`: each channel the cast
  writes, `sShade sAlbedo sDepth sNormal sLit sId sShare sWClass sWave`, in its own plane, a byte a pixel saying it is
  good; 20 bytes a pixel), all but what a queued or running re-cast still covers (`SG.pendingOver`). A strip coming on
  is cut along the tiles (`split`) and each piece the cache holds whole is copied in (`load -> boolean`), the rest
  cast; the ink, the contact shade and the water are drawn again over both. `queueRect` drops the tiles under its rect
  (`drop(gx0, gy0, gx1, gy1)`, on the layer or off it); a bake of the island's own view (not a stage's: the hatch scene
  leaves it be), the growth's end and a new tier clear it (`clear`); `SG.tilesOk(s)`: only for the island's own view, no
  growth going, `Tuning.PixelPanCacheTiles` above 0. At most that many tiles (768, about 15.7 MB); past it the one used
  longest ago goes. `stats() -> { loaded, missed, saved, dropped, evicted, tiles }` (since the last read). Walking the
  pan preview's square a second time, the strips' cast went from about 21 ms a frame to under 2. `PanCache.new()` makes another
  store with the same functions (the next tier cast ahead), `take(tx, ty)` / `put(tx, ty, tile)` move a whole tile
  between stores, `full(tx, ty)` and `keys()`.
- **The next tier, cast ahead** (`PC`, the request of 2026-11-20: "Is there a way to make island expansion seamless,
  with no lag? Could you pre render max expansion floors so that expanding simply switches to that expansion level?").
  The player's next island stands staged in the world (PlotService: `workspace.Staged.Plot_<i>`, collision groups
  nothing collides with; `PC.watch` hides its parts from Roblox's own picture with `LocalTransparencyModifier` 1, which
  `watchStatic` puts back to 0 when they land on an island). Once its `Tier` attribute says all of it is there, a job
  (`PC.start`) pairs the staged models (chunks `Chunk_<cx>_<cz>_...`, the tree `<uid>:tree:...`) with the island's
  models they replace and lists the tiles of `PanCache.TILE` the swap changes (each model's box and its shadow:
  `SG.boxRect`). In the frame's spare time (no bake, re-cast or re-bake waiting; `Tuning.PixelPreCastMs`, 2 ms) the
  tiles within `PC.MARGIN` (160) art px of the layer are cast nearest the view first (`PC.step`), each on a small layer
  of the tile and 2 px round it (`castSample` in two phases, then `refineShadows`) with rays in the `PreCast` group
  that pass the replaced models and every other plot's staged island, then its middle saved into a store of its own
  (`PanCache.new()`); a tile with any open sky is left out. A part that comes or goes over a cast tile drops it
  (`PC.drop`); a bake, a new view, a tier, a stage or a change to the staged island starts the job again (`preReset`:
  the part ids and the grid it used are gone). The swap (`PC.swap`, from `watchStatic`): the first staged part landing
  on the island `PC.apply`s the job: every cast tile goes into the pan cache (`take`/`put`) and, where the layer shows
  it, onto the layer (`load`, then the ink, the contact shade, the water and the grade over it); the region's other
  tiles on the layer are queued, joined into runs along each row; and the staged parts' coming and the replaced
  models' parts' going (`oldParts`: kept as a set, a part going may be cut off from its model by then) cast nothing.
  After the swap the job answers for its models' comings and goings for 8 s (`untilT`), then lets go (`PC.step`,
  `PC.swap`: `preReset`), so the island after the next is cast ahead in its turn; before 2026-11-20 it was kept until
  the next bake, and the next expansion was never cast ahead while the models it had swapped in counted as drawn on
  every later change ("there are artifacts that appear around after expanding"). `PC.apply` empties the pan cache
  before putting the cast tiles in (no tile of the island as it was comes back on a pan), and restarts a whole bake
  under way (`rebakeAt`). A model arriving under the name of a staged one (`newNames`) that is not it, a fresh copy, is
  queued whole once (`recast`) instead of part by part. PlotService moves the staged tree straight into the island's
  `Decor` (it went through nil, which a client receives as a new copy: "the tree outlines are still broken").
  `debugPre() -> { tiles, rays, pasted, cast, skipped, reset, other, early, job? }`. The expansion preview
  (`expandperf=<tier>`) waits for the job, swaps, and checks the picture against a fresh cast (`debugCastCheck`: the
  differences left are faces lying at one depth, which the simulator's ray index, built per filter, may break either
  way, and the layer's last column, whose shadow edges the fresh cast cannot see past).
- **What a frame costs while the view pans** (the request of 2026-11-15: "the camera moving is always very laggy"):
  every pan composes and uploads the whole picture, so neither may cost the whole picture's Luau work. `SG` (one
  table: the main chunk is at 200 registers) holds `SG.buf`, the static layer graded (`gradeSpan` over `sColor`,
  `sId` and the lamps' pools), kept in step with it: a pan shifts it like the static buffers and grades only the
  strips it casts (and 3 px round them, for their ink and contact shade); a re-cast rect, the water's changed pixels
  and the wind's painted and restored pixels grade themselves again (`SG.rect`, `SG.px`); a bake, the island growing,
  a stash coming back, a failed or removed effect layer, a new grade or dim and a rebuilt pool map clear `SG.ok`, and
  the next whole upload grades it all once. A whole upload (`uploadAll(s, over, sticks, fxBook, fxN)`) copies `SG.buf`
  and grades from the frame only what is drawn over the static picture: the moving models' rects, this tick's effect
  pixels (their book) and the stuck pixels. Moving models keep their picture (`Dyn.cache`, a `DynCache`): a model
  drawn afresh is drawn into a scratch frame of its own (`SG.drawPic` into `SG.isoFor`: far and empty, the layer's
  size and `SG.ISO_M` (96) px more all round, at the layer's camera windowed out by that much, so a model past the
  layer's edge is drawn whole; each draw wipes what it wrote), and every pixel of it (colour, depth, id, `PX_BYTES` 14
  each) is kept with its parts' CFrames, Sizes and shown flags, the static picture's epoch `SG.ver` (bumped by
  anything that changes the static picture except a pan), the scale, and where its blob shadow is cast from (`shp`,
  its PrimaryPart's position). A kept picture stands for a draw while every part stands as it did, the epoch and the
  scale are the same and it lies at least partly on the layer (`SG.blitOk`); it goes down depth tested like the draw
  (`SG.blitAt`, `t + bias < depth`, clipped to the layer). The models still change at the tier's `hz` (`SG.dynAcc`):
  between two of those a model shows its kept picture even when it has moved, except a founder. What every model
  shows a compose is worked out first (`SG.plan` -> `{ PlanEntry }`: the model, its picture and layer rect, its
  shadow's centre and radii): a kept picture that stands, or a draw afresh within the tick's budget
  (`Tuning.PixelDynMs` of drawing, `Tuning.PixelMaxDyn` models, read on `SG.clock`), the founders first, then a model
  with no picture at all (`SG.bare`), then the longest undrawn, a model whose last picture lay wholly off the layer
  last (`SG.offPic`; one that has not moved since needs none); past the budget a model shows its kept picture a tick
  longer where it last stood. A kept picture slides with its model (`PixelRenderer.glide`: `Dyn.gNow`, where the model
  stands now, and `DynCache.anchor`, where its parts stood when it was drawn): `SG.glideOf` gives the whole art px
  across and down and the depth to add, the picture goes down there (`SG.blitAt(..., dz)`), its blob shadow moves by
  the same px, and an incremental compose takes a picture shown at another place or depth as changed (`Dyn.shDz`).
  (The request of 2026-11-18, "make it such that overworld creatures move smoother": on a busy island a walker was
  posed and drawn a few times a second and its picture jumped 4 to 7 px between; now it moves about 27 times a
  second, a pixel at a time, the `crowd` preview.) Its blob shadow is its picture's (`SG.shadowGeo(s, model, first, held)`), so a model
  and its shadow move together. Before (the stress test of 2026-11-17, "do a stress test with the maximum amount of
  decor and buildings at the highest expansion level"), a model that moved every tick was kept only while the view
  panned and only with no other model in its rect, and on a full Everdrift about 48 models a frame past the budget
  had no picture and were left out (`debugPerf().skips` counts them, `skipWhy` says why). Sims and previews:
  `debugPerf()` (ms summed since the last read: frames, the slowest frame `maxMs` and the frames over 25 ms `slow`, the
  scroll and its cast and ink, the compose and its copy, models, outlines, rims and effects, whole uploads and their
  grade, whole regrades, the water and the wind, kept pictures used and models drawn, the pan cache's `stats()` as
  `cache`, the incremental composes `incFrames` and the art px they redid `incPx`, the whole ones `fullFrames`, the
  tiles each source marked `markBy`, the models left out `skips` and why `skipWhy`), `debugClock(fn?)` (the clock the
  budgets and timings read, `SG.clock`: the stress preview walks the world at 60 frames a second of its own time and
  hands its real clock in), `debugIncCheck() -> { off, ties, checked, px, seen }` (arms a check of the next incremental
  compose: drawn without the budget, then composed whole at once and the frames before the effects compared; returns
  the last one's result: `ties` the pixels where two models meet within the depth bias, which the one put down first
  keeps), `debugInc()` (whether the island composes incrementally now), `debugGradeCheck() -> { checked, off, image, recasting }` (`SG.buf` against grading `sColor` afresh, and
  the last whole upload against grading the frame afresh), `debugKeepCheck() -> { off, hits, checked }` (two composes
  of one moment, with and without the kept pictures, the effects left out: the pixels that differ),
  `debugBaseCheck() -> { n, rows }` (the incremental compose's base against its frame: the pixels that differ other
  than this tick's effects and the stuck ones, -1 with no incremental compose going; the everdrift preview logs it after
  each jump and sim_world expects none after the big island's re-bakes. The sweep of 2026-11-19 found a finished bake
  copying the new picture onto the frame without asking for a whole compose, so the incremental ones went on from the
  old place's base and every effect taken off put back an old pixel: rows of another spot's colours trailing each
  leaf and wisp of wind. `finishBake` asks for one now),
  `debugCastCheck(full?, mask?) -> { off, checked, ids, lits, shades, ties, ex, tieEx, inkOff?, skyOver?, ghost?,
  tiles?, box?, mask? }` (the static layer against casting all of it afresh at its pan, then put back: what pans and
  the pan cache left different; a few shadow-edge pixels is the usual. `ties`: another part met at the same depth, the
  ray index's choice. With `full` the ink and contact shade are drawn again and the colour compared too, `inkOff`, and
  the pixels off sorted: `skyOver` nothing on the layer where a fresh cast meets a part, `ghost` the reverse, the 32 px
  `tiles` and the `box` they fall in, and with `mask` a byte a layer pixel: 1 sky over, 2 ghost, 3 another part or
  depth, 4 ink alone, 5 a tie; the `expandrim` and `treewalk` previews) and
  `debugWaterCheck() -> { off, checked, wind }` (the water pixels showing a tone not the frame's, and the pixels the
  wind has painted). The `pan` preview walks the founder round a square twice (the second time over ground the pan
  cache has kept), then stands, and reports them.
- **The incremental compose** (`SG.incCompose`; the stress test of 2026-11-17, "do a stress test with the maximum
  amount of decor and buildings at the highest expansion level. Try walking around to move the camera. It should be
  smooth. If not, find ways to optimize it"): a whole compose puts every moving model back over the static picture and
  inks and grades it all, and while the view panned every frame was composed whole. Now the composed frame stays and
  a compose redoes only the layer's tiles (`SG.TILE` 4 art px square, a byte each in `SG.bits`; `SG.mark`, `SG.hit`,
  `SG.runs` the marked tiles as rects, a run joined to the one above it over the same columns) where something
  changed: where a model's picture was and is when it is another picture or the same at another place (a founder
  always), where a blob shadow was and is when it moved, where a model went (`SG.forget`: unregistered or registered
  again; `SG.dirty`, global rects), a static pixel the water or the wind changed under a model or a shadow (`SG.sync`:
  one that shows the static picture takes its new colour on the frame, the base and the graded copy at once and the
  whole image goes up), and a band of tile rows round and round (one every third compose: whatever a compose of a few
  tiles might leave lasts a few seconds at most). An unchanged model or shadow that meets a pan's strip has that part
  marked too. In the tiles and the strips the static picture goes back (`restoreRect`, the sticky pixels with it), the
  blob shadows the tiles meet are drawn again clipped to them (`drawShadow(..., clip)`), an unchanged model the tiles
  meet is put down whole (outside them its pixels already show it, and a kept picture never beats its own depth), the
  changed ones where they are now; then the tiles are inked (`Shading.outline(..., dynFrom)`: only pairs with a moving
  model's pixel, the static picture's own ink staying as the bake left it), the founders' rims drawn, the tiles copied
  to `SG.base` (the frame before the effects: last tick's effect pixels are put back from it, `fxPrev`, as the static
  picture alone would leave holes in the models under them), the effects run, and the tiles, the strips and the
  effects' pixels (both books) graded into `SG.out` (`SG.gradeRect`: the static grade copied, the pixels the frame has
  other than the static picture graded from it) and uploaded (`SG.upRect`; the whole image after a pan or a water
  frame, or when the rects are many). `SG.live(s)`: the layer's whole compose set `SG.base` up (`SG.incStart`, not on
  a stage, not with the lamps' pools on), the graded static picture is in step, `Tuning.PixelIncCompose` is 1; a
  bake, a re-cast, the island growing, a new grade or dim and an effect layer failing still compose whole. The sticky
  pixels go on the base too (`SG.stickPut`: where it shows the static picture or the old sticky colour). On the
  village walking the pan preview's square a frame costs as before (about 22.5 ms) and standing a quarter less; on a
  full Everdrift (the `stress` preview) a frame's composing went from about 74 ms to under 30.
- **The water and the wind, a slice at a time**: their frames come `WATER_HZ` (6) times a second, and each used to be
  one pass over every pixel of the layer (about 20 to 30 ms for the water and 14 for the wind, a hitch six times a
  second). Now the next frame is worked out a slice at a time over the period before it (`SG.WATER_SLICES`, 8: every
  eighth row of the world's grid, so a pan in between moves no pixel into another slice; the slices due by the
  period's share gone, all of them by its end) and put on all at once when it comes. `SG.waterSlice(s, j)`: in slice
  j, a water pixel whose colour is its shade or this frame's tone and whose tone changes for the next frame (from
  `SG.waterTables(k)`, each class's tone at each wave phase for frames k - 1 and k; every water pixel when
  `SG.waterAll`, after a bake, the growth's end or a stash coming back) goes in `SG.waterPend` (global x, global y,
  colour now, colour next). `SG.waterApply(s)` puts on each still on the layer and still that colour, grading it from
  `SG.waterGrade` (water colour and part -> graded colour, under the grade and dim of `waterGradeKey`). `SG.waterFix`
  also queues the next frame of a strip whose slice was already worked out. (`SG.windSlice` and `SG.windApply`, the
  wind's own slices, went on 2026-11-20; `SG.windPend`, `windDone` and `windVoid` stay, always empty.)
- **Invalidation**: a part that comes or goes anywhere under `Workspace.Plots` queues the global-art-px rect it and its
  sun shadow on the lawn cover (`partRect`); queued rects are re-cast pixel by pixel by the same rule (anchors, then
  the rest), at most `Tuning.PixelInvalidateRaysFrame` rays and `Tuning.PixelInvalidateMs` a frame, then their shadow
  edges refined and re-outlined `FIN_ROWS` rows at a time within the same time (phases 3 and 4 of `InvCur`); rects over a third of the
  layer re-bake it (a new island), 0.15 s later and with 8 ms more a frame (`rush`); while that re-bake is pending a
  part's rect is not worked out (an island's rebuild is ~2,500 of them in one frame). After a re-cast (the rect and a
  pixel round it: the report of 2026-11-18, "some shadows still appear stepped like this", a re-cast had kept its 2x2
  blocks' shared sun) and at the end of a bake the shadow edges are refined (`refineShadows`, the tiers with shadows). Rects in global px survive pans.
- **Re-bakes behind the picture**: a bake started while a finished picture is on screen (`Surf.ready`; not a jump,
  whose picture is of another place) casts into fresh buffers (`back`) with its own part ids (`backTabs`, swapped in
  only while `bakeSome` runs), so the frames go on meanwhile: the models, the water and the wind keep drawing over
  the old picture at its camera (no pans or re-casts until it ends). The finished bake's buffers become the layer's
  and the whole image uploads. Before, the screen stood still for the whole bake. The finishing passes after the
  last cast pass are banded too (`bakeFin`, `FIN_ROWS` 12 rows at a time within the frame's budget: the shadow edges
  refined, then the ink outline and the contact shade), and `finishBake(s, b, true)` only swaps the buffers in. (They
  used to run in one go, a 340 to 410 ms frame at the end of every re-bake: the expansion's worst hitch.)
- The bake's rays are in the collision group `PixelRays` (the invisible walls never meet them) and exclude
  `Workspace.PixelDynamic` and every player's character (refreshed when characters come and
  go). Dynamic models whose first part lies more than `CULL` (48) art px off the layer are skipped; at most
  `PixelMaxDyn` are drawn afresh a tick, within `PixelDynMs` (`SG.plan`).
- **Stages** (nothing opens one now): a stage view bakes at the street's budget; the
  street's finished layer is kept aside (its buffers and part ids) and restored at once when the street's key comes
  back, unless a part under `Workspace.Plots` came or went meanwhile (then it bakes again). `ready()`: the view now has
  its finished picture (always true in the classic style). `setOffset(dx, dy)`: the layer shifted by whole art px
  (a hit's jolt in a minigame).
- **Water**: a part with a `PixelWater` attribute (1 deep water and 2 the shallows (the sea's, gone since 2026-11-20; 2 now the ponds, fountains and the rivers
  drawn on the island through `Parts.water`, 3 the foam, and a waterfall's white water, 4 falling water: class 6, its
  phase from its height and a little across, so pale streaks (`waterTone`: a crest and a lighter band under it, 14
  phase units a cycle, 3 a frame) run down the little waterfall's and the Spring Grotto's falls; the 2026-11-14
  request, "waterfalls having flowing water"; `waterColor`'s cache keyed `base * 32 + cls * 4 + tone`) marks its pixels in the bake
  (`sWClass`) with a wave phase from their ground position (`sWave`: bands across the water, bent by two sines);
  `WATER_HZ` (6) times a second, not on the low tier, every water pixel not under an ink line is shaded again from its
  baked tone: crests a light blue (`WATER_CREST`), troughs darker (`mixShaded` mixes in the layer's packed format,
  `Shading.pack`: red in the low byte), the foam's white coming and going (`waterColor`, cached per class, tone
  and phase), and the whole image uploads (composing incrementally, each changed pixel goes straight onto the frame,
  `SG.sync`). Its shadows and the islanders over it stay put. A stage's water moves too.
- **Wind** (GAME_DESIGN 8): gone since 2026-11-20 ("the outlines are still broken on the tree. no need to add rustling to
  the tree and other objects anymore, these cause broken outlines"). It moved pixels of the static layer's outline
  (a canopy's edge flicking out or in a pixel, a flag's columns dropping or lifting) on parts tagged `PixelWind`;
  `sWClass` classes 4 and 5 are no longer given, nothing paints, and `windRestore` (still called before a scroll, a
  stash and a bake) finds nothing to undo. The pass is in this file's history.
- **A spotlight** (once the battles'; nothing sets it now: `setDim(k)`, `debugDim()`): the static picture darkened by `dim` (0 .. 1,
  in tenths: each step re-uploads the picture) in `gradeSpan` after the grade, a static pixel (`id < DYN_ID0`) only and
  never a glowing one (`dimOf`, cached per colour: greyer by 0.35 x dim, times 1 - 0.5 x dim, cooled); the dynamic
  things (the fighters, their effects) as they are.
- **A picture in the world's light**: `gradePixel(c, g?)` puts a packed pixel (Snapshot's format) through `gradeOf`
  with grade `g` or the one now (as it is with none): the hatch scene's baked driftling (§10.11).
- **The time of day** (GAME_DESIGN 8; `setGrade(Grade?)`, `debugGrade() -> string` its key, "" by day): the layers
  keep their daylight colours; every uploaded pixel (`uploadAll`, `uploadRect`; the static picture's through `SG.buf`,
  above) goes through `gradeOf` (cached per colour and light level, cleared when the grade changes, which also
  uploads the whole picture; `gradeSpan` grades a run of one colour of one part under one pool once): desaturated by
  `sat`, times `mr mg mb`, plus a blue `lift` in the shadows. `Grade { mr, mg, mb, lift, sat, lamps }`. Neon parts
  (`EMISSIVE` statics, `dynGlow` dynamics) keep their colour; round them `lightMap` (u8 a pixel, 0..3, rebuilt by
  `buildLight` when the picture moved or a part came or went, at most every `LIGHT_EVERY` seconds, and every second
  for the moving lights; a dynamic part marked "PixelNoPool" glows but pools nothing, a hatching egg's cracks;
  `PixelRenderer.onComposed(fn?)`: fn runs at the end of each `compose`, with the world as the new picture shows it
  (an overlay on a moving model places itself then; kept on the module table, the main chunk being at 200 registers); a pan shifts it with the static layer, the strips coming in dark until the rebuild) pools
  warm light in three stepped rings (`RING`: 0.35, 0.65 and 1 of the radius, twice as wide as tall: the ground at
  2:1), each pool as big as its light (`lightRadius(area)`: `LIGHT_K` 1.2 x area ^ `LIGHT_POW` 0.6, between
  `LIGHT_MIN` 2 and `LIGHT_MAX` 22 art px): a static light is a patch of `EMISSIVE` pixels touching 8 ways (a flood
  fill over the static layer; its pool at the patch's middle, 3 px lower), a dynamic one a model's Neon parts together
  (their area the two biggest faces of each on the screen, art px per stud `cam.s / cam.K`; the pool at their
  area-weighted middle, 3 px lower),
  `lamps` of the way back to the colour by day, warmed, times how dark the hour is (`dark`: from the light's colour,
  0 by day and in the golden dusk, 1 at night) and 0.85 at most. As it gets dark the luminance over a knee is pressed
  down (`press`: up to 0.45 of it for white at night), so pale colours (shells, sand, sails) don't glow.
- **Surface textures** (GAME_DESIGN 2: "textured objects", "wood detail"; Random Bakery's material texture, widened):
  a static pixel of a textured colour may be shaded toward the band darker or lighter on its own ramp (`Shading.toonAt`'s
  `lift`) as it is shaded at bake time (`shadeAt`: the bake, a pan's strips, a re-cast, `refineShadows`), so it costs
  no ray. Since the request of 2026-11-14 ("make the noise textures across everything more less contrast with
  whatever material they are on, such as the 2d grass sprites and the sand dots") a mark takes only part of that step:
  `toonAt(..., lift, soft)` mixes the surface's band colour and the stepped one channel by channel, `soft` of the way
  (`Shading.softMix`, cached by the pair; both ends are tones of the same ramp, so no new hue and no palette snap),
  by kind `Shading.TEX_SOFT` (before: a whole band, 1): grass 0.45, sand 0.5, stone 0.45, wood 0.5, thatch 0.5, brick
  0.6, metal 0.55, glass 1 (its body is the material, not a mark). `Shading.texKind(rgb)` names the kind from the palette (`TEX_WOOD`: wood, wood_dark, bamboo, desk;
  `TEX_METAL`: steel, steel_dark; `TEX_GLASS`: window; `TEX_GRASS`: grass, grass_dark, moss, leaf, leaf_dark, swamp;
  `TEX_SAND`: sand, sand_dark; `TEX_STONE`: rock, rock_dark, slate, basalt, pavement; `TEX_THATCH`: straw;
  `TEX_BRICK`: brick; clay stays plain: here it is pots, jars, tent stripes and roof tiles). The first time the bake
  meets a part (`castSample`) it works out its `TexInfo` once (`texInfoOf`): the kind, its colour, its screen box in
  global art px (its centre's `Raster.gridPoint` and its box's projected half extents, from one `GetComponents`: the
  same at every pan), how its long axis runs on screen (`fam`: 1 upright, 2 level, 3 and 4 the two 2:1 slopes) and a
  `seed` from where it stands (never its id: a fresh bake numbers the parts afresh). `NO_TEX` for a part with none: a
  plain colour, a glowing one, water (`PixelWater` 1 to 3: animated on its own), a round brick thing, or one too small
  on screen for its pattern to read (`TEX_MIN`, e.g. 6 x 4 art px for wood, 8 x 5 for grass). The table (`texs`) lives
  with the other id tables (`staticIds`, `albedos`, `waters`): a bake behind the picture has its own
  (`backTabs.texs`), a stage's stash keeps the street's, and a new id clears its entry. `texLift` picks the pattern:
  `Shading.grassMark` (faces whose normal's y is 0.7 or more only), `sandMark`, `stoneMark`, `thatchMark` (faces whose
  normal's y is under 0.9 only: a roof's slope, a bale's side, never a slab of sandstone path), `grain(fam, seed, gx,
  gy)`, `mortar(courseFam, gx, gy)` (`Shading.courseFam` of the face's normal and the view's rotation, cached per
  normal index; none on faces that look up or down), `streak` and `glass` (from the part's box). A lighter mark shows
  only on a face in full sun (`Shading.band` 1: it turns that pixel `SUNLIT`), a darker one wherever a darker band is
  left, so in a shadow the texture fades into the shade like the rest of the face. A pixel tinted by glass in front
  shows none. The grid patterns are hashed from the global art pixel (`Shading.texHash`) in cells, at most one mark a
  cell and never on a cell's last row or column, so marks never touch into a blob. The blob shadows and the contact
  shade draw a pixel's shadow tone as before (a darker mark at the shade band is the shade band). The dynamic layer
  has none: a pattern on the screen's grid would slide over a model as it moves.
- **Smooth shading across a model's balls** (the request of 2026-11-14: "egg and creature models look blotchy due to
  how they are detailed using balls and other small shapes. Could you smoothen these blotches out or detail them so
  they look more natural?", then "This is also the case for the tree of life"; `Render/Smooth`, pure, and
  `Pixel/SmoothParts`): a model with its "PixelSmooth" attribute true (every driftling, `Kit.finish`; both egg
  builders; the Tree of Life, `DecorModels.build`) is lit as one surface. At a hit point `Smooth.normal` leans the
  normal toward each ball's outward direction, weighted (1 - d / (`REACH` 0.5 x its radius))^2 by d, how far the point
  is past that ball's surface (0 out of reach), so the light runs on across a join and down a chain of balls instead of
  ringing each one. A part's role (`SmoothParts.role`): "PixelOwn" or Neon keeps its own normal (the face parts,
  `facePart`; an egg's gems; the tree's Lawn, EggLawn and Moss), "PixelFollow" or any non-ball shape takes the body's
  normal where it lies on it and its own where it stands off it (spots, blush, bands, an egg's marks), any other ball
  leans and follows. Moving models (`registerDynamic`: `Dyn.smooth`, `DynPart.sm`): each frame the draw gathers the
  model's balls (`texOpt.xs ys zs rs cnt`), each leaning or following part asks `Smooth.near` for the balls within its
  bounding radius plus their reach (`texOpt.idx n`) and is drawn with `shadeTex`, which blends the normal before its
  texture's lift (`texOpt.role`). A following part lying on a smooth solid (the request of 2026-11-15; an ellipsoid,
  an egg or a cut egg's half) takes that solid's normal too: the draw packs the model's solids each frame
  (`Smooth.packSolid`, `SOLID_STRIDE` 18 numbers each: centre, rotation, inverse half sizes, an egg's equator and
  halves; `texOpt.sol scnt`), each following part lists the ones within reach of it (`texOpt.sidx sn`), and
  `Smooth.onSolids` gives the nearest one's gradient there and a weight (1 on its surface, 0 `SOLID_REACH` 0.12 studs
  off it), blended into the normal in `shadeTex`. A smooth solid itself keeps its own normal (`SmoothParts.role`: its
  "PixelShape" set). The static bake (`castSample`): a hit on a smooth model's part asks
  `SmoothParts.staticNormal` (the model's balls gathered the first time one of its parts is hit; `SmoothParts.reset` at
  `startBake`; `SmoothParts.changed(part)` when a part comes to or leaves a smooth model under Workspace.Plots drops
  that model's balls and the renderer casts the model's whole box again once that frame, since in the game the tree's
  parts reach the client over several frames) and stores
  the result as a fine normal index, `Shading.fineIndex` (27 .. 255: 229 directions on a Fibonacci spiral, within 12
  degrees of any direction; `Shading.normalVec` decodes both kinds; 0 .. 26 stay the world's coarse ones, so every
  "faces up" test is unchanged). The renderer's `NX NY NZ` and `courseFams` tables hold all 256.
- **Driftling textures** (the request of 2026-11-14, "apply texture to each of them"; `Render/DynTex`, pure): a dynamic
  part with a "PixelTex" attribute (its kind, `DynTex.KIND`, read at `registerDynamic`) is drawn with `shadeTex` where
  the view has at least `DynTex.MIN_PX_PER_STUD` (12) art px a stud: Raster hands every shade the hit's distance `t`
  along the pixel's ray (`Shade`'s seventh argument; the solids pass it, a uniform face never needs it), the shade
  finds the hit point in the part's own frame, lays it flat round the part's axis (`DynTex.uv`: a ball, an ellipsoid
  or an egg round its Y, a cylinder or a tapered limb round its X, a box across and up) and `DynTex.lift(kind, u, v, px, seed)` says whether the pixel steps a
  band lighter (+1) or darker (-1) on its ramp (`Shading.toonAt`'s lift, half of the step: `DynTex.SOFT` 0.5, a
  whole band before 2026-11-14). The patterns are measured in art px (`px`
  studs a pixel), so a mark is one pixel at any zoom: fur, fluff, feather, scale, shell, stone, brick, bark, crystal,
  skin, ice, velvet, chitin, jelly, ember. Below the threshold (the islands, 8 px a stud) parts draw plain.
- **Driftling eyes** (the request of 2026-11-15, "the eyes still do not look detailed or accurate and are mostly just
  simple discs"; `Render/EyeTex`, pure): `EyeTex.STYLE` (the twenty styles and "closed"), `EyeTex.sample(code, u, v,
  side, ppu, iris, dark, lid, white) -> (rgb1, lift1, glow1, rgb2, lift2, glow2, k)`: the layers painted at (u, v) on
  an eyeball's face (u across toward its +X, v up, each -1 .. 1; the visible eye within `EDGE` 0.9), stacked in order,
  each a shape's signed distance turned into how much of the pixel it covers (0.5 - d x ppu, ppu the pixels to one
  unit), the last partly covering one returned as the edge layer over its share k: the anti-aliasing. The parts: the
  dark eye of a cute creature (a dark eyeball, the iris a crescent low in it lit a band lighter at its foot, a darker
  pupil), the cartoon eye (a white that glows but for the lid's shadow over its top, the iris with a ring a band darker
  and its lower half a band lighter, the pupil), a cat's slit (an ellipse 0.14 x 0.68) or a goat's bar (0.6 x 0.15) in
  an eye all iris, a bird's broad ringed iris, beads with a ring and a ground reflection, two catchlights up toward the
  light (the top left) and low on the other side, a star or a heart of light, a gem's four facets lit by quadrant, a
  lit slot, a compound eye's hexagonal cells, the dark rim (about a pixel wide, heavier along the top: the upper lid's
  lashes), a sleepy upper lid down to 0.14 + 0.12 u^2, a fierce one slanting down to the inner side, the shut lid's
  dark line bowing down (a blink) or up (happy). An eye under 6 pixels across keeps its main colour and one catchlight.
- **Effects** (`addFxLayer(name, draw: (Fx.Ctx) -> ()) -> () -> ()`; `Render/Fx`; the request of 2026-11-13: "use 2d
  details to add to the athmosphere, such as grass, wood detail, birds and other details"): each tick, after the
  dynamic models and their outline and before the upload, every layer (the newest first) gets a `Fx.Ctx` over the
  frame: the frame (colour, depth, ids), its camera, the static buffers (`sColor`, `sId`, `sNormal`, `sAlbedo`,
  `sDepth`, `sWClass`), art px per stud (`ppu`), `ver` (`staticVer`, bumped by `staticChanged()` at every bake's end,
  scroll step, finished re-cast, stash return and new layer: what a layer works out from the static picture may be
  kept until it changes), `now`, `dt` (clamped to 0.25), `idOf(part)` and its book of written pixels. Effects write
  colour only (`Fx.put`; a light's pixel also writes `Fx.GLOW_ID`, 65535, which `isGlow` treats as Neon, so the
  night's grade keeps its colour). A see-through effect (`Fx.mix`, a faded sprite) goes on with `Fx.blendOver(over,
  under, a)`: over an opaque pixel the usual mix (`Fx.blend`); over the clear sky (alpha 0, where the painted sky
  behind the layer shows) its own colour at opacity a, so the sky shows through it (the report of 2026-11-20, "fog
  becomes black when outside of the island": mixed as if the clear pixel were black, the mist over the sky came out
  dark grey). Two books swap every tick: last tick's pixels go back to the static picture
  (`fxRestore`, colour and id) before the dynamic layer is drawn. `fxShown` (u32 a pixel) holds the effect colour the
  image shows there, its top byte the tick's mark (1 or 2): a pixel written this tick in a new colour, or one last
  tick's effects left, marks its 16 x 8 tile (`FX_TW`, `FX_TH`); the tiles go up in runs along their rows (a gap of one
  tile joins two; over `FX_MAX_RUNS` (40) runs, one rect a row of tiles), so an effect at rest costs no upload.
  **Sticky** pixels (`ctx.stick(i, c)` / `ctx.unstick(i)`, through `Fx.stickSprite` / `Fx.unstick`): things that stay
  put on the picture (the lawn's tufts and flowers) are kept in `stickCol` (u32 a pixel) and `stickList` and put back
  over the static picture wherever the frame takes it back (`restoreRect`, `fxRestore`, a full compose's copy), so they
  are drawn once and again only when they change; their changes mark their tiles; `staticChanged()` drops them all
  (every caller uploads the whole picture), as does removing a layer. A layer that errors is removed with a warning.
  They run inside `compose`: paused with the renderer, at its tier's rate, never in the classic style.
  `fxStats() -> { ms, bookMs, px, changed, rects, upPx, ticks, layers }` (the last tick's: the layers' ms, the books'
  ms, pixels written, changed, the rects and pixels uploaded).
- **Blob shadows**: a dynamic model with a `PixelShadow` attribute (radius, studs) shades the static pixels in an
  ellipse under its PrimaryPart on the ground at `PixelGroundY` as in the sun's shadow (the palette's own shadow tone;
  never an ink line or the sky), smaller the higher it is; none while its PrimaryPart is see-through or below its
  ground (a stage's thing put away under the floor); only on its ground: a static pixel whose surface (its ray's
  origin plus the look times its depth) stands more than `SHADOW_LIFT` (0.9) studs over `PixelGroundY` is a roof, an
  awning or a wall, and the blob passes it by (the report of 2026-11-18, "also, shadows clip through buildings": a
  driftling behind a stall darkened the stall's awning in front of it); drawn before the models, restored with their rects. The
  shadowed tone of each static pixel is worked out once and cached (`sShadowC`) until the static layer changes (a
  bake, a pan, a re-cast), so a cloud's big shadow stays cheap.

**`Pixel/PanCache`** (the request of 2026-11-16: "is there any way to optimize the camera movement? it is still very
laggy when moving around"): the static picture's cast pixels kept by the world's art grid in 32 x 32 tiles, so a strip
a pan brings back is copied, not cast (PixelRenderer's "The pan cache" above has its rules). No rays and no Instances:
`TILE`, `BYTES_A_PIXEL`, `setMax(n)`, `clear()`, `size()`, `save`, `load`, `split`, `drop`, `stats()`.

**`Pixel/Grow`** went on 2026-11-19 with the island's growth on the picture (GAME_DESIGN 4.4: "No need for the
transition anymore").

### 9.4 Text and pictures
`Pixel/PixelText` (copied): labels drawn in the pixel font into shared EditableImage atlas pages; a bound TextLabel
keeps its `Text`. A label bound with style `kind` "outline" or "title" and `under` the ink (or no `under`, or one
as dark: every channel under 0.25) draws its outline and depth in a darker step of its own face colour, 0.3 of the
face plus 0.3 of the palette's ink, following `setColor` and a changed `TextColor3` (selective outlining; a title on
the big face is baked again); `underShade` and `setUnder` still name the colour outright, and the drop shadow of
"shadow" and the weight of "weight" stay as given. `PixelText.overflows() -> { { name, text, w, h, bw, bh, clipped } }` (previews and sims: the bound
labels on show whose words need more room than their box, a line too wide or too many lines; `clipped` when the label
truncates them; the previews log each as an OVERFLOW line, the request of 2026-11-14, "there is a few boxes where text
overflows. can you prevent this?"). `Pixel/Snapshot` (copied): pixel-art pictures of models drawn analytically (`Render/Picture`), for
UI icons: the Staff panel's portraits (`UIKit.portrait`: a developer's head and shoulders turned to face the viewer). `Pixel/ImageMemory` (copied): every EditableImage is made through
it. Since 2026-11-21 `Render/Picture.Options` (and Snapshot's) take `place` (shade as the pixel filter shades a moving
model, `Shading.toonAt` in that place, in place of the fixed day palette), `textures` (a driftling's `PixelTex`
surface texture drawn as the filter does: `Picture.Solid.tex`, `texSeed`, `texV`, `texSoft` read by Snapshot, a step per
pixel in `Job.lift` from `DynTex.uv` and `DynTex.lift` at `Job.texPx` studs a pixel, from `DynTex.MIN_PX_PER_STUD` up)
and `grade` (a function on every shaded pixel that does not glow): a picture that sits in the world, the hatch scene's
baked driftling (§10.11). Without them a picture is drawn as before.

## 10. Interface

### 10.1 `UIKit`
The screens' layouts (GAME_DESIGN 2.1, 2026-11-21): `touch()` (touch and no mouse) picks the touch layout, `phone()`
the phone's sizes. `canvasOrigin(root)` gives a root's canvas top left in full-screen px, `AbsolutePosition.X` added for a
root kept inside a notched phone's safe area. `tabbed(body, items, picked, onPick, prefix?) -> (page, top)`: a desktop's
tabs across the top (`tabs`, the page the body, `top` under them), a touch screen's rail of tiles down the left
(`Tab_<id>`, icon over name, a dot on one with something waiting), the page a `TabBody` frame beside it with its own
`W`/`H`. `tooltip(target, title, detail?, key?)`: a glass card over the target, shown on hover after 0.25 s on a desktop
and while a finger holds it on a touch screen (`onHold`); `hideTip()`. `keyCap(parent, key, pos, z?) -> Frame`: a
shortcut's letter on a teal cap (`Key`, raw text). `setPanelKeys(map)`: a desktop window's shortcut shown left of its
close mark (the HUD hands over its key map). `relayout()`: every canvas laid out again and `Resized` fired (a screen
change with no signal: the simulator's device switch). On a touch screen the close mark is 22 UI px on coral
(`button_close`) with `big_close`, and the awning shows `big_<icon>` when one is drawn; on a desktop the awning drags
the window (in whole UI px, clamped to the canvas). `NOTICE_FOOT` (36) and `NOTICE_W` (200): a desktop's notices stack
in the bottom right corner, the newest lowest, `NOTICE_FOOT` over the canvas's bottom, at most `NOTICE_W` wide;
`setNoticeTop` moves only a touch screen's (top centred) stack.
`Pixel/ScreenSize`: `full() -> Vector2` (the whole screen in UI units: the larger of `Camera.ViewportSize` and a probe
ScreenGui that ignores every inset, so a notched phone's side margins count), `Changed` (fires when it changes),
`start()`. `CameraController.screenSize`, `PixelRenderer`'s layer, `SkyBackdrop`, `HatchBackdrop`, UIKit's viewport and
`LoadingCard` read it (the right-edge bar of 2026-11-21).
`UI/Hud` on a touch screen: `MenuBar` (a row of `Menu_<panel>` squares along the bottom on a `Dock` of glass: pals,
hatch, index, looks, top, settings, build; centred between the left 30% of the screen and the jump button, a tablet's
`Label_<panel>` names only where they fit; `Menu_build` mint with a `BuildRing` outline under it; the camera keeps the
row clear), `Status` and `Quest` at the left edge under the top bar, `MenuSide` (`Menu_rewards`, `Menu_store`), `TreeCard` as a square (`TreeOpen`, `TreeBar`,
`TreeNext` showing the time alone), `CoinsPlus` on the coins chip, `CardFold` on
the island card and `QuestFold` on the quest's card (both fold on every screen; the quest's starts folded on a touch screen, still showing `Which`, `Bar`, `Progress` and `QuestGo`, its `Words` only when open, as many lines as they wrap to), `Chip_season` / `Chip_weather` with their time alone (UI/WeatherChip), the island card in the top bar's row and `Offers` flush right. On a desktop: `TopBar` spans the
canvas with `Chip_rate`, `Chip_isle` and `Chip_charm` besides the coins, season and weather; `MenuBar`'s buttons carry
`Key` caps and tooltips; the keys (B P H N L G T M K, E for the tree) open and shut their menus.
Roots `World` (DisplayOrder 7, full screen: popups over the islands), `Hud` (10), `Modal` (20), `Popup` (25), each
with a `Canvas` frame in UI px (UIScale K) on the screen's grid. `color(key)`, `inkOf(c)` (an outline's colour
beside `c`: 0.45 of it plus 0.3 of the UI's ink, the world's step; every outline the UI draws takes it), `hex`, `P`, `size(root)`, `phone`,
`canvasOrigin`, `text(parent, text, size, pos, opts)` (PixelText-bound; `TextTruncate` AtEnd, so words too long for
the box end in "..." inside it, the last line of a wrapped one too, never past its edge), `setText`, `setTextColor`, `textWidth`,
`lineHeight`, `lines(text, w, face?)` (how many lines a wrapped label breaks it into). Languages and smooth text
(2026-11-20, docs/LOCALIZATION.md): a label keeps its English and shows `Lang.t` of it, and English written to it later
turns into its translation as it lands (`opts.raw` / `ButtonOpts.raw`: shown as written, a player's name);
`applyLanguage(choice, smooth)` (a language, "auto" resolved with `Player.LocaleId`, and the text style: every label
again, drawn in the pixel font or smooth, then `Resized` and the open panel built again; nothing when neither
changed), `LanguageChanged` (Signal(code) after it), `smooth()` (Text on Smooth, or a language the pixel font cannot
draw), `scriptFace()` (Builder Sans bold); a smooth label is a native TextLabel, `NATIVE_SIZE` 9 / 17 UI px, a stroke
at `NATIVE_STROKE` 0.55, also for words with letters the pixel font lacks (`Lang.needsScript`); `textWidth` and `lines`
measure what is shown (smooth words with `TextService:GetTextSize`, else `Lang.estimateWidth`); `rawWidth(s)` (words
never translated: a name tag), `wrap(text, w, face?) -> { string }` (the translation broken into a wrapped label's
lines, each kept: the hatch scene's passive plate). The look since 2026-11-14
("make the ui appear like this instead, with a black transparent background and make it neater", with a picture of
Random Bakery's HUD): `glass(parent, size, pos?, corner?)` (black see-through glass: `Palette.ui.glass` at
`GLASS_ALPHA` 0.38 transparency, corners of at most two steps, no outline, frame, bevel or shadow: every HUD block,
the tray, the notices, the hatch scene's plates; a panel's glass at `PANEL_ALPHA` 0.16), `row(parent, size, pos?, c?,
alpha?)` (an item's veil over the glass: `veil` white at `ROW_ALPHA` 0.9, one-step corners; `c` tints it, a picked
card the accent at 0.55), `PAD` (4 UI px inside a block), `isNeutral(color)`; `plate` with `{ glass = true }` or the
old `{ wood = t }` is glass, with `{ row = true }` a veil. `plate(parent, size, pos?, color?, alpha?, corner?, style?)` (stepped corners with a 1 px outline, `inkOf(color)` unless `style.edgeColor` names one,
following them: "Fill" rects inside "Edge" rects, none overlapping; `style { edge = false }` a flat swatch, `{ shadow
= true }` a 2 px drop shadow right and below, "Shadow"; the island's looks (GAME_DESIGN 2): `{ wood = t }` a frame of
planks t px wide outside the outline and another outline round it ("Wood": a "Board" behind, "Hi" / "Lo" bevel rows,
"Seam"s every `PLANK` px, a "Nail" in each corner; the plate then takes t + 1 px more on every side, the shadow moved
out with it), `{ bevel = true }` a lit top row and a shaded bottom one, "BevelHi" / "BevelLo"), `plank(frame, h, k?)`
(since 2026-11-14 a faint white `TitleRule` at row h + 1, `PAD` in from each side: the planks went with the frames),
`setPlate` (the fill), `rect`, `button` (a TextButton with a child "Words" label over a flat plate (no outline) with a
darker 1 px "Lip"; a coloured button flat in its colour, lighter while hovered, `button_off` grey disabled; a neutral
colour (`plate`, `plate_light`, `frame`, `frame_dark`, `glass`) makes a dark glass button: `glass` at `DARK_ALPHA`
0.3, white words, a faint veil while hovered, no lip; `opts.ghost` (the menu bar) shows no surface until hovered,
then a veil; `opts.textColor`; disabled = `AutoButtonColor` false; fires on `Activated`), `setEnabled`, `setButtonText`,
`setButtonColor`, `buttonWidth`, `bar -> (frame, set)`, `clear`, `vlist`, `hlist`, `scroll` (a "List" with a 3 px bar and, as a sibling at its foot, the 7x7 `arrow_down_t` "MoreBelow" while its canvas runs past its window and is not scrolled to the end: the bar alone was easy to miss on a phone, the sweep of 2026-11-19), `searchBox(parent, w, pos,
onChange, name, text?) -> Frame` (Build mode's `BuildSearch` and the Hatchery picker's `PalSearch`: a see-through
TextBox `Box` over the pixel font's `Query`, "Search" while empty, the clear mark `ClearSearch` while there are words;
`onChange(q)` with the words trimmed and in lower case whenever they change), `confetti(parent, n?,
colors?)` (a burst of 1 px pieces and 1x2 sticks that fly, tumble and fade), panels
(`registerPanel(name, { title, icon?, w, h, hFor?, props?, build })`, `hFor(w)` the height for the width the screen leaves it in place of `h` (Settings: its rows wrap on a narrow panel), the body that big with the awning on top (`SHEET_TOP` 25 UI px), within the screen less a few px; since 2026-11-19 ("Look at the bakery game and see its menu. Make a similarly polished and themed menu for different tabs") a **sheet** over a `sea_shade` veil (0.45 transparent): a "Frame" holding the "Glass" plate (black glass at `PANEL_ALPHA`), the "Head" (the awning: a "Band" clip with the `awning` plate, its "Stripe"s and "Fold"s, the "Hem" of `SCALLOP` 9 px scallops; the "Icon" `mini_<icon>`, the "Title" in cream with an ink outline, the "Status" line, the "Props" shelf with the def's `props` mini icons, the "Close" button (`awning_dark`, the `mini_close` sprite)) and the "Body"; `openPanel(name, arg)`, `openCount()` (openings so far: a panel takes its argument's tab once an opening), `closePanel`, `currentPanel`,
`refreshPanel` (keeps the "List" scroll), `PanelChanged`, `bodyWidth`, `bodyHeight`). Screens (2026-11-19, "make mobile and tablet as responsive and catered to as possible ... Make menus fill the screen on mobile with currency showing and an exit button"): `phone()` (a short side of 500 screen px or less), `touch()` (touch and no mouse), `tablet()` (touch, not a phone); `TOUCH_MIN` 44 screen px: on a touch screen `button` gives a button smaller than that a see-through "Hit" TextButton child round it (its pad, ZIndex 4) that presses it too; `onHold(target, show, hide)` (a finger held `HOLD_SECS` 0.35: show, lifted: hide); `setWallet(get, changed)` (Main.client: the view's shells and `StateClient.Changed`). A sheet on a phone is the Modal canvas's whole size (no margin, square glass corners), on a tablet 1.3 times its design within the canvas less 24; on a touch screen the Modal root ignores the top bar's inset and keeps only the device's safe area (`IgnoreGuiInset` true, `ScreenInsets` DeviceSafeInsets; a desktop's CoreUISafeInsets, set again on `relayout`), so a phone's sheet reaches the screen's top under Roblox's buttons, and a sheet whose top is under them moves its icon and title right of them and its body below them (`coreButtons`: GuiService.TopbarInset's free part, or `CORE_W` 176 screen px into the safe area and the top bar's inset where it reads 0; the 2026-11-21 request "flush it upwards, such that it sits on the roblox icon"); `canvasOrigin` keeps a notched phone's left margin for any root but a ScreenInsets None one; on a touch screen the awning is `AWNING_TOUCH` 24 tall (the body starts 4 lower), its exit 20 x 20 (else 15) and a "Wallet" chip before it (`mini_coin` and the label named "Shells", `Numbers.short`, set again on every `changed`); a phone's awning has no props shelf. (The sheets were cream paper for a few hours on 2026-11-19, the words recoloured while a panel built, "paper mode"; it went with "please make it such that the menu and ui remain in dark mode": the colouring stayed on while a button waited on the server and leaked into the HUD.) `tabs(parent, items { id, text, icon?, dot? }, picked, y, onPick, prefix?) -> height` (buttons `Tab_<id>`, the picked one `button` teal, the rest dark glass, a red "Dot", a second row when too wide), `TAB_H` 14, `heading(parent, text, y, icon?, right?) -> (label, note?, 12)` (`sheet_head` light teal, the `sheet_wave` sprite after it, a right-hand "Note"). `clear` keeps a child with the `Keep` attribute (a text box being typed in), `Resized` (fired once a frame whenever a root's canvas
changes size: K or the viewport changed, or a root was laid out again on its own, as Roblox does after the camera's
ViewportSize event and when the top bar's inset or a safe area settles; everything laid out from the canvas's size
rebuilds on it, and the bottom pieces, the HUD's menu bar and tips and Build mode's tray, are anchored to the
canvas's bottom edge so they stay on screen meanwhile), `notice(text, color, seconds)` (a toast at the top, as
many lines as its words take at its width (`lines`), up to the screen less 16 px wide; while a panel is open, its
status line next to the title instead when the words fit it, else the toast as usual (the request of 2026-11-19, "it
seems like the text gets cut off for some alerts": "Every hut is full. Swap one out, or build another hut." (the words then) needed 232
px, a 320 panel's line about 190); opening a panel clears the toasts, so nothing covers a panel; the toasts stack one under another from y 24, 8 px apart, a new one sliding 8 px down into its place and the rest moving up when one goes: they all went to one spot before, each over the last; the sweep of 2026-11-19), `clearNotices`, `setNoticeTop(y?)` (the toasts start at y while something sits over their spot: the HUD's day banner gives its bottom edge and a gap, nil back to 24; the ones showing move with it), `floatText(world, text, color, big)`, `portrait(parent, look, size, pos)`, the `Stage` root (DisplayOrder
22, full screen: a microgame's overlay, its UI px the world's art px), `tween` (a UDim2 property
eases on Heartbeat snapped to whole UI px, Quad out, the newest tween of a property winning; the rest through
TweenService), `Resized`, the effects `burst(parent, x, y, colors, n?, speed?)` (1 px bits from a point of a frame), `burstOn(gui,
colors, n?, speed?)` (from a GUI object's middle, on its canvas: it outlives a rebuilt panel), `popText(parent, x, y,
text, color)` (a word rising and fading), `shine(button)` (a light band sweeping across its plate, clear of the
corners) and `bitsAt(world, colors, n, speed?, gravity?)` (bits on the World canvas from a world point). Motion
(GAME_DESIGN 15): a button lightens while hovered, its plate and words sink 1 UI px while pressed,
and `Activated` plays `click` (or `deny` when disabled); a panel's shade fades in and its frame rises 10 UI px into
place; a notice slides down into the stack and fades out.

### 10.16 The Rewards sheet (`UI/RewardsUI`; GAME_DESIGN 15)
The panel "rewards" (argument a tab: today tasks spin index codes; `props` egg_3 gift wheel): `UIKit.tabs` with a dot on
each tab with something waiting, then a "List" scroll per tab. Today: the "Daily reward" heading ("Best n"), the
"Streak" row (Claim `DailyClaim` or "Next in ..."), the seven `Day_<i>` cards (got, now, plain; the seventh twice as
wide), the "Gifts for playing" heading, the "PlayGift" row (Claim `PlayClaim` or the next gift's `PlayTimer`) and the
eight `Play_<i>` cards. Tasks: `Task_<i>` rows (a bar, the count, `TaskClaim_<i>` or Done or the gift), the "Bonus" row
(`BonusClaim`). Lucky Spin: the `Slice_<i>` prizes with their odds and `Spin` (under them; on a phone first, under the heading, where a landscape screen's fold left it): the reply's `slice` drives a light round
the prizes (`spinAt`, repainted by name so a rebuilt sheet keeps it), slowing, then the notice (`StoreUI.rewardText`
from "spin", which `StoreUI` leaves to it). While it runs the sheet is rebuilt with `SkipSpin` ("Skip") in Spin's
place: it sets `skipSpin`, and the light's loop (which waits a frame at a time) stops and lands on `slice` at once
(2026-11-20, "make a skip for lucky shell spinning"). Index: `IndexGift_<i>` rows (`IndexClaim_<i>`). Codes: the "CodeField" (a
row kept across rebuilds, `Keep`, with a TextBox "Box" under the pixel font's copy "Typed") and `Redeem`. API:
`init()`, `words(v, reward, short?)`, `icon(reward)`, `ready(v)` (the server's count and a gift for playing come due
since), `playSecs(v)` (today's seconds, running on from the last tick Fx's `play`), `status(v, line)` (Hud's: the
"gift" line, tapped `openWaiting`, and a "boost_<id>" line per timed boost; the open sheet's timer), `openWaiting()`
(the sheet on the first tab with a red dot, else "today"), `TABS`, `tabOf()`. `Hud` adds the menu
bar's `Menu_rewards` ("Gifts", between Looks and Store) with a red "Dot" while `ready` > 0, and calls `status` four
times a second. The Hatchery panel (`Menus`) shows `Breed.preview` on a pair's row ("MutsLead" "Hatches with:", the
mutations, the "Cost" line) and a warming egg's mutations; the Tree panel's odds never say "not yet".

### 10.20 The Top sheet (`UI/TopUI`; GAME_DESIGN 16)
The panel "top" (title `Top@@board`, apart from the Looks screen's Top slot; argument a tab: coins charm hatched
driftlings friends; `props` trophy coin friends): `UIKit.tabs`, then for a board the "Hint" and "Every" lines, the pinned "You"
row and a scroll of `Row_<rank>` rows (the player's own named "You"; ranks 1 to 3 in `accent`, `rank_silver`,
`rank_bronze` with `mini_trophy`; players on this server in `sheet_head`; a name the server sent empty is "Player
{1}"; on driftlings the value is `Social.decode`d: the points on the right and, after the name, the kind's "Pal"
label in its rarity's colour, `star_t4` and the "Stars" count), "Loading..." until `lb.get` answers (asked in the background at most every 60 s a board; the sheet is built
again when it lands), "Empty" when nobody's on it or the read failed (asked again in 10 s). Friends: the "Invite
friends" heading, the "TheyGet" and "YouGet" rows (`RewardsUI.bundle` of `REFERRAL.invitee` / `.inviter`), `Invite`
(`TopUI.invite`: `SocialService:CanSendGameInviteAsync`, then `PromptGameInvite` with an `ExperienceInviteOptions`,
`PromptMessage` in the player's language and `LaunchData` `{"r": <user id>}`), "Invited" and "TodayLeft", the "Play
together" heading and the "Here" row ("Now" while friends are here), "Referred" for a player who joined from an invite.
API: `init()`, `TABS`, `tabOf()`, `status(v, line)` (Hud's: the "friends" line, tapped open on Friends), `invite()`.
`Hud` adds `Menu_top` ("Top", `mini_trophy`, between Gifts and Store) and calls `status` with the rewards' lines;
`StoreUI.rewardText` heads "friend" as "A friend you invited" and "invited" as "Welcome gift". New sprites:
`mini_trophy` (a gold cup on a brown foot) and `mini_friends` (two founders side by side).

### 10.2 `WorldView` and `EggView`
The islanders: a walker per hut driftling (`MicroModels.driftling` in its species' shape and colours), parsed from
each owned plot's `Pals` attribute and placed among the buildings read from its `Static.Decor` models' names
(`uid:id:x:z:rot:lvl`). A driftling goes to the building it works at (or its hut) and works there by its kind
(`palMoodOf`: `dip` at a pier or kelp farm, `peck` at the other farms, `push` at the wood and the boosts, `wave` at the
shops, `nap` at a hut or the hatchery, for longer: `DriftModels.animate`'s work moods), now and then a stroll
(`strollPoint`: a buildable cell off the Tree of Life where it stands). One new in a hut on an island already peopled has just
hatched: it steps out where its egg lay (`EggView.hatchPoint`) with a cheer and walks off to work (`born`). Workers
stand along the building's front, turned three-quarters to the view (east or south). Only islands within 100 studs of
the view's centre are drawn (synced every half second); no campfire's flame or smoke since 2026-11-20 (`fireOn` went
with the campfire). Each island's sign gets a World-root label (its name, the own in gold, or
"Unclaimed isle"; the `SignBoard` is looked up once in `Static.Land` and kept in `signBoards[i]` while it stays in the
world, looked for again every 0.5 s while missing, so no frame walks the island's thousands of parts); a tap (`onTap`: a press let go within 8 px, not on the interface, not in Build mode) goes to
`EggView.tapAt` first (an egg under the own tree: the tree panel); otherwise its ray (`PixelRenderer.screenRay` in the
`PixelRays` collision group, as the picture's, so it passes the islands' invisible walls, which Roblox hits whatever
their CanQuery says because they collide) on a Tree of Life (`treeOf`: a model with the `Decor` attribute "tree")
opens the "tree" panel for the own one, or for a neighbour's says "Not your tree. Yours is at home."; on a Hatchery (`hatcheryOf`: `Decor` "hatchery") the "hatch" panel for the own one, a notice for a
neighbour's (2026-11-14); on a sign it shows `signCard(i)` (the day, driftlings, charm). Fx "hatched" (`hatchedOne`) bursts
bits of the hatchling's rarity's colour at `EggView.hatchPoint`, a rare or better one's name floating up; a
Hatchery's hatchling (Fx "turn" `hatched`) gets its name and pink bits over the Hatchery; `cheer(words, color)` makes
the own islanders cheer. Its Heartbeat runs `EggView.step` with the view's centre (world x).
Only the walkers near the screen have a model (the stress test of 2026-11-17, a full Everdrift's 840 driftlings): one
within `MODEL_NEAR` (24) art px of the layer (`PixelRenderer.nearScreen` of its foot) is dressed (`dress`: a model of
its kind from `pool[sig]`, else `MicroModels.species(sig, "world")` with `PixelShadow` 1 and `PixelGroundY` the
lawn's, registered as a moving model) and one past `MODEL_FAR` (80) undressed (`undress`: unregistered, then parked at
y -400 in the pool while it holds fewer than `POOL_MAX` (200), else destroyed; parked rather than unparented, so the
scene's ray structures stay as they are). The dressed ones are posed through a budget (`posePals`): one walking every
`POSE_WALK` (1/30 s), one standing, working or napping every `POSE_STILL` (1/15 s), the longest waiting first, at
most `POSE_BUDGET` (6) a frame, about what the pixel filter draws afresh in a frame there. Between poses a walker's
picture slides on: each frame every dressed walker hands the pixel filter where it is and where its model was last put
(`Walker.px`, `pz`; `PixelRenderer.glide`). `debugMoving()` (previews: every dressed model, where it stands and whether
it walks); `holdPal(plot, id, secs, x?, z?)` puts it at `x`, `z` first. Each island's `Pals`
attribute is parsed again only when it changed (`palsRead`). `debugCost()` (seconds in each part of the Heartbeat since the last read: `walk`, `pose`, `rest`, `tags`,
`eggs`, `frames`, and the models `dressed` and `pooled`; `WorldView.clock` is the clock it reads).
A driftling under a tap (GAME_DESIGN 6, "One driftling's card"; tried after `EggView.tapAt` and before the ray):
`palAt(pos) -> Walker?` projects every walker (`PixelRenderer.project` of its foot and of its model's top, `Thing.h`) to
a screen box, as wide as 0.6 of its height each side (8 px at least) and half its height plus 4 px up and down from
its middle (10 px tall at least), and takes the box holding the tap whose middle is nearest; the tap's ray
(`rayParams()`: the PixelRays group, PixelDynamic and the characters excluded) meeting something nearer the camera
than the walker's middle less its radius and 1.5 studs passes it over for the next; never while the camera is in stage
mode. `openPal(w)` opens "pal" `{ id }` for the own island's, or `{ id, plot, sp, muts, work, home, isle }` for a
neighbour's (`work`/`home` the building ids standing at those uids, from `spotsNow`; `isle` its `StudioName`); each
walker keeps its `muts` from the `Pals` attribute. With a mouse, `stepHover` (ten times a second, nothing over the
interface (`InputChanged` processed), a panel open or in Build mode) floats the name of the walker under the pointer
over its head in its rarity's colour (`PalHover`, World root). `rigCount()` /
`ownRigCount()` / `ownCount()` (the walkers drawn: all, the own island's), `tapScreen(pos)` (a tap at screen px,
handled as a player's), `palScreen(plot, id) -> Vector2?` (a walker's box middle in screen px, as an InputObject's),
`palKeyAt(pos) -> string?` (the walker `palAt` picks, "<plot>:p<id>") and `holdPal(plot, id, secs)` (it stands still
that long) for the sims and previews. (No `TideView.ashore`; the old tree's label `updateTreeLabel` and `grownOne`
stay gone.)
`EggView` (client, GAME_DESIGN 6): every island's eggs from its plot's `Eggs` attribute (`id.rarity`; the islands
within `NEAR` (100) studs of the view's centre, synced every half second; an egg whose rarity changed under the same
id, the quest's egg, gets its new shell and rises again) round its tree, found from the tree's decor
model name (`uid:tree:x:z:rot:lvl`) and kept with that model (`treeSpots`) until it is gone: every egg asks every
frame, and an expansion builds the tree again at its next stage, last among the island's pieces, so reading every
piece's name each time cost 38 ms a frame on a full tier 15 island in the simulator (2026-11-19). The eggs a bigger
island lays rise at once (they waited for the growth until it went). Each egg is a `TreeEgg` model (`Models/EggModels.build(r)`, shared with the hatch
scene) in `Workspace.PixelDynamic` (registered with the renderer): a nest (since the request of 2026-11-15, "can you
also do the same with creature and egg models?": a ring of round straw tufts in two tones hugging the egg's foot with
stalks sticking out, cream down for the legendary, pink and white blossom for the mythic, silver and white for the
celestial; something by it from `TRIM[r]`: a pebble, a leaf and clover, a blue berry, a pink flower, petals,
crystals; a small highlight on the shell's lit side, three gems in the legendary's band, a gold `Star` on the
celestial's crown; the lawn glow from epic up 1.4 times the egg wide at `LAWN` 0.145, the tree's `EggLawn` height,
so it shows), the shell (since the request of 2026-11-15, "can you redo all the creatures and eggs ... currently, all
of them are modelled using blobs, which is unnatural": one smooth egg `1.06 x SIZE` tall and `0.86 x SIZE` wide, split
`SPLIT_EGG` 0.6, cut at `CUT` 0.6 of its height into an `EggBot` part `Shell` and an `EggTop` part `Top` that flies off,
Raster.drawSolid; the nest's tufts flattened ellipsoids along its ring, its stalks tapered limbs, what lies by it and a
touched egg's weather piece ellipsoids, drops eggs) and its marks, by `LOOK[r]` (`EggModels.LOOK`,
also `EggView.LOOK`; the common's freckles in two sizes and two browns, the bands on the side the camera sees)
(GAME_DESIGN 6: "color each egg differently with different effects"; `{ body, mark, marks, glow, lawn? }`: common
`cream` with `sand_dark` spots, uncommon `green` with a `white` band, rare `blue` with `white` spots, epic `purple`
with `pink` spots, legendary `gold` with a `yellow` band, mythic `wall_trim` (rose) with a `white` band and five
`cherry` buds round its crown, celestial `night` with `screen_on` spots and five small white Neon dust dabs; "spots" six dabs on the side facing the view, "band" twelve
dabs a little up and down in turn round its middle; the marks Neon from rare up, so a light pool at night); the epic and
legendary (mythic, celestial) a thin Neon disc of `lawn` colour on the grass under it; the epic two Neon `Mote`s (pink,
white), the mythic two (`cherry`, white), the celestial nine `Orbit` beads (white, `screen_on`, yellow) on a tilted ring
(fx kind "orbit"): the egg's `fx`, moved every frame (`stepEgg`: they circle and bob, put under the lawn while the egg sinks or cracks). The
legendary's band of light and `Beam` went on 2026-11-14 ("remove these rectangular effects everywhere, instead make it
twinkles"): its gold sparks and stars twinkle round it. `SIZE[r]` (1.25 .. 1.82) a rarer one bigger. Its sparks
(`stepSparks`, 2D on the World canvas at whole UI px): every `EVERY[r]` seconds or so (none, 0.8, 0.42, 0.26, 0.14,
0.11, 0.08)
an egg lying still (risen, not sinking or cracking) sends one up: an uncommon a green 1 px leaf drifting up, a rare a
`twinkle_1`/`twinkle_2` star blinking round it, an epic pink and white 1 px sparks rising, a legendary gold and white
ones and now and then a `spark_1..3` star, a mythic pink and white sparks and `twinkle_p1..p3` stars, a celestial motes
of every colour and `glint_1..3` glints; at most `SPARKS` (140) at once, none with the pixel filter off, each gone
with its egg. Slot k of a lot of n lies on the
lawn at `DecorModels.EGG_RING` from the tree's middle, spread evenly over the arc from `ARC0` (-62°) to `ARC1` (152°)
(the south and east, the side the view looks at); a lot keeps its slots while it lasts (an egg's slot its place in
the lot's order from its first id, `lotFirst`, or, when that slot is taken or past the ring, the first free one: an
expansion's extra eggs after a hatch never land on another egg's spot), the ring as many slots as `Tuning.EggCount`
by the island's tier. A
whole new lot (every egg gone at once and new ones in) rises out of the lawn (`RISE` 0.6 s, `STAGGER` 0.12 s apart,
from `DEEP` 1.4 studs under) while the old eggs sink (`SINK` 0.5 s); an egg laid on the own island while it grows
(`PixelRenderer.growing()`: the expansion's extra eggs) waits under the lawn (`wait`) until the growth is over, then
rises one after another round the ring (0.15 s, then `STAGGER` by slot) with a little overshoot (`pop`: an ease out
with a back); one gone while the rest stay, or one the own
player just hatched, cracks (`CRACK` 0.9 s: a shake, then `Top` flies off turning and the rest sinks); every egg rocks
for a moment every 7 s. No price tags or names over them (the request of 2026-11-13: "remove these, the eggs should be
buyable only after the player clicks on the tree or enters the tree menu"). On tip 4 a `TutArrow` (`arrow_down`, 13 px) bobs over
the own tree (unless a panel or the hatch scene is open); with the tree off the screen, or too near its edge, the arrow
sits 14 px in from the edge on the line from the screen's middle to the tree, `arrow_left` / `right` / `up` / `down` by
the way it lies, bobbing along it. Build mode closes itself 0.8 s after the view's tip goes from 3 to 4 (the hut placed
in it; BuildUI's `tutWas`), so the tree and the arrow show; opened again on tip 4 it stays. `hatch(id, swap?)` (sends `egg.hatch`; done, the panel shuts and
`HatchScene.play({ sp, muts, r, hr, new }, after)` runs; `after` opens the tree panel again if Hatch was pressed there (once no other hatch waits: `HatchScene.waiting()`) and
says "Hatched a rare Wispwing." in its rarity's colour ("New! Hatched..." when the result's `new` is true), with what a swap sold for; the egg's place kept as the
island's hatch point; `full` opens the tree panel's swap picker `{ hatch = id }`; other refusals in words), `best(v, n) -> { Laid }` (the view's eggs, the rarest first, then the lower id; when the shells cover none of
the best n, the best one they cover takes the last place: the HUD's card and the tree panel), `tapAt(pos) -> boolean`
(a tap at an InputObject's position, below the top bar, so the inset is added back: when it lands on one of the own
island's eggs, risen and not leaving, the "tree" panel opens; nothing is bought; true when it hit one), `step(t,
focusX)` (WorldView's Heartbeat: the near islands synced, every egg moved, the tips' arrow kept), `count(plot?) -> number`
(the eggs drawn, not counting ones sinking or cracking: the sims and previews), `where(plot, id) -> Vector3?` (an
egg's foot now, world; nil when not drawn), `hatchPoint(i) -> (x, z)` (where island i's last hatched egg lay; else in
front of the tree's hollow, `DecorModels.HOLLOW`; else `Street.spawn`).
`StreetLife` (client, started after AvatarView): a flock of three gulls crossing the sky between the islands every 14-24
s, each crossing its own (east or west, a slant, a height, a weave, each gull a little behind the next), every gull
turned the way it flies (the model's head is +Z) and gliding now and then (no clouds' shadows: the player asked for
them gone; the four sailboats went with the sea on 2026-11-20). `count()` for the CLI.
`AmbientView` (client, started after StreetLife; GAME_DESIGN 8.1): the islands' small lives, one effect layer
("ambient", `PixelRenderer.addFxLayer`) drawn with `Render/Fx` and UI/ArtData's `fx_` sprites (`Fx.define`: the frames
`fx_<group>_1..n`; a group's small sprites `fx_<group>s_*` where the island shows small, `ppu` under `BIG_PPU` 7).
Every claimed plot whose island's box (its cells and rim, `Street.cellBounds`) lies on the layer gets an `Isle`
(made when it comes into view, let go `ISLE_KEEP` 10 s after it leaves; looked at every `ISLE_EVERY` 0.5 s): its cells
by the tier's shape (`buildLand`: tufts sown in patches, `Fx.patch(x, z) * 0.4` a grass cell, kept in 8-stud
chunks culled to the screen; little flowers in clusters, 2.5 % of the cells; no beach, sea or fish since
2026-11-20), and what its models hold (`scan`, again 0.6 s after a piece comes or goes in its `Static.Decor` or a
chunk in its land model, `Isle.landModel`; each of the land's chunks, or the empty lot as one, is looked at as a unit: the
highest `Post`, `Rail` or `Top` of each fence, each `Ridge`, flat `Roof` and the sign's `Top` to perch on; `Flower`,
`Bloom`, `Blossom`, `Petals`, `FlowerHeart` parts for the butterflies; `Leaves`, `Blossom` and `Leaf` parts a stud or
more across, their colour, a blossom or a pale pink one dropping petals; `Chimney`, `Smoke`, `Coals` (and the
smokehouse's `Vent`) smoking, `Steam`, `Teapot`, `Mug` steaming, and since 2026-11-19 (the request "detail all decor
more, some having animations") `Flame` throwing up sparks (`Fx.KINDS.ember`: rising, winking), `Spray` throwing drops
up from a fountain's jet that fall back (`Fx.KINDS.spray`: launched up, falling, gone where they land) and `Sparkle`
twinkling now and then somewhere on the part (the glint sprite, at most 40 glints at a time); at most 64 such
spots an island; the cells the pieces cover, so no bird stands in a building). A tick (`draw`, nothing while `CameraController.view().stage`): `stepLife` (the birds, the butterflies,
leaves, wisps, fireflies), then the tufts and flowers (`drawDecos`: once per `ver`, whether the lawn itself
shows at the tuft's foot (an up-facing static pixel at its depth whose albedo is the grass or the dark grass) and the
lawn's tones there (`Fx.tones` of the static colour, pulled toward it: `softTones`, `TUFT_K` 0.38 of each step
kept, a flower's petals `FLOWER_K` 0.6; whole tones before 2026-11-14); stuck with `Fx.stickSprite` in the frame of the gust passing
(`Fx.gust`, `Fx.swayFrame`) and stuck again only when that frame changes; a lower tier keeps a share), the
glints on the rivers and ponds (a few a second on random water pixels, by `sWClass`), the
particles (`Fx.step`: drops, wisps, leaves), the birds and the butterflies, the fireflies last. Birds (`stepBird`;
4 an island at high, 3 medium, 2 low, pips and wrens in turn, and a gull): away, then in (flown in from one side of
the screen over 1.6 s, a gull over 2.4 s) to a perch picked on screen round its middle (an ellipse
0.24 x 0.3 of the screen, a gull's 0.3 x 0.36: never under the HUD's cards), nobody within 3.5 studs (a gull 5) and no
other bird on it (`pickPerch`: a rail, ridge or the sign 45 %, else a lawn cell; a gull a lawn cell
only), perched (pecks, hops along the perch, looks round, 20 to 70 s, a gull 12 to 30), then off (`flee`: away from
whoever came near, or when bored; at dusk) and away 6 to 16 s (a gull 25 to 60). Who walks: every player's character
and the models in `Workspace.PixelDynamic` on the lawn (`PixelGroundY` the lawn's: the driftlings), every
`RIGS_EVERY` 0.15 s. Butterflies (3 an island at high) by day (`DayLight.frac` 0.06 to 0.68) between the flowers,
resting on one now and then; fireflies (22 at high) at night (0.78 to 0.97) over the lawn's spots; birds by day (0.03
to 0.72). Reduced motion (`GuiService.ReducedMotionEnabled`): no particles, flights
or sway. `stats()` (what is alive and drawn, and the last tick's parts in ms: `msLife`, `msDecos`, `msParticles`,
`msCreatures`), `birds(plot)` (`{ sp, state, x, y, z, on }`), `debugRun(on)` (the sims: the lives stepped on
Heartbeat with the view's own camera while no picture is drawn), `debugHurry()` (every bird, gull and leaf due
now), `setSuspended(on)` (a timing's A/B).

`Spinners` (GAME_DESIGN 11; the request of 2026-11-14, "other models should be animated if possible too, such as
windmills being able to spin", and of 2026-11-19, "detail all decor more, some having animations"): every `SCAN_SECS`
1 the islands within `NEAR` 220 studs of the view are looked over. A piece's moving parts are found once (a weak
table by model): the parts its builder marked with `Parts.move` (attributes `Move` "spin" | "swing" | "bob",
`MoveHub` a Vector3 in the piece's frame, `MoveAxis` "X" | "Y" | "Z", `MoveSpeed`, `MoveAmp`, `MovePhase`), or for
an older building its `SPECS` entry by part name (windmill: `SailArm`, `Sail` round (0, 3.4, 0.9) on its Z, 0.9
rad/s; waterwheel: `Rim`, `Spoke`, `Paddle` round (0, 1.2, 0) on its Z, -0.7; grandmill: `Paddle` round (1.6, 1.5,
-0.6) on its X, 0.7). Every piece with moving parts on an island near the view gets a moving copy once: its moving
parts cloned (anchored, no collision or query) into a `Spin_<name>` model in `workspace.PixelDynamic`, registered as
a moving model, the originals hidden (`PixelRenderer.hideStatic`) for good, each part kept as its offset from its hub
(the model's `At` frame times the hub). Of those, the `MAX_MOVING` 40 on the screen (`PixelRenderer.nearScreen`, 24
art px) nearest the view's middle are `active` and move; a copy that stops being active is put back at rest (`hub *
off`, its pose as built), and with reduced motion none move. (A first version dropped the copies past the cap and
showed their parts again: on a full island every pan cast parts in and out of the picture, the renderer baked again
every second and drew nothing new, 2026-11-19.) Every `POSE_SECS` 0.05 (20 times a second, the pixel picture's own
pace: posing all 40 every frame took about 2 ms a frame on a full island) the active copies still near the screen
move: spin `hub *
fromAxisAngle(axis, phase + t * speed) * off`, swing the same by `amp * sin(phase + t * speed)`, bob lifted by `amp *
sin(...)` and rocked 0.06 rad round the axis; the phase is the part's own plus a piece's offset from its name and
place. A piece gone (moved, rebuilt, cleared) drops its copy at the next scan. `start()`, `debugState() -> { count,
moving, parts, ids, kinds, still }`.

`BuildingTags` (GAME_DESIGN 4.6; the requests of 2026-11-14, "show capacities of work buildings when hovered over. if
noone is working on a building, make a alert on top of said work building stating so. do the same for huts and
housing" and "Make it say "Empty""; 2026-11-15, the boost buildings' card and the workplaces' earnings; 2026-11-17, "remove
the empty alert that appears above huts and work places"): the own
island's workplaces (`Island.works`), huts (kind "nest") and boost buildings (kind "gen" with a `boost`), scanned from
its `Decor` folder when it changes (`ChildAdded` / `ChildRemoved`, or another plot; the stress test of 2026-11-17: a
full Everdrift's thousand pieces were looked over whole twice a second), the counts worked out again from the view
every `SCAN_SECS` 0.5 (a `Spot` `{ uid, id, model, top, work, kind, room, n, extra? }`: `top` over
its bounding box, kept while the model stays; `kind` "work", "nest" or "boost"; `room` the building's `jobs` for a
workplace, the hut's `slots`, 0 for a boost building; `n` the view's driftlings whose `work` / `home` it is;
`extra` the card's other lines, worked out for the card shown (`extrasOf`, once a view) from the view as a profile: a workplace's "Earns N shells/min"
(`Island.output` x (1 + `charmBonus`) x `incomeMult` x 60 / `TurnSeconds`), a boost building's "+15% to all from 2
boosts" (`Island.boostInfo`: the total to a tenth of a percent) and "One more adds
+2.5%" or "Max boost 70%"). WorldView drives it: `step(t, plot, hoverPos?, palHovered)` every Heartbeat (the plot
changing clears everything), `tapAt(pos) -> boolean` from `onTap` after the eggs, the driftlings, the tree and the
Hatchery. No alerts over empty spots since 2026-11-17 (a `BuildingAlert` tag, "Empty", bobbed over each spot with `n`
0). The `BuildingCard` (on the Popup root since 2026-11-15, over the HUD's cards, moved there from the World canvas's position by the two roots' origins; glass: `Name` in the
accent, then a line each with its icon: `mini_work` or `mini_nest` and `Line` "Workers n/2" or "Living here n/room" in
`bad` at 0, `good` when full, else `text`, and for a workplace `mini_coin` and `Line2` its earnings; a boost building's
`mini_boost` and `Line` its knack's boost in `good`, `mini_star` and `Line2` what one more adds in `text_dim`; 16 + 10
px a line high; 2 px over `top`, kept on the screen and `CARD_TOP` 22 below the top of the HUD's canvas, under the top bar's chips): a tap's for `CARD_SECS` 3 (while no panel is open), else the pointer's,
looked for every `HOVER_SECS` 0.1 with a mouse, no panel, not Build mode (`CameraController.isFree`) and no driftling's
name showing. The pick ray (`PixelRenderer.screenRay`, `PixelRays`) includes only the spots' models and the tree's
(`pickList`), so decor in front never hides a building and the tree does. `debugState() -> { spots, alerts, words,
card, card2, cardUid, hit }` (`alerts` and `words`: any `BuildingAlert` left on the World canvas, none now) (`card` the name and the first line, `card2` the second; `hit`: what the last pick met), `debugSpots() -> { { uid, id, work, kind, n, room, tap? } }` (`tap`:
an InputObject point on its middle, nil off the screen).

The Hatcheries' tags (the request of 2026-11-20: "the hatchery should have the timer above its building, and show
ready! once the egg is ready. clicking it while ready shows the hatching screen just like hatching an egg normally,
but with the resultant creature"): the scan keeps the own island's Hatcheries too (`hatches`: uid -> `{ uid, model, top
}`), and every step a `HatchTag_<uid>` (glass on the World root, 15 px high: `mini_egg_<rarity>` and `Words`, the
time left as `Numbers.clock(StateClient.eggLeft(egg))` in `text` or "Ready!" in `good`, bobbing a pixel every half
second; attributes `Uid`, `Ready`, `Key`; a ghost `HatchTap_<uid>` over it: `EggView.tapHatchery(uid)`) stands 2 px over
`top` of each with an egg in the view; none while the camera has a stage or `HatchScene.isOpen()`. Built again only when
the rarity, the ready state or the words' width change. `debugHatch() -> { { uid, words, ready, shown } }`.

### 10.3 `Hud`
The look since 2026-11-14 (GAME_DESIGN 2, Random Bakery's HUD): every block is `UIKit.glass`, `EDGE` 5 UI px from the
screen's edges, `GAP` 3 between blocks stacked in a column. The `TopBar` (`CHIP_Y` 4, `TOP_H` 14 tall) holds the chips
side by side, `CHIP_GAP` 7 apart, each as wide as its words need (`CHIP_MIN`: 40, 40, 46; `layoutTop` when a value's
text changes); the cards start at `CARD_Y` = `CHIP_Y` + `TOP_H` + 4; the right column `CARD_W` 116 wide (104 on a
phone); the menu bar on one glass `Dock` (`DOCK` 3 round its ghost buttons); the camera's strips are kept clear of all
of it. Chips on one line (`Chip_shells`, `Chip_season`, `Chip_weather`; frames in the `TopBar`, each an 11 px icon and its
`Value`; the shells easing to the store, the number flashing gold when it changes; `Hud.topChip(name, icon?, text?,
color?)` sets the season's and the weather's icon, words and colour, nil words hiding it; no `Chip_wood` since
2026-11-14, no `Chip_day` or `DayBar` since the same day: "also, this can be compressed into one line. remove the "day
1" as well"; no food chip since 2026-11-13); then `Home`, a button shown while the founder is off their own island, sending `char.home`, and in its place
while they are home `Visit` (since 2026-11-20, when the islands took to the sky: shown when Build mode is shut and
`VisitUI.islands()` lists someone, looked at every 0.5 s; it opens the "visit" panel) (no `MusicToggle` since 2026-11-14: the music, the sounds and the pixel art are the
Settings panel's, `UI/SettingsUI`; the right-hand column's top is `rightTop()`: `CHIP_Y`, level with the top bar, when
the top bar and Home (or Visit) leave the column room, else `CARD_Y`; the top bar and Home call `restackSoon` when that may change),
the `Status` panel under the top bar on the left (`Hud.statusLine(name, icon?, text?, color?, onTap?)`: adds, changes
or, with a nil `text`, removes a line `Status_<name>` (an 11 px `mini_<icon>` and its `Text`; given `onTap`, a ghost
button `StatusTap_<name>` under them that calls it: the gift's line, `RewardsUI.openWaiting`); hidden while it has no lines and
for a panel or Build mode; the `Quest` card sits under it; a module mounted from Hud can be handed `Hud.statusLine`),
the menu bar
(`Menu_build`, `Menu_pals`, `Menu_hatch` (the Hatchery, `mini_egg`, after Driftlings once the view's tier reaches
the Hatchery's: `buildBar` again when that changes; 2026-11-14), `Menu_index`, `Menu_looks`, `Menu_store` (the Store,
`mini_store`; GAME_DESIGN 14.2), ghost buttons, each with
its icon, Build's words in the accent; while Build mode is open the bar and the
cards step aside and the tips banner sits on the tray (`BuildUI.trayHeight()`: lower while a piece is picked) with a
Build mode wording (`TIPS_BUILD`)), the `IslandCard`
on the right (the island's name for its tier, driftlings in huts / the huts' room (`Pals`), driftlings at work / the places at
work (`Working`, `mini_work`: one with a job, `Pal.work` not 0, out of `Island.jobPlaces(v.pieces)`; the requests of
2026-11-16, "can you make another detail to show creatures working, with x/y", and 2026-11-17, "for working, make it
x/y, where x is amount of creatures working and y being the amount of work spaces available"), charm
(`Charm`), the charm bonus (`CharmBonus`, "+43%"; the visitors' line went on 2026-11-14), and what a turn makes of shells a minute, `Rate_shell`: `Numbers.perMin`), the `TreeCard` under it
(GAME_DESIGN 6: the `mini_tree`, "Tree of Life" ("Eggs" on a phone) and `TreeOpen` opening the "tree" panel,
`TreeNext` ("New eggs in 2:41") over `TreeBar` (an ink bar whose fill Heartbeat runs down from
`StateClient.clutchLeft`), then a row each of `EggView.best(v, 3)` (on a phone `best(v, 1)`): `EggIcon_<id>` (the
small `mini_egg_<rarity>` sprite, 9x11, in line with the name: a row is 15 px), `EggName_<id>` (the rarity's name in its colour) and `CardPrice_<id>` (its cost, a label with
`PriceIcon`, `good` when the shells are there, else `text_dim`), or "No eggs right now", and over the rows the
see-through `TreeCardTap` opening the "tree" panel (the card buys nothing itself); built again from each
view only when the rows' ids, costs, whether the shells cover them or the number of eggs change (its `Key`
attribute); on a phone the card at the top left; the island card and it hidden in Build mode and while any panel is
open, since 2026-11-14, so nothing shows through a panel's glass), the questline's card `Quest` (GAME_DESIGN 9: down the left under the `Status` panel, `QUEST_W`
150, under the `TreeCard` on a phone; hidden while the tips are on and for a panel; `updateQuest(v)` from the view
through `Quest.current` / `Quest.progress`, laid out again when the quest or its count changes, sliding in: the
quest's `mini_` icon, `Title` (wrapping onto a second line when it is wider than its 106 px, the card growing by one
line: "Discover 12 unique creatures" did till its title became "Find 12 kinds" on 2026-11-19; none wraps now), `Which` ("3/20"), `Words` (up to four lines), then the `Bar` and `Progress` with `QuestGo` (`goTo(go)`: a
panel, "tree" included, or `BuildUI.open(tab)`), or once done the reward (`Reward_shells`) and
`QuestClaim` (shining; `quest.claim`, then a notice of what it paid)), the tips banner (`Tips`, kept on the menu bar or the build tray every Heartbeat once its 0.2 s bounce is done, since the tray changes height with no word to the HUD and a correction during the bounce was overwritten by it: the user's report of 2026-11-14, "the tutorial tooltip sometimes gets hidden by the build menu after something is built"; the steps of
GAME_DESIGN 9 (`tut` 1 .. 4: a hut, an egg hatched, a workplace, the last, in the user's words of 2026-11-21;
`TIPS_BUILD` empty, the same words in Build mode); tip 4 (`Plot.TIP_LAST`) has `TipsOk`, sending `tut.next`; while
tip 1 or 3 is up and Build mode and every panel are shut, the menu bar's `Menu_build` pulses: its plate the accent
toward white, its words white, `UIKit.shine` every 1.2 s, attribute `TipPulse` (restored when it stops); glass with white words; on a
phone held sideways it keeps to the room left of the island card, on one held upright to the width up to the jump
button (2026-11-18: it had 59 px there and cut its words off), as many lines as its words need; in Build mode it sits
over the tray and over the Free Decor tab on its corner while that shows, `tipsLift`), and the `DayBanner` (Fx "day" and "turn":
the day, what hatched; at least 140 wide, and as wide as its big-font title after the icon (`textWidth(title, "big")`
+ 28: "An egg hatched!" is 142) and each line; over a panel or in Build mode a notice instead; while it shows the
notices stack below it, `UIKit.setNoticeTop`); the status lines hide under a panel and in Build mode, a line's icon
is made again only when it changes, and the top chips' words (`topChip`) are put back after the HUD rebuilds; Fx "eggs" (`onEggs`): "There are new eggs under the tree!" (a fresh lot or an expansion's extra eggs alike) and the `rare`
sound, or, with an epic or legendary egg among them (or `turned`, the quest's egg, of any rarity: "A rare egg
waits at the tree."), "An epic egg waits at the tree." in its rarity's colour, the `grow` sound and a
burst over the `TreeCard`. Shells coming in rise from their chip
("+12", at most every 2 s, from `StateClient.Tick`). Every frame it holds the founder's `JumpHeight` at 0 while Build
mode or a panel is up, else `Tuning.JumpHeight` (the phone's jump button hides with it), and sets the music's mood
(`Audio.music`). It reports its blocks to the camera (on PC the top strip, the menu bar and the card's place; on a
phone Roblox's top bar and the menu bar). The store's `Offers` column (`StoreUI.offers(canvas, v, CARD_W)`, built
again when `StoreUI.offerKey(v)` changes) sits under the right-hand column (the island card, and the tree's card on a
desktop) and hides with the cards: `Offer_StarterPack` (until `gifts.starter`; its `Offer_StarterPack_Go` opens "store"
on "eggs"), `Offer_VipGift` (VIP owned and `vipDay` not today; `Offer_VipGift_Go` sends `vip.daily`), `Offer_Offline`
first while `offline` waits ("Away earnings", "+N": opens "welcome") and `Offer_Group` right after the Starter Pack
while `groupOn`: "Join the group" / "Free gift" while `group.member` is false, "Group gift" / "Ready" while it is and
`group.gift` isn't (both open "store" on "passes"), each a glass
chip with its `mini_` icon, `Text` and, when both fit, `Sub` (its price or "Ready"). `Hud.start` runs `StoreUI.init()`
after `Menus.init()`, then `FounderUI.init()` (10.18).

### 10.4 Menus
`UI/PalTip` (GAME_DESIGN 6, the request of 2026-11-15): `attach(target, pal)` on a row or button that shows one
driftling (Menus' `Pal_<id>`, `SwapOut_<id>`, `Parent_<id>`, `Swap_<id>` rows and the Hatchery's `Slot_a/b_<uid>`):
`MouseEnter` (not on a touch-only device) shows the tip at the pointer (`GetMouseLocation` less the Popup canvas's
origin, in UI px), `InputChanged` mouse movement follows it, `MouseLeave` hides it; a touch held `HOLD_SECS` 0.35
shows it above the finger (`InputObject.Position` plus the inset), `InputEnded` hides it; the target's `Destroying`
(a panel built again) hides it. `show(pal, at, touch?)`, `hide()`, `lines(pal) -> { { text, color, tier?, title? } }`
(the name with its rarity; "Works farms x.., wood x.., shops x.." from `RarityWork` x (1 + `Traits.workAt`) at each
knack, or "Works x.. anywhere" when they agree within 0.05; the rarity's base; the passive; each mutation (its
name and stars by `TierStars`, then `Traits.describe(fx)`, on the next line when it doesn't fit); "Its <egg luck / egg
price / charm> count(s) while in a hut" for the keys it has; "Sells for N shells"), `debugState() -> { shown,
texts }`. The card: glass made solid (`UIKit.setPlate` 0), `PalTip`, at most `TIP_W` 190 wide plus padding, a long
line wrapped up to three, on the Popup root kept on the screen.
`Menus` registers the panels (the villagers' "folk" went with them; each is built again with every view): "pal"
(GAME_DESIGN 6, "One driftling's card"; title "Driftling", 320 x 182: `WorldView`'s pick opens it; `{ id }` the own
island's from the view, `{ id, plot, sp, muts, work, home, isle }` a neighbour's; "That driftling is
gone." with `AllPals` when the own one is gone): `Portrait` (`icon_<species>` on a veil), `Name` (big, its rarity's
colour), `Rarity` ("Rare ***"), `Kind` (`Islets` name and "kind", the knack's words from `Data/Creatures`' `knack`),
`Blurb` (its description, only when the body is 150 px tall or more: not on a phone); on the left `PassiveRow`
(`Passive`, `PassiveFx` over two lines), then a line a mutation: `Mut_<id>` (its name in its tier's colour, the stars after it: `TierStars.label`),
`MutFx_<id>` (its blurb), `MutIcon_<id>` (a weather family's `mini_` icon, from `Data/Weather.KINDS`), or `MutsTitle`
"No mutations"; on the right three rows (`Top`, `Sub` each): `Where` ("Works at the Veggie Patch", "x1.4 here, x2.2 at
its best": `Tree.worthAt` there, and the most over every knack in `Data/Buildings`; or "Resting"), `Hut` ("Lives in
the Driftling Hut"), `Price` ("Sells for n shells", a neighbour's "Worth n shells"); the foot: the own one's `PalAll`,
`PalWork` (the work picker `{ pal = id, back = "pal" }`), `PalMove` (the hut picker `{ move = id, back = "pal" }`: with
`back = "pal"` both pickers' Back and a choice return to the card), `PalSell` (two taps; then the "pals" list); a
neighbour's `ReadOnly` ("Lives on Bo's Isle."). "pals"
(`OpenTree` ("Eggs") and, when a Hatchery stands, `OpenHatch` at the top, the hint beside them in up to three lines
(`UIKit.lines`: "6 in huts, room for 8. Hatch more at the tree."); a row a driftling, every one,
the hardest workers first (`Tree.better`) and those with no hut last, `Pal_<id>`: portrait, name in its rarity's
colour, its rarity, passive and its effects, mutations (`Mut_<id>` each), where it lives and helps (`Where`; "No hut.
Waiting for room." in orange); `Move_<id>` opens the hut picker (the same panel with `{ move = id }`: a
row a hut with its room, `Move_<uid>`; a full hut lists its driftlings with `SwapWith_<id>`, sending `pal.house { id,
uid, swap }`), `Help_<id>` the work picker (a driftling in a hut only): every workplace on the island whatever its knack, the fastest for this driftling first (`Tree.worthAt`), each `Spot_<uid>` with its name, who works there, its speed `Speed` ("x1.1", the fastest in the accent colour) and `Go_<uid>` ("Here", "Swap" when full, else "Go"), then `Rest` (`Go_0`), `Sell_<id>` (two
taps, `Tree.price`); with no driftling, "No driftlings yet. Tap an egg under the Tree of Life to hatch it." (or "Build
a hut, then hatch an egg under the Tree of Life." with no hut)), "tree" (GAME_DESIGN 6, title "Tree of Life", 380 x
196: on the left `Pace` ("New eggs every 6:00", from `clutchSecs`: 3:00 with Quick Tree), `Next` ("Next in 2:41") over `TreeBar` (its fill
run down every Heartbeat from `StateClient.clutchLeft`), `Room` ("7 eggs a lot. In huts 6/8", orange when full),
"Odds now" and the odds of each rarity (`Odds_<r>`, `Tree.odds`; "<0.1%" under a tenth of a percent, "not
yet" at 0) and, short of the last tier, `Grow` "Grow your island for rarer eggs and bigger lots."; on the right `Eggs` ("Under the
tree") with `EggCount` ("6 eggs"), the `List`: first the bag's eggs (GAME_DESIGN 14.2) when it holds any, `BagHead`
("Your eggs: 2") and a row each, the rarest first, `BagEgg_<id>` (its `egg_<rarity>`, `Name`, "Free to hatch",
`BagHatch_<id>` sending `EggView.hatchBag`), then a row each of `EggView.best(v, #v.clutch)` (every egg, the rarest first), `Egg_<id>`: the `egg_<rarity>`
sprite, "Rare egg" in its colour, "Hatches a rare creature" (`Hatches`; "an" before uncommon and epic) and `PanelHatch_<id>` (its cost
and `PriceIcon`, sending `EggView.hatch`, or with fewer shells than its cost `StoreUI.eggInstead(r)`), or "No eggs
left. More soon."; under them `StoreUI.eggRows`:
`BuyHead` ("Buy an egg") and a row an egg product from Uncommon up, `BuyEgg_<key>` (its `egg_<r>`, "Rare Egg" in its
colour, "Free to hatch" and `Buy_<key>`, its Robux, `StoreUI.buy`); with `{ hatch = id }`, every
hut full, the swap picker: a hint naming the egg's rarity and cost ("Huts full. Pick one to sell for the rare egg
(1,200 shells)."), `Back`, and a row a hut driftling, the weakest first, `SwapOut_<id>`:
portrait, name, rarity, how fast it works, mutations, "Sells for n" and `SwapTake_<id>`, sending `egg.hatch { id,
swap }`; with `{ hatch = id, bag = true }` the same for a bag egg ("... for the epic egg from your bag ...",
`SwapTake_<id>` sending `EggView.hatchBag(id, swap)`); once a new lot has replaced the egg, "That egg is gone." and back to the tree
panel), "hatch" (the `Hint`: "Breed two driftlings for an egg. Rarer parents tend to make rarer eggs. Legendary and up need both parents that rare.", the panel's whole width; a row a Hatchery `Hatch_<uid>`: its egg (`egg_<rarity>`,
`EggName`, `EggLeft` ("Hatches in 3 min" from `StateClient.eggLeft`, or "Ready to hatch."), `EggBar`, its parents, a ready egg's `HatchNow_<uid>` (`EggView.hatchery(uid)`), `FinishNow` in the first warming egg's row: `StoreUI.buy("HatcheryNow")`) or the slots `Slot_a_<uid>` / `Slot_b_<uid>` (the
picker: the same panel with `{ hatch = uid, slot }`, a row `Parent_<id>`, `PickParent_<id>`; over the list the search box
`PalSearch` (`UIKit.searchBox`) and "Sort by" `Sort_rarity` / `Sort_muts`, the picked one teal (2026-11-19: "for
hatchery, make a search function, and a sort by mutation rarity or creature rarity"): `parentList(v, other, q, sort)`
keeps the driftlings whose kind, rarity, passive or mutation names hold the words and orders them, `rarity` by the
kind's rarity then the mutations, `muts` by the mutations (their tiers highest first, compared in turn, then the
count; a flaw is 0) then the rarity, then the name and the id; typing or a new order fills the "List" again without
building the panel, so the box keeps the keyboard; the words and the order stay in the module (`pickQuery`,
`pickSort`) while the game runs; `NoParent` when nothing matches; `Menus.debugParents(other, q, sort) -> { id }` for
the sims), the likely child
(`Child`: its portrait if seen, else its shape and ???, its rarity), `Cost` ("300 shells, hatches in 12 min. Mutations both carry pass on, maybe a tier up. The rest pass on half the time.", up to three lines, the row 76 px for a third),
`Breed_<uid>`, on while the shells are there), "index" (`Entry_<species>`, 90 tall in three columns: portrait or silhouette, name or "???" (65 px beside the
portrait: Glimmerfleece's), the kind of island it comes from, its passive once seen with its effects in up to four
lines from the top (`PassiveFx` 40 tall; it was 20 in a 70 card, and 37 kinds' effects ended in "..."); "Seen n of 55 kinds"; a kind not open yet says the island tier
it hatches from: "From island Lv 4."). "looks" is `UI/FounderUI`'s since 2026-11-20 (10.18; `UI/StoreUI`'s from 2026-11-14). `Words.errText(err)` words every ErrCode (`no_hut`: "Build a hut
first."; `full`: "Huts full. Swap one out or build a hut."; `not_found`: "That egg is
gone."; `fixed`: "The tree stays. You can move it."; `huts`: "No more hut
room. Grow the island."; `work`: "No more work spots.
Grow the island."; no `food`). In Build mode `BuildUI`
words a refusal itself first (`buildErr`): `blocked` "Doesn't fit there.", and `full` by the count that ran out
(`Plot.group` of the piece: the paths and water, the fencing, or the island's pieces, each with "Grow the island");
the rest go to `Words.errText`.

### 10.6 `AvatarView`
A founder per player (`CharacterModels.buildStanding`, look from the player's `Founder` attribute, else one from the
UserId; drawn at `Tuning.FounderScale` 0.75 by `CharacterModels.setScale(rig, k)`: the parts' sizes once, and every
pose shrunk about its base, the feet, in `posePose`; the name's height follows it), registered with the renderer and posed every frame at their character: feet on the ground under the
HumanoidRootPart (a raycast down past characters and rigs, `RespectCanCollide`: only what the founder stands on, never
a building, tree or piece of decor it walks through; a second ray without it finds a river or pond's water no more
than a stud over that ground, for the wading) while the Humanoid stands (its `FloorMaterial`), in the air
(`FloorMaterial` Air) at the root's height less its rest offset (learnt while it stands), posed "jump"
(`CharacterModels.poseAction`), with a puff of dust on landing; facing the root's look direction, walking at the speed
the root moves. The own founder's feet are heard (Roblox's own character sounds are off: `RbxCharacterSounds`): a
step every `5.4 / speed` seconds (0.24 .. 0.5) while it moves faster than 4 studs a second, `step_wood` on a plank,
beam or edge part, `step_water` on a part with `PixelWater` no lower than 0.3 under the lawn (a river or pond drawn on
the island, GAME_DESIGN 4.3; walking there kicks up `Puffs` "drop" splashes in place of dust, every 0.24 s, 0.14 s
running; nobody swims since the sea went on 2026-11-20); `step_sand` on ground under the lawn's height,
else `step_grass`; `jump` as it leaves the ground, `land` (on the boards a firmer `step_wood`) as it comes down. The Roblox avatar is hidden on every client (`LocalTransparencyModifier` 1 on its parts and decals).
The look (GAME_DESIGN 14.1): `Data/Looks.decode` of the `Founder` attribute, the indices clamped to the lists and a
worn piece kept only when it is a known `Data/Cosmetics` id of that slot; the attribute string is the rig's key (a new
one rebuilds it). Every founder is registered with the renderer's rim (`registerDynamic(model, "self")` for the own,
`"player"` for the rest) and, in the classic style (`tier() == "off"`), carries a white outline `Highlight` (the own
`AlwaysOnTop`, the rest `Occluded`), made and dropped as the tier changes. Every founder, the own too, has a name tag
(`Controllers/NameTags`: `make(player)`, `refresh(tag, player)` (the name and the "Title" attribute's title, its words
and colour from `Data/Titles`; laid out again only when they change), `place(tag, worldTop)` (whole UI px over the
point, hidden off the view), `drop`, `texts(tag) -> (name, title?, shown)`), on the World root (hidden with it in the
hatch scene; hidden too while a cutscene poses the own rig), placed over `CharacterModels.topOf(rig)` (the head and a
hat, worked out once a rig) every frame. `founderPos()`, `count()`, `lookOf(player)`, `debugTag(player) -> (name?,
title?, shown)`, `debugRig(player) -> (rig?, outlined)` (CLI checks), `setOverride(fn?)` (a cutscene poses the own rig
instead: `fn(rig, t, dt)` every frame; nil gives it back).
Standing about (GAME_DESIGN 9, the request of 2026-11-15): each record counts `idle` (seconds on the ground slower than
1.5 studs a second; 0 walking, jumping or in a cutscene) and poses the rig with
`CharacterModels.poseFounder(rig, base, t, speed, idle, dozing, quiet, squash)`: `dozing` once `idle` passes
`Tuning.DozeSecs` (40) and, for the own founder, nothing touched for as long (`UserInputService` InputBegan or
InputChanged moves the clock); `quiet` is `GuiService.ReducedMotionEnabled` (no fidgets); `squash` 1 .. 0 over 0.2 s
after a landing. A dozing founder puffs a Z every half `NOD_SEC` (the small `zz_s` and the big `zz_b` by turns,
`PixelSprites` on the World canvas, named "Zed", z 6): each starts just right of its name tag at the head's height,
rises 16 UI px and drifts 8 right over 1.8 s, swaying, popping in 2 then 1 px low, blinking out over its last 0.3 s
(still with reduced motion), whole UI px. `cheer()` (Hud's quest claim, BuildUI's island grown) poses the own founder
`poseAction` "cheer" for 1.6 s and wakes it. `debugIdle(player) -> { idle, dozing, fidget?, zeds, cheering }` and
`debugAway(secs)` (the input clock moved back, `idle` at least that) for sims and previews.

### 10.7 `BuildUI` (Build mode), `BuildFx` and `Puffs`
Prices are `Plot.price(view, id)` everywhere in Build mode (the cards, the tip, the info plate, a stroke's cost, the
afford key, the inventory's Sell at `Refund` of it) and replacements `Plot.replaceCost(q, id, view)`: with the Free
Decor pass decor, paths, water and fences cost 0 and read "Free", and so does the tips' workplace while the tips ask
for one (`Plot.tipWork(tier)` on step `Plot.TIP_WORK` 3; the request of 2026-11-14, "make the first snack stall in the
tutorial free", the best workplace since 2026-11-21) (`price` writes "Free" in the accent for 0; a card's
`Shells` label says "Free"; GAME_DESIGN 14.2).
`open(tab?)` (the HUD's Build button; `tab`: the tray opens on that tab, the quests' Go; an old tab's name, `farm`
`wood` `shop` or `gen`, opens Work on that row; a tip's tab still wins): closes any panel,
`CameraController.setFree(true, TRAY_H + 8)` and lays out the tray `BuildTray` along the bottom (black glass at
`UIKit.PANEL_ALPHA` since 2026-11-14, its tabs dark glass buttons, the chosen one the accent, the cards faint veils, a
picked one an accent veil; `TRAY_H` (82) tall, shorter while a piece is picked, below). With nothing
picked it holds: the tabs `Tab_work Tab_nest Tab_path Tab_fence Tab_water Tab_nature Tab_decor Tab_fun Tab_inv` (Work,
Huts, Paths, Fences, Water, Nature, Decor, Fun, Inventory, each with its `mini_` icon `work nest path fence water nature
decor fun inv`; the icons alone when the names and the 180 px right of them don't fit; it opens on Work's Wood row);
`QuickRemove` (16 wide, orange, the `mini_takeup` sprite; `quickRemove(true)`, below) at 162 px from the right; the count (`Count`: the tab's group against its
limit, `Plot.group` and `groupLimit`: the pieces on Work, Nature, Decor and Fun, the tiles on Paths and Water, the
fence lengths on Fences, the huts' room (`housing`) against `housingLimit` on Huts, the places at work (`work`) against `workLimit` on Work; a hut card whose slots won't fit, a workplace card whose `jobs` won't (2026-11-18) and the Hatchery's at `hatcheryLimit` greyed, "Full" / "Max" (it was "No room" until 2026-11-19: too wide for the card's 34 px line), a tap saying why (`roomErr`: `huts`, `work` or `hatcheries`); orange when full); `Expand` ("Island max", greyed, at the
top tier; `expandIsland(tier)`: since 2026-11-20 behind the loading card, `LoadingCard.cover` with the next island's
name and "Growing your island"; once it covers the screen `island.expand` is asked, the bar goes to 0.35, then to 0.6
when the island's `Static` folder's `Built` attribute reaches the answer's `tier` (8 s at most), the words to "Drawing
your island", and `finish()` once `PixelRenderer.busy()` is false (8 s at most; `PixelRenderer.setHidden(true)` from
the moment it covers the screen until then); without the card it asks at once.
Its price under it in `ExpandCost`; the fanfare and "Your island grew into Moonlit Bay. There's more to build now." (or
how many buildings had to move), named from the answer's `tier`, come once the card has gone, or a refusal's notice) and `BuildDone`; the search box `BuildSearch` (a TextBox `Box` under a
pixel-font copy of its words, `Query`, "Search" while empty, and `ClearSearch`), with the search button `SearchButton`
just before it (16 wide, the 11 x 11 `mini_search` magnifier; it calls `focusSearch()`, the cursor into `Box`; the
accent colour while a search is on): both on the tabs' plank right of the tabs when there are 80 px free there (the box
62 to 110 wide), so Decor's fourteen chips fit one line on a computer, else at the end of the chips' row, the box 96
wide or 70 on a screen under 500; the box kept across rebuilds so typing keeps the keyboard, cleared when Build mode
closes; under the tabs the tab's rows (`Chips`, scrolling sideways: `Chip_all` and a `Chip_<sub>` a row,
`CHIPS`: Work's `farm wood shop gen`, Water's `tiles bridge float` ("Water", "Bridges", "On the water"), Nature's
`trees plants rocks`, Decor's 13 themes, Fun's `seats lights play treats fountains`; a tab with one row shows a
`TabHint` instead), or, while the search box has words, "Everything called "lantern":" and every piece whose name, row
or tab holds them; then the cards (`Cards`, scrolling sideways, the scroll kept while the tab, row and words stay):
`Card_<id>` (38 x 46, a carved board; `TutGoal` on the tip's) holding `Buy_<id>`: the piece's picture (`thumb_<id>`,
24 x 24; its tab's `mini_` icon when there is none) over its price in shells (`Shells`, red when short), or `Lock` ("Lv7"
on a locked card, "Full" on a hut at the huts' limit), or, for one waiting in the inventory, `Held` ("Free") and
`Count` ("x3", low in the picture's right corner); the list from `Data/Buildings` (never the tree) by tab and row, the
open ones first by price, then the locked ones by tier. The Inventory tab (2026-11-14) has no count; its row `InvRow`
(scrolling sideways) holds `InvSell` ("Sell", or "Selling: tap a card" while on: orange) and `Clear_pieces`,
`Clear_tiles`, `Clear_fences` ("Clear buildings", "Clear paths and water", "Clear fences"; greyed when the
group has none; the first tap turns one to "Tap again to put away 18" in `button_close` red for `CLEAR_WAIT` (4) s,
the second sends `plot.clear` and says "Moved 18 to the Inventory."); its cards `InvCard_<id>` with
`Inv_<id>` (by the tabs' order, then price; `Held` "Free" and `Count`; with Sell on, orange, the share it sells for in
`Shells` and a tap sends `inv.sell` `{ id, n = 1 }`: "Sold a Lumber Camp for 55 shells."; else a tap picks it with
`inv`, so only the ones waiting go down) or `InvEmpty` ("Nothing put away yet. ..."). A mouse over a card shows `BuildTip` (172 wide, over
the tray: `TipName`, its size ("3 x 3", "2 x 2 tiles", "2-stud lengths"), `TipAbout` (its blurb, what it makes a
minute for each common driftling, a workplace's places ("Up to 6 workers."), a hut's room and comfort, its charm, "Goes over water." or "Goes on water."),
`TipLocked` ("Opens at island level 7.") and its price, or `TipHeld` ("3 in your inventory. Free to put down.")). A tap on a card: a locked one says "Needs island
level 7.", a hut at the limit `Words.errText("huts")`, a workplace at the cap `Words.errText("work")`; any other is picked, with a word on what to do
("Tap the grass to place it.", "Tap the water to place it.", "Drag along the grid
lines."...).

With a piece picked (`pick(id, rot?)`), a ghost model (`Ghost` in `Workspace.PixelDynamic`: the piece and its
`Footprint`, a raised neon frame of four edges just above the grass (for a fence length, a bar along its line), cyan
(`screen_on`) where `Plot.fits` says it fits, red (`berry_red`) where not) stands on the cell under the pointer
(mouse) or the last tap (a tile snaps to the even studs, a fence length to the nearest grid corner); the bar shows
`Rotate`, `Place` / `Move here` (on while it fits) and, for a piece picked up off the island, `Copy` (not for the
tree), `Replace` (when `Plot.replacements` has any) and `Store` ("Put away", greyed for the tree, `Plot.isFixed`),
then `Cancel`; under them the `Info` plate (its picture, `What` ("Placing: Oak Tree", "Moving: Lumber Camp Lv2"),
`Blurb` (what it is), the price of a new piece (`Held`, "3 in the inventory", for one waiting there: right of the
name, or on a line of its own under it on a narrow plate, a phone held upright, where it ran over the name, 2026-11-18)
and, with a
keyboard, `Keys`: "R rotate. E place. Esc cancel.", "R rotate. C copy. X put away. Esc
cancel." or "Esc stops drawing."), as tall as its
words, and the tray shrinks to the plate's height so more of the island shows (`trayHeight()`: the tray's height now,
`TRAY_H` with nothing picked; Hud's tips banner sits on it). `Replace` turns the bar to `ReplaceBack`, `ReplaceWhat`
and a card a replacement (`Swap_<id>`: its picture, its name, its room or charm, and `SwapTo_<id>` with
`Plot.replaceCost`; the tray keeps its full height for them); a tap sends `plot.replace` (the `level_up` sound, "The
Driftling Hut is a Cozy Burrow now.", `BuildFx.drop`). A tap on a placed piece of the own island (a ray into its
`Static.Decor`) picks it up. A press dragged more than 8 px pans the view (`CameraController.panBy`); the view follows
the founder, and when it moves a picked piece's ghost goes again to the cell under the mouse's last place (`hover`). The keys (input
not already taken, so never while typing in the search box): R (`rotatePicked`: a quarter turn, a fence length between
0 and 90), E or Return (`confirm`), C (`copyPicked`: a new pick of the same piece, turned the same way), X or Delete
(`storePicked` through `storeAt(i)`: `plot.store`, then `BuildFx.cleared` and "Snack Stall put away."),
Esc (drops the pick, ends Quick remove, or with neither closes Build mode). `confirm()` calls `BuildFx.expect`, then
sends `plot.place` (the piece stays picked for another copy, its ghost off the cell just filled until the mouse moves to
another or a tap: `Pick.filled`, `moveGhostTo(pos, tapped?)`; unless it was the tip's or the last one picked from the
Inventory tab; a pick from the
Inventory tab with none left there is dropped, never bought: "None left.") or `plot.move`, then
`BuildFx.drop`; `close()`; `isOpen()`; `Changed: Signal<boolean>`. The tray is laid out again on each view, on
`UIKit.Resized` and when what can be afforded changes (`StateClient.Tick`). The tips (`tutOf(step, tier)`: tip 1
(`Plot.TIP_HUT`) Huts and the hut, 3 (`Plot.TIP_WORK`) Work's Workplaces row and `Plot.tipWork(tier)`; tip 2, an egg
hatched, has no building; the hut placed with Build mode open on tip 1, it closes 0.8 s after the tips reach tip 2): opening, and each new tip while open (`followTut`, from the rebuild; it waits while a piece is picked),
turns the tray to the tip's tab and row; the tip's card (`TutGoal`; never one too full or locked) has its whole `Buy_<id>`
button in the accent yellow (not `button_ok` green), pulsing toward white by `TIP_PALE` (0.35) and shining every
`TIP_SHINE` (1.2) seconds (`UIKit.setButtonColor`, `UIKit.shine`; 2026-11-20, "make the highlight during tutorial
make the whole green button yellow instead and shine"), and its tab, while another is shown, pulses to the accent; placing the tip's building drops the pick so the tray goes on to the next tab. `TRAY_H` (82),
`debugState() -> { tab, chip, goal?, quick, selling }`, `debugTip(id) -> boolean` (a card's tooltip, as a mouse over it),
`debugSearch(text)` (typed into the box), `focusSearch()` (the search button's work), `tapScreen(pos, mouse?)` (the sims'
and previews' tap; with Quick remove on, its tap).

**Quick remove** (2026-11-14): `quickRemove(on)` swaps the tabs for its bar (`QuickTiles` "Paths and water",
`QuickFences` "Fences", `QuickBox` "Box", `QuickLook` "Look around", `QuickStop` "Stop", `BuildDone`, and the `Info`
plate: `mini_takeup`, "Quick remove", what a tap and a drag do, the `Stroke` label), nothing picked and no cards. A tap
(`quickTap`) on a piece puts it away (`storeAt`; the tree refused with `Words.errText("fixed")`); on bare ground the
tile (or the fence) under it comes up. A press dragged past 8 px starts an Erase stroke from the press (Line or Box,
not in Look around, which pans): `strokePlan` with no pick marks "lift" where a path or water tile (`plot.unpaint`
kind "all"), or with Fences a length (`plot.unfence`), lies; the release sends it like Erase, then "9 in the inventory
now.".

**Drawing paths, water and fences** (GAME_DESIGN 4): picking a drawn piece (`Plot.isDrawn`) opens the draw bar
(`DrawLine`, `DrawBox`, `DrawErase`, `DrawLook`, `Cancel`, `BuildDone`, and the `Info` plate with the `Stroke` label:
"12 tiles, 540 shells", "5 lengths, 120 shells", "5 to take up") instead of the ghost. A press starts a stroke (not in
`DrawLook`, which pans), a drag adds to it (`strokeTo`; a tile's cell is its north-west corner on the even studs, a
fence's edge `{ x, z, rot }` a length from a grid corner: Line fills the gaps between the cells it passes, or runs
along x then z from the last corner; Box every cell of the rectangle from the press, or the edges all the way round
it; `DRAW_MOST` 240 a stroke), the mouse alone previews one cell (or the first length east), and the release sends it
(`finishStroke`: the cells the plan can change, in batches of `PAINT_MAX`, through `plot.paint`, `plot.unpaint` with
the picked piece's kind, `plot.fence` or `plot.unfence`; the refusals in words; then `BuildFx.stroke`).
`strokePlan(cells) -> ({ "lay" | "swap" | "lift" | "no" }, n, cost)` (cell by cell, by the server's rules: one of
another look swapped, `Plot.fits` for a new one, the group's limit, the inventory's first for nothing (a pick from the
Inventory tab: only those), then the shells; "12 tiles, free" when none are paid); `showDrawGhost` lays a flat neon
plate a cell, or a bar an edge (`DrawGhost` in `Workspace.PixelDynamic`, parts `Cell`): cyan to lay, yellow to swap,
orange to lift, red where it can't. `debugDraw(cells, mode, keep?) -> plan` (the sims' and previews' stroke through
tiles' cells or fences' corners, mode "line", "box" or "erase", with Quick remove on its Erase stroke; `keep` leaves
the markers up without sending).

(`Controllers/GrowFx`, the growth's spray and sounds, went with the growth on 2026-11-19.)
`Controllers/BuildFx` (GAME_DESIGN 4.5): `expect(plot, id, x, z, rot) -> key` (BuildUI calls it before it asks
`plot.place`, `plot.move` or `plot.replace`: a watch on the plot's `Decor` holds the server's model of that spot, matched
by the `:id:x:z:rot:` part of its name, out of the island the moment it arrives, so the picture never draws it before
its drop; let go after `EXPECT_SECS` (5) when no drop takes it; nothing with the pixel filter off), `release(key)` (the
ask refused: the watch stops, anything held goes back), `drop(plot, uid, id, x, z, rot, lvl?)` (a piece put down: the
server's model, held by `expect` or found in `Decor` then, stays out of the island while a stand-in built by
`DecorModels.build` (`DropIn`, its `WorldPivot` set upright over its spot and moved by world height alone, its
"PixelLead" `LEAD` (0.2), registered with the renderer) falls `DROP_H` (1.6) studs in `DROP_T` (0.16 s), faster as it
goes, and hops `BOUNCE_H` (0.25) in `BOUNCE_T` (0.14 s); then the real one goes back and the stand-in rests on its spot
until `PixelRenderer.casting(real)` has been false two frames running, at most `SETTLE_MAX` (3 s): the report of
2026-11-20, "when a building is placed, it seems to shift right instead of shifting down. also, they seem to vanish for
awhile before appearing, especially for bigger buildings"; the stand-in used to go at the landing while a big
building's rect took several frames to cast, and was moved along its pivot's own up, which a new model does not set).
`BuildUI.confirm` takes the spot (`id`, `x`, `z`, `rot`) once, before it asks, and hands that to `expect`, the ask,
`drop` and the filled cell: the pick's `x` and `z` follow the pointer while the ask waits for the server, and the drop
used to take them after it (the report of 2026-11-20, "putting down a building/anything leaves a clone of it that
lingers awhile if you drag away while doing it": the stand-in fell under the pointer and waited `SETTLE_MAX` for a model
that never came there, the real one held for `EXPECT_SECS`); a pick the pointer took to another cell meanwhile keeps its
ghost there.
At the landing
(`land`): six `poof` clouds on a ring round the footprint, bursts of its feel's two particle kinds (`FEEL`: wood `wood
dust`, stone `chips dust`, plant `leaf dust`, water `drop drop`, metal `glint dust`, magic `magic star`, sand `dust
dust`, snow `snow snow`, cloth `confetti dust`, fire `ember dust`), two `twinkle`s over its top, its `place_<feel>`
sound and, for a charm of 1 or more, `Puffs.float("+N", ...)` in pink with `mini_charm`; with the pixel filter off,
only the landing), `stroke(plot, id, places, fence, clearing)` (a `poof` and three particles at each tile or length,
at most 24 spread along the stroke, the sound in a run of up to six 0.05 s apart, two twinkles over the last; taking
up: dust and the `close` sound), `cleared(plot, id, x, z, rot)` (a puff and dust where it stood, `close`), `showing()`
(drops under way, for the sims). `Controllers/Puffs`: `burst(kind, at, n, radius?)` (n particles of a kind from a
world point, spread flat over `radius`: `KINDS` `dust chips wood leaf petal drop ember snow confetti magic glint` (1 px
rects in their palette colours, each kind with its speed up and out, gravity, life and sway) and the sprite kinds
`twinkle` (`spark_1..3`), `star` (`twinkle_1`, `twinkle_2`) and `poof` (`poof_1..3`); moved in world studs every
Heartbeat and drawn on the World canvas at whole UI px where `PixelRenderer.projectPixel` puts them; at most `MOST`
(260) at once; nothing while the pixel filter is off), `float(text, at, color, icon?)` (words rising 14 px over 0.6 s
from a world point and blinking out by 1.1 s), `count()`.

**Tap twice, Undo, Select and the layouts** (GAME_DESIGN 4.7; 2026-11-21). The tray's top plank holds, right to left:
**Done** (`BuildDone`), **Undo** (`Undo`, `mini_undo`, 16 x 13, enabled while `view.undo > 0`; in every bar: the
catalog, a pick's action bar, the draw bar, Quick remove, Select and the layouts), **Expand** (now `-66 - bw` from the
right, its price on the second row at `-122`), the tab's count (`-164`), then the tools as `iconButton`s (16 x 13):
**Quick remove** (`QuickRemove`, `-180`), **Select** (`SelectTool`, `mini_select`, `-198`) and **Layouts**
(`LayoutsTool`, `mini_layouts`, `-216`). The tabs show their icons alone when their names don't fit in `s.X - 234`, each
named on a mouse's hover. `toolTip(button, name, key?)` (a mouse only: `UserInputService.MouseEnabled`) puts a
`ToolTip` glass plate over a button on MouseEnter with `TipName` and `TipKey` (drawn raw: "V", "M", "R", "Del",
"Ctrl+C", "Ctrl+Z", "Esc", "E"); MouseLeave or a rebuild takes it away.
- **Tap twice** (`onTap` with a touch, `onPickGhost`, `tapOnGhost(pos, center, spans, models)`): with a pick set, a
  tap whose ground point is within `TAP_NEAR` (1.5 studs) of the ghost's middle, or whose ray meets the ghost model's
  bounding box while its ground point is off the footprint (`rayHitsBox`, the slab test), calls `BuildUI.confirm`; a
  tap elsewhere on the footprint nudges the ghost there (`moveGhostTo`), anywhere else moves it there. A mouse keeps
  "a click where the ghost stands" (`same and mouse`).
- **Undo** (`undoNow`, the button, Ctrl+Z or Cmd+Z: `IsKeyDown` LeftControl, RightControl, LeftMeta or RightMeta):
  "Nothing to undo." with an empty stack (no request), else `plot.undo`; "Undone." on success (the pick and a lifted
  group dropped, the group pruned), "That can't be undone now." for not_found, `buildErr` for the rest.
- **Select** (`sel { on, uids, look, mode "" | "move" | "copy", dx, dz, rot, start, cur, tap }`; `selectTool(on)`, V):
  its bar (`selectBar`: `SelBox`, `SelLook`, `SelMove` (M), `SelTurn` (R), `SelCopy` (C, Ctrl+C), `SelStore` (Del, X),
  `SelStop` (Esc); lifted: `SelTurn`, `SelPlace` (E), `SelCancel` (Esc)) and its info row ("12 selected", "Moving 12
  pieces", a lifted copy's `Plot.copyCost` with "{1} from the inventory" and its coins, `buildErr` of `Plot.roomFor` in
  red). A tap toggles the piece under it (`selTap`, `pieceAt`), a drag past 8 px draws a box between two studs
  (`sel.start`, `sel.cur`; `selBox` adds what `boxPieces` finds, `Plot.MANY_MAX` at most). `showSelMarks` builds
  `SelMarks` (a dynamic model: a gold neon frame round each piece, `SEL_FRAMES` (80) of them, then a flat gold mark
  each; the box a yellow frame). `selLift(mode)` lifts the group (a copy starts to the east by its width);
  `selGhostTo(pos)` puts the group's box middle on the stud under the pointer (even studs with tiles or fences) and
  `showSelGhost` builds `SelGhost` (each piece's `DecorModels` model, `SEL_MODELS` (40) at most, over a footprint frame:
  cyan where `Plot.movesFit` says it fits, red where not). A second tap within `TAP_NEAR` of the tap that placed it, a
  tap on a model, or a click where it stands sends `plot.moveMany` / `plot.copyMany` (`selConfirm`); a copy stays
  lifted for another. `selTurn` turns a lifted ghost a quarter, else sends `moveMany` with rot 90; `selStore` sends
  `plot.storeMany`. A right click that doesn't drag, or Esc, lets the current tool go (`cancelTool`: the pick, a
  lifted group, Select, Quick remove, the layouts).
- **Layouts** (`layoutsOn`, `layoutsBar`): `LayoutsBack`, the title, and a plate a slot (`Slot_<i>`: "Slot 1", "Saved 5
  min ago" (`savedAgo` from `os.time()`), "Level 3, 120 pieces" or "Empty"; `Save_<i>`, `Load_<i>`). Save over a saved
  slot and Load each ask first (`layoutAsk { slot, what, at, plan }`, `ASK_WAIT` 5 s: "Tap again"); Load's first tap
  sends `layout.quote` and shows the plan ("120 pieces, all yours" or "110 yours, 10 to buy", the price, "3 won't fit"),
  the second `layout.load` ("Layout loaded." / "Layout loaded. 3 didn't fit."). Load is grey on an empty slot or when the
  coins don't cover the plan.
- **For the sims and previews**: `BuildUI.undo()`, `debugSelect(on, uids?, box? (x0, z0, x1, z1[, 1 to leave the box
  up]))`, `debugSelectAct(what, dx?, dz?, rot?, keep?)` ("move", "copy", "place", "turn", "store"),
  `debugLayouts(on, slot?, "save" | "load")`; `debugState()` adds `sel`, `picked`, `lifted`, `layouts` and `ghost`.
- **The HUD around it** (what a HUD change must leave room for): the tray is `UIKit.plate` on the Hud canvas, 8 px in
  from both sides and 6 px up from the bottom, `TRAY_H` (82) tall (as tall as its info row while a piece is picked or
  Quick remove or Select is on), anchored bottom left; `CameraController.setFree(true, TRAY_H + 8)` keeps the view's
  centre above it. Above its right corner sits the Free Decor tab (15 px up) and the tips' banner sits on its top edge
  (`BuildUI.trayHeight()`). The tray covers the screen's whole width along the bottom; the tooltips and the card tips
  go just above the tray or the button. Nothing else of the HUD is expected under it.

### 10.11 The hatch scene (`UI/HatchScene`, `UI/HatchBackdrop`, `Models/EggModels`; GAME_DESIGN 6.2)
**What hatched, baked** (the request of 2026-11-21: "the hatching of eggs is laggy, could you bake in the animation of
the creatures when it is hatched instead of rendering the whole model?"). From the scene's first frames (`bakeStart`,
once the stage is drawn: `stageScale()`, the stage's art px a stud measured with `projectPixel` across the world view's
right, `VIEW_R`) the kind that will hatch is drawn as pictures through `Pixel/Snapshot` while the egg waits: one
`MicroModels.species` model in a parentless Folder, posed by each picture's builder (`palShape(r, k)`: its growth,
squash and stretch and the white silhouette, the same function the live model follows), all at the stage's px a stud
(`scale`) with its feet at one `anchor`, sized for its widest stretch plus `BAKE_PAD` 6 px; `BAKE_FPS` 15 a second for
its way out (`popEnd` = `POP_UP` + its leap + 0.6 s of spring, priority 6), then `IDLE_N` 12 of it standing over `IDLE_T`
2.4 s (priority 5). They are drawn as the pixel filter draws a moving model: `outline` "inner", no shadows inside it,
`place` `Shading.INDOOR`, its surface `textures` and `grade` the light of the rarity it hatches as (`GRADE[hr]`,
`PixelRenderer.gradePixel`, glowing parts left alone). Snapshot draws for `BAKE_MS` 6 ms a frame meanwhile
(`setBudget`, back to nil when the scene closes). At the hatch, with every way-out picture ready (`allReady`), `bake.mode`
"pop" and no model is made; else the live model as before ("live"), and the standing pictures take over once it has
landed and settled 0.6 s (`dropPal`). `stepBaked` shows the picture for the moment (nearest `k * BAKE_FPS`; standing,
played there and back) on one `ImageLabel` (`Snapshot.label`, then `Snapshot.show`), "HatchPal", ZIndex 20 on
`HatchBackdrop.layer()` (the sky's life layer, under the pixel layer, so the shell stays in front of it as the live
model's depth had it; made again with the layer on a resize), its feet at `projectPixel` of its spot raised by its hop.
The landing's thud, dust, ring, jolt and stars (`palLanded`) are the same for both. The screen changing size while it
waits bakes again; once it shows, the live model takes over (`newPal`, white if it still is). `bakeStop` releases the
pictures and the model at the close. The preview `hatch=<r><hr>` logs the frames' real time and rays while it comes out
and stands (the request's numbers: hatch=33 from 109.7 to about 50 ms a frame coming out and 80 to about 7 standing,
hatch=77 from 143 to about 72 and 107 to about 12, in the preview's emulator).
`HatchScene.play(res, after?)` (`res = { sp, muts, r, hr, new? }` from `egg.hatch`; one scene at a time; `after` runs when it
ends; a hatch while a scene shows waits its turn and plays when that one closes, the tree panel shut meanwhile: two
quick hatches showed both at once before, the sweep of 2026-11-19), `waiting() -> number` (the hatches waiting), `skip()` (a tap: the next reveal, else the hatch, else away; taps under `TAP_GAP` 0.22 s after the last count
as one, and taps while the egg rises wait), `isOpen()`, `setQuick(on)` (sims: it ends at once, `after` still runs),
`debugState()` (`{ open, phase ("egg", "breaking", "hatched", "done"), r, hr, clock, lift, reveals, left, crack, shake,
shown, muts, rays, shards, pal, baked, bakedReady, bakedAll, egg, glowing, title, titleOff, name, fresh, passive, light,
hush, slow, jolt, squash, letters, ribbon, stars, wait, build }`; `pal` what hatched shows (the live model or its baked
pictures), `baked` the bake's mode ("" none yet, "baking", "live", "pop", "idle", "off") and `bakedReady` of `bakedAll`
its pictures drawn; `shake` how hard it shakes this frame; `fresh` the "New!" tag shown; `light` the
god rays lit (`HatchBackdrop.debugLight`), `hush` how dark the sky is, `slow` the slow motion running, `jolt` the
picture's offset (art px), `squash` the egg's, `letters` the name's letters in, `ribbon` its ribbon shown, `stars` the
stars circling, `wait` and `build` this scene's). `res.new` (the result's `new`: a kind
never had) puts `HatchNew` beside `HatchName` when it shows: a 1-step-corner plate in `accent` with its outline
and `Word` "New!" in `text_ink`, slamming 16 px down into place at the name's right past its place and back (`showNew`, a
cue once the name is in), twelve `accent` and white dots, a `flare_*` sprite, an 8-ray starburst and Audio "sparkle". The egg drops in (2026-11-14, in place of rising from below):
`liftOf(s, clock)` is its height over its resting spot: `DROP_FROM` 9 studs while it waits (`GLORY.wait`, `s.wait`),
then falling to 0 over `FALL` 0.52 s (gravity), then the bounces `BOUNCE` { 0.75, 0.2 } studs over `BOUNCE_T`
{ 0.3, 0.18 } s (arcs), `DROP` 1 s after its wait (taps wait).
It rests with its foot on the pedestal's top at `FLOAT_Y` (`footY(r)` = `FLOAT_Y - EggModels.heroBottom(h)`);
the first landing calls `landed(s, 1)` (Audio "pop" low, a kick of 0.35, ten dust dots from its foot), "sparkle" and
`HatchBackdrop.land()`; the second `landed(s, 0.45)`. What hatched stands at `FLOAT_Y`. `debugState().rings` is
`HatchBackdrop.rings()`. `backdrop(s)` passes the pedestal: its top centre (`projectPixel` of the spot at `FLOAT_Y`) and
half width (the egg's widest, 0.37 h, times 2, along the camera's flat right). `HatchBackdrop.show(r, ex, ey, base?)`
paints it (`BASES` by rarity: top, topLit, side lit, side, sideDark, trim, gem, ink, flower, ring): the column under it
(0.58 of the half width, fluted every 4 px but not on its first and last columns, dithered darker toward the foot, down
past the picture's bottom; `shaft(x, y, shade)` its stone `shade` steps down the ramp colLit, col, colDark, colDeep), the
side (joints every 9 px, the trim band at its foot), the top (lit rim, inlaid ring, the egg's dithered shadow, gems from
rare up), the cap's shadow on the shaft (since 2026-11-15, "it dosent seem like the top part is casting a shadow on the
bottom part of the pillar": under the cap's lip, two steps down the ramp for a row then one step, 0.22 of the cap's
height deep at the left to 0.45 at the right, stepping at the flutes), the outline of the whole down to the
picture's foot (since 2026-11-15, "it seems like the outline gets broken in the pillars": it stopped 2 px under the cap;
the 4-neighbour pixels outside it, each elbow on a curve a step of anti-aliasing, halfway between the stone and the
line, instead of a doubled pixel; since 2026-11-20 each pixel of it a darker step of the stone beside it, the
commonest of its 4-neighbours there and the darker on a tie, 0.45 of it plus 0.3 of the base's `ink`), two tufts on
the rim. Since 2026-11-19 the sky's corners are darkened (dithered) before
the land, and the land is painted per range (`ridgeOf(li, x)`; the sky's stops end at `hyS`, 3 px over the far range's
highest crest, so no seam meets a ridge): a five-tone ramp from the range's `hills` pair (`deep` = the sky's first stop,
`warm` = its `glow`); each column's rounded top (`topsOf`), a lit cap (slopes facing left) and a shaded cap (facing
right) in whole px, none thinner than 2; patches from `vnoise` (smooth value noise on `lattice` points, cached per
range) scaled by depth (`k` 0.6 at the range's highest top to 1.7 at the foot), lone pixels and one-pixel streaks
cleaned away, the nearest range a tone or two darker toward the corners; only the pixels a nearer range leaves
showing are worked out. The ridge is anti-aliased at its steps only: where a run sits a pixel under its neighbour,
half the run (one to four px) on that side takes the neighbour's top tone mixed over what lies behind at
(n - k) / (n + 1). Then blades in clumps (taller toward the front), tufts of three and flowers (`B.flower`) in the
nearest grass.
`paint` keeps the picture's colours (`skyPx`) and a mask of the pedestal (`pedMask`: 1 the top, 2 the side and the
shaft, 3 the outline) for the light. The skies have no clouds, no trees on the hills and no islets since 2026-11-14 (`Sky` lost `clouds` and `trees`;
`hash2(x, y)` scatters pixels without lines). The rings: their own `EditableImage` ("Rings" on the
HatchSky layer, 2 x half width by 0.84 x, centred on the top), redrawn each step while any spread: `land()` starts one
and sets them going every `RING_EVERY` 0.85 s, each widening from half to 0.97 of the half width over `RING_LIFE` 1.7 s
(ease out), a midpoint ellipse (height 0.42 of its width) in `ring`, then two steps toward the top's colour.
`EggModels.hero` builds on the driftlings' 0.05-stud fine grid since 2026-11-15, its shell one smooth egg (since the
request of 2026-11-15 to redo the eggs: an `EggBot` and an `EggTop` solid, `2 x 0.37h` wide, split 0.62, cut at
`SPLIT` 0.56; `shellR` and `surf` from the egg's own curve), its marks within `WINDOW` 88 degrees of the front, nearly
flush and painted on the side the camera sees, lit by the shell under them (`Smooth.onSolids`): the uncommon's zigzag with a
dark edge, a vine and a `Sprout` (a tapered stem, two flat leaves); the rare's frost band with icicles; the legendary's five gems in gold
bezels; the mythic's pearls kept off the outline; the celestial's constellations; the stars and glints thin crossed
Neon bars marked `PixelNoPool` like the cracks, kept off the cracks' paths. Both shell halves get `PixelTex`
(`DynTex.EGG[r]`), `PixelTexSeed` (11 + r) and `PixelTexSoft` 0.8 (one frame, so the pattern runs on across the cut);
PixelRenderer's dynamic parts read those (texV, texSeed, texSoft; `texOpt` in the draw). `EggModels.heroBottom(h)` is
0: nothing of the smooth shell reaches under its foot.
Each reveal tap plays Audio `crack` (pitch up with `crack`), and so does the tap that hatches it; the hatch plays
`crack_open`. The egg shakes as it cracks (`stepEgg`; the request of 2026-11-14: "Make eggs shake while being cracked
open"): a tap's shake (`kick`, 1 for a step up, 0.6 for a mutation) rocks it on its foot about the line the camera looks
along and jumps it sideways along the camera's flat right, dying away over 0.6 s; rays of light stream out of the cracks shown
(`stepBeams`: `BEAM_COUNT` 4, 7 or 10 rays at once by the cracks shown, 14 once they glow; a `Beam` a holder at a
crack piece's projected point with `BEAM_MAX` 44 one-px rects, seeded by `seedBeam`: the slope from `BEAM_DIRS` (16
clean slopes) nearest the way out from the egg's middle, now and then the next one round, 8 + 3 x crack to 16 + 7 x
crack px long (22 to 44 once they glow), white for its first quarter (half once they glow) then the rarity's light,
see-through by `BEAM_FADE` a quarter; it grows out over 0.12 s, dims at 70% of its life (0.45 to 0.95 s, 0.3 to 0.7
once they glow) and is seeded again elsewhere; `beamsMade` counted for `debugState.beams`; the rays are put on their
cracks by `placeBeams`, run from `PixelRenderer.onComposed` right after each new picture, so they sit where the
picture drew the cracks (it draws 20 to 30 times a second, the screen 60: placed every frame they ran ahead of a
shaking egg), a new ray hidden until then; with no picture for 0.25 s they place themselves); once the cracks glow it
trembles
(0.15); the tap that hatches it starts phase "breaking": every crack shows, a crunch, and for `GLORY.build` s (`s.build`,
0.6 for a common egg up to 1.4) it shakes harder and faster (0.55 rising to 1.45) before the shell opens; a tap after
0.35 s of it hatches it at once.
The grander scene of 2026-11-15 ("make the egg revealing much more grander with more animations and effects"; GAME_DESIGN
6.2): `GLORY` rows also carry `wait` (s before it falls), `build`, `slow` (real s of slow motion at the break, the
scene's clock at `SLOW` 0.3: `s.clock` is the scene's, `s.real` real time, `s.slowUntil`), `show` (s from the break to
"done", 0.7 for a common egg), `beams` (god rays in the fan, 0 for common), `reach` (their length, share of the screen's
height), `hush` (the sky's darkening at the end of the build-up), `rings` (shockwaves at the break), `motes` (circling it
while it waits), `hop` (studs what hatched leaps); `rayLen` went. The egg squashes and stretches (`squashOf`: the last
`squash(s, k)` springing back, its breath while it waits, pulses of swelling in the build-up; applied to every part's
offset (x and z times sx, y times sy) and size (times sx) in hundredths, `s.sizes`, `s.crackSizes`; `debugState().squash`),
wobbles more often and harder the longer it waits (`s.wob`, from `s.landAt` or the last tap; a hop past 6 s), leaps
`RISE_H` 0.8 studs and spins once over `RISE_T` 0.6 s at a step up (`s.riseAt`, a landing after), lifts 0.22 studs in an
epic or rarer build-up, and its cracks blaze between white and `RAY[r][2]` there (`s.blaze`, `refreshDynamic`).
`crackFx` at each reveal: a squash, a `FLARE` (`flare_1..3`) where the newest cracks are (`crackPoint`, from `s.cf`),
sparks from there, every crack ray seeded again, `HatchBackdrop.pulse()`, a shockwave from rare up. `rise` adds the
flash in the rarity's colour, a light burst (`s.lightAt`, `s.lightK`), two shockwaves, a jolt, stars flying out, Audio
"ding" at 0.95 + 0.12 a step up (`s.rises`), the title slamming in white and turning (`setTitle(..., slam)`). The build-up
plays Audio "tick" rising in pitch (`s.tick`) with sparks from a crack, "thunder" low from legendary up. `hatch` adds
`GLORY.rings` shockwaves (cues 0.07 s apart, reaching further the rarer), a dust ring, the slow motion, a white
silhouette (`MicroModels.recolor(thing, "white")` till `s.whiteUntil`), confetti with `alt` shades, and the card as cues
(`cue(s, t, fn)`, run by `stepCues`; `finish` runs them all and ends every slide: a tap after 0.3 s in phase "hatched",
or `show` s after the break). `stepPal`: grows from 0.3 stretched over `POP_UP` 0.12 s, leaps `GLORY.hop` studs (in the
air 0.32 + 0.02 r s, stretched by its speed), lands (`s.palDown`: Audio "pop" and "jump", dust, a dust ring, a pulse,
a jolt from rare up, `GLORY.stars` stars orbiting it: a `Dot`'s `orbit`, hidden behind it, frames looping), springs
back from a squash, mood "idle" then "hooray" from 0.12 s after landing to 2.3 s, then "idle". The overlay's moving
pieces (`slide(s, gui, to, dx, dy, dur, over)`, stepped by `stepMoves` on whole px, `back` overshooting about a tenth;
`relayout` ends a plate's slide), starbursts (`starburst`: 4 or 8 rays of 1 px rects at z 36, shooting out in 0.1 s and
going from the inside out), the stepped flash (`flash(s, k, color?, dur?)`, four steps), the jolt (`jolt(s, k)`,
`stepJolt`: `PixelRenderer.setOffset`, `HatchBackdrop.offset` and the overlay root together, dying over 0.32 s),
`HatchMote` frames (the motes in front of it; behind it they go to the backdrop), `HatchLetter` labels (rare up: the
name's letters, `showLetters`, 0.035 s apart, z 36, the name's own label hidden), `HatchRibbon` (uncommon up: `ribbon`,
1 px rects from `TAIL` and the band, the line in `text_ink` over it) and `HatchBurst` rects. `stepLight` fills a
`HatchBackdrop.Light` every frame: the fan's beams (brightness by phase: 0.3 waiting from epic up, 0.4 glowing from rare
up, 0.25 to 0.85 in the build-up from uncommon up, a burst fanning out over 0.3 s and fading over 1.2 s (1.6 at the
hatch), 0.6 behind what hatched from epic up; a wave of brightness travelling round them; `SHINE[r]` colours, moving
round the fan for mythic and celestial), the halo (`RAY[r][1]`), the shadow while it falls, the `waves` as rings, the
motes behind it and `s.hush`.
`play` builds the queue of reveals (`Reveal = { kind = "rise", r }` for each rarity from `r + 1` to `hr`, then
`{ kind = "mut", i }` for each mutation) and opens at once: the moving things in `HatchDynamic`, each registered with
the renderer: the egg (`EggModels.hero(r, EGG_H[r])`: `EGG_H` 2.3 .. 2.8, its foot `FLOAT_Y` 1.2 studs above `ORIGIN`
(0, 0, 9000) with nothing under it), the bits of shell (`HatchShards`: thrown out at the hatch, falling away, gone after 2 s) and what
hatched (`MicroModels.species`, scaled up to `PAL_SCALE` 1.35 with an overshoot, "idle" throughout since 2026-11-16), turned
`PAL_TURN` 30 degrees past facing the viewer: three quarters, as its portrait (the request of 2026-11-16).
`CameraController.setStage({ name = "hatch", ..., top = 30, bottom = 40, clear = true, empty = true })` (its points
the egg's room times `STAGE_ROOM` 1.45 about the egg's middle: "make the egg and creature smaller in the hatching
screen") frames the egg
on an empty see-through stage, so the renderer has its picture at once and `HatchBackdrop` shows round the egg; the HUD
and World roots are disabled meanwhile, and so are the phone's touch controls (`GuiService.TouchControlsEnabled`, in a
pcall); `DayLight.hold` holds the rarity's `GRADE`; `setOffset` jolts the picture at the hatch. A tap (`HatchTap`, or
Space, Enter, ButtonA) in phase "egg" takes the queue's head: a "rise" builds the next rarity's egg, its rays, its
light and its sky with a flash, a hard shake, sparks and stars and the new rarity's name alone as the title (as the
egg's own title is its rarity's name: `eggWords`); a "mut" shakes
the egg and slides in the plate `HatchMut_<i>`. Each runs `crack` one further (0 .. 3: a `Crack` shows while its
`stage <= crack`). With the queue empty the cracks turn Neon in the rarity's light (`glowing`) and `HatchHint` says "Tap
to hatch it"; the next tap shakes it open (phase "breaking", `s.build` s) and then it hatches (phase "hatched": the top flies off, the rest falls, `HatchName` and `HatchLine`,
the passive's plate `HatchPassive` on top of the mutations' (`showPassive`: `mini_star`, its name in the accent, its
`Traits.describe` words, as wide as they need up to the room right of the driftling, wrapping beyond; slot 0 kept free
for it while the mutations reveal; no "No mutations" plate since 2026-11-14; `debugState().passive` its name); `GLORY.show` s later phase "done" and "Tap to go on", and that tap closes it: the
stage off (the island's picture comes back from the renderer's stash at once), the roots back, then `after`. The
overlay is a `HatchScene` frame on the `Stage` canvas: `HatchTitle` (the egg's words and each step up; gone once it
hatches, "remove the it hatched text"), `HatchName`, `HatchLine`, the plates `HatchMut_<i>`
(`Name`, `Blurb`), `HatchHint` (on 0.85 s of every 1.2). The title, name, line and hint span the overlay by scale
(`UDim2.new(1, 0, ...)`, the foot ones from its bottom), never by the canvas's size when made: the user's report of
2026-11-14, "it sometimes doesnt center the text here" (a canvas that settled or changed size after the scene opened
left them off centre). The Stage canvas's `Size` changing (`s.resize`, a deferred `relayout`) places the plates again
by their `Slot` and `PlateW` attributes (`plateAt`), the "New!" tag by `newTagAt`, and paints the sky again round the
egg (`backdrop`); `debugState().titleOff` is the title's box off the screen's middle in screen px. Also: `HatchFlash`, 1 px `HatchDot`s and `HatchStar` sprites, and the
see-through `HatchTap`. `GLORY` by the rarity shown (seven rows, like `GRADE`, `RAY`, `EGG_H` and `TWINKLE`: each
rarity's twinkle frames, `twinkle_*` up to epic, `spark_*` legendary, `twinkle_p1..p3` mythic, `glint_1..3` celestial):
rays, sparks, shards, flash, jolt, confetti, stars, wait, build, slow, show, beams, reach, hush, rings, motes, hop. Under
the rose sky pink petals fall (`fireflies`; thick for 3.5 s after a mythic hatch), under the starry one white and cyan
motes rise (and glints rain for 3.5 s after a celestial hatch); for 3 s after a legendary or rarer hatch twinkles fill
the sky (`stepTwinkles`).
`EggModels.hero(r, h) -> (model, parts, top, fx, cracks)`: the shell one smooth egg cut in two (above),
marks as flat Cylinder discs on the shell (`dab`), beads (`bead`: gems, the crown's points), strips (leaves, icicles),
the shine (white), the fx (`mote` x3 epic, mythic and celestial, `halo` x20 legendary and mythic, `orbit` x28 celestial: a tilted ring round its middle; with the cracks' light the only Neon parts, since Neon pools light round it at night) and the cracks (`Crack = { p, off,
stage }`: 1 a short crack at the top, 2 running down and branching, 3 round the front of its middle; each piece one
Neon strip about two art px wide, no dark edge, at its exact size (off the 0.25 grid `Blocks.part` snaps to) and 0.17
studs off the shell's true surface (the balls' union, `shellR`), over the painted marks and past the raster's depth
bias; "PixelNoPool"; out of sight until the scene's taps reach its stage; the scene colours them in the rarity's light
before the pixel filter takes the model in, and white once nothing is left to reveal). Parts above `SPLIT` (0.56) are the top.
`HatchBackdrop.paint(r, W, H, ex, ey) -> buffer` (the sky picture, RGBA at the art grid: banded sky with dithered
seams (`SKIES[r].stops`, seven skies), the galaxy's band (`milky`, celestial), aurora, stars, sun, moon, two moons
(`twomoons`, mythic) or a ringed planet (`planet` and its `ring`, celestial) with its halo, clouds, the egg's glow at
(ex, ey),
three ranges of grassy hills, lit and patched, their ridges anti-aliased at the steps), `show(r, ex, ey)` (paints it into an `EditableImage` on the
`HatchBackdrop` ScreenGui and starts the sky's life on `HatchSky`; behind the picture two `Back` frames in its top and
bottom colours for an edge that shows while it jolts), `step(dt)` (birds in `WINGS` beats, a shooting
star, twinkles: K x K frames at whole art px; the rings; the light), `pulse()` (one more ring now), `offset(dx, dy)` (the
picture and the life layer's `Layer` frame moved by whole art px), `light(l?)` (`Light = { x, y, rays, reach, levels,
lens, cols, halo, haloK, haloCol, shadow?, rings: { Ring = { x, y, r, flat, k, col } }, motes, hush }`, drawn on the
next step: three `EditableImage`s of the picture's size on `Layer` over a `Hush` frame (the night colour, 0.55 at hush 1)
and under the twinkles and the rings: "Rays" (the fan, `layFan`: n thin wedges, 42% of the way round, the long and the
short (0.64) in turn, kept off the pedestal; each beam's pixels listed nearest first with their strength, how far
along and their dither threshold, `cut[q]` the pixels within q twentieths of its length; a beam's brightness taken in
eighths and its reach in twentieths, drawn again whole only when its brightness or colour changes, else only the pixels
between its old and new reach; up to 4 steps of 0.15 toward its colour), "Halo" (drawn again when its radius moves
`HALO_STEP` 3 px or its strength an eighth; 3 steps of 0.13, `FALL_OFF` by distance squared) and "Glow" (the shadow, the
rings as midpoint ellipses with a half-strength one a pixel inside, the motes; at most 30 times a second, the box it
covered cleared and uploaded); each upload a region's rows), `debugLight()`, `hide()`.

### 10.15 The welcome-back card (`UI/WelcomeUI`; GAME_DESIGN 14.3)
`WelcomeUI.init()` (Hud.start) registers "welcome" (title "Welcome back", `mini_coin`, 250 x 112): `Shells` ("+N
shells", big, in the accent, after the `Shell` sprite), `Away` ("You were away X. Your driftlings kept working, at
30% pace." or, past the cap, "... worked 3 h of it, ..."; "at full pace" with the pass), without the Offline
Pass `PassNote` with `SeePass` (opens "store" on "passes"), with it and past the cap `CapNote`, then `Collect`
(`offline.collect` "free") and, while `offlineDouble`, `CollectDouble` ("double") with `DoubleNote`; a collect closes
it with "Collected N shells." `WelcomeUI.step()` (Hud's heartbeat) opens it by itself once a report (keyed by its
`away` and `shells`) when the loading card is down (`LoadingCard.state().up` false), no panel is open, Build mode is
shut and the hatch scene isn't playing; it closes the card when the view has no report. `WelcomeUI.open()`.

### 10.14 Settings (`UI/SettingsUI`; GAME_DESIGN 9)
The panel "settings" (the menu bar's `Menu_settings`, icon `mini_gear`, 236 wide, `heightFor`: taller when narrow and for the Language row's lines): `ROWS` Language
(`settings.lang`, 2026-11-20: Auto and each `Lang.LIST` language by its own name, `raw` buttons, a `flow` row that
wraps onto as many lines as the body needs; `own` like Screen), Text (`settings.text`: Pixel, Smooth, with the hint
"Smooth is easier to read on a small screen."), Music (`settings.music`), Sounds
(`settings.sfx`), Pixel art (`settings.pixel`: high, medium, low; no off button, the user's wish) and Screen
(`settings.screen`: auto, 100, 125, 150, 175, 200; its six buttons on a line of their own under the label, `own`, with
a hint and `Found_screen`, what Auto found, "Found {n}%", right of the label; `SettingsUI.apply()` hands the value to
`DisplayScale.setChoice` every frame), each a row of buttons
`Set_<k>_<v>`, the chosen one lit. A tap sets a pending value (used until the view says the same), applies it at once (`Audio.setMusicOn`,
`Audio.setSoundsOn`, `PixelRenderer.setTier`, `SettingsUI.applyLanguage` for lang and text) and sends `settings.set`; a refusal drops the pending value with a notice.
Under them the View row (2026-11-18, `settings.zoom`): `ZoomOut` (-), the track (an ink frame round a groove, filled to
the knob), its ten notches' ticks `ZoomTick_<i>` (1 x 3 px under the track, the default's 1 x 4), the 7 x 11 knob
`ZoomKnob` and `ZoomIn` (+); `ZoomSlider` over the track takes a press and a drag (mouse or touch) and picks the nearest
notch. On a narrow panel (a track beside the label would be under `TRACK_MIN` 110 UI px: a phone held upright) the
slider goes on its own line under the label, the body's whole width, and a hint wraps (it was cut off there before).
`SettingsUI.setZoom(n)` moves the knob at once with the flip sound; `ZOOM_WAIT` (0.3 s) after the last notch
it calls `CameraController.setZoom` and sends `settings.set` (a refusal puts the camera back with a notice).
`SettingsUI.zoom()` (the pending notch, else the view's), `SettingsUI.value(k)`, `SettingsUI.applyLanguage()`
(`UIKit.applyLanguage(value("lang"), value("text") == "smooth")`: Main at start and on every view change), `SettingsUI.apply()` (Hud's heartbeat: music and sounds follow the settings). `Audio.setSoundsOn(on)`
stops every one-shot (`Audio.play` returns false) and fades the loops to nothing; `Audio.soundsOn()`.

### 10.13 The Store (`UI/StoreUI`; GAME_DESIGN 14.2)
`StoreUI.init()` registers "store" (title "Store", `mini_store`, 380 x 210; its argument a tab id; "looks" went to
`UI/FounderUI` on 2026-11-20: 10.18), and words the store's Fx: `pass` with `bought` (a thanks line by key), `rewards`
(`StoreUI.rewardText(from, given)`: "<from>: <what>." with each thing when three or fewer, else counted; `from` a
product or pass key, "track" or "vip"), `titles` ("New title: X. Wear it in Looks.", Newcomer never). `StoreUI.buy(key)`
hands a pass to `MarketplaceService:PromptGamePassPurchase` or a product to `PromptProductPurchase` only when
`Monetization.isEnabled(id)`; else the notice "Not on sale yet.". `StoreUI.robuxText(key)` is a key's price
words ("R$ 25", the live price once known) for other panels' buy buttons: the tree panel's `TreeRefresh` ("New eggs
now", `RefreshEggs`) and `TreeQuick` ("Shorten cooldown permanently: R$ …", while `QuickTree` isn't owned; 22 px tall with its words wrapped when they are wider than the button) under its timer bar
(the panel 226 tall for them), and Build mode's `BuyFreeDecor` (`mini_decor`, "Free Decor", on a tab over the tray's
right corner while `FreeDecor` isn't owned). The `RefreshEggs` product (`Store.product`) runs the tree's clock out
(`clutch.left = 0`) so `IslandService.step` lays a fresh lot at its next tick (Fx "eggs"); its `given` is
`{ kind = "eggs", n }` ("new eggs at the tree"). `StoreUI.eggRows(list, order, w) -> number`
puts the egg products at the end of another panel's list (the Tree of Life's) and returns the next LayoutOrder.
`StoreUI.eggKey(r) -> string` (the egg product of rarity r, or the cheapest above it: `EggUncommon` for a common egg)
and `StoreUI.eggInstead(r)` (the request of 2026-11-18: a tree egg short of shells, "Not enough shells. Buy
a rare egg with Robux?" on the status line and `StoreUI.buy` of that product; until its id is set, "Not enough
shells."). The tree panel's Hatch calls it before asking when the view's shells fall short,
and `EggView.hatch` calls `EggView.onShort` (set to it by `Menus.init`) when the server says `money` (the swap
picker's Swap, a race). Prices: `GetProductInfoAsync` once per set id
in the background (`PriceInRobux`, the panel refreshed when it lands), else `SuggestedRobux`, written "R$ 399".
"store": the tabs `Tab_passes`, `Tab_eggs`, `Tab_shop`, `Tab_track` (each a `mini_` icon and its words; the open one
`button`), then the tab's `List` (scrolling):
- passes: the group card `Group` first (GAME_DESIGN 14.3: `mini_folk`, "Our group", `Blurb` (the gift and the boost,
  or "You're in" once in), `GroupJoin`: "Join" (`group.check`; not in yet: `GroupService:PromptJoinAsync`,
  then `group.check` again), "Joined" disabled once `group.member`, "Soon" disabled while `groupOn` is false), then
  `Pass_<key>` rows (icon, `Name`, `Blurb`; OfflinePass with `mini_moon`), `Buy_<key>` (its price, or "Owned" disabled); VIP owned: `VipGift`
  ("Daily gift" while `vipDay` isn't the sea clock's UTC day, sending `vip.daily`; else "Owned" and "Again
  tomorrow").
- eggs: `Product_<key>` rows (the Starter Pack hidden once `gifts.starter`; Finish Hatcheries saying how many warm; the
  eggs `egg_<r>` in their colours), `Buy_<key>`, and `BagNote`.
- shop: `ShopLeft` ("New pieces in 3 h 40 min", run down from `Store.rotation(StateClient.seaClock())`), `ShopRefresh`
  ("New set R$ 19"), a grid (three columns from 330 px) of `Piece_<id>`: `Pic_<id>` (`CosmeticIcons.image` centred in
  24 px), `Name` (rarity colour), `Kind` ("Rare, hat"), then `Price` and `ShopBuy_<id>` (`shop.buy`) or `Owned` and
  `Wear_<id>` (`look.wear`; "Wearing" off while worn).
- track (a pass, running sideways; GAME_DESIGN 14.3): `TrackIcon`, `TrackTitle` ("Pass Track") and `TrackLevel`
  ("Level 6/30"); `TrackBox` with `TrackNext` ("Next: level 7"), `TrackBar` and its `Fill` (`trackInto` / `trackNeed`),
  `TrackPoints` ("40/220" or "Max") and `TrackLeft` ("Ends in 27 days. ..."); `Buy_PremiumTrackTop` without the pass;
  `FreeHead`, `PremHead`; then the `Track` scroller (sideways, `TRACK_COL` 50 a column (as wide as "Legendary"), `TRACK_GAP` 3): `TrackLine`
  and its `Fill` (to the points so far), a `Level_<L>` tag a level (`Num`; pink reached, yellow the next), and the
  cards `FreeCard_<L>` over it and `PremCard_<L>` under it: the picture (a piece's, `egg_<r>`, `mini_star` for a
  title, `mini_coin`), `Caption` (`rewardShort`: shells as `minuteShells` x minutes in short, the egg's rarity, the
  piece's name when it fits else "Look", "Title"; "Claim" when ready), `Got` (`mini_check`) once taken, `Lock`
  (`mini_lock`) on the premium side without the pass, and over a card ready to take a see-through `Claim_<L>` /
  `ClaimP_<L>` (`track.claim`). It opens at the level being worked on, a column in, or the first reward waiting
  further back, and keeps its place (`trackScroll`, UI px; `CanvasPosition` counts screen px, `UIKit.P` a UI px).
  When the panel is short (a phone) the heading, `FreeHead` and `PremHead` go and the box says "Pass Track: level
  6/30" as `TrackLevel`.
`StoreUI.offers` / `offerKey`: the HUD's chips (10.3). `EggView.hatchBag(id, swap?)` sends `bag.hatch` and plays
the same hatch scene as `EggView.hatch` (a shared `played`); `full` opens the tree's swap picker with `bag = true`.

### 10.18 My founder (`UI/FounderUI`; GAME_DESIGN 14.4)
Random Bakery's "My baker" screen (`src/client/UI/BakerUI.luau` there) brought over on 2026-11-20 (the request: "Port
the entire character customization menu from the bakery game to this game, such accessory colors and other features,
along with the accessories it has"), without its pets and staff. `FounderUI.init()` registers "looks" (title "My
founder", `mini_visitor`, 560 x 272; a phone's sheet fills the screen, UIKit) with the argument a tab id (`TABS`:
`skin`, `style`, `bangs`, `hair` (hair, hair2), `eyes` (eye, eye2), `shirt`, `top`, `apron`, `hat`, `face`, `neck`,
`back`, `hand`, `outfits`, `titles`; "pieces" means `hat`); the tab picked stays for the next opening.
State: `working` (the Types.Look being tried, `FounderUI.working()` for the sims; nil while shut), `kept` (a look the
X left unsaved, back on the next opening with "Not saved yet"), `tab`, `angle` (1..8). The sheet's root frame
("Founder") has the `Keep` attribute, so `UIKit.refreshPanel` (Hud's, on every view) leaves it; `build` lays it out
again only when `signature(view)` changes (`Looks.encode(founder)`, how many pieces and titles are owned, the title
worn, the outfits) and never while it closes after a save. A tab, an outfit saved or deleted rebuild it (`rebuild`);
an option picked repaints in place (`onDraft`: the cells, the caption, the status, the stage).
Layout (`layout`): side by side (the stage `math.clamp(W * 0.31, 96, 190)` wide), stacked under 300 px (the stage 40%
of the height, 96 to 220); `compact` under 190 px for the right side (no caption line: `Status` and `Choice` ride on
the stage's glass, the tabs a strip). Names the sims use:
- the stage `Stage` (a TextButton, a drag of `DRAG_STEP` 14 px a step turns it), `TurnLeft` / `TurnRight` (ghost
  buttons with `arrow_left` / `arrow_right`), the picture `Founder` (an ImageLabel bound to a Snapshot of
  `CharacterModels.preview(tidy(working))`, `w, h = 2 * half, up + foot` at one `scale` and `anchor` (the feet) for
  every angle, yaw `(angle - 1) * 45`; `REACH_UP` 5.6, `REACH_SIDE` 2.4, `REACH_DOWN` 0.5 studs, the scale the
  largest of 8..26 that fits), the name tag `TagName` / `TagTitle` (or `Status` on a compact stage), `Choice` at its
  foot when compact. A new picture shows when drawn (`bindWhenReady`), the founder hopping 2 px (`hopStage`: a
  snapped tween); the angle on show is drawn at priority 3, the thumbnails 2, the next angles 1, the rest 0;
  `KEEP_LOOKS` 4 looks' pictures are kept, every picture released on close (`mine`);
- the tabs `LooksTab_<id>` (two rows when they fit, else a sideways strip `Tabs` scrolled to the open one);
  `Choice` (`captionText`: "Wizard Hat, Blue", "Magic Wand, Tipped forward", "Brown and Snow", "<name> (locked)",
  "Outfit 2", "Your outfits: 2/10", "Wearing: Islander") and `Status` ("Not saved yet" while
  `codeOf(working) ~= codeOf(founder)`; `codeOf` = `Looks.encode(tidy(look))`, `tidy` dropping defaults and the tint
  of an empty slot or a rainbow piece);
- the colour row `Colours` (a tab with `tint`): `ColourLabel`, then `Swatches` of `Tint_<Looks.tints id>` cells (a
  chip each; `Tint_orig` the piece's own `color` or the apron's, cream for a piece with none, with an = on it) setting
  `working[Looks.tintField[slot]]`, or `ColourNote` ("Pick one to colour it.", "This one keeps its own colours."); the
  Hand tab's `TurnHeld` (`mini_refresh`, `turn % #Looks.turns + 1`);
- the grid `Options` (cells `cell` px, as many across as fit at 40 px, 30 compact, at most 48; thumbnails 6 px smaller,
  4 under 40): `Option_<value>` (a list index, a piece id, `Option_none`; a second field's `Option_<key>_<value>`;
  `Section` heads it), a colour field's chip, else an ImageLabel `Thumb` bound to a Snapshot of `thumbLook(key,
  value)` (the look being tried wearing that option, the tints, the turn and what the family does not show taken off)
  cropped and framed by `THUMBS[key]` (`lo` / `hi`: the part centres kept; `yaw`, `pitch`, `scale` for 40 px, `focusY`,
  `focusX`). A piece cell has a 1 px bar in its rarity's colour and, not owned (`Owned` attribute false), its
  thumbnail at 0.45 and `Lock` (`mini_lock`); `ShopCell` (`mini_store`, "Shop") ends a piece tab and opens "store" on
  "shop" (the look kept without a notice). Outfits: `SaveOutfit` (a plus; `outfit.set { i = #outfits + 1, look }`,
  "This look is saved already." / "Your outfits are full. Delete one first." first), `Outfit_<i>` (a whole-founder
  thumbnail, `OUTFIT_THUMB`; a tap wears it) with `DeleteOutfit_<i>` (`mini_close`) on the one worn: a first tap arms
  it (red), a second sends `outfit.set { i, look = "" }`; the last answer's `outfits` stands for 5 s till the view has
  it. Titles: `TitleList` with `Title_none` / `WearTitle_none`, `Title_<id>` / `WearTitle_<id>` (`title.set`), then
  `Locked_<id>` with `StoreUI.howWords`;
- the actions: `Randomise` (`mini_dice`; "Random" or the die alone when narrow: owned pieces only, most in their own
  colours), `ResetLook` (skin, hair, style, shirt, the second colour and the eyes kept), `CancelLook` and `SaveLook`
  (`look.set { look = Looks.encode(cleaned(working)) }`: `cleaned` swaps a piece not owned back for the one worn there
  with its tint and turn; "Saving", then a 4 px hop, `UIKit.confetti` and the sheet closing 0.6 s later with "Saved.
  Everyone sees your new look."; a look that is the one worn closes at once; a refusal says why and stays).
Pictures: `pixelPictures()` (`Snapshot.available()` and `PixelRenderer.tier()` not "off"), else ViewportFrames
(`viewportOf`, a 20 degree camera at the same yaw, pitch and focus; the stage's camera goes round on a turn), and
`PixelRenderer.Changed` rebuilds the sheet in the other kind. A tap on a locked piece notices where it comes from
(`whereFrom`: "Sold in the shop now and then.", "A pass track reward.", ...) and "It won't save till it's yours.".

### 10.12 The weather (`Controllers/WeatherView`, `UI/WeatherChip`; GAME_DESIGN 13)
`WeatherView`: one effect layer of its own (`PixelRenderer.addFxLayer("weather", draw)`, Render/Fx, whole art
pixels, depth-tested, no parts) for `Weather.at(StateClient.seaClock())`'s kind. Each kind's strength fades in and out
over `FADE_IN` 4 s. `DENSITY` (spawns a second per 1000 layer px at full strength: rain 3.2, storm 5, snow 1.2, blossom
0.45, leaves 0.4, haze 0.25, breezy 0.35; times 0.5 / 0.75 / 1 by the picture tier); rain and storm are streaks
(`MAX_STREAKS` 1600) of `RAIN_RGB` drawn back along their motion with `Fx.mix`, splashing as they land; a breezy
day's wind comes as wisps (at most `MAX_WISPS` 7 at once, times the tier scale and the strength): a near-white
`WISP_RGB` line 12 to 20 layer px long straight back from its head, a pixel lower over its back part, its ends faded
and the whole of it fading in and out over its 1.6 s (some fifty faint streaks of the lit colour under them read as a
broken picture in a still frame, the sweep of 2026-11-19); the streaks' list is compacted in place each frame; snow (sprites
`fx_flake1..3` from ArtData's `fx_flake_1..3`), petals and leaves (`Fx.KINDS`, tinted), haze motes and splashes share
one `Fx.newSystem(1000)`; fog is `FOG_CLOUDS` 5 `Cloud`s (`{ x, y, vx, born, w, h, dx, dy, d, b, low, n }`, 5 x the
tier scale, at least 2): x, y in global art px (the cam's `gx`, `gy`, so they hang over the world as the view pans),
drifting right at 2.5 to 6 px a second; `shapeCloud` lays out 4 to 7 flattened puffs on a cloud 110 to 210 px wide
(times the screen's fit, `min(W / 640, H / 360)` clamped 0.6 .. 1.2) and half as tall and keeps each pixel's thickness
step (`d`: 1/4 .. 1), its `BAYER` 4x4 threshold (`b`) and whether it is on the underside (`low`); a pixel draws when
`d x FOG_DENSITY x strength x fade > b` (`FOG_DENSITY` 0.55, `FOG_FADE` 2.5 s), mixed at `FOG_ALPHA` 0.34 in `FOG_TOP`
or `FOG_LOW` (subtle since 2026-11-20, GAME_DESIGN 13: it was 8 clouds, solid in their middles, mixed at 0.62). The first clouds are
spread in slots across the screen; one gone off downwind comes back upwind with a new shape, one left behind by a pan
wraps to the far side. The light: the
kind's grade stepped in `GRADE_STEPS` 4 over `GRADE_SECS` 2 through `DayLight.setWeather`; a storm flashes it (x1.28,
lift +10) for 0.12 s every 7 to 16 s and plays `Audio.play("thunder")` 0.6 to 1.4 s after. Sounds: `Audio.ambience`
"rain" (1.4 x rain), "downpour" (0.45 x storm), "wind" (0.12 always, a soft wind round the floating islands in the
surf's place, plus 0.4 x the breeze, half the blossom or leaves, 0.6 x storm).
Nothing on the hatch scene's stage; reduced motion clears the particles. `start()`, `debugSet(kind?)` (hold a kind
at full strength and its light at once), `debugFlash(secs?)`, `debugState() -> { kind, season, strength, drops,
flakes, fog, lines, flashing }`.

`WeatherChip`: two chips on the top bar's line (`Hud.topChip("season", icon, "Winter · 2 h 30 min")` and
`Hud.topChip("weather", icon, "Rain · 10 min", tone)`, the tone the kind's `mark` lifted 45% toward white when it has
a family, else the text colour), updated every 0.5 s when the words change; notices on Fx "weather" (a new season:
"<Season> is here. <blurb>" in the accent colour; else the kind's `starts`). `start()`, `debugState() -> { season,
weather, text }`. `Hud.statusLine` restacks the left column (the quest's card slides to its new place) when a line
comes or goes.

The eggs: `EggView` reads "id.r.kind" from the plot's `Eggs` attribute into the egg's `wx`;
`EggModels.build(r, bare?, scale?, wx?)` puts the kind's piece over a touched egg's crown (rain: a white cloud and
three blue drops; storm: a slate cloud and a lit yellow bolt; snow: a snow cap; blossom: a five-petal flower; leaves:
a maple leaf; haze: a small lit sun; fog: five puffs of mist round its middle), the crown pieces in its top half. The
Tree panel's row for a touched egg (36 tall) adds the kind's `laid` words, its `mini_` icon and the mutation's name
and stars in `Traits.TIER_COLOR`. Sprites (`gen_art.py`): `mini_breeze rain storm fog snow petal heat leaf` and
`mini_season_spring summer autumn winter`, `fx_flake_1..3`.

### 10.19 The sky (`UI/SkyBackdrop`) and Visit (`UI/VisitUI`; GAME_DESIGN 2, 8)
The requests of 2026-11-20: "Never mind, make it a floating island instead, with a 2d skybox. Expanding makes the island
bigger.", "polish the skybox more. it should be of the same quality as the ones in the egg hatching screen, with day and
night cycles with moon and sun rising", "make the clouds look more natural and polished. same with the background
islands", then with two reference pictures "use these landscapes as reference, no need to make the clouds so detailed
with outlines, just simple shapes and color is enough. make variations to them as well", "same with the floating
islands, they should be sillouhetted instead" and "make the sea of clouds a more fluffy connected mass of clouds that
arent just circles. Remove the clouds that appear in the background". `SkyBackdrop.start()` (Main, after WeatherView) steps on Heartbeat. A
ScreenGui "SkyBackdrop" at `PixelDisplayOrder - 3` (behind the hatch scene's backdrop and the pixel layer), enabled only
while `PixelRenderer.isActive()` (the classic style shows the world itself), holds back to front: `Sky` (the bands, the
stars, the galaxy), `Sun` and `Moon` (small images moved on their arcs), `FarA`/`FarB` (the far islets and the sea of
clouds, the picture twice side by side: it drifts right a pixel every `SEA_DRIFT` 6 s and slides `FAR_PARALLAX` 1/16 of
`CameraController.pan()`; no clouds drift across the sky since the last request above) and `Life` (Frames
a K x K screen px: birds, twinkles, a shooting star). Every picture is the screen's size in art px (`PixelRenderer.pixelScale`
K screen px each).
- **The hour's colours:** a `Key` gives six sky stops, the clouds' rim (`lit`), body and underside (`shade`), the hour's
  dark (`ink`: the far islets lean toward it, the birds are drawn in it) and how much night shows (`stars`). The day's
  own keys (`MORNING`, `DAY`, `AFTERNOON`) are the same every day; the night, the first light, sunrise, sunset and dusk
  come in three `VARIANTS` (a deep blue night under purple banks lit magenta, a peach dawn, a rose and gold sunset; a
  lavender night, a lilac dawn, a pink and violet sunset; a sea-blue night, a golden dawn, an ember-red sunset),
  `variantNow()` = `DayLight.skyNight() % 3 + 1` (it turns at noon, inside the day's own key, so nothing jumps).
  `keysOf(v)` lays a variation's keys at hours 0, 0.15, 0.2, 0.235, 0.29, 0.36 .. 0.64, 0.71, 0.765, 0.8, 0.86 .. 1;
  `paletteAt(h, kind, v)` mixes the two keys round the hour in `NOTCHES` 10 steps and the weather's `WX` entry pulls
  every colour toward its grey at the colour's own lightness (`tint`, `k`, `dark`: rain 0.55, storm 0.72, fog 0.62, snow
  0.45, haze 0.3), hides the stars (`stars x (1 - 1.5 k)`), veils the sun and moon
  (their ImageTransparency `veil`) and fades the far things (`fade`). A palette's key is the weather, the key names
  and the notch: a new key paints again.
- **The shapes** (`buildGeo(W, H)` once a screen size): a class a pixel in byte buffers. The sky: the band (stop 0 .. 5, `bandOf`: the middle 60 % of each band an ordered 4 x 4
  dither into the next), the galaxy (0 .. 3, slanting up to the right, a lane of dust fading in and out down its
  middle) and a star (dim, bright; a cross's white middle and arms, blue arms, or a gold middle with red arms) with
  its threshold, so they come out one by one as the night deepens, the brightest first. The front: up to five far
  islets as silhouettes (`islet`: a flat grass top two rows deep with rounded ends, a two-row cliff under it, a round
  belly narrowing to a ragged point with short points hanging under it, one to four trees on one-pixel trunks along
  the top (round crowns, now and then a pine), stones floating below; its body the sky's colour at its height mixed
  toward the hour's dark by 0.16 to 0.32 (bigger, nearer), its top edge a step toward the clouds' rim colour) and the
  sea of clouds (`seaShapes`: `SEA_LAYERS` 5 ridges with their feet at `SEA_BASE` 0.79, 0.83, 0.875, 0.92 and 0.975 of
  the height, each one connected mass whose height above its foot at each column is a slow swell (soft lobes summed)
  plus the highest of: big round domes (half ellipses 0.8 to 1 as tall as half wide), a lower row of domes set half a
  step between them, small domes heaped on the big ones, and a floor at three tenths of the nearest big peak, so the
  notches stay rounded and never cut to the foot; the domes grow toward the front (`k` 0.6 to 1.6) and every lobe wraps
  round the width, so the picture tiles; each ridge one flat colour, no lit edge along the top and no darker underside
  since the requests "no need to make the outlines on top of each layer" and "remove the dark shading at the bottom
  of the sea of clouds"; the ridges step evenly from `far` (the clouds' shade mixed 0.45 toward the sky's fourth stop,
  then 0.2 (more in haze) toward its last) to `near` (the clouds' body 0.6 of the way to their lit tone) since
  "Increase the contrast between cloud sea layers"). The clouds drifting across the sky (streaks and puffs) went with the last request above.
- **A notch** (`newJob`, `colourRows`, `finish`): small lookup tables (the sky's 256 classes, the front's); the two
  pictures coloured `ROW_PIXELS` (25,000) pixels a frame and uploaded together once whole, so the old picture shows
  until the new one is done. Measured in the previews at 640 x 360: the shapes 137 ms (a new screen size), a notch
  34 ms in all, spread over about ten frames.
- **The sun and the moon** (`paintBody`, `arc`, `placeBody`): the sun's u = (hour - 0.23) / 0.54, the moon's the rest of
  the day from sunset; `arc` puts the middle at x = W (0.1 + 0.8 u) and y from `HORIZON` (0.77 of the height, half
  behind the sea of clouds) up to 0.14 by sin(pi u); shown from u -0.06 to 1.06. A body is a flat disc (radius 5 % of
  the height, 6 .. 16 px, the sun's up to 1.9 times that near the horizon, the moon's 85 % of it) with half-covered edge
  pixels at half alpha, over a halo of dithered rings (the sun's a pale cream disc, one or two rings of 0.13 alpha out
  to 1.9 .. 2.8 radii, warmer near the horizon, in five steps; the moon's a cool 0.09 a step); the moon has three
  craters and a phase from `skyNight() % 8` (`MOON_BITE`: a shadow disc beside it, full, gibbous, half, crescent, then
  the same waxing). Painted again only when its size, its warmth step or its phase changes.
- **The life** (`stepLife`): 16 twinkling pixels once the night passes 0.35 to 0.71 (by their index); a shooting star
  every 5 to 13 s past 0.6 of the night (a head and a tail of four fading tones, 0.7 s); by day (night under 0.2, the
  weather's k under 0.6) a flock of two to five birds every 18 to 40 s, in the palette's ink, flapping in two frames.
- `paint(kind, W, H, hour?, variant?) -> (sky, front)` (RGBA buffers), `debugHour(h?, night?)` (DayLight.debugSky:
  the night picks the variation and the moon's phase), `debugTimes(W, H, clock?) -> (shapes, notch ms)`,
  `debugState() -> { on, kind, key, W, H, paints, geos, pending, seaOff, hour, stars, sun, sunX, sunY, moon, moonX,
  moonY, birds, twinkles, streak }`.

`VisitUI` (the islands float apart, so nobody walks or swims to a neighbour): `init()` registers the "visit" panel
(icon "visitor", 220 wide, a row each: the island's name, its owner and tier's name, a Visit button `Visit_<plot>`
sending `char.visit`; "Nobody else is here yet." when alone; a refusal says to wait or that the island is gone),
`islands() -> { { plot, name, owner, tier } }` (the other claimed plots, from `Plot_<i>`'s attributes). The HUD's Visit
button (10.3) opens it.

### 10.17 The sweep of 2026-11-19 (costs cut on the client)
The request: "optimize the game further, fix bugs, and polish everything fully". What the probes showed and what
changed, module by module:
- `EggView`: an egg's parts are moved with one `Workspace:BulkMoveTo` (`moveParts`, `moveCfs`), and only when the egg
  moved (`cf`) or cracks; its lights and sparkles are stepped at 12 Hz (`fxT`), not every frame. A full ring of eggs
  took 2.5 ms a frame on the stress island; about 1 ms now.
- `StreetLife`: a boat or a bird is placed only while it is within `NEAR_PX` (64) art px of the screen
  (`PixelRenderer.nearScreen`); out of view it is parked once at `PARK` (y -400) and left there.
- `AvatarView`: a founder's look is decoded once per attribute string (a weak-keyed `lookCache`), and the ground
  rays' filter list is rebuilt only when the moving models or the characters changed (`updateFilter`, compared item by
  item), not on every foot's ray.
- `WeatherView`: the streaks' list is compacted in place (a new list every frame was up to 1,600 entries in a storm).
- `WorldView`: an island's driftlings count as shown when the island is owned (`peopled`), not only while one is near
  the view, so they are not dressed and undressed as the camera passes.
- `PixelRenderer` (`SG.plan`): a model off the screen with no picture and no blob shadow kept is skipped before its
  plan entry is made.
- `BuildUI`: the ghost is rebuilt only when the piece or its turn changed (`moveGhostTo`), not on every move.
- `UIKit`: a grid tween cut short (its instance gone) drops its book entry, so the table of tweens no longer grows.
- `Plot.spot` and `Plot.refit` (server, section 6): the ring search and the water first (a stall of seconds gone).
On the stress island (the harness's own clock, its Luau ray casts included): the walk's first leg 132.6 ms a frame
before, 125.5 after (the pixel filter 118.5 to 114.1); standing 58.5 ms to 24.9 (the world view 8.4 to 5.1, the eggs
2.5 to 1.1).

### 10.8 and 10.9 (gone)
The walk in and home (`Voyage`) and the islet's screen (`ExpeditionUI`, `MicroStage`: the stages, the battles, the
skill window, the cards) went with the expeditions (GAME_DESIGN 7, 2026-11-12). Their text is in this file's history,
up to commit f667462.

### 10.10 Sprites (`PixelSprites`, `ArtData`, `ThumbData`, `CosmeticThumbData`)
The cosmetics' pictures (GAME_DESIGN 14.1): `UI/CosmeticThumbData`, "look_<id>" 24 x 24 in ArtData's format,
generated by `scripts/gen_art.py` from `scripts/cosmetic_thumbs.txt`, which `sh tools/preview/cosmetic_thumbs.sh` makes:
the preview scenario `cthumbs` (`tools/preview/cosmetic_thumbs.luau`: each piece's `CosmeticModels.parts` alone, a top
on a little body in its colours, turned 25 degrees to the camera, a back piece 205 so its back shows, a part thinner
than a sixteenth of the piece's span made that thick; `Pixel/Snapshot` on five canvases a pixel apart) tidied by
`tools/preview/gen_thumbs.py --cosmetics` (the catalog's tidying; the full set and order from `Data/Cosmetics`).
`PixelSprites` finds them by the "look_" prefix; `UI/CosmeticIcons` (`image(parent, id, pos?, z?)`, `size(id)`,
`has(id)`) draws a piece's picture, or its slot's mini icon when it has none.
The store's 11 x 11 icons (2026-11-14): `mini_store` (a stall with a striped awning: the menu bar's Store),
`mini_crown` (VIP), `mini_ticket` (the pass track), `mini_lock` (a premium card without its pass), `mini_check` (a track reward taken), `mini_gift` (the Starter Pack, VIP's gift), `mini_refresh` (two
turning arrows: Shop Refresh; My founder's Turn), each with its `_sil`. `mini_dice` (2026-11-20: a white die with three
pips, My founder's Randomise) is its own `HAND` call.
Every `mini_` icon is hand-toned: `HAND(name, rows, ramps, flat?)` in `gen_art.py` takes 9 x 9
rows where `1234`, `5678` and `abcd` are the dark, shadow, base and light tones of up to three `RAMPS`, `w` a white
glint, `x` near-black, other letters the sprite's `flat` keys; the `ICONS` table holds 43 of them, eight more are their
own `HAND` calls. `mini_coin`, the money's icon (every price, the counter, the rewards), is a gold coin on the `Y` ramp
with a groove pressed round its face; it replaced `mini_shell`, the region-shaded scallop, on 2026-11-20 ("change the
currency to just coins", "make coin icons coins now, including developer products"), and the icon name `"coin"` took
`"shell"`'s place wherever an icon is named without its `mini_` (the HUD's chip, its rate line, a quest's reward, the
Welcome back sheet, the Store's props). `build()` gives a hand-toned sprite (`spec.hand`, each ramp character's ramp and tone) the same inner
anti-aliasing as a shaded one: a ramp pixel that meets the outline only at a corner steps a tone down (light to base,
base to shadow unless the corner is its top left, shadow to dark at its bottom right). `mini_wheel` is the Lucky Spin's prize wheel (purple rim with seven gold bulbs, six wedges, a red pointer). `mini_heat` is a thermometer,
`mini_takeup` an arrow up out of a tray.
A mutation's tier (2026-11-14, in place of the "*" text): `star_t1` .. `star_t4`, 7 x 7 hand-toned stars (white, green,
teal, gold: the ramps `W G C Y`, the tiers' `Traits.TIER_COLOR`). `UI/TierStars`: `label(parent, text, tier, x, y,
opts?) -> (TextLabel, width)` draws the name (a TextLabel, `opts.name`, its Text the name alone) in its tier's colour
and, as the label's children `Star_1` .. `Star_n`, one star a tier 8 px apart, 2 px after the name, then
`opts.suffix` (the Driftlings list's ","); `measure(text, tier, suffix?)`, `width(tier)`, `shown(label)` (the stars a
label has: the sims). Used by the Driftlings list (`mutLine`), the driftling's card (`Mut_<id>`), the Tree panel's
`WeatherMut` and the hatch scene's `HatchMut_<i>` plates.
`ArtData` (generated by `scripts/gen_art.py`; do not edit): `{ [name]: { w, h, px, pal, alpha } }`, one character a
pixel (`.` clear, else an index into `pal` 0xRRGGBB with its `alpha`). How `gen_art.py` shades (GAME_DESIGN 2):
`cel_tones` over the whole silhouette (the base; a 1 px shadow along the bottom and right edges, two under a
portrait's belly; a short light on the upper half of the top-left edges of masses 3 px thick), close hue-shifted
ramps (`RAMPS`, `M` the magmole's warm basalt, `E` cream), no grain, curves inside the outline softened a step toward the
shadow; the outline is never anti-aliased on its outside. The outline (and a `#` line inside a sprite) is never flat
ink since 2026-11-20 (selective outlining, GAME_DESIGN 2): `ink_of(c)` gives each outline pixel 0.45 of the colour
beside it inside the silhouette plus 0.3 of the ink (`pick_beside`: the commonest of its 4-neighbours there, the
darker on a tie; a `#` pixel takes its 4-neighbours that are not `#`, else its diagonals), the step `Shading.inkOf`
takes in the world. A sprite's `_flash` keeps its outer ring (found by shape, `outer_ring`, not by the ink's colour)
and turns the rest white; a `_sil` (not found yet) is one dark ring, `ink_of(drk1)`, round a see-through ink body.
The driftlings' portraits are not masks: `PORTRAITS`, read
from `scripts/portraits.txt` (GAME_DESIGN 2: each driftling's 3D model drawn by `Pixel/Snapshot` at 32 x 32, turned
30 degrees, pitch 15, in the preview scenario `pportraits`, its head 1.45 times bigger and its eyes 1.1 again, in its
body plan's style (`portraitPose` with `EYE_STYLE`: a size, an iris in the species' accent unless it is in `DULL` or
too near the body, then the plan's own colour, a black `Pupil<L|R>` part as a dot, slit or bar, a Neon glint or none,
a Neon glow for a sprite; a golem keeps its slits; the scenario draws them in flat ink, `Shading.setFlatInk`), then
tidied by `tools/preview/gen_portraits.py`: binary alpha, the outline made again 1 px on the four sides (each pixel
`ink_of` the body colour beside it, the commonest there and the darker on a tie), lone spikes and notches, the bands' dither settled, creases 1 px and a shade of the colour beside
them, dark bodies lifted (not the eyes), a little more saturation, near tones merged, curves softened inside; `sh tools/preview/portraits.sh` runs the three and remakes `ArtData`).
The islands' small lives (`AmbientView`, drawn by `Render/Fx` into the pixel layer, not the interface) are `fx_`
sprites in `ArtData`, hand-shaded with digit tones (`FX` and `GROUND` in `gen_art.py`; no `_flash`): `fx_pip`,
`fx_wren`, `fx_gull` (four frames: sitting or standing, pecking, wings up, wings down; teal `T` and coral `Q` ramps),
`fx_fish` (nose up, level, nose down), each with a small version (`fx_pips` ...) for a screen that shows the island
small, all outlined (a darker step of the colour inside, like every sprite); and without an outline (ground and light, like the sparks) `fx_tuft` (upright, leaning
with the wind, leaning back), `fx_flower`, their small `fx_tufts` and `fx_flowers`, `fx_bfly`, `fx_leaf`,
`fx_petal`, `fx_glint`, `fx_ripple`. The pixels a tinted sprite draws in `tn0` .. `tn3` (the same values as
`Fx.TONES`) take the tones of a colour given at draw time (`Fx.tones`, Render/Ramp's ramp).
The overlay's sprites also have a white `<name>_flash`; the icons have a dark `<name>_sil` (not met yet); an
animation's frames `<name>_1`, `<name>_2`... share one canvas (bottom centre). The sprites: the driftlings' portraits
`icon_<species>` (32x32: drawn from its model; `Menus` puts a row's words at `PX` 40, right of one), the small icons
`mini_<name>` (11x11: `shell food wood sun moon charm folk pal visitor home nest tree train boost path decor work fence
water nature fun start loot chest wild rest boss star boat`; `tree` the Tree of Life's (its card, panel and quests: a
round crown with glowing fruit on a short trunk); Build mode's tabs `work` (a hammer), `nest`, `path`, `fence`,
`water`, `nature` (a pine), `decor` and `fun` (a balloon); `charm` (a heart) the "+N" over a piece put down; no `tide`
since the tide went; `food` unused since the Work tab took the Farms tab's place; `train`, `start`, `loot`, `chest`,
`wild`, `rest`, `boss` and `boat` unused since the expeditions went), the eggs `egg_1` .. `egg_7` (12x15 inside the outline, hand-toned with `HAND` like the small ones since 2026-11-19: `BIG_EGG_TONES` lights the shell from the top left, and `BIG_EGG_MARKS` holds each rarity's marks, taken from the egg masks by `egg_marks`; `sphere_tones` is still in `S` but no sprite uses it now), matching
`EggView.LOOK`: cream with brown freckles, green with a white zigzag band, sky blue with white stars, purple with two pink
stripes spiralling up it, runes between them and a pink ring round its foot (marks `s`, `w`, `p`), gold with a band of
light, rose with a white crescent and band (ramp `H`), night blue with the band of the galaxy slanting up across it
(lilac at its edges, pale blue along its spine, white stars in it), a gold star on its crown, a four-pointed star, cyan
stars and a little stardust (ramp `I`, marks `m`, `M`, `v`, `g`, `y`, `a`, `z`, `d`; the band since the same day's
"you didnt apply the retheme for epic and celestial eggs", the first redraw having read too close to the old one; the small ones the same marks at their size, since 2026-11-19: "redetail these two with
better theming."); the common one's freckles a caramel core and a paler edge, soft and anti-aliased; the tree's panel, the store and the Hatchery), the small eggs
`mini_egg_1` .. `mini_egg_7` (7x9 inside the outline, hand-toned with `HAND` from `MINI_EGG_TONES` and each rarity's
marks in `MINI_EGG_MARKS`; the HUD's eggs card), the twinkles `twinkle_p1..p3` (7x7, pink) and
`glint_1..3` (9x9, white and cyan, pink diagonals), the arrows `arrow_<dir>` (13x13) and
`arrow_<dir>_t` (7x7), `note`, `heart`, `spark_1..3` (a gold spark: a legendary egg's, Build mode's twinkle),
`twinkle_1`, `twinkle_2` (7x7: a small white star opening and closing, cyan at its tips: a rare egg's), `poof_1..3`
(7x7: a little cloud that swells, thins and breaks up: `Puffs`' `poof`), `bombfuse`.

The build catalog's pictures are in `ThumbData` (generated by `scripts/gen_art.py` from `scripts/thumbs.txt`; do not
edit), ArtData's format in a module of its own so ArtData stays small: `thumb_<id>` (24x24) for every piece in
`Data/Buildings` but the Tree of Life, no `_sil` or `_flash`. Each is the piece's model drawn by `Pixel/Snapshot` from
the world's camera (yaw 45, pitch 30) at lvl 1 in the preview scenario `pthumbs` (`tools/preview/thumbs.luau`): a path
or water tile as a 2 x 2 block (the water tiles' lvl from `PlotService.waterMasks`, so the banks run round the block;
`DecorModels.build` flies no pennant on a water tile now, and `thumbs.luau` still takes any pennant parts off), a fence
as a corner (rot 0 and rot 90 from one post), a piece with `water` "over" on a stream two tiles wide at right angles to
its long side, one with `water` "on" on a pond a stud wider all round (in whole tiles). It is drawn on canvases of 24 to
28 px, each at its own scale, and `tools/preview/gen_thumbs.py` keeps the biggest drawing that fits 24 x 24 (the outline
in the outer pixel), tidies it with `gen_portraits.tidy(px, thin=True)` (the portraits' rules, but a 1 px pole, a
spire's tip and a tile's points stay, and a gap deeper than a pixel stays open) and centres it by whole pixels.
`sh tools/preview/thumbs.sh` runs the lot (about 8 s); run it again after a piece's model changes.

`PixelSprites` (a name starting `thumb_` is looked up in `ThumbData`, any other in `ArtData`):
`has(name)`, `size(name) -> (w, h)`, `image(parent, name, pos?, z?) -> GuiObject` (an ImageLabel `Sprite_<name>`
showing the sprite's EditableImage, made once and shared, `ResampleMode` Pixelated, at the sprite's own size: no
scale; without EditableImages a Frame of 1 px run rects), `anim(parent, names, pos?, z?) -> Anim { f, w, h, set(i),
flash(seconds?), moveTo(x, y) }`.

## 11. Verification

- `bash scripts/check.sh`: Rojo sourcemap, luau-lsp strict analysis (0 errors), luau-compile, the specs (`tests/run.luau`
  lists them: Util, Validate, Numbers, DataIntegrity, Traits, Island, Tree, Breed, Economy, Plot, Quest, Schema,
  Shading, Raster, Rim, Fx, PixelFont), the Rojo build. Must end with `ALL CHECKS PASSED`.
- `tools/sim`: the fake Roblox engine boots the real server and client; this game's scenarios and their baselines
  are in `tools/README.md` and `CLAUDE.md`.
- `tools/preview`: PNGs of the real renderer and UI at device sizes (`tools/README.md`).

## 12. What came from Random Bakery

Copied unchanged or nearly: `Render/Raster`, `Render/Picture`, `Render/PixelFont`, `Render/PixelFontData`,
`Render/Ramp`, `Pixel/BakeCast`, `Pixel/ImageMemory`, `Pixel/PixelText`, `Pixel/Snapshot`, `Logic/Util`,
`Models/Blocks`, the specs `Raster` (its framing fixture now a local outline instead of the bakery's Layout), `Rim`,
`PixelFont`, `Util`, `tests/TestKit.luau`, `scripts/gen_pixelfont.py`, `tools/setup.sh`, `tools/defs`, the sim and
preview engines, `docs/WORKFLOW.md`. Adapted: `Render/Shading` (its LUT colours are the palette and the older rooms'
themes; the bakery's wallpapers and land tiles are gone) and its spec, `scripts/check.sh` (no server-codes steps; the
locale steps came back on 2026-11-20 with the languages, `Locale/Lang`, `scripts/locale_strings.py` and
`scripts/gen_locale.py`: docs/LOCALIZATION.md; builds `build/ByteSizeStudio.rbxlx` as its check), `Net`, `Render/Fx` (the effect layer, cut down: no
seasons or places, no weather or shelters; sprites from `ArtData` instead of legends, tinted sprites, sticky pixels,
a light's glow id; the renderer's books upload only the pixels that changed). Written new for this game: everything else, including a much smaller
`PixelRenderer` (one fitted scale with pans and rect re-casts, no Actors, no Hold, no per-plot indoor light) and
`CameraController` (the fitted home view, following the founder, Build mode's free pan), and the sea of islands
(`Data/Street`, `StreetModels`, PlotService's plots and open water, AvatarView's founders), modelled on Random Bakery's
street of bakeries and its plot (ROUND3.md 6.6, 9) but smaller: buildings on a whole-stud grid, with paths, water and
fences drawn in lines and boxes the way the bakery's floors are.
