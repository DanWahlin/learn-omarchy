---
shaping: true
---

# Shortcut Arcade Prototypes

## Source

> I'd like you to think through a creative way we could add a fun and engaging
> game for people to practice Omarchy shortcuts in. Something visual and part
> of the app, but also something where they can learn and progress (and aren't
> penalized if they can't remember something - maybe they get a hint and no
> points or something).
>
> Be creative and think outside the box. What's fun, helps them learn, is also
> addictive (so they build that keyboard muscle memory and always want to "beat
> their last score" or something like that)?
>
> Once you've defined several potential plans, build them out fully so in the
> morning I can try the different prototypes. Try to come up with at least 3
> ideas. Something quick and easy for people to use but also super fun -
> something they want to keep doing to get better and better at Omarchy.

## Problem

Lesson practice is effective but still feels like course review. Learners need
short, repeatable play loops that build shortcut recall without turning a
forgotten answer into failure or risking real desktop state.

## Outcome

Learners can launch three distinct visual games from Learn Omarchy, practice
real course shortcuts safely, request hints without losing progress, and chase
locally saved personal bests.

## Requirements

| ID | Requirement | Status |
|---|---|---|
| R0 | Practice must feel like a visual game inside Learn Omarchy | Core goal |
| R1 | Every challenge must reinforce real shortcuts from the loaded course | Must-have |
| R2 | Forgetting an answer must never end a run or subtract earned points | Must-have |
| R3 | A hint must reveal the answer while making that challenge worth zero points | Must-have |
| R4 | Sessions must be quick to start, replay, and compare against a personal best | Must-have |
| R5 | Game input must not execute the represented desktop action | Must-have |
| R6 | The experience must honor the active theme, text scale, and reduced motion | Must-have |
| R7 | Scores must stay local and remain separate from lesson completion | Must-have |
| R8 | Challenge prompts and shortcuts must come from course data instead of a duplicate catalog | Must-have |

## Shapes

### A: Shortcut Sprint

| Part | Mechanism | Flag |
|---|---|:---:|
| A1 | A 60-second run serves shuffled shortcut prompts one at a time | |
| A2 | Fast correct answers and streaks increase points | |
| A3 | H reveals keycaps; the learner still presses the shortcut for zero points | |
| A4 | Wrong chords produce friendly feedback without reducing score or streak | |
| A5 | Results compare score and streak with locally saved bests | |

### B: Window Rescue

| Part | Mechanism | Flag |
|---|---|:---:|
| B1 | A simulated six-window desktop presents a sequence of rescue tasks | |
| B2 | Each correct shortcut repairs, moves, or activates one visual window | |
| B3 | The run has no countdown; clean solves earn points and hints earn zero | |
| B4 | Completion reports clear time, clean rescues, score, and personal best | |
| B5 | All effects remain inside the simulation and never alter desktop state | |

### C: Keyfall

| Part | Mechanism | Flag |
|---|---|:---:|
| C1 | Shortcut prompts fall toward a visible deadline line | |
| C2 | Correct shortcuts clear cards with speed and streak scoring | |
| C3 | H freezes and reveals a card for zero points | |
| C4 | A card reaching the line reveals itself and retries instead of costing a life | |
| C5 | A fixed twelve-card run ends with score and personal-best comparison | |

## Fit Check

| Req | Requirement | Status | A | B | C |
|---|---|---|:---:|:---:|:---:|
| R0 | Practice must feel like a visual game inside Learn Omarchy | Core goal | ✅ | ✅ | ✅ |
| R1 | Every challenge must reinforce real shortcuts from the loaded course | Must-have | ✅ | ✅ | ✅ |
| R2 | Forgetting an answer must never end a run or subtract earned points | Must-have | ✅ | ✅ | ✅ |
| R3 | A hint must reveal the answer while making that challenge worth zero points | Must-have | ✅ | ✅ | ✅ |
| R4 | Sessions must be quick to start, replay, and compare against a personal best | Must-have | ✅ | ✅ | ✅ |
| R5 | Game input must not execute the represented desktop action | Must-have | ✅ | ✅ | ✅ |
| R6 | The experience must honor the active theme, text scale, and reduced motion | Must-have | ✅ | ✅ | ✅ |
| R7 | Scores must stay local and remain separate from lesson completion | Must-have | ✅ | ✅ | ✅ |
| R8 | Challenge prompts and shortcuts must come from course data instead of a duplicate catalog | Must-have | ✅ | ✅ | ✅ |

## Decision

Build A, B, and C as bounded prototypes behind one Shortcut Arcade entry point.
They intentionally test three engagement loops: time pressure, visual
progression, and moving-target urgency. Keep shared extraction, hint, scoring,
input, and persistence mechanisms in one component so the prototypes can be
compared without tripling infrastructure.

## Breadboard

### Places

| # | Place | Description |
|---|---|---|
| P1 | Course menu | Existing lesson selection screen |
| P2 | Arcade hub | Blocking full-screen game selection |
| P3 | Shortcut Sprint | Timed recall run |
| P4 | Window Rescue | Simulated desktop rescue run |
| P5 | Keyfall | Falling-card recall run |
| P6 | Run results | Score, best, replay, and game selection |

### UI Affordances

| # | Place | Component | Affordance | Control | Wires Out | Returns To |
|---|---|---|---|---|---|---|
| U1 | P1 | topicPanel | Shortcut Arcade button | click | → P2 | - |
| U2 | P2 | ArcadePanel | Three game cards | click | → N2 | - |
| U3 | P2 | ArcadePanel | Best-score summary | render | - | - |
| U4 | P2 | ArcadePanel | Back button | click | → P1 | - |
| U5 | P3 | ArcadePanel | Prompt and timer | render | - | - |
| U6 | P3 | ArcadePanel | Score and streak | render | - | - |
| U7 | P4 | ArcadePanel | Six-window rescue board | render | - | - |
| U8 | P4 | ArcadePanel | Current rescue task | render | - | - |
| U9 | P5 | ArcadePanel | Falling challenge card and deadline | render | - | - |
| U10 | P5 | ArcadePanel | Score, streak, and card count | render | - | - |
| U11 | P3/P4/P5 | ArcadePanel | Hint button and H key | activate | → N5 | - |
| U12 | P3/P4/P5 | ArcadePanel | Shortcut input | press chord | → N4 | - |
| U13 | P6 | ArcadePanel | Run summary and personal best | render | - | - |
| U14 | P6 | ArcadePanel | Replay button | click | → N2 | - |
| U15 | P6 | ArcadePanel | Choose another game button | click | → P2 | - |

### Code Affordances

| # | Place | Component | Affordance | Control | Wires Out | Returns To |
|---|---|---|---|---|---|---|
| N1 | P2 | ArcadeLogic.js | `buildChallenges(course)` | call | → S1 | → U2 |
| N2 | P2/P6 | ArcadePanel | `startGame(mode)` | call | → N3, → S3 | → P3/P4/P5 |
| N3 | P3/P4/P5 | ArcadeLogic.js | `shuffled(challenges)` | call | → S2 | → U5/U8/U9 |
| N4 | P3/P4/P5 | ArcadePanel | `submitKeys(keys)` | call | → N6 | - |
| N5 | P3/P4/P5 | ArcadePanel | `showHint()` | call | → S4 | → U11 |
| N6 | P3/P4/P5 | ArcadeLogic.js | `keySignature(keys)` comparison | call | → N7 | - |
| N7 | P3/P4/P5 | ArcadePanel | `completeChallenge()` | call | → N8, → S3 | → U6/U7/U10 |
| N8 | P3/P4/P5 | ArcadeLogic.js | `scoreAnswer()` | call | → S3 | → U6/U10 |
| N9 | P3/P4/P5 | ArcadePanel | `finishGame()` | call | → N10 | → P6 |
| N10 | P6 | ArcadeLogic.js | `recordResult()` | call | → S5 | → U13 |
| N11 | P6 | ArcadePanel | `persistStats()` | call | → S6 | - |
| N12 | P1/P3/P4/P5 | shell.qml | inhibited key routing | key event | → N4/N5 | - |

### Data Stores

| # | Place | Store | Description |
|---|---|---|---|
| S1 | P2 | `challenges` | Course-derived shortcut challenges |
| S2 | P3/P4/P5 | `deck` | Shuffled challenges for the current run |
| S3 | P3/P4/P5 | Session state | Mode, score, streak, time, hint, and progress |
| S4 | P3/P4/P5 | `hinted` | Makes the current challenge worth zero |
| S5 | P6 | `stats` | Sanitized best scores, streaks, plays, and clears |
| S6 | P6 | `arcade.json` | Local persisted personal bests |

## Slices

| # | Slice | Mechanism | Demo |
|---|---|---|---|
| V1 | Shared arcade foundation | Course extraction, safe input, local stats, hub | Open Arcade and see three playable choices populated from the course |
| V2 | Shortcut Sprint | Shape A | Play a timed run, use a hint, and beat the saved score |
| V3 | Window Rescue | Shape B | Repair all six simulated windows without changing the real desktop |
| V4 | Keyfall | Shape C | Clear falling prompts; let one reach the line and recover without losing |
| V5 | Integration and acceptance | Theme, text scale, reduced motion, tests, docs | Launch all modes from the course menu and retain personal bests after restart |
