"""
    XCore

Julia port of the xAct/xCore utility layer required by xTensor and xPerm.

Only Category-A symbols (used by xTensor/xPerm) are implemented here.
Category-B symbols are aliased to Julia built-ins.
Category-C symbols (display, FoldedRule, testing framework, namespace management)
are intentionally omitted — see sxAct-8wd design notes for the full categorisation.

FoldedRule decision: SKIP.  FoldedRule and its companions (CollapseFoldedRule,
DependentRules, IndependentRules) are not referenced anywhere in xTensor or xPerm.
They are a Wolfram-specific rule-sequencing idiom with no downstream consumers in
the packages we are porting.
"""
module XCore

# ============================================================
# Exports
# ============================================================

# 1. List utilities
export JustOne, MapIfPlus

# 2. Argument guards
export SetNumberOfArguments

# 3. Options
export CheckOptions, TrueOrFalse

# 4. Symbol naming and dagger character
export SymbolJoin, NoPattern
export DaggerCharacter, HasDaggerCharacterQ, MakeDaggerSymbol

# 5. xUpvalues
export SubHead, xUpSet!, xUpSetDelayed!, xUpAppendTo!, xUpDeleteCasesTo!

# 6. Tag assignment
export xTagSet!, xTagSetDelayed!

# 7. Unevaluated append
export push_unevaluated!

# 8. Extensions system
export xTension!, MakexTensions

# 9. Expression evaluation
export xEvaluateAt, XHold

# 10. Symbol registry and validation
export ValidateSymbol, FindSymbols
export register_symbol
export xPermNames, xTensorNames, xCoreNames
export xTableauNames, xCobaNames, InvarNames, HarmonicsNames, xPertNames, SpinorsNames, EMNames
export WarningFrom, xActDirectory, xActDocDirectory

# 11. Misc
export Disclaimer

# ============================================================
# Category B: stdlib aliases (one-liners, no logic needed)
# ============================================================

# DeleteDuplicates → unique  (order-preserving, used 11× in xTensor, 2× in xPerm)
const DeleteDuplicates = unique
export DeleteDuplicates

# DuplicateFreeQ → allunique  (used 11× in xTensor, 2× in xPerm)
const DuplicateFreeQ = allunique
export DuplicateFreeQ

# ============================================================
# 1. List utilities
# ============================================================

"""
    JustOne(list)

Return the single element of a one-element collection; throw otherwise.
Used inside xTensor for pattern-match assertions.
"""
function JustOne(list)
    length(list) == 1 || error("JustOne: expected a list with one element, got $(length(list))")
    first(list)
end

"""
    MapIfPlus(f, expr)

Map `f` over a vector/tuple (multi-term, analogous to Plus-headed expr),
or apply `f` once to `expr` if it is a scalar.
"""
MapIfPlus(f, expr::Union{AbstractVector,Tuple}) = map(f, expr)
MapIfPlus(f, expr) = f(expr)

# ============================================================
# 2. Argument guards
# ============================================================

"""
    SetNumberOfArguments(f, n)

No-op compatibility shim.  Julia enforces arity through method dispatch;
wrong-arity calls produce `MethodError` automatically.  This function is
provided so that xTensor/xPerm code that calls `SetNumberOfArguments` at
load time does not error.
"""
SetNumberOfArguments(f, n) = nothing

# ============================================================
# 3. Options
# ============================================================

"""
    TrueOrFalse(x)

Return `true` if `x isa Bool`; return `false` otherwise.
"""
TrueOrFalse(::Bool) = true
TrueOrFalse(_) = false

"""
    CheckOptions(opts...)

Validate that every element (after flattening one level) is a `Pair`.
Returns a flat `Vector{Pair}` on success; throws on invalid structure.
"""
function CheckOptions(opts...)
    isempty(opts) && return Pair[]
    flat = collect(Iterators.flatten(opts))
    all(o -> o isa Pair, flat) ||
        error("CheckOptions: expected Pair rules, got: $(flat)")
    flat
