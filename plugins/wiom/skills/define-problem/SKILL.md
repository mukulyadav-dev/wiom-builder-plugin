---
name: define-problem
description: Wiom Builder problem definition. Turns a concern, observation or proposed solution into an evidence-backed problem brief for review by Dhruv, Manas or Satya. Run by typing /wiom:define-problem followed by what prompted it, or "continue <case id>".
disable-model-invocation: true
---

Start or continue a Wiom Builder problem-definition case for: $ARGUMENTS

The Wiom Builder service supplies this case's instructions, case id and context pack in a "Wiom Builder case" block in this session's context. Follow that block.

If no "Wiom Builder case" block is present, the service did not respond or the plugin is not configured. Tell the builder in one or two plain sentences that the Wiom Builder service could not be reached, that this session is not being recorded, and that they should check their token (run /plugin, open the wiom plugin, configure) or contact Mukul. On Windows, the plugin also needs Git for Windows installed (git-scm.com), followed by a restart of Claude. Do not draft a brief without the service.
