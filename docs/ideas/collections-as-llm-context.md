# Idea: Collections as design context for LLMs

**Status:** Back burner — parked for later. Not building this now.
**Captured:** 2026-06-17

## The one-liner

Let a Muse collection become *feedstock for an LLM* — share it (or expose it over MCP)
so an AI can study the collection and generate or iterate on brands, UIs, looks &
feels, and motion, using the saved work as the reference.

## Why this matters

Today a collection is a place to *look*. This turns it into a place to *make from*.
The images, AI descriptions, palettes, and vibe of a collection become a brief the
LLM can read — so instead of describing a style in words, you hand it the moodboard
and say "make me this, but for X."

## What it could do

- **Share a collection → LLM** : export a collection in a form an LLM can ingest
  (images + the AI descriptions we already generate + palettes + any notes).
- **MCP server for Muse** : expose collections through an MCP tool so any agent
  (Claude, etc.) can browse a user's collections and pull one in as context.
- **Generate from a collection** :
  - a **brand** (logo direction, palette, type, tone)
  - a **UI / screen design** in that style
  - a **look & feel** spec / design language
  - **motion** direction (pacing, easing, character of animation)
- **Iterate** : "same vibe, but warmer" / "take this collection and push it editorial."
- Use a collection as a **few-shot example set** — show, don't tell.

## How it leans on what we already have

- AI image descriptions (Supabase Edge Function + Haiku) — already the per-image
  "what this is" layer an LLM would read.
- Collections / gallery — the grouping unit we'd share.
- Share extension inbox — proves the plumbing for moving content in/out.
- (Future) palette extraction would make the context even richer.

## Open questions for later

- What's the shareable format? (bundle of images + structured JSON of descriptions/palettes?)
- MCP server: separate service, or built on the existing Supabase backend?
- Privacy: collections are personal — sharing to an LLM needs an explicit, clear action.
- Output destination: does generated design land back in Muse, in Figma, or just as a brief?

## Next step when we revisit

Pick the smallest version that's real: probably "export one collection as an LLM-readable
brief" before building a full MCP server.
