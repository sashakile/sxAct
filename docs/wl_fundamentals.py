# To add a new cell, type '# %%'
# To add a new markdown cell, type '# %% [markdown]'
# %%
from wolframclient.evaluation import WolframLanguageSession
from wolframclient.language import expression, wl, wlexpr

session = WolframLanguageSession()
basePath = "C:\\Program Files\\Wolfram Research\\Wolfram Engine\\12.1\\AddOns\\Applications\\"


# %%
session.evaluate(wl.FullForm("{a,b,c}"))


# %%
session.evaluate("FullForm[a+b+c]")


# %%
session.evaluate("?Apply").args[0]


# %%
session.evaluate("FullForm[a+b+c]")


# %%
session.evaluate("Plus[a,b,c]")


# %%
session.evaluate("FullForm[{a,b,c}]")


# %%
session.evaluate("List[a,b,c]")


# %%
session.evaluate("Apply[Plus,{a,b,c}]")


# %%
session.evaluate("Trace[Apply[Plus,{a,b,c}]]")


# %%
session.evaluate("Apply[List,a+b+c]")


# %%
session.evaluate("Apply[List,1+2+3]")

# %% [markdown]
# ### Non-atomic expressions

# %%
session.evaluate("Part[{a,7,c},1]")


# %%
# Part 0 is the head of the expression
session.evaluate("Part[{a,7,c},0]")


# %%



