# Validation functions for Julia-side input defense.
# Called from XPerm, XTensor, and XInvar entry points.

"""
    validate_identifier(name; context="") → Symbol

Validate that `name` is a safe ASCII identifier: `[A-Za-z_][A-Za-z0-9_]*`.
Returns the name as a Symbol on success; throws `ArgumentError` otherwise.
"""
function validate_identifier(name::Union{Symbol,AbstractString}; context::String="")::Symbol
    s = string(name)
    ctx = isempty(context) ? "" : " in $context"
    if !occursin(r"^[A-Za-z_][A-Za-z0-9_]*$", s)
        throw(
            ArgumentError("Invalid identifier '$s'$ctx: must match [A-Za-z_][A-Za-z0-9_]*")
        )
    end
    return Symbol(s)
end

"""
    validate_perm(p; context="permutation") → nothing

Validate that `p` is a well-formed permutation: elements in 1:n with no duplicates.
"""
function validate_perm(p::Vector{Int}; context::String="permutation")
    n = length(p)
    seen = falses(n)
    for x in p
        (1 <= x <= n) || throw(ArgumentError("$context: element $x out of range 1:$n"))
        seen[x] && throw(ArgumentError("$context: duplicate element $x"))
        seen[x] = true
    end
    return nothing
end

"""
    validate_disjoint_cycles(cycles) → nothing

Validate that no element appears in more than one cycle.
"""
function validate_disjoint_cycles(cycles::AbstractVector{<:AbstractVector{<:Integer}})
    seen = Set{Int}()
    for cyc in cycles
        for x in cyc
            x in seen &&
                throw(ArgumentError("Cycles: element $x appears in multiple cycles"))
            push!(seen, x)
        end
    end
    return nothing
end

"""
    validate_order(order; context="perturbation order") → nothing

Validate that a perturbation order is >= 1.
"""
function validate_order(order::Int; context::String="perturbation order")
    order >= 1 || throw(ArgumentError("$context must be >= 1, got $order"))
    return nothing
end

"""
    validate_deriv_orders(deriv_orders) → nothing

Validate that derivative orders are non-negative and sorted non-decreasing.
"""
function validate_deriv_orders(deriv_orders::Vector{Int})
    for (i, d) in enumerate(deriv_orders)
        d >= 0 || throw(
            ArgumentError(
                "deriv_orders: element at position $i is $d (must be non-negative)"
            ),
        )
        if i > 1 && d < deriv_orders[i - 1]
            throw(
                ArgumentError(
                    "deriv_orders: not sorted — element $d at position $i " *
                    "is less than $(deriv_orders[i-1]) at position $(i-1)",
                ),
            )
        end
    end
    return nothing
end
