# sxAct — xAct Migration & Implementation
# Copyright (C) 2026 sxAct Contributors
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

"""
    xAct

The primary entry point for the Julia port of the xAct suite.
Bundles XCore, XPerm, and XTensor into a unified namespace.
"""
module xAct

using Reexport

include("Validation.jl")
include("XCore.jl")
include("XTensor.jl") # XTensor includes XPerm
include("XInvar.jl")
include("TExpr.jl")

export XCore, XTensor, XPerm, XInvar, reset_state!

@reexport using .XCore
@reexport using .XTensor
@reexport using .XTensor.XPerm
@reexport using .XInvar
@reexport using .TExprLayer

# Wire XCore symbol validation into XTensor's def_*! functions
XTensor.set_symbol_hooks!(XCore.ValidateSymbol, XCore.register_symbol)

"""
    reset_state!()

Perform a global reset of all xAct subcomponents (XCore, XPerm, XTensor).
"""
function reset_state!()
    XCore.reset_core!()
    XTensor.reset_state!()
    XInvar._reset_invar_db!()
end

end # module xAct
