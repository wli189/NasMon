# Domain Docs

This repo uses a **single-context** layout. All domain documentation, context, and architectural decisions are at the root or in a central directory.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root (if it exists). This provides the high-level overview of the NasMon iOS app.
- **`docs/adr/`** — contains Architecture Decision Records relevant to the entire project.

If any of these files don't exist, **proceed silently**. Don't flag their absence. The engineering skills will create or update them lazily as necessary during work.

## File structure

```
/
├── CONTEXT.md              ← High-level app overview (optional but recommended)
├── docs/adr/               ← Architecture Decision Records
│   └── 0001-initial-project-setup.md
├── NasMon/                 ← iOS App target
├── NasMonTests/
└── NasMonUITests/
```

## Use the glossary's vocabulary

When your output names a domain concept (e.g., "NAS", "Device", "Metric"), use the term as defined in `CONTEXT.md` if present. Don't drift to synonyms the project explicitly avoids.
