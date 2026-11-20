# Languages and smooth text

The request (2026-11-20): "like the bakery game, make translations for different languages, and an option to turn off
pixel text". Random Bakery's languages came across whole (its `Locale/Lang`, its string catalog and its check), fitted
to this game.

The game is written in English and stays English wherever it is decided: the code, the server, saves, the sims. A
client shows the words in its player's language where it puts them on screen.

## 1. The languages

`Locale/Lang.LIST`, `{ code, name, pixel }`: English (`en`), Bahasa Indonesia (`id`), Español (`es`), ไทย (`th`),
Português (`pt`), العربية (`ar`), Русский (`ru`), Français (`fr`), 简体中文 (`zh`) and Italiano (`it`), the bakery's
ten in its order. `pixel` says whether the pixel font draws it: Thai, Arabic and Chinese have letters it cannot hold,
so they are always smooth (section 3). The pixel font has the accented Latin letters and Cyrillic the rest need
(`scripts/gen_pixelfont.py`).

Driftlings keep their names in every language (they are this game's own words, like a pet's name). Rarities,
buildings, decor, mutations, cosmetics and titles are translated.

## 2. Which language

Settings has a **Language** row: **Auto** and each language by its own name (a button for each, wrapping onto as many
lines as the panel needs). A pick shows at once and is saved: action `settings.set { k = "lang", v = "auto" | code }`
(`invalid` otherwise), `profile.settings.lang` (Schema default `"auto"`; an unknown value is `"auto"`).

**Auto** is the player's Roblox language (`Player.LocaleId` through `Lang.resolve`): its first two letters when the
game has that language (`pt-br` is Português, `zh-tw` 简体中文), else English.