end

# ============================================================
# 4. Symbol naming and dagger character
# ============================================================

"""
Global dagger character appended to daggered symbol names.
Default is the Unicode dagger `†` (U+2020), matching xCore's `\\[Dagger]`.
"""
const DaggerCharacter = Ref{String}("†")

"""
    SymbolJoin(symbols...)

Create a new `Symbol` by concatenating the string representations of all arguments.
Analogous to Mathematica `SymbolJoin`, used 21× in xTensor for composite names.
"""
SymbolJoin(symbols...) = Symbol(join(string.(symbols)))

"""
    NoPattern(expr)

Identity function.  Julia has no Pattern/Blank wrappers; this is a no-op shim
preserving call-site compatibility with xTensor code that calls `NoPattern`.
"""
NoPattern(expr) = expr

"""
    HasDaggerCharacterQ(s::Symbol) -> Bool

Return `true` if the symbol name contains `DaggerCharacter[]`.
"""
HasDaggerCharacterQ(s::Symbol) = occursin(DaggerCharacter[], string(s))

"""
    MakeDaggerSymbol(s::Symbol) -> Symbol

Toggle the dagger character:
- If present, remove it.
- If absent, insert it before the first `\$` in the name, or append it.
"""
function MakeDaggerSymbol(s::Symbol)
    name = string(s)
    dg   = DaggerCharacter[]
    if occursin(dg, name)
        Symbol(replace(name, dg => ""))
    else
        idx      = findfirst(==('$'), name)
        new_name = isnothing(idx) ? name * dg : name[1:idx-1] * dg * name[idx:end]
        Symbol(new_name)
    end
end

# ============================================================
# 5. xUpvalues
# ============================================================
#
# Mathematica upvalues attach dispatch rules to a "tag symbol" rather than to
# the function head.  Julia has no equivalent runtime mechanism.
#
# Design choice: implement as a two-level Dict keyed by (tag, property).
# This is sufficient for xTensor's usage pattern of storing per-object
# properties (indices, symmetries, metrics, …) on registered tensor symbols.
#
# Protection (Protect/Unprotect) is a no-op — Julia has no runtime symbol
# protection.  Callers that relied on protection for thread safety must add
# their own synchronisation when porting to concurrent Julia code.

const _upvalue_store = Dict{Symbol, Dict{Symbol, Any}}()

"""
    SubHead(expr) -> Symbol

Return the innermost atomic head of a nested expression.
For a bare `Symbol`, returns itself.  For an `Expr`, recurses into `expr.head`.
"""
SubHead(s::Symbol) = s
SubHead(e::Expr)   = SubHead(e.head)
SubHead(x)         = x

"""
    xUpSet!(property, tag, value)

Attach `value` as the `property` upvalue of `tag`.
Equivalent to Mathematica `xUpSet[property[tag], value]`.

Returns `value`.
"""
function xUpSet!(property::Symbol, tag::Symbol, value)
    d = get!(() -> Dict{Symbol,Any}(), _upvalue_store, tag)
    d[property] = value
    value
end

"""
    xUpSetDelayed!(property, tag, thunk)

Attach a zero-argument function `thunk` as a delayed upvalue.
Callers retrieve the value by invoking the stored thunk.
"""
function xUpSetDelayed!(property::Symbol, tag::Symbol, thunk)
    d = get!(() -> Dict{Symbol,Any}(), _upvalue_store, tag)
    d[property] = thunk
    nothing
end

"""
    xUpAppendTo!(property, tag, element)

Append `element` to the upvalue list `property[tag]`, initialising to `[]` if absent.
"""
function xUpAppendTo!(property::Symbol, tag::Symbol, element)
    d   = get!(() -> Dict{Symbol,Any}(), _upvalue_store, tag)
    lst = get!(d, property, Any[])
    push!(lst, element)
    lst
end

