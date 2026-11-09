# Nudge Agent Attention

Nudge Agent Attention lets people notice and answer interactive coding agents without leaving their current workflow. It is independent of any particular agent host, with Claude Code as the primary integration and Codex as the next integration.

## Language

**Coding Agent**:
An interactive Claude Code or Codex process working with a person on a software task.
_Avoid_: Conductor agent, bot

**Agent Connector**:
A reversible, user-wide integration installed and managed by Nudge for one Coding Agent, translating that agent's native events and responses from every local project into Nudge Agent Attention.
_Avoid_: Conductor integration, account connection

**Agent Turn**:
The work triggered by one user prompt, ending when the Coding Agent finishes its response and waits for the next prompt.
_Avoid_: session, task, prompt

**Agent Attention**:
An item a Coding Agent raises because the person should know something or provide input.
_Avoid_: Nudge, ping, generic notification

**Completion Alert**:
An Agent Attention item raised when an Agent Turn ends and the Coding Agent is ready for review or another instruction.
_Avoid_: session ended, done ping

**Question Request**:
An Agent Attention item containing one or more related questions the Coding Agent needs answered before it can continue.
_Avoid_: prompt, approval notification

**Approval Request**:
An Agent Attention item asking for explicit authorization before a Coding Agent performs a restricted action.
_Avoid_: Question Request, permission notification

**Approval Decision**:
The response to an Approval Request: allow once, allow for the current agent session, or deny. An integration may omit the session-wide choice when its Coding Agent cannot support it safely.
_Avoid_: permanent permission, Quick Answer

**Active Request**:
The single live Question Request or Approval Request currently offered through Nudge. While it is occupied, other interactive requests remain in their originating agent interfaces rather than forming a queue.
_Avoid_: inbox item, pending queue

**Active Question Set**:
An Active Request containing one or more questions that can be reviewed and revised before the set is submitted.
_Avoid_: pending queue, question backlog

**Question Step**:
One question within an Active Question Set.
_Avoid_: pending question, separate request

**Draft Answers**:
The revisable answers selected across an Active Question Set before the person submits them together to the Coding Agent.
_Avoid_: partial replies, sent answers

**Freeform Answer**:
A Draft Answer entered as text when the listed choices do not express what the person wants to say.
_Avoid_: Other option, message

**Quick Answer**:
A short response chosen in Nudge and returned to the Coding Agent that requested it.
_Avoid_: acknowledgement, reply message

**Question Handoff**:
The transfer of a live Question Request from Nudge back to its originating agent interface when the person returns there.
_Avoid_: dismiss, cancel, jump

**Jump Target**:
The exact interface containing the originating Coding Agent, such as a terminal tab, editor session, or Conductor workspace.
_Avoid_: tab, deep link

**Host Fallback**:
A jump that activates the originating host application when its exact Jump Target cannot be addressed. Its label names the app rather than promising a tab-level jump.
_Avoid_: Jump Target, broken jump
