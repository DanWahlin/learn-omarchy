# Video script: Building Learn Omarchy with GitHub Copilot CLI

**Target length:** about 13 to 14 minutes. The narration is about 1,600 words (roughly 11 minutes at 150 words per minute); on-screen quotes and demo beats with no voiceover fill the rest. The section timestamps include those beats.
**Format:** one video. The story fits under 15 minutes, so no series split is needed.
**Tone:** conversational, first person, screen-heavy. Dan on camera for the cold open, the "what I learned" section, and the close. Everything else is screen recording with voiceover.

**Working title options**
- I Built a Desktop Tutor for Omarchy with GitHub Copilot CLI
- A Flying Robot Teaches You Omarchy (Built with Copilot CLI)
- 3 Weeks, Hundreds of Prompts, 1 Omarchy App: Building Learn Omarchy with Copilot CLI

**Thumbnail idea:** Ohm-1 pointing at an open Omarchy menu, big keycaps reading SUPER + SPACE, text "BUILT WITH COPILOT CLI" in the pixel wordmark style.

---

## 0:00 Cold open (about 45 seconds)

**VISUAL:** Real Omarchy desktop, no intro. Ohm-1 flies down from the bar, lands beside the Apps menu, and points. Keycaps at the bottom light up as SUPER + SPACE is pressed. Cut to Dan on camera.

**VO / ON CAMERA:**
That little robot is Ohm-1. He's flying around my real Omarchy desktop, pointing at the real menu that just opened, and the app knows that menu really opened.

At 12:48 in the morning on September 2nd, I typed one prompt into GitHub Copilot CLI asking for an interactive help system for Omarchy. Three weeks later, that app was in Omarchy's official package repository. You can install it with one command.

I didn't hand-write the code. But I did have to make a lot of decisions, and push back a lot, to get it there. That's what this video is about.

**ON SCREEN TEXT:** Learn Omarchy · built with GitHub Copilot CLI

---

## 0:45 What Learn Omarchy is (about 1 minute 15 seconds)

**VISUAL:** Quick montage. Lesson list with 16 lessons. Ollie the owl narrating with word-by-word captions. A terminal launching and being moved to workspace 2. The Arcade hub with Window Rescue, Shortcut Sprint, and Keyfall.

**VO:**
Learn Omarchy is a course that runs on top of the desktop you're learning. There are two guides, Ohm-1 the robot and Ollie the owl. They narrate each lesson, the captions type out as they talk, and they fly to whatever part of the screen they're explaining.

The key part is that you do everything for real. When a lesson says "press Super + Enter to open a terminal," you press it, a real terminal opens, and the app checks that it actually happened.

There are 16 lessons and 93 activities covering apps, windows, workspaces, capture tools, themes, and more. There's also a small arcade with three games for practicing shortcuts, because repetition is a lot easier when there's a score.

**ON SCREEN TEXT:** 16 lessons · 93 activities · 394 narrated clips · 3 games

---

## 2:00 Why I built it (about 45 seconds)

**VISUAL:** Brief shots of the Try Omarchy VM (or a still), then the 2019 MacBook Pro running Omarchy. Show the GPU-power blog post briefly.

**VO:**
I'm pretty new to Omarchy. I first tried it in a VM on my M3 Max, which was...rough. Apps beach-balled when I closed them, keys repeated themselves, and Copilot CLI found a background service that had restarted almost 44,000 times. I eventually moved Omarchy to a 2019 MacBook Pro, which is its own story that I wrote up on my blog.

Omarchy is keyboard-first, and once it clicks it's really fast. But there's a lot to learn up front, and I learn by doing. So I wanted something that teaches you on the actual desktop instead of in a browser tab next to it.

---

## 2:45 The first night (about 1 minute 45 seconds)

**VISUAL:** The genesis prompt on screen, highlighted line by line. Then the first commit in `git log`: 1:00 a.m., 15 files. Early prototype footage or screenshots with keycap boxes.

**VO:**
My first prompt was pretty detailed. Highlight parts of the screen using the user's theme colors. Play spoken instructions. Show key combinations in boxes at the bottom. Add a help button that can do the shortcut for you. Store lessons in JSON, and package the whole thing for Linux. Then: write a plan, and build it step by step.

The first smart call Copilot CLI made was skipping Electron. Omarchy already ships Quickshell, which is QML-based, so it built native Wayland overlays on top of Hyprland. TypeScript handled the tooling and validation.

About twelve minutes later, I had a first commit. And then the real loop started. Try it, notice something, say it in one sentence.

**ON SCREEN (quotes, typed out):**
- "The boxes need to be larger and space further apart."
- "The key button backgrounds need to be solid."

