# Wiom Builder plugin

Claude Code marketplace `wiom-builder` with one plugin, `wiom`. It holds only the plugin plumbing (a skill, hooks and an MCP connector). Instructions and context are served by the Wiom Builder service, so nothing here is Wiom-specific content.

## Install (builders)
1. Install Claude Code (Desktop app or terminal) and sign in with your Claude Pro/Max account. Windows: also install Git for Windows.
2. In Claude Code: `/plugin marketplace add wiom-tech/wiom-builder-plugin`, then `/plugin install wiom@wiom-builder`, and paste your token when asked.
3. Run `/wiom:define-problem <what prompted this>`. To continue a case: `/wiom:define-problem continue PD-…`.

## Privacy
Only sessions where you typed a `/wiom:*` command are sent to the Wiom Builder service, from the command onward. Every other Claude Code session stays on your computer.
