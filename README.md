# UHCC — Annoy Me More

**Annoy Me More** is a small companion add-on for **Ultimate Hardcore Challenge UI** (UHCC). It does **not** replace UHCC: keep the main add-on installed and updated as usual. This add-on only adds **optional** rules on top of what UHCC already does.

---

## Who is it for?

Players using **UHCC** on **WoW Classic Era** who want an extra layer of “hardcore” pressure—mainly a **fatigue** system that rewards resting, sitting, eating at an inn, and pacing movement, instead of sprinting everywhere non-stop, plus an optional **drink and eat on a schedule** challenge.

You do **not** need to be technical. If you can install add-ons and open the UHCC window, you can use this one.

---

## What does it actually do?

### Fatigue (optional)

When you turn **Fatigue** on (see *How to turn it on* below), your character builds up tiredness from **running** and **walking**, and recovers when you **stand still**, **sit**, **lie down**, **eat or drink**, or rest in an **inn**—similar to the idea that you cannot go full speed forever without a break.

- A **fatigue bar** can appear on screen once you have real fatigue built up (it stays hidden while you are still in the “fresh” range).
- **Jumping** costs a little extra fatigue each time.
- **Healing** (potions, bandages, spells that actually restore health) can shave fatigue down a bit.
- If you push **too far**, you get **warnings** (screen messages) so you know to slow down and rest. The add-on also shows a small **icon** when you are in the worst “exhausted” state.

Nothing here talks to the server: it is all **local** to your game client, for your own challenge run.

### Consume now (optional)

When you turn **Consume now** on (same place as Fatigue, under **Annoy Me More**), the add-on asks you to **drink** and **eat** on a simple schedule—like remembering to stay hydrated and fed on a long journey.

**How it works, in plain words**

- **Drink:** about every **18 minutes**, you should drink for a while (see below).
- **Eat:** about every **26 minutes**, you should eat for a while.
- If you **drink or eat early** while you are still in the “safe” countdown window, that timer **starts over** from the full length again—so grabbing a sip or a bite ahead of time is rewarded.
- If the countdown **runs out**, you get a **short on-screen bar** (about half a minute) that fills up while you still have time to drink or eat without the big warning.
- If you **ignore that bar until it finishes**, you get a **red screen** and a clear message: you **must drink** and/or **must eat**, depending on which timer you let slip.
- To clear the **urgency bar** or the **red screen**, you need to **keep drinking or eating for about 10 seconds in a row** (not just one click). If the buff drops, the count starts over—same idea for both the bar phase and the red screen.

**When you log out or reload**

- Timers **pause** while you are away. When you come back, you pick up **where you left off** (time spent offline does **not** eat your countdown).
- Note: if the game **crashes** or closes without a normal logout, the add-on may not get a chance to save that “paused” snapshot; in that rare case, timers may behave like the old wall-clock style until the next clean logout.

**What the add-on looks for**

- It tries to notice drink and food buffs the way the game shows them (names and icons). Some items or buffs might not match perfectly; if something feels off, try another drink or food type and see if it registers.

### What it does *not* do

- It does **not** change UHCC’s own files.
- It does **not** remove UHCC’s “Annoy me” behaviour—it **adds** to it.
- It does **not** give you advantages; it is meant to make you **manage** your character more carefully.

---

## Requirements

1. **Ultimate Hardcore Challenge UI** must be installed (this add-on lists it as a dependency).
2. **WoW Classic Era** (interface version matches the `.toc` file, e.g. `11508`).

---

## How to turn Fatigue or Consume now on

1. Open the **UHCC** window (minimap button or your keybind).
2. Go to the **Settings** tab.
3. Turn on **Annoy me** (main UHCC option). *Options in Annoy Me More only work when “Annoy me” is on.*
4. In the same area, find the section **Annoy Me More** and check **Fatigue** and/or **Consume now**.

If you turn **Annoy me** off later, those extras turn off with it (your choices stay saved for when you turn it back on).

---

## Saving your progress

Your fatigue progress is saved **per character** so a disconnect or `/reload` does not fully reset your tiredness (within what the add-on is designed to save).

**Consume now** timers are also saved **per character**. They **freeze** when you log out or reload, so a long break away from the game does not silently push you into a punishment screen.

---

## Troubleshooting (simple)

| Problem | What to try |
|--------|-------------|
| I do not see any new options | Make sure **both** UHCC and **Annoy Me More** are enabled on the character select screen. |
| Fatigue is greyed out | Enable **Annoy me** in UHCC first, then open the settings again or reopen the UHCC window. |
| I want to stop using Fatigue | Open UHCC → Settings → **Annoy Me More** → uncheck **Fatigue**. |
| Consume now does not notice my drink/food | Try another consumable; the add-on looks for typical drink/food buff patterns. |
| The red screen will not go away | Drink or eat **continuously** for the full ~10 seconds the add-on expects; stopping early resets that short timer. |

---

## Credits & support

- **Annoy Me More** extends **Ultimate Hardcore Challenge UI**; follow that project for core challenge rules and updates.
- For issues specific to **Annoy Me More**, use the repository or contact path given by the maintainer of this add-on.
- https://github.com/JulioPotier/UhccAnnoyMeMore
- Top me golds on Kirbybank-Soulseeker ;)
---

*Play safe, rest often, and have fun on your hardcore journey.*
