# Inventory Locator Service

## Project Purpose

A personal inventory system for tracking workshop and household items with precise location information. The system enables:

- **Fast item entry**: Add items quickly with photos and location codes
- **Flexible search**: Find items via text search or AI-powered semantic queries
- **Location hierarchy**: Shelf → Bin structure for organized storage
- **Multi-device workflow**: Capture photos on phone, instantly sync to desktop
- **Data integrity**: Enforces constraints to prevent orphaned items and location conflicts

**Target:** Catalog 1000+ workshop items with sub-30-second add-item workflow.

**Tech Stack:**
- Phoenix with LiveView for real-time UI
- PostgreSQL with full-text search and pg_trgm for fuzzy matching
- Elixir on Erlang/OTP (see README.md for exact versions)
- Python FastAPI service (future) for AI-powered search via LangChain + VertexAI

**Key Design Decisions:**
- Multiple items per location allowed (co-location with user warnings)
- Active items must have locations; archived items keep location as "ghosts"
- String-based location entry (type "A-3" → system validates and normalizes)
- Phoenix PubSub for real-time photo sync between devices

See `docs/SPEC.md`, `docs/DESIGN.md`, and `docs/PLAN.md` for complete specifications.

---

## Coding Guidelines

### General Principles

Our code is truth. If you want to know how the system works, read the code. We keep documentation to a minimum, so that it does not become out of date.

Code should read like prose. Comments should only be used to add context, cite sources, or explain why a particular design was chosen. Comments should never explain *what* the code does.

Similarly, moduledocs and docstrings should be avoided unless ABSOLUTELY necessary. We are not creating public APIs. This is internal code. If a length explanation is necessary, then our module is probably too complex.

DO NOT use default values. This only leads to confusion and bugs.

We are building a prototype. DO NOT WORRY ABOUT BACKWARD-COMPATIBILITY. We can always make breaking changes, as we are the only users of this code at the moment.

### Elixir Style

Follow the [Elixir Style Guide](https://github.com/christopheradams/elixir_style_guide). Use `mix format` to automatically enforce most formatting rules.

**Key points beyond the formatter:**
- Group single-line function definitions together; separate multiline defs with blank lines
- Use pipe operator for function chains; avoid single-use pipes
- Pattern matching and control flow should be visually consistent
- Comments go above the code they describe, never inline explanations of *what*
- **Every function must have a @spec** - Document argument types and return types for all public and private functions
- Aliases belong at the module level
- **Never use anonymous catch-all (`_`) in case/with statements** - Use a named variable and log it: `other -> Logger.warning("Unexpected: #{inspect(other)}")`
