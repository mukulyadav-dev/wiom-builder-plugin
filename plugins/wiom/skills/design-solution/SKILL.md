---
name: design-solution
description: Wiom Builder solution design, using the Wiom Unified Design Builder (owner Ashish Agrawal). Takes a problem (or an approved problem brief id) through diagnosis, routing and conceptual design to a reviewed solution concept. Run by typing /wiom:design-solution followed by the problem, or an approved PD case id, or "continue <CD case id>".
disable-model-invocation: true
---

Start or continue a Wiom Builder solution-design case for: $ARGUMENTS

The Wiom Builder service supplies this case's instructions, case id and the local path of the design builder folder in a "Wiom Builder case" block in this session's context. Follow that block. If the block says the case cannot start, tell the builder why in one or two sentences and stop.

If no "Wiom Builder" block is present, the service did not respond or the plugin is not configured. Tell the builder in one or two plain sentences that the Wiom Builder service could not be reached, that this session is not being recorded, and that they should check their token (run /plugin, open the wiom plugin, configure) or contact Mukul. On Windows, the plugin also needs Git for Windows installed (git-scm.com), followed by a restart of Claude. Do not start designing without the service.
