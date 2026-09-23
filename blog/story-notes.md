# Learn Omarchy: story arc, facts, and notes

Research sources: Copilot CLI session history (cloud and local), checkpoints, the
`DanWahlin/learn-omarchy` git history and tags, PR `DanWahlin/learn-omarchy#1`,
and `omacom/omarchy-pkgs#435`.

## The one-sentence story

Dan typed "I'm on Omarchy linux right now and would like to build a help
system" into Copilot CLI at 12:48 a.m. on September 2, and three weeks later
the result was in Omarchy's official package repository, after a long run of
overnight builds, blunt taste calls, and "that's not real life" corrections.

## Story arc (seven beats)

1. **The itch (Aug 29 to Sep 1).** Dan is new to Omarchy. He tries it in a VM
   on an M3 Max (beach balls, a service that restarted 43,946 times), then runs
   it on a 2019 MacBook Pro. Omarchy is keyboard-first, and there's a lot to learn.
2. **The first night (Sep 2, 12:48 a.m.).** One detailed prompt: theme-colored
   highlights, narration, key combos in boxes, a help button, JSON lessons,
   packaged for Linux. Copilot picks Quickshell/QML because Omarchy already
   ships it. First commit at 1:00 a.m.: 15 files, 1,523 lines.
3. **"Have it ready for me in the morning."** Research, then build overnight.
   Morning result: 7 modules, 21 activities. A review grades it B and finds five
   bugs; "Fix all of these."
4. **A character is born.** Microsoft Agent nostalgia becomes HEXON, a CRT
   robot generated with an image model on Microsoft Foundry. "He has 4 eyes?"
   Later renamed Ohm-1 ("Friendly eyes are key") and joined by Ollie the owl.
   Character packs become data-only so the community can add their own.
5. **The real desktop fights back.** Hyprland eats the final key of global
   shortcuts, so the app verifies outcomes instead of keystrokes. The app must
   never touch the learner's own windows (per-launch ownership tokens). Narration
   gets Azure Speech word timings so captions type in sync. Overnight audit:
   "I need everything working 100%" finds 15 issues, two blocking 26 steps.
   Copilot says "I wouldn't call it 100% ready yet."
6. **Shipping.** CI in an Arch container, rc.1 to rc.5, 0.1.0 on Sep 12,
   website ("Not very fun - learning should be fun"), learnomarchy.com, the
   Arcade ("Go! See you in the morning"; then "This looks very complex... I felt
   like it was complex myself!"), and the Omarchy package PR merged Sep 21.
7. **The twist.** The guide points at the Omarchy icon instead of the menu that
   opened. Digging in reveals Omarchy 4.0.3 restricted third-party plugins, so
   the app's geometry plugin had been quietly failing. Retire it, fix a
   Hyprland alpha=0 bug, and answer "OK - so it's 100% safe?" honestly: "Not
   100%. No change to people's machines is." Dan chooses the conservative path.

## Verified numbers

| Item | Value | Source |
| --- | --- | --- |
| Genesis prompt | Sep 2, 2026, 12:48 a.m. PDT | session `28034c5d`, turn 8 |
| First commit | `7414ecf`, Sep 2 01:00:52 PDT, 15 files, 1,523 insertions | git |
| Build window | Sep 2 to Sep 22, 2026 (about three weeks) | git |
| Commits | 61 on `main` | git |
| Conversation turns | 615 in the six largest sessions (more than 600 overall) | local session store |
| Code size | ~23.5k lines QML, ~15k TypeScript, ~4.4k JS/MJS, including tests | git ls-files |
| Course | 16 lessons, 93 activities | `courses/omarchy-basics.json` |
| Narration | 394 clips (two guides), each with word timings | repo |
| Tests at v0.2.4 | 553 Node tests, 447 QML tests (4 expected skips) | local runs |
| Overnight audit | 15 lessons / 91 steps; 15 issues; 2 blockers affecting 26 steps | session `8c70b35c` |
| First review | Grade B, five issues | session `28034c5d` |
| Walkthrough video | 148 seconds, 7 modules / 21 activities | session `3e5c38fc` |
| Arcade PR | #1: 78 files, 11,384 additions, 1,423 deletions | GitHub |
| Releases | rc.1 to rc.5, 0.1.0 (Sep 12), 0.2.0 to 0.2.4 (Sep 22) | tags |
| Omarchy packages | `omacom/omarchy-pkgs#435` merged Sep 21, 2026 | GitHub |
| Screenshots pasted | 24 in the final long session alone | session `b31dac41` events |

## Things Dan should verify or adjust before publishing

- Authorship claims ("I built Learn Omarchy with Copilot CLI", "I didn't hand-write the code") are yours to confirm. Soften to "most of the implementation" if you edited code by hand.
- Motivation lines ("a lot to learn", "I learn best by doing") are inferred from
  the genesis prompt's "100% interactive" and the Omarchy setup sessions.
  Adjust to your actual reason.
- Opinions attributed to you ("That's exactly the answer I want", "the biggest
  lesson") are drafted in your voice but aren't direct quotes. Keep, change, or cut.
- Model names: session usage shows several models (mostly GPT-6 Astra, plus
  GPT-5.6 Sol and Claude Opus). The drafts only say you switched models for a
  second opinion ("Have Claude to a review of everything once you're done").
  Name models if you want.
- The Sep 13 session already flagged Omarchy's plugin restriction; the app's
  fallback hid the impact until Sep 22. The drafts mention this in one line.
  Cut it if you'd rather keep the twist simpler.
- Video timing assumes ~150 spoken words per minute.

## Do not publish

- Any `.env` contents, API keys, endpoints, Cloudflare token, or credential file
  locations (the image generation and Azure Speech sessions referenced them).
- sudo or password prompts, lock screens, private
  draft release URLs, local absolute paths, clipboard contents, or unreviewed
  desktop screenshots.
- Microsoft Agent characters are inspiration only. Ohm-1 and Ollie are original.

## Footage and assets to capture

- Ohm-1 flying from the bar to an opened menu and pointing (the Sep 22 fix).
- Keycaps lighting up as a shortcut is pressed; a lesson completing.
- Word-synced caption typing along with narration.
- Early HEXON concept art and the "four eyes" sprite (from session files), then
  current Ohm-1 and Ollie.
- The Arcade hub (one Start button) and one round of each game.
- Native Capture exercise: Super+Ctrl+C menu, region select, paste to finish.
- Terminal: `omarchy pkg add learn-omarchy`, then Super+Space, "Learn Omarchy".
- GitHub: releases page, PR #1, omarchy-pkgs #435 merged.
- Copilot CLI: parallel background agents list, a pasted screenshot, a session
  resume after reboot, an ask_user form.
