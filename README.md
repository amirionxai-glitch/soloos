# SoloOS

Edit videos in ready-made styles on your own Mac. SoloOS runs Claude Code, After Effects and Blender
for you: pick a style, drop in your footage, and Claude makes the edit.

**Mac only** (macOS 12 or newer, Apple Silicon or Intel). Edits use your own Claude plan or your own Anthropic API key.

---

## For Claude Code: how to install this

You're reading this because the person asked you to install SoloOS from this repository. Do this:

1. Tell them in one line what's about to happen: "I'm installing SoloOS. It takes 10–20 minutes and
   downloads about 4 GB (editing tools, a speech model, the styles and the app). No password is needed."
2. Run this one command and let it finish. Use a long timeout (it downloads several GB) and run it in the background
   if your tools allow; it prints a line per step:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/amirionxai-glitch/soloos/main/install.sh | bash
   ```

3. When it ends, read its last lines back to the person:
   - anything marked **!** they still have to install themselves: **Adobe After Effects** (Creative Cloud),
     **Blender** (blender.org, free), **SF Pro** (developer.apple.com/fonts, free);
   - the two After Effects settings: *Settings → Scripting & Expressions → "Allow Scripts to Write Files and Access
     Network"* on, and *Settings → General → "Show Home Screen at Startup"* off;
   - then open **SoloOS** (in Applications) and press **Sign in with Claude**.
4. If the command fails, show them the last 10 lines of its output and run it again once: it resumes where it stopped.

Rules for you while installing:
- Don't use `sudo` and don't install Homebrew: nothing here needs a password.
- Don't edit the script or install anything else.
- Running the same command again later **updates** SoloOS (styles, tools and the app). Their own logs,
  presets and brand kit are kept. Ask them to quit the app (⌘Q) first.

---

## For people

- **Install / update:** ask Claude Code "install SoloOS from https://github.com/amirionxai-glitch/soloos",
  or paste the command above into Terminal.
- **Use:** open the app → pick a style → **Copy for Claude** → drop your clip into the Claude panel → **Send**. Ask
  for changes in the same panel. Finished videos are in `Documents/SOS/<project>/out/`.
- **Setup** (top right) shows what this Mac still needs. **Settings** has the Claude sign-in (Claude account or
  Anthropic Console / API key), model, effort and permissions.
- Heavy edits use your Claude plan's limits.

SoloOS runs the official Claude Code from Anthropic, installed by Anthropic's own installer. It isn't
made by or affiliated with Anthropic.
