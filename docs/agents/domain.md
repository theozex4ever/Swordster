# Domain docs

Swordster is a single-context project: `GLOSSARY.md` at the repository root
defines domain vocabulary, and `docs/adr/` records architectural decisions.

Before exploring domain behavior, read the glossary. Before proposing or making
a change, read ADRs relevant to that area. Use the glossary's canonical terms in
specs, ticket titles, code discussions and tests.

If a proposal conflicts with an ADR, identify the conflict and its reason
explicitly. Resolve new terminology through domain-modeling; keep the glossary
limited to domain definitions and record implementation decisions separately.

If a referenced domain document is absent, proceed with available context.
Create glossary entries and ADRs lazily when terms or decisions are resolved.
