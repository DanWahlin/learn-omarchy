# Arcade

Arcade turns course shortcuts into three short games on the
`feature/shortcut-arcade` branch. Open Learn Omarchy, choose **Arcade**
from the course menu, or press `A`. A separate development worktree can run
this branch without changing the main course installation.

## 80s presentation: analysis and implementation plan

The previous presentation used conventional rounded dialogs, pill badges, small
race markers, and thin neon outlines. Color alone did not make it feel like an
arcade. Repeating status prose also competed with the one thing to learn.

1. **Use a recognizable display language.** Original five-by-seven pixel
   lettering for marquees, scores, and outcomes; angular cabinet bezels and
   raised rectangular controls. Keep instructional text in the readable UI font.
2. **Give each game a distinct stage.** Sprint gets a moving vector-grid
   horizon and ghost race; Keyfall gets a raster starfield and separate recall
   and practice landing bays; Rescue keeps its approved ship, planet, and
   simulated desktop. Do not replace the guide artwork.
3. **Make outcomes physical, not verbose.** Pixel-point bursts with short
   sparks, correct catches toward Recalled, hints toward Practice, and a brief
   miss/rebuild transition. Never deduct earned points or disguise assisted
   recall as independent recall.
4. **Keep the interface lean.** One highlighted starting game; Options and
   Your progress collapsed; concise results with at most three actions.
   No lives, coin economy, dashboard, or extra confirmation screens.
5. **Verify learning and accessibility.** Exercise the full course's canonical
   chords, every Rescue mission, fresh/replay behavior, hints, misses, deadlines,
   retries, capture loss, and endings. Render compact/large-text, dark/light,
   and reduced-motion variants. Motion stops when inactive; reading surfaces
   remain opaque and scanlines stay behind, not over, instructional text.

All game accent colors now derive from the current theme accent, including
Rescue and Keyfall rather than fixed green and purple. This is an in-app
presentation change, not a change to the user's desktop theme.

## Start here

Choose **Play** on the **Start here** Window Rescue card: an untimed game with hints whenever
you need them. Sprint and Keyfall are also available from the first screen.
Choosing a game starts it immediately; there is no extra confirmation screen.
Sprint's card identifies its 60-second limit, Keyfall provides reading time
before each prompt moves, and Window Rescue remains untimed.
The Lessons dialog's **Arcade** entry uses a compact illuminated marquee
treatment so the game area is visually distinct from lesson utilities.

The home screen keeps learning statistics out of the way. **Options** contains
the optional topic and Keyfall speed settings. **Your progress** shows practice
history, milestones, and suggested shortcuts to revisit. Both start collapsed;
the underlying learning history is still saved automatically.

The hub and active playfield expand on wider screens. Paused and results views
stay content-sized. A consistent close button returns directly to the hub from
a game instead of acting like pause. Arcade text is larger than the course's
compact controls and still follows the user's Text size preference. The
selected guide has a larger header portrait.
Its backdrop follows the current Omarchy wallpaper, including background
switches while the app is open. The wallpaper is decoded in the background
before Arcade opens and retained between visits so it is normally ready
immediately. The dialog and reading cards stay opaque;
only the wallpaper behind them is dimmed. This reads Omarchy's existing
background selection without changing your theme or desktop settings. If the
image is unavailable, a notice appears and the theme's background color is used.
The hub, game, pause, completion, and results surfaces are also created up front
and reused, avoiding page-construction flashes while moving through a round.

## Controls and safety

- Choose a game with `1`, `2`, or `3`, or use the on-screen controls.
- Press the shortcut described by the task. Answer keys stay hidden unless you request a hint.
- Press `H` to reveal the keys. Press it again to hide them; the answer remains
  practice-only after using help.
- Press `P` during Window Rescue or Keyfall to pause. Sprint is a continuous
  60-second challenge and does not have a manual pause.
- Press `Escape` or the close button during a game to abandon that run and
  return directly to the arcade hub. Practiced shortcuts remain in learning
  history, but an abandoned run is not saved as a completed score.
- Finishing a round first shows a focused completion screen. Choose
  **See results** for a concise score, first-try summary, and next action.
  Window Rescue omits elapsed time, deck-record comparisons, repeated mission
  metadata, and navigation helper copy because the mission is untimed and its
  actions are self-explanatory.
- `Escape` from results returns to the arcade hub; from the hub it returns to
  the course menu. If Options or Your progress is open, Escape closes that
  section first.

