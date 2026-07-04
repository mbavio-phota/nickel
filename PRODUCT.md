# Product

## Register

product

## Users

Developers who run fleets of coding agents through Conductor on their Mac and want to
check in from their phone: on the couch, in transit, between meetings. They are experts
in their tools (Linear, GitHub, terminal editors) and in a monitoring mindset — glance,
nudge, unblock, move on. Sessions are short and frequent.

## Product Purpose

Nickel is the companion app to Conductor (conductor.build): browse projects,
manage cloud workspaces, and chat with running coding-agent sessions via the public API.
Success is a user who *enjoys* opening the app for a 30-second check-in — it should feel
like visiting your agents, not like reading a server dashboard.

## Brand Personality

Playful precision. Three words: **lush, precise, alive**. The shell is expressive and
fun (generated gradient covers, floating pill actions, warm copy) — inspired by
Hypelist's trick of keeping chrome neutral while content carries the color. The content
layer stays developer-tool calm: SF Mono for identifiers, exact status semantics, quiet
chat. Delight lives in navigation and headers; never in the transcript.

## Anti-references

- Server-admin gray: stock grouped lists, bare disclosure rows, dashboard sameness.
- Loud SaaS: gradient text, hero metrics, confetti, decorative motion in the work area.
- Fake social app: no likes, avatars, or engagement mechanics — the fun is visual, not
  behavioral.

## Design Principles

1. **Content wears the color, chrome stays quiet.** Generated cover art (seeded per
   project/workspace) does the emotional work; controls stay neutral + one orange.
2. **Glanceable state first.** Status (ready/working/error) must be readable in under a
   second from any screen — chips with dots and words, never buried.
3. **The chat is a workbench.** Transcript, composer, and JSON chips stay calm, dense,
   and precise. No decoration where the user reads agent output.
4. **Identifiers are sacred.** Branch names, models, remotes, IDs are always SF Mono,
   always truthful, never truncated into ambiguity.
5. **Warmth in the words.** Empty states and system moments get personality (the demo
   world is Matrix lore for a reason); errors stay direct and actionable.

## Accessibility & Inclusion

- Dynamic Type respected on all text; layouts scroll rather than clip.
- Overlaid text on cover art always sits on a dark scrim (≥4.5:1 for body, ≥3:1 large).
- Status never conveyed by color alone — every dot ships with a text label.
- Reduce Motion disables the status pulse and press-scale effects.
- All tap targets ≥44pt; custom cards keep accessibility labels equivalent to old rows.
