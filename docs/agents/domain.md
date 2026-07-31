# Domain Docs

How the engineering skills should consume this repository's domain documentation.

## Layout

This repository uses a single-context layout:

/
├── CONTEXT.md
├── docs/
│   └── adr/
└── lib/

`CONTEXT.md` is the shared glossary and domain overview. Architectural decisions live in `docs/adr/`.

## Before exploring

- Read `CONTEXT.md` at the repository root.
- Read ADRs under `docs/adr/` that affect the area being changed.
- If these files do not exist yet, proceed silently.

The `/domain-modeling` skill creates these files lazily when terminology or architectural decisions are actually resolved.

## Use the glossary's vocabulary

When an issue title, proposal, hypothesis, test, or implementation names a domain concept, use the term defined in `CONTEXT.md`.

If a required concept is missing, reconsider whether new terminology is necessary or record the gap for `/domain-modeling`.

## Flag ADR conflicts

If proposed work contradicts an existing ADR, surface the conflict explicitly instead of silently overriding the decision.