**VO:**
About half an hour after that, before bed, I raised the bar.

**ON SCREEN (quote):** "Build out a full tutorial... Reasearch it first... make it top notch professional. Something that we could actually ship. Have it ready for me in the morning when I wake up."

**VO:**
When I came back, I had seven modules and 21 activities. I asked for a full code review before trusting any of it. It got a B, with five real bugs. My whole reply was "Fix all of these." That became my pattern for the rest of the project: let it build big things while I'm away, and always review when I'm back.

---

## 4:30 A robot is born (about 1 minute 45 seconds)

**VISUAL:** The Microsoft Agent prompt on screen. Early HEXON concept art. The character lab app with animation strips. The "four eyes" sprite if available. Then current Ohm-1 and Ollie side by side.

**VO:**
Then I typed a prompt I never expected to type into a terminal. Microsoft used to have these Agent characters that flew around your screen. Merlin, Peedy, that crowd. I asked Copilot CLI to research them and tell me if we could do something similar for Omarchy.

It came back with a plan, plus a warning not to copy any of the original characters. So we made an original one. Copilot CLI used an image model on Microsoft Foundry to create a retro CRT robot called HEXON, turned the art into sprite strips, and built a little lab app so I could test animations.

And this is where it got funny.

**ON SCREEN (quotes, one at a time):**
- "He has 4 eyes?"
- "We only want 2"
- "...he could just stay upright given that rockets on his boots now."

**VO:**
So he got rocket boots. A few days later he got a better name, Ohm-1, and a friendlier face, because I told Copilot, "I think he looks kind of mean. He needs to have an inviting look." Ollie the owl joined as a second guide.

Both guides are now character packs. They're just data: images, narration, and a manifest. No code is allowed inside a pack, so anyone could add a third guide without touching the app.

---

## 6:15 The real desktop fights back (about 2 minutes)

**VISUAL:** Split screen: pressing SUPER + CTRL + A, the audio panel opening, and the app's keycap not lighting. Then the fixed version where the lesson completes. Diagram: "keystroke → outcome".

**VO:**
Building a tutorial video is easy. Building a tutorial that runs on your real desktop and never breaks anything is not.

Problem one: global shortcuts. When you press one, Hyprland handles it before the app even sees the last key. I saw this right away. The audio panel opened, but the app never lit up the "A" key.

The fix was to stop checking keystrokes and start checking outcomes. Did the audio panel actually open? Did a new window appear? Did the workspace change? That's how every lesson verifies you now.

**VISUAL:** A tutorial terminal opening beside a "real work" window. Callout: "Only windows the app launched."

**VO:**
Problem two: your windows. Some lessons open a terminal and have you move or close it. The app must never touch your real work. A code review caught a serious bug where just focusing one of your own windows could make the app think it owned it. So now, each tutorial window gets a token. The app checks that token before it moves or closes anything, and if it can't prove ownership, it doesn't act.

**VISUAL:** Captions revealing word by word in sync with narration.

**VO:**
Problem three was more fun. I asked if we could sync the text with the audio, since Azure's text-to-speech can report when each word is spoken. It can. Now all 394 narration clips have word timings, and the captions type out right along with the voice.

---

## 8:15 "I need everything working 100%" (about 1 minute 45 seconds)

**VISUAL:** The overnight audit prompt on screen. A gallery of lesson screenshots from the audit. Then the Capture lesson: the old fake "Start recording" button versus Omarchy's real Super + Ctrl + C menu.

**VO:**
Unit tests only get you so far here. So one night I asked Copilot CLI to go through every lesson, every step, like a real user would. Words, shortcuts, animations, pointing. And I told it, "I need everything working 100%."

By morning it had walked 91 steps with both guides and found 15 issues. Two were blockers affecting 26 steps. It fixed all of them. And I liked that it didn't just tell me what I wanted to hear. After an earlier audit, it told me flat out, "I wouldn't call it 100% ready yet."

The other rule I kept enforcing was: teach the real Omarchy, not a fake copy. The first Capture lesson had its own buttons for selecting a region and starting a recording. So I asked, "That's not real life is it?"

It fixed screenshots first. Later I found the recording exercise still had fake buttons, and I told it, "I need you to be more thorough about all of this." This time it audited Omarchy's actual commands and menus. Now you use Omarchy's real Capture menu, and the app just watches for the file Omarchy saves.

---

## 10:00 Shipping it, and the Arcade (about 1 minute 45 seconds)

**VISUAL:** GitHub Actions run, green. Releases page with 0.1.0 through 0.2.4. The learnomarchy.com website. Then the Arcade: the overcomplicated dashboard version (if captured), then the simplified hub with one Start button. One quick round of each game.

