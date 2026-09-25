# HelpMe Reward

A deadline manager for households that hold more premium credit cards than they can track. On opening it answers one question, "what am I about to lose?", and warns before each credit lapses.

A household signs in, and the service tier keeps its cards, credits and claims ([[api]]). This directory is the product specification every implementation is written against. See [[domain]] for the concepts, [[reminders]] for the part that is the product, [[design]] for how it looks and behaves, and [[tests]] for what the suites pin. The frozen reference implementation is the [[pwa]].

## The household premise

The hard case is not two different cards with clashing offers. It is the same card held twice: two Platinums in one household means every credit exists twice, and one booking cannot draw on both.

So the app is a *household* deadline manager. Cards belong to people (`Card.holder`), and credits are matched across them by [[domain#Overlaps]]. The holder is asked for at add time rather than inferred, because telling two identical Platinums apart is the whole point.

## Three distinctions that drive everything

Most of the design decisions in the domain layer trace back to one of these three.

- **Cycles are calendar objects.** A monthly credit is "September", not "the last 30 days", and a Sapphire Reserve travel credit runs on the cardmember year. The anchor is recorded per credit, never guessed from the cadence. See [[domain#Benefit#Cycle anchors]].
- **Locked is not unclaimed.** A credit behind an unticked enrolment box is money you *cannot* spend, not money you are failing to spend. It is counted separately and never dunned. See [[domain#Status ladder#Locked is not unclaimed]].
- **Partial use is normal.** $40 of a $100 dining credit is the common case. An app that only offers a tick mark trains people to lie to it. See [[domain#Claims]].