All shortcut input stays inside the game. Window Rescue never launches,
closes, or rearranges real desktop windows. Hints never remove earned points.
A hinted answer earns no score but still counts as practice. A correct answer
after a wrong attempt is not labeled a first-try recall.

The course toolbar is hidden inside the arcade. Entering a game captures
shortcuts for practice; losing capture pauses the round, and resuming captures
them again.

The bundled deck uses canonical actions derived from the course, rather than
counting every lesson's wording as a different shortcut. Prompts specify their
target and direction without requiring an earlier lesson's desktop state.

### Curriculum and randomness audit

The bundled course has 66 eligible lesson steps, representing **40 distinct
key combinations**: 8 app actions, 9 window actions, 8 workspace actions,
13 system actions, and 2 capture actions. This is coverage of the course's
shortcut curriculum, not every possible Omarchy feature or a test of real
desktop execution.

The six Rescue missions contain 36 task positions using 19 distinct actions.
Their order is deliberate: launching, focusing, moving, and closing must make
sense in the simulated state. Fresh missions randomize which scenario is
chosen, not the prerequisite order inside it. Scratchpad recovery now hides
the special workspace before closing the browser; it does not assume ordinary
focus cycling can cross between special and regular workspaces.

The audit found that fresh short adaptive decks were selecting only starter
material. New material now remains reachable across all difficulty levels
while retaining practice priorities. Seeded regression runs exercise all 40
combinations across fresh decks. Same-deck replays preserve the original order
and pace rather than randomizing a supposedly comparable challenge.

## Shortcut Sprint

A 60-second rapid-recall round. Quick first-try answers build the score.
**Replay this deck** keeps the same order so scores are comparable;
a fresh run reshuffles the deck. A previous run's recorded answer times provide
a personal pace reference.

The playfield is a recall circuit rather than an empty timer screen. A live
two-lane race console shows completed answers for the current run and the saved
best-score ghost at the same elapsed time. The racer advances only when an
answer is completed, the pace label states whether the learner is ahead,
behind, or even, and short score bursts keep feedback near the active prompt.
Faster runs continue into numbered laps rather than pinning the racer at the
finish line; counts and the ahead/behind comparison remain cumulative.
The moving vector grid stops in reduced-motion mode. The hub preview uses two
recognizable hover racers, speed marks, a timer, and a checkered finish line.

Hints reveal the answer without stopping Sprint's timer. A hinted run still
records learning, but it cannot overwrite an uninterrupted personal-best
challenge record. Automatic safety suspension remains available if the app
loses keyboard capture.

## Window Rescue

A calm, untimed series of six-step simulated desktop missions. Fresh runs
randomly choose from terminal setup, tiled-layout cleanup, workspace sorting,
scratchpad recovery, file-window shaping, and browser workspace recovery.
Immediate fresh runs avoid repeating the mission that just appeared; the
results screen can still replay the exact mission on purpose.

Each mission is also a short flight with its own callsign and destination.
The flight route sits below the simulated desktop, matching Sprint's bottom
race layout while keeping score and first-try streak at the top. The route is
outside the scrolling content so the ship and destination stay visible on
smaller screens, including when hints expand the instruction card.
It replaces a generic progress bar with a ship, five system
checkpoints, and a destination planet. Completing the sixth action reaches the
planet. Every completed action advances the ship, including guided practice,
while a prominent score or **Practice** burst reflects how the step was completed.
The ship and planet use matched transparent generated artwork with recognizable
spacecraft and ringed-planet silhouettes at HUD scale.
Stars drift slowly behind the route, completed checkpoints illuminate, and the
final flight holds briefly at the destination before the completion screen.
Reduced-motion mode keeps the route static and moves the ship immediately.

Every mission uses canonical shortcuts from the course. Generic terminal,
browser, and Files boxes show focus, tiling, floating, fullscreen, workspace,
and scratchpad changes without opening or controlling real applications. The
browser includes recognizable navigation chrome, an address field, and a
responsive high-level page rather than imitating a specific installed browser.
In
each step, the instruction gets a brief one-time emphasis so the next action
is clear even when the simulated desktop begins empty. The header explicitly
labels it as the **Next action**. Until the learner interacts, the action text
and a low-contrast outline slowly breathe toward the mission accent color.
Launch steps stage a translucent Terminal, Browser, or Files target in the
layout position the successful simulated app will occupy, then crossfade it
into the real simulation. Reduced-motion mode keeps both cues static. In
the terminal setup mission, moving the window follows it to workspace two.
The scene then explicitly announces its mission-only return to workspace one
before asking the learner to switch back; that reset is not an effect of the
real shortcut.

