# spec

SoT: `notes/specs/` = live log of USER desires + instructions (wants · features · ideas · decisions).

Missing dir → create `notes/specs/`.

## write — same turn, before code

On any USER:

- feature / spec / desire / idea / design instruction
- plan change / refine / drop / reject / postpone
- decision (incl. answers to agent Qs)
- accepted agent proposal

→ refactor `notes/specs/` into spec docs. Even if USER only said “implement”.

## how

- doc per topic / feature: `notes/specs/<topic>.md`
- new area → new doc
- structure no longer matches USER intent → split · merge · rename · move
- each doc = **current desired state** for that topic
- together = every still-active USER desire + instruction
- latest USER statement wins
- superseded text → **delete** (not strike, not “was X now Y”)
- dropped feature → **delete the doc** (or its section)
- only USER-originated + USER-accepted
- USER silence ≠ accept
- ❌ changelog · dates · history · impl USER did not decide · agent guesses
- ❌ one monolith file

## commit

`notes/specs/` is tracked → commit spec changes with the code they describe. Each agent's branch carries its version of the spec; merge specs like code.

## read

Before plan / implement / review vs wants → read every doc in `notes/specs/`.