A change runs `UIKit.applyLanguage(choice, smooth)`: every label UIKit made shows its words again (UIKit keeps each
label's English), drawn in the pixel font or smooth as the new language and style want; the screens lay themselves
out again (`UIKit.Resized`) and an open panel is built again, so every box takes the new words' width.
`UIKit.LanguageChanged` fires after it. Main calls it once the first view has arrived, before the HUD is built, and on
every view change (it does nothing when nothing changed).

## 3. Smooth text

Settings' **Text** row: **Pixel** (the default) or **Smooth** ("Smooth is easier to read on a small screen."), saved as
`settings.set { k = "text", v = "pixel" | "smooth" }`, `profile.settings.text`.

A smooth label is a native TextLabel in Roblox's Builder Sans, bold (`UIKit.scriptFace`), 9 UI px for the small face
and 17 for the big one, with a soft dark stroke (0.55 transparent) standing in for the pixel font's shadow and outline.
Roblox draws Thai, Arabic and Chinese in its own fallback fonts. Labels are smooth when:

- Text is on Smooth, or the language is one the pixel font cannot draw (`UIKit.smooth()`);
- or the words themselves have letters the pixel font lacks (`Lang.needsScript`): a language's own name in Settings, a
  player's display name on their name tag.

Smooth words are measured with `TextService:GetTextSize` (Builder Sans bold), else `Lang.estimateWidth`, so
`UIKit.textWidth`, `UIKit.lines` and every box built from them fit what is shown. Only the words change: the sprites,
icons and the world stay pixel art.

## 4. Where words are translated

`Lang.t(s)`, in this order:

1. the exact string; the same words in capitals; the words with spaces round them (the spaces kept);
2. a count, a rank or a number round a known name (`2x {name}`, `{name} ★3`, `{name} 0.5%`);
3. the most specific template that matches (the most fixed letters), its `{n}` parts translated in turn; a `{n}`
   glued to letters (`Lv{1}`) only takes a number; a short template (under five fixed letters: `{1} and {2}`) only
   takes words the table knows, or numbers;
4. the same affixes round any words that translate; line by line and sentence by sentence when one of them is known;
   a name made of known names;
5. else the English.

A key may carry a note after `@@` that is never shown, when one English word means two things: `Back@@slot` is the
back slot on the My founder screen, apart from the Back button; `On@@auto` is the work picker's status, apart from
Settings' On; `{1}: {2}@@pair` (a passive and what it does) and `{1}: {2}.@@reward` (a reward notice) are layouts a
language sets its own punctuation in. English shows the words before the `@@`.

Results are cached, and what `t` returns is never translated again (`Lang.produced`). `Lang.keep(s)` marks words that
are already in the language on show; `Lang.f(template, ...)` fills a template's translation with values as they are
(a value that needs translating goes through `t` first); `Lang.fmt` does the same with named slots; `Lang.an(anTpl,
aTpl, name, ...)` picks "An {1} egg" or "A {1} egg" by the name in English and gives the language's own sentence
otherwise; `Lang.list(items)` joins pieces already translated with the language's own comma and "and" (the keys
`, @@list` and ` and @@list`: "、" and "和" in Chinese). `UIKit.wrap(text, w)` breaks the translation into the lines
a wrapped label would show (at spaces, or between any two characters in Chinese and Thai), each kept, for code that
lays its lines out itself (the hatch scene's passive plate).

- **UIKit.text** (every label of every screen) shows `t(text)`, and English written to the label later
  (`label.Text = ...`, `UIKit.setText`) turns into its translation as it lands. A label made with `raw` shows its
  words as written (a player's name).
- **Sentences built in code** are whole templates, never English pieces glued together (a mutation's effects,
"+{1}% work", "eggs cost {1}% less", one key each way; Build mode's "Placing: {1}"; the reward notices, their pieces
translated and listed with `Lang.list`): "An {1} egg waits at the
  tree." and "A {1} egg waits at the tree." rather than "A" .. rarity .. " egg"; one and many are separate keys ("1
  tile, free" and "{1} tiles, free"); a building's tooltip in Build mode joins translated pieces (with no spaces in
  Chinese). Durations (`Numbers.duration`) are `{1} h`, `{1} h {2} min` and `{1} min`.
- **Pixel/PixelText** draws `t(label.Text)` as a safety net, so no frame shows English in another language by
  accident, unless the label is bound `raw`.
- **The loading card** (`src/first/LoadingCard`) gets the game's words once Main has set the language
  (`LoadingCard.useLang(Lang, UIKit.smooth)`, `LoadingCard.reword()` after a change). A player whose Roblox language is
  one of the others sees the dots alone under the title until then (8 s at most), so no English line flashes up first.
  The game's name stays as it is.

## 5. The language tables

`locale/<code>.json` (English to the language's words; the place to edit them) and the generated
`src/shared/Locale/<code>.luau` (`python3 scripts/gen_locale.py`). A translation keeps every `{n}` of its key (it may
move them), else the generator leaves it out with a warning and the game shows that string in English.
`locale/extra.txt` lists templates the game builds that no single literal holds (the durations); the catalog adds
them.

## 6. The check: every word in every language

`scripts/check.sh` fails when the game can show a string a language has no words for:

- `scripts/locale_strings.py` lists the words the game can show: every string literal in `src/first`, `src/client`,
  `src/server` and `src/shared/{Data,Logic,Config}` that is not a name the code looks things up by
  (`FindFirstChild("Glow")`, `Instance.new("Frame")`, an id, a path, a sprite's pixels, a log line), plus every chain
  of literals and values (`"Sold " .. n` is `Sold {1}`; `string.format`'s `%s` and `%d` are `{n}` too).
  `python3 scripts/locale_strings.py --list` prints it.
- The Lang spec takes each of them in each language: a key of the table, or a string the table's keys and templates
  translate (each `{n}` filled with a number). A failure names each string and where it is.
- `locale/ignore.txt` lists strings the scan finds that are never shown (a part's or a panel's name, a log line), one
  per line exactly as `--list` prints them.

The sims and previews also capture every string a client asks `t` for (the loaders patch `Lang.seen` to a shared
table and the report prints `@@LANG` lines), which finds words the scan cannot see.

A change that adds or changes words a player sees adds their translations to every `locale/<code>.json` in the same
change, then runs `python3 scripts/gen_locale.py`.

## 7. Previews

`lang=<code>:<scenario>` shows any preview scenario in that language and `smooth:<scenario>` with Text on Smooth; they
stack (`lang=ru:smooth:panel=settings`). The output file names don't carry the prefix, so give each its own folder.
