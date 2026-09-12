# Shortcut Arcade prototypes

Shortcut Arcade turns course shortcuts into three short games. Open Learn
Omarchy, choose **Shortcut Arcade** from the course menu, then pick a mode.
Press `A` from the menu to jump there directly.

## Shared rules

- Press the shortcut shown by the prompt.
- Press `H` or choose **Show Hint** to reveal the keys.
- A hinted answer is worth zero points, but it still advances the run.
- A wrong answer never removes points, breaks the run, or triggers the real
  desktop action.
- Personal bests are stored locally in
  `~/.local/state/learn-omarchy/arcade.json` (or under `XDG_STATE_HOME`).

## Shortcut Sprint

A 60-second rapid-recall round. Quick clean answers and longer streaks earn
more points. Use it for a fast warm-up or to chase a new high score.

## Window Rescue

A calm six-task mission on a simulated desktop. Each correct shortcut restores
one window. There is no countdown, so this mode favors deliberate recall and a
clean completion.

## Keyfall

Twelve shortcut prompts fall toward the recall line. Clear each one before it
arrives for speed and streak points. If a card reaches the line, the game
freezes it, reveals the answer, and lets you continue without losing a life or
any points already earned.

These are intentionally different prototypes: Sprint tests rapid recall,
Window Rescue tests visual progression, and Keyfall tests focused flow under
light pressure.
