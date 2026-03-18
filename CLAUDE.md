# sxAct Claude Instructions

## Development Workflow

- **CRITICAL: follow TDD and Tidy First** for all implementation tasks.
    - **TDD (Test-Driven Development):** Write the test case *before* the implementation code. Ensure it fails first, then implement the fix/feature.
    - **Tidy First:** Before adding new functionality, perform any necessary cleanup or refactoring of the surrounding code to make the new change easier to implement and maintain.

## Commands

Always use `uv` to run Python tools:

```
uv run pytest tests/ ...
uv run python ...
```

Never invoke `.venv/bin/python` or `python` directly.
