# Building Learn Omarchy using GitHub Copilot CLI

At 12:48 in the morning on September 2nd, I typed this into [GitHub Copilot CLI](https://github.com/features/copilot/cli/):

> "I'm on Omarchy linux right now and would like to build a help system. A type of 'course' people could go through that's 100% interactive."

Three weeks later, anyone running [Omarchy](https://omarchy.org/) can install the result with one command:

```bash
omarchy pkg add learn-omarchy
```

That app is [Learn Omarchy](https://learnomarchy.com). Two animated guides, a robot named Ohm-1 and an owl named Ollie, fly around your *real* desktop, point at the real menu bar and windows, talk you through each lesson, and check that the real desktop action actually happened after you press a shortcut. There are 16 lessons, 93 hands-on activities, 394 narrated clips, and a small arcade with three games for practicing shortcuts. It's now in Omarchy's official package repository.

If you haven't run into it yet, Omarchy is DHH's opinionated Arch Linux setup built on [Hyprland](https://hypr.land/), a tiling Wayland compositor that you drive almost entirely from the keyboard.

I built Learn Omarchy with Copilot CLI. I didn't hand-write the QML, the TypeScript tooling, the CI pipeline, or the Arch packaging. What I did do was decide what "good" meant, over and over, and push back when it wasn't there yet. That turned out to be the real job, and it's what this post is about.

## Why a Tutorial App for a Desktop?

I'm fairly new to Omarchy. I first tried it in a VM on my M3 Max using Try Omarchy, which was...an experience. Beach balls when closing apps, keys repeating 30 times, and (as Copilot CLI discovered) an input-method service that had restarted 43,946 times and filled the journal with 263,688 log lines. I eventually moved Omarchy onto a 2019 MacBook Pro, which led to its own adventure that I wrote about in [How I Cut GPU Power from 18 W to 4 W on an Omarchy MacBook Pro](https://blog.codewithdan.com/how-i-cut-gpu-power-from-18-w-to-4-w-on-an-omarchy-macbook-pro-with-github-copilot-cli/).

Omarchy is keyboard-first. That's the whole point, and once it clicks it's fast. Getting there means learning a lot of shortcuts, menus, and conventions, though, and I learn best by doing things rather than reading about them. So I wanted a course that ran *on* the desktop you're learning, not in a browser tab next to it.

## The First Night

My opening prompt was long and specific. I asked for theme-aware highlights around parts of the screen, spoken narration, key combinations shown in boxes at the bottom of the screen, a help icon that could perform the shortcut for you, lessons defined in JSON, and a Linux package to install it all. I finished with "create a plan in learn-omarchy/.plans/plan.md and then implement it step by step."

The first interesting decision Copilot CLI made was what *not* to use. It skipped Electron and a web app entirely and chose [Quickshell](https://quickshell.org/) and QML, because Omarchy already ships Quickshell for its own shell. That meant native Wayland overlays that sit on top of Hyprland without adding a big runtime. TypeScript handled validation and tooling, JSON held the course, and Bash handled the launcher.

The first commit landed at 1:00 a.m.: 15 files and 1,523 inserted lines. Then the real work started, which looked a lot like my other projects. I'd try it, notice something off, and say so in a sentence:

- "Can we make it so that when they press a key the appropriate box is highlighted? That way they know they're doing it right?"
- "The boxes need to be larger and space further apart."
- "The key button backgrounds need to be solid. Otherewise I can see through and it's confusing."

Typos and all. That's how it went for three weeks.

### "Have It Ready for Me in the Morning"

About half an hour after that first commit, before heading to bed, I raised the stakes:

> "Build out a full tutorial that walks people through key aspects of Omarchy. Reasearch it first... Think through that deeply, build it out fully, make it top notch professional. Something that we could actually ship. Have it ready for me in the morning when I wake up."

Copilot CLI kicked off a background research agent, loaded an Omarchy skill I use for safe system changes, and got to work. When I came back to it, I had seven modules and 21 activities with a topic picker, narration, keycap feedback, and progress tracking.

I asked for a full code review before trusting any of it. The review agent gave it a B and found five real bugs, including shortcut matching that accepted extra keys and narration that got cut off when audio playback shut down. My entire response was "Fix all of these." It fixed them and re-ran the review to confirm.

That became a pattern I used for the rest of the project: let it build big things while I'm away, but never skip the review when I get back.

## Meet Ohm-1 (and Ollie)

Here's a prompt I never expected to type into a terminal:

> "Microsoft used to have a Microsoft Agent character that could fly around. Research that, watch some videos of it in action, and then report back on if we could implement something."

If you remember Merlin and Peedy, you know exactly what I was picturing. Copilot CLI researched Microsoft Agent, pointed out the difference between Agent and Clippy, and (importantly) told me not to copy any of the original copyrighted characters. It recommended an original sprite-based character instead.

So we made one. Using an image model on [Microsoft Foundry](https://ai.azure.com), Copilot CLI generated concept art for a retro CRT robot named HEXON, then built sprite strips and a small "character lab" app so I could watch animations in isolation. The feedback loop was pretty funny in hindsight:

- "When standing he kind of 'shifts' weird from the left to right."
- "He has 4 eyes?"
- "We only want 2"
- "The flying down and up the (the angles) just aren't working well. If we can fix them great, but otherwise he could just stay upright given that rockets on his boots now."

He got rocket boots and stayed upright. A few days later he got a name that fit Omarchy better, Ohm-1, and a friendlier face after I told Copilot "I think he looks kind of mean. He needs to have an inviting look" and "Friendly eyes are key." Ollie the owl joined as a second guide.

Eventually both characters became *character packs*: data-only folders with a manifest, sprites, narration, and a declarative intro sequence. No executable code is allowed inside a pack, paths are validated, and community packs can live in your user data folder. Adding a third character doesn't require touching the app.

## Teaching on a Real Desktop Is Hard

A tutorial that plays a video is easy. A tutorial that runs on your actual desktop, watches what you do, and never breaks anything is a lot harder. A few problems stood out.

### The Shortcut Disappears Before You See It

When you press a global shortcut in Hyprland, the compositor handles it before the app ever sees the final key. I noticed this right away: "A was never highlighted in the app. The audio panel did open…" The shortcut worked, but the app couldn't *see* it.

The fix was to stop verifying keystrokes and start verifying outcomes. Instead of asking "did they press Super + Ctrl + A?", the app watches for the audio panel surface to open. The same approach now covers windows, workspaces, menus, and panels.

### Never Touch the Learner's Windows

Some lessons launch a terminal or browser and then have you move, resize, or close it. The app must only ever act on windows *it* launched, never your real work. A code review caught a high-severity bug here early on: simply focusing an existing window could make it look tutorial-owned, which made it eligible for cleanup.

Copilot CLI redesigned ownership around a token passed to each tutorial launch, verified against the process that actually owns the window. Focusing a window no longer grants anything. If ownership can't be proven, the lesson explains how to recover instead of guessing.

### Narration That Types Along

Two guides with 16 lessons adds up to a lot of audio. At one point I asked:

> "do we have a way to sync the audio to the text? I believe that's supported by the Azure TTS. It'd be great to type the text out in sync with the audio being spoken."

It was. Copilot CLI wired up Azure Speech word-boundary events, saved timing files next to each MP3, and built caption components that reveal each word as it's spoken. If you mute audio or turn on reduced motion, captions fall back to plain text. All 394 clips have matching timings, and a validation check catches stale timing data or timings that run past the end of a recording.

## "I Need Everything Working 100%"

Unit tests only get you so far with an app like this. Early on I asked Copilot CLI to launch the app, run through the entire course automatically, record a video, and analyze each part. It produced a 148-second walkthrough and used it to fix animations and pointing problems it found along the way.

A week later I set the bar higher before going to bed:

> "go through every single lesson and each step in it one by one. Do everything it says, validate everything from the words used to the keyboard shortcuts, to the animations and character pointing. In the morning I'll check on your work. Please be very thorough and do this like a user would. I need everything working 100%."

By morning it had walked 15 lessons and 91 steps with both guides, taken screenshots, and found 15 issues. Two of them were blockers affecting 26 steps. I said "Please fix all of those," and it did, including regenerating 26 narration clips whose wording changed.

One thing I really appreciated during this stretch: Copilot CLI wouldn't just tell me what I wanted to hear. After an earlier audit it said "I wouldn't call it 100% ready yet," and explained why. That's exactly the answer I want from something I'm about to ship with.

## Real UI, Not Fake UI

The rule I kept coming back to was simple: teach people the real Omarchy, not a copy of it. Early on, one lesson popped up a full-screen dialog to choose a terminal. I stopped that immediately: "I'm not sure we want to change the interface like that - ever!"

The Capture lesson (screenshots, screen recording, text extraction, and QR codes) is where this rule got tested the most. The first version had course-owned buttons like "Select region" and "Start recording." When I noticed, I asked a simple question: "That's not real life is it?"

Copilot CLI replaced the screenshot exercise with Omarchy's native workflow. The app just watches for a new screenshot to appear. I tested the rest of the lesson later and found the recording exercise *still* had its own buttons, so I pushed harder: "I need you to be more thorough about all of this."

This time it audited Omarchy's installed commands and menus directly. Screen recording now uses Omarchy's real Capture menu (Super + Ctrl + C, Screenrecord, With no audio) and the app only observes the recording file Omarchy creates. Text extraction and QR codes use the native tools too, and you finish by pasting the result. The course never starts or stops a real recording on your behalf.

## Shipping It

I didn't want people enabling plugins or running setup scripts. My instruction for packaging was "I don't want them to enable anything. That sohould be built in." Copilot CLI built an Arch package, then a CI pipeline in GitHub Actions that runs inside an Arch Linux container as an unprivileged user, runs the Node and offscreen QML tests, builds the package with `makepkg`, and publishes checksummed releases when I push a tag.

There were five release candidates (one was broken by a race in a cancellation test) before 0.1.0 shipped on September 12th.

The website took some back and forth too. The first version had Mac-style window buttons in the corner, and I told Copilot CLI "Omarchy doesn't have that" and "I also feel like the current website is too business like. Not very fun - learning should be fun." I also pointed out that "Omarchy has a very 80s 'ascii text' type of vibe to it so we should integrate that." The final site at [learnomarchy.com](https://learnomarchy.com) leans into that pixel and terminal look, and it fits Omarchy much better. Before making the repo public, Copilot CLI scanned the files *and* the git history for anything that looked like a credential.

The biggest milestone was getting into Omarchy's official package repository. Copilot CLI studied how the repository tracks upstream releases, prepared the package definition, validated it against the edge, rc, and stable repos, and helped me open [omacom/omarchy-pkgs#435](https://github.com/omacom/omarchy-pkgs/pull/435). It merged on September 21st. New GitHub releases now become eligible for the package repository after a 24-hour waiting period, followed by the repository's normal sync and build.

One habit saved me twice: build the exact package *before* pushing a release tag. Both times it caught a stale check in the package verifier that would have failed the release.

## The Arcade (and Overcomplicating Things)

Learning shortcuts is more fun when there's a score, so one night I asked for a game:

> "I'd like you to think through a creative way we could add a fun and engaging game for people to practice Omarchy shortcuts in... addictive... always want to 'beat their last score'... Try to come up with at least 3 ideas... Go! See you in the morning."

It came up with three: Window Rescue (a simulated desktop mission), Shortcut Sprint (60-second rounds), and Keyfall (shortcuts fall toward a catch zone). Hints are allowed and wrong answers never cost points, because I didn't want practice to feel like punishment. I had Copilot CLI keep all of it on a separate branch and worktree, with its own launcher, so `main` stayed stable while we experimented.

Then it overdid it. The Arcade grew a dashboard, statistics, recommendations, and a lot of explanatory text. I told it "This looks very complex for someone just going there for the first time. I felt like it was complex myself!" Copilot agreed it had overcomplicated things, and we simplified the entry screen to one clear Start button with everything else tucked away.

A few other favorite moments from the Arcade: "The ship looks like a fish." (It did.) And after one change went badly sideways: "You totally broke it." The final Arcade PR touched 78 files with about 11,000 lines added.

## The Plot Twist at the End

On the last day, while testing the Menus and Apps lesson, I noticed something wrong. When a menu opened, Ohm-1 flew back up and pointed at the Omarchy icon in the corner instead of at the menu that had just opened.

Tracking that down turned up a much bigger problem. Omarchy 4.0.3 had restricted what third-party shell plugins can access, and Learn Omarchy's geometry plugin depended on exactly those internals. It had been quietly failing and falling back to rougher measurements. (Copilot had actually flagged the restriction days earlier, but the fallback hid the impact.) There was no supported way to measure an open menu anymore.

So we retired the plugin completely and rebuilt pointing around Omarchy's supported bar measurements and lesson estimates. Along the way Copilot CLI found a second bug: Omarchy disables animations on the bar, which makes Hyprland report the bar layer as fully transparent. Learn Omarchy had been treating the bar as hidden on stock installs, so even the supported measurements were failing.

Cleaning up the old plugin on people's machines raised a question I should probably ask more often. Copilot's first plan removed the old plugin automatically on launch, and I asked: "OK - so it's 100% safe? I just want to introduce any issues on peoples' machines." (I meant *not* introduce, but you get the idea.)

The answer was honest: "Not 100%. No change to people's machines is." It walked through what could go wrong and what protected against it. Since very few people had the old plugin installed, I chose the conservative path. Normal launches no longer run any plugin commands, and only `learn-omarchy --uninstall` removes an unchanged copy of the old plugin.

## Three Weeks by the Numbers

| | |
| --- | --- |
| Elapsed time | About three weeks (September 2 to 22) |
| Commits | 61 |
| Conversation turns | More than 600 |
| Code | About 43,000 lines of QML, TypeScript, and JavaScript (including tests) |
| Course | 16 lessons, 93 activities, 2 guides |
| Narration | 394 clips with word-synced captions |
| Tests | 553 Node tests and 447 QML tests |
| Releases | Five release candidates, then 0.1.0 through 0.2.4 |

## What I Learned

Here are my biggest takeaways from building Learn Omarchy with Copilot CLI.

- Taste is still my job. Copilot CLI wrote the code, but "too complex," "not very fun," "the ship looks like a fish," and "that's not real life" came from me. Those calls shaped the product more than any single prompt.
- Overnight runs work when you define "done." "Have it ready in the morning" worked because I also said what ready meant, and I always asked for a review or an audit when I got back.
- Make the AI use the real thing. Recorded walkthroughs, screenshots, and driving the live app caught problems that unit tests never would have.
- Screenshots beat descriptions. I pasted 24 screenshots into one session alone. "This text is cut off" plus an image is faster and more precise than a paragraph trying to explain it.
- Parallel reviews help, but they don't replace testing. Near the end, five review agents audited different parts of the codebase at the same time and found real dead code and bugs. The menu-pointing bug still took hands-on testing to find.
- Session history is a safety net. My machine locked up once and I had to reboot. I asked Copilot CLI "What was the last learn-omarchy session we were in?" and it found the session and gave me the exact `/resume` command to pick up where I left off.
- Ask whether it's safe. Once your code runs on other people's machines, the conservative option is usually the right one.

## Try It Yourself

If you're running Omarchy, update and install it:

```bash
omarchy update
omarchy pkg add learn-omarchy
```

Then press **Super + Space**, type **Learn Omarchy**, and press Enter. You can also visit [learnomarchy.com](https://learnomarchy.com) or check out the [source code on GitHub](https://github.com/DanWahlin/learn-omarchy).

Building this was a ton of fun. If you give Learn Omarchy a try, let me know what Ohm-1 gets wrong. He's still learning too.