"""
    xUpDeleteCasesTo!(property, tag, pred)

Remove all elements satisfying `pred` from the upvalue list `property[tag]`.
"""
function xUpDeleteCasesTo!(property::Symbol, tag::Symbol, pred)
    d = get!(() -> Dict{Symbol,Any}(), _upvalue_store, tag)
    if haskey(d, property)
        filter!(x -> !pred(x), d[property])
    end
    nothing
end

# ============================================================
# 6. Tag assignment
# ============================================================
#
# Mathematica TagSet/TagSetDelayed attach rules "owned" by an arbitrary tag
# symbol.  We store these in the same _upvalue_store with a `:tag_` prefix
# on the property key, distinguishing them from plain upvalues.

"""
    xTagSet!(tag, key, value)

Assign `value` to `key` in the tag-indexed store for `tag`.
Analogous to Mathematica `xTagSet[{tag, lhs}, rhs]`.
"""
xTagSet!(tag::Symbol, key, value) = xUpSet!(Symbol(:tag_, key), tag, value)

"""
    xTagSetDelayed!(tag, key, thunk)

Delayed variant of `xTagSet!`.
"""
xTagSetDelayed!(tag::Symbol, key, thunk) = xUpSetDelayed!(Symbol(:tag_, key), tag, thunk)

# ============================================================
# 7. Unevaluated append
# ============================================================
#
# Mathematica's AppendToUnevaluated modifies OwnValues without evaluating the
# existing list elements.  Julia always evaluates eagerly; push! is equivalent.

"""
    push_unevaluated!(collection, value)

Append `value` to `collection`.  Julia evaluates eagerly so this is an alias
for `push!`; the "unevaluated" qualifier is a Mathematica artefact.
"""
const push_unevaluated! = push!

# ============================================================
# 8. Extensions system  (xTension / MakexTensions)
# ============================================================
#
# xTension registers hooks to be fired at "Beginning" or "End" of Def* commands
# (e.g. DefMetric, DefTensor).  Used 46× in xTensor.
#
# Design: keyed Dict from (defcommand::Symbol, moment::String) to hook vector.

const _xtensions = Dict{Tuple{Symbol,String}, Vector{Any}}()

"""
    xTension!(package, defcommand, moment, func)

Register `func` to be called at `moment` ("Beginning" or "End") during
execution of `defcommand`.  `package` is a string label used for grouping
(stored as metadata only; hooks fire in registration order).
"""
function xTension!(package::AbstractString, defcommand::Symbol, moment::AbstractString, func)
    moment in ("Beginning", "End") ||
        error("xTension!: moment must be \"Beginning\" or \"End\", got \"$moment\"")
    key = (defcommand, moment)
    push!(get!(() -> Any[], _xtensions, key), func)
    nothing
end

"""
    MakexTensions(defcommand, moment, args...)

Fire all hooks registered for `(defcommand, moment)` with `args...`.
"""
function MakexTensions(defcommand::Symbol, moment::AbstractString, args...)
    key = (defcommand, moment)
    for hook in get(_xtensions, key, Any[])
        hook(args...)
    end
    nothing
end

# ============================================================
# 9. Expression evaluation
# ============================================================

"""
    XHold{T}

Wrapper analogous to Mathematica's `xHold` / `HoldForm`: prevents the contained
value from being printed at high precedence.  Julia evaluates eagerly, so this
is purely a display/typing artefact.
"""
struct XHold{T}
    value::T
end
Base.show(io::IO, h::XHold) = print(io, "XHold(", h.value, ")")

"""
    xEvaluateAt(expr, positions)

No-op shim.  In Mathematica, this forces evaluation at given subexpression
positions.  Julia evaluates eagerly; there is nothing to force.
Provided for call-site compatibility.
"""
xEvaluateAt(expr, _positions) = expr

# ============================================================
# 10. Symbol registry and validation
# ============================================================

# Central registry: symbol name → owning package name.
# All packages call register_symbol() at load time to populate this.
const _symbol_registry = Dict{String, String}()

