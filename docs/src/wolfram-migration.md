# Migrate a Wolfram xAct workflow to XAct.jl

!!! info "LLM TL;DR"
    - Use `uv run xact-test translate` to convert Wolfram xAct expressions into Julia, Python, TOML, or JSON
    - Use `uv run xact-test repl` for interactive translation
    - This page is the migration workflow guide
    - For command mappings and function tables, use [Wolfram Translation Reference](wolfram-translation-reference.md)

This guide shows how to move an existing Wolfram xAct workflow into the XAct.jl ecosystem. You should already have completed [Installation](installation.md) and have a Wolfram expression, notebook, or `.wl` file ready to translate.

## Choose the migration mode

Use the mode that matches your starting point:

| Starting point | Best tool |
| :--- | :--- |
| One or two expressions | `uv run xact-test translate -e ...` |
| A whole `.wl` file | `uv run xact-test translate --file ...` |
| Interactive exploration | `uv run xact-test repl` |
| Need function mappings first | [Wolfram Translation Reference](wolfram-translation-reference.md) |

## Translate a single Wolfram expression

Use `translate -e` when you want a quick, explicit conversion.

```bash
uv run xact-test translate -e 'DefManifold[M, 4, {a, b, c, d}]' --to julia
```

Expected output:

```julia
XAct.def_manifold!(:M, 4, [:a, :b, :c, :d])
```

You can switch the output format with `--to json`, `--to python`, or `--to toml`.

## Translate a short Wolfram session

Separate expressions with semicolons when you want a small script translated in one shot.

```bash
uv run xact-test translate -e \
  'DefManifold[M, 4, {a,b,c,d}]; DefMetric[-1, g[-a,-b], CD]; ToCanonical[g[-b,-a]]' \
  --to julia
```

This is the fastest way to bootstrap a REPL session or draft Julia script.

## Translate an existing `.wl` file

Use `--file` when your Wolfram source is already in a notebook export or script.

```bash
uv run xact-test translate --file my_notebook.wl --to julia > my_notebook.jl
```

Wolfram comments `(* ... *)` are stripped automatically.
For multiline material, `--file` is usually easier than `-e` because it avoids shell quoting problems.

## Use the interactive migration REPL

The REPL is the best fit when you want to translate and inspect results incrementally.

```bash
# Parse, translate, and execute in Julia
uv run xact-test repl

# Translate only
uv run xact-test repl --no-eval
```

In translate-only mode, each input shows the Julia form that would be emitted.
In full mode, the translated expression is also evaluated.

## Verify the translated result in Julia

After translation, run the result in a clean Julia session and compare the outcome you expect.

```julia
using XAct
reset_state!()

M = def_manifold!(:M, 4, [:a, :b, :c, :d])
def_metric!(-1, "g[-a,-b]", :CD)
ToCanonical("g[-b,-a]")
```

For larger migrations, translate first, then normalize the generated code into a repeatable Julia script or TOML test file.

## Turn the migration into a regression test

If the migrated expression matters for future work, convert it into TOML and run it through the verification layer.

```bash
uv run xact-test translate -e \
  'DefManifold[M, 4, {a,b,c,d}]; DefMetric[-1, g[-a,-b], CD]; ToCanonical[g[-b,-a]]' \
  --to toml
```

Then run the resulting test file with the verification tooling.
This gives you a reproducible parity check instead of a one-off migration.

## Troubleshoot common migration failures

| Symptom | Likely cause | Fix |
| :--- | :--- | :--- |
| Translator warns about an unrecognized function | The function is not yet mapped or uses a different accepted name | Check [Wolfram Translation Reference](wolfram-translation-reference.md) and adjust the input |
| Output uses string expressions where you expected typed ones | The translator targets broadly compatible API forms | Accept the translated output first, then refactor to typed API manually if desired |
| Shell quoting becomes painful | Multiline or heavily nested Wolfram input | Put the source in a `.wl` file and use `--file` |
| Translation succeeds but runtime evaluation fails | The translated code still needs setup or ordering fixes | Run in a clean session with `reset_state!()` and add missing definitions |
| You only need a lookup table, not a workflow | Wrong document | Use [Wolfram Translation Reference](wolfram-translation-reference.md) |

## Keep the roles of the migration docs separate

Use this page for the migration procedure.
Use [Wolfram Translation Reference](wolfram-translation-reference.md) for supported function mappings, naming differences, and quick Wolfram-to-Julia lookup.
Use [Getting Started](getting-started.md) if you are learning the Julia or Python APIs from scratch rather than porting existing Wolfram material.

## Continue after the first successful translation

- Learn the native API in [Getting Started](getting-started.md)
- Practice with the [Basics tutorial](examples/basics.md)
- Look up function mappings in [Wolfram Translation Reference](wolfram-translation-reference.md)
- Review implementation status in [Feature Matrix](status.md)