**VO:**
I wanted installing it to be simple. No plugins to enable, no setup scripts. Copilot CLI built an Arch package and a GitHub Actions pipeline that runs every test in an Arch container. When I push a tag, it builds the package and publishes a checksummed release.

The first website had Mac-style window buttons in the corner. Omarchy doesn't have those. It also felt too business-like. I said learning should be fun, and that Omarchy has an 80s, ASCII-text kind of vibe. The site you see now leans into that.

Then one night I asked for a game to practice shortcuts. Something addictive, where you want to beat your last score. "Come up with at least 3 ideas... Go! See you in the morning."

It built three: Window Rescue, Shortcut Sprint, and Keyfall. It also overbuilt the Arcade with dashboards, stats, and a lot of text. I told it, "This looks very complex for someone just going there for the first time. I felt like it was complex myself!" So we cut it down to one big Start button. And yes, at one point I had to tell it, "The ship looks like a fish."

**ON SCREEN TEXT:** omacom/omarchy-pkgs #435 · merged September 21

**VO:**
On September 21st, Learn Omarchy was accepted into Omarchy's official package repository.

---

## 11:45 The plot twist (about 1 minute 15 seconds)

**VISUAL:** Before: Ohm-1 flying to the Omarchy icon after a menu opens. After: Ohm-1 pointing at the opened menu. Then the ask_user conversation with "Not 100%. No change to people's machines is." highlighted.

**VO:**
On the very last day, I noticed Ohm-1 pointing at the Omarchy icon in the corner instead of at the menu that had just opened.

Tracking that down turned up something bigger. Omarchy 4.0.3 had restricted what third-party plugins can see, and our geometry plugin depended on exactly that. It had been quietly failing. So we retired it, and switched to Omarchy's supported measurements. Along the way we also found that Hyprland reports Omarchy's bar as fully transparent, so the app thought the bar was hidden.

Removing the old plugin from people's machines raised a good question. Copilot's first plan did it automatically on launch. So I asked, "OK, so it's 100% safe?"

Its answer: "Not 100%. No change to people's machines is." Since very few people had it installed, we went with the conservative option. Normal launches never touch your config, and only the uninstall command cleans up the old plugin.

---

## 13:00 What I learned, and try it (about 1 minute)

**VISUAL:** Dan on camera. Cut to terminal: `omarchy pkg add learn-omarchy`, then Super + Space and "Learn Omarchy".

**ON CAMERA:**
A few things I'd pass on.

Taste is still your job. Every "too complex," "not fun," and "that's not real life" came from me, and those calls shaped this app more than any prompt.

Overnight runs are great, but only when you define what "done" means and review the work when you get back.

Make the AI use the real product. Screenshots and live testing found things unit tests never would.

And when your code runs on other people's machines, ask whether it's safe. The conservative choice is usually the right one.

**ON SCREEN (terminal):**
```bash
omarchy update
omarchy pkg add learn-omarchy
```

**ON CAMERA:**
If you're on Omarchy, give it a try. Links are below. And if Ohm-1 gets something wrong, let me know. He's still learning too.

**END CARD:** learnomarchy.com · github.com/DanWahlin/learn-omarchy · blog.codewithdan.com

---

## YouTube description draft

I built Learn Omarchy, an interactive course where animated guides teach you Omarchy on your real desktop, entirely with GitHub Copilot CLI. It took about three weeks, more than 600 conversation turns, and a lot of "that's not real life" feedback. In this video I walk through how it came together, what went wrong, and what I'd do again.

Install on Omarchy: `omarchy pkg add learn-omarchy`
Website: https://learnomarchy.com
Source: https://github.com/DanWahlin/learn-omarchy
GitHub Copilot CLI: https://github.com/features/copilot/cli/

## Chapters

- 0:00 Cold open
- 0:45 What Learn Omarchy is
- 2:00 Why I built it
- 2:45 The first night
- 4:30 A robot is born
- 6:15 The real desktop fights back
- 8:15 "I need everything working 100%"
- 10:00 Shipping it, and the Arcade
- 11:45 The plot twist
- 13:00 What I learned, and try it

## Recording notes

- Record the cold open last, once the menu-pointing fix is in the installed 0.2.4 package.
- Never show `.env` files, API keys, sudo prompts, or the lock screen. Review every desktop shot for notifications and clipboard contents.
- Session screenshots and early HEXON sprites are in the Copilot CLI session files. Pick images that don't show local paths.
- Before recording, check the numbers on screen against `story-notes.md`.