The simulated desktop uses restrained navigation-console framing and mission
status labels without reducing the usable desktop area. The Window Rescue
preview on the hub shows only the generated ship and destination planet.
Successful actions receive short guide reactions; wrong attempts still remove
no points and do not move the ship backward.

Results reflect recall rather than a global letter-grade scale: completing
every task on the first try earns perfect recall. A custom course without the
required mission actions shows an unavailable-mission message rather than
substituting unrelated tasks.

## Keyfall

Choose a comfortable pace for a twelve-prompt round. Each card has a reading
phase before falling. If it reaches the recall line, it becomes a guided
practice card with the answer revealed. No life or earned points are lost.

The playfield presents each shortcut as an incoming signal moving through a
five-lane catch field. The landing area keeps a lightweight tally in
**Recalled** and **Practice** bays, counting independent and assisted attempts
in this round, not distinct weak shortcuts. Correct answers light Recalled.
On wide screens the card lands toward the appropriate bay; compact and
reduced-motion layouts keep it centered and readable. A requested hint glides into
Practice; a miss briefly glitches away and rebuilds there with the keys
visible. Running out of falling time also rebuilds the card in Practice but
does not count as a wrong keypress. Repeated wrong input keeps the revealed
answer visible. The hub preview shows a shortcut made from visible keycaps falling
toward the same glowing catch platform.

Shortcuts needing help can return after other cards, giving you a chance to
recall them without looking. At most six extra practice prompts can be added,
so practice cannot trap you in an endless run. Reduced-motion mode keeps the
prompt and ambient signal packets stationary while showing time with a progress
indicator.

All three games use the same prominent animated points burst after a scored
answer. Assisted answers show an equally visible Practice burst instead.
Reduced-motion mode keeps this feedback stationary. Sprint's larger recall
card and the non-Rescue playfields use layered neon frames derived from the
current Omarchy theme rather than hardcoded colors.

## Practice and progress

Recommended and targeted practice focus on skills needing another attempt,
with familiar material mixed in. Practice launched from results stays in the
same game; Window Rescue repeats the same mission as non-comparable practice.
The hub's general recommendation uses relaxed Keyfall for a small review set.

The mastery view distinguishes practice with help, independent recall, and
reliable recall over time. Repeating a revealed answer is useful practice, not
proof of mastery. Reliable recall requires successful first-try answers in
separate sessions at least a day apart. There are no expiring rewards or lost
daily streaks. The First practice, Independent recall, and Retained across days
milestone badges stay earned even if a later attempt needs help.

Practice and score challenges are separate. Personal-best comparisons are
keyed by the mode, exact ordered deck, pace, and scoring version. A different
deck, a guided run, or an older scoring system does not set a misleading
comparison target.

## Local storage

Arcade progress is stored in
`${XDG_STATE_HOME:-$HOME/.local/state}/learn-omarchy/arcade.json`, separately
from lesson progress. The versioned format retains earlier aggregate scores
while adding per-skill practice and comparable challenge records.

Completed answers save learning as you play. Save errors appear in the arcade;
a later completed answer retries a failed write. An unreadable file or an
unsupported format version is preserved rather than overwritten. In that
case, the visible notice explains that the session cannot be saved.

No network service, account, leaderboard, or telemetry is required.

## Automated coverage and visual review

`npm run check`, `npm test`, and `npm run test:ui` cover course/asset integrity,
logic and storage, shell input routing, and the rendered QML components.
`tests/qml/tst_arcade_journeys.qml` loads the real bundled course and submits
answers through the game's key-input boundary. It advances the clock
deterministically rather than waiting a real minute for every Sprint test.

The full-course matrix includes every Rescue mission clean, hinted, and after
a wrong attempt; all three Keyfall paces with clean, hint, wrong-key, and
deadline outcomes; spaced retries and replay; every canonical chord in Sprint;
and timed records with fewer or more answers than a single deck contains.
Additional checks cover repeated assisted mistakes, animation cancellation on
restart, numbered race laps, responsive bounds, long score labels, theme
changes, and at least 4.5:1 accent-text contrast against the reading surface.
Existing tests cover keyboard capture, safety pause, navigation, migration,
and preserved corrupt/future-version progress.

Visual review also renders hub, active play, help, score feedback, pause,
completion, and results, using the current wallpaper and original guide pack,
plus compact, light-theme, and reduced-motion variants. These checks establish
behavior and presentation constraints; they cannot prove subjective fun or
replace learner feedback.