# Per-package name lists.  Populated via register_symbol(); also open for
# direct push!() by packages that manage their own registration.
const xPermNames     = String[]
const xTensorNames   = String[]
const xCoreNames     = String[]
const xTableauNames  = String[]
const xCobaNames     = String[]
const InvarNames     = String[]
const HarmonicsNames = String[]
const xPertNames     = String[]
const SpinorsNames   = String[]
const EMNames        = String[]

# Map package label → per-package list (used by register_symbol).
const _PACKAGE_LISTS = Dict{String, Vector{String}}(
    "XCore"    => xCoreNames,
    "XPerm"    => xPermNames,
    "XTensor"  => xTensorNames,
    "XTableau" => xTableauNames,
    "XCoba"    => xCobaNames,
    "Invar"    => InvarNames,
    "Harmonics"=> HarmonicsNames,
    "XPert"    => xPertNames,
    "Spinors"  => SpinorsNames,
    "EM"       => EMNames,
)

"""Current warning source label, analogous to Mathematica `\$WarningFrom`."""
const WarningFrom = Ref{String}("XCore")

"""Path to the xAct installation directory."""
const xActDirectory = Ref{String}("")

"""Path to the xAct documentation directory."""
const xActDocDirectory = Ref{String}("")

"""
    register_symbol(name, package)

Register `name` (a `Symbol` or string) as owned by `package`.

- If the name is already registered by the **same** package, the call is a
  no-op (idempotent).
- If the name is already registered by a **different** package, throws an error.
- On success, also appends `name` to the per-package name list if `package` is
  one of the known xAct package labels.
"""
function register_symbol(name::Union{Symbol, AbstractString}, package::AbstractString)
    sname = string(name)
    if haskey(_symbol_registry, sname)
        existing = _symbol_registry[sname]
        existing == package && return nothing   # idempotent
        error("register_symbol: \"$sname\" already registered by $existing")
    end
    _symbol_registry[sname] = package
    lst = get(_PACKAGE_LISTS, package, nothing)
    isnothing(lst) || push!(lst, sname)
    nothing
end

"""
    ValidateSymbol(name::Symbol)

Throw if `name` collides with any symbol already registered in the xAct
registry, or if it is exported by Julia's `Base`.  Returns `nothing` on success.

Error conditions (mirrors Mathematica `ValidateSymbol`):
- `name` is in `_symbol_registry` → already used by that package
- `name` is a `Base` export → reserved by Julia
"""
function ValidateSymbol(name::Symbol)
    sname = string(name)
    if haskey(_symbol_registry, sname)
        pkg = _symbol_registry[sname]
        error("ValidateSymbol: \"$sname\" already used by $pkg")
    end
    if isdefined(Base, name) && Base.isexported(Base, name)
        error("ValidateSymbol: \"$sname\" is a Julia Base export")
    end
    nothing
end

"""
    FindSymbols(expr) -> Vector{Symbol}

Recursively collect all `Symbol`s in `expr` (including inside `Expr` args and
collections).  Returns a deduplicated vector.
"""
FindSymbols(s::Symbol)                          = [s]
FindSymbols(e::Expr)                            = unique(vcat(FindSymbols.(e.args)...))
FindSymbols(v::Union{AbstractVector,Tuple})     = unique(vcat(FindSymbols.(v)...))
FindSymbols(_)                                  = Symbol[]

# ============================================================
# 11. Misc
# ============================================================

"""
    Disclaimer()

Print the GPL warranty disclaimer, analogous to Mathematica `Disclaimer[]`.
"""
function Disclaimer()
    println("""
    BECAUSE THE PROGRAM IS LICENSED FREE OF CHARGE, THERE IS NO WARRANTY FOR
    THE PROGRAM, TO THE EXTENT PERMITTED BY APPLICABLE LAW.  EXCEPT WHEN
    OTHERWISE STATED IN WRITING THE COPYRIGHT HOLDERS AND/OR OTHER PARTIES
    PROVIDE THE PROGRAM "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER EXPRESSED
    OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF
    MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE.
    (See the GNU General Public License for the full text.)
    """)
end

end # module XCore
