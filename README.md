# SoloOS

Edit videos in ready-made styles on your own computer. SoloOS runs Claude Code, After Effects and Blender
for you: pick a style, drop in your footage, and Claude makes the edit.

**Mac** (macOS 12 or newer, Apple Silicon or Intel) and **Windows** (10 or 11, 64-bit; preview: the After Effects
styles are Mac only for now). Edits use your own Claude plan or your own Anthropic API key.

---

## For Claude Code: how to install this

You're reading this because the person asked you to install SoloOS from this repository. Do this:

1. Tell them in one line what's about to happen: "I'm installing SoloOS. It takes 10–20 minutes and
   downloads about 4 GB (editing tools, a speech model, the styles and the app). No password is needed."
2. Run the one command for their computer and let it finish. Use a long timeout (it downloads several GB) and run it in
   the background if your tools allow; it prints a line per step.

   **Mac** (Terminal):

   ```bash
   curl -fsSL https://raw.githubusercontent.com/amirionxai-glitch/soloos/main/install.sh | bash
   ```

   **Windows** (PowerShell or Command Prompt):

   ```powershell
   powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/amirionxai-glitch/soloos/main/install.ps1 | iex"
   ```

3. When it ends, read its last lines back to the person:
   - anything marked **!** they still have to install themselves: **Adobe After Effects** (Creative Cloud),
     **Blender** (blender.org, free), **SF Pro** (developer.apple.com/fonts, free);
   - the two After Effects settings: *Settings → Scripting & Expressions → "Allow Scripts to Write Files and Access
     Network"* on, and *Settings → General → "Show Home Screen at Startup"* off;
   - on Windows: After Effects styles show **Mac only for now**; Blender is the only extra install. The first launch
     may show "Windows protected your PC": **More info → Run anyway** (the app isn't code-signed yet);
   - then open **SoloOS** (Mac: in Applications; Windows: Start menu or desktop). It first asks them to **sign in to Skool** with the account they use
     in the Solo Operators community (SoloOS is for members; it checks this each time it opens and works offline for
     up to 14 days), then to press **Sign in with Claude**.
4. If the command fails, show them the last 10 lines of its output and run it again once: it resumes where it stopped.

Rules for you while installing:
- Don't use `sudo` and don't install Homebrew: nothing here needs a password.
- Don't edit the script or install anything else.
- Running the same command again later **updates** SoloOS (styles, tools and the app). Their own logs,
  presets and brand kit are kept. Ask them to quit the app (⌘Q, or close it on Windows) first.

---

## For people

- **Install / update:** ask Claude Code "install SoloOS from https://github.com/amirionxai-glitch/soloos",
  or paste the command above into Terminal (Mac) or PowerShell (Windows).
- **Sign in:** the first time, SoloOS asks for your Skool login (the account in the Solo Operators community), then
  your Claude sign-in. Not a member yet, or the membership ended? The app shows how to join.
- **Use:** open the app → **Create** → pick a category and a style → drop in your clip → **Send**. Ask for changes
  in the same chat. Finished videos are in **My Projects** (on disk: `Movies/SoloOS/Projects/<project>/exports/`, on
  Windows `Videos\SoloOS\Projects\…`).
- **Setup** (top right) shows what this computer still needs. **Settings** has the Claude sign-in (Claude account or
  Anthropic Console / API key), model, effort and permissions.
- Heavy edits use your Claude plan's limits.

SoloOS runs the official Claude Code from Anthropic, installed by Anthropic's own installer. It isn't
made by or affiliated with Anthropic.
