# Resources for Wolfram Language Client

[Wolfram Client Library for Python (Video)](https://www.youtube.com/watch?v=YXGyrkKQuVo)


- Understand `wl` object factory and how it's used to represent Wolfram Language expressions in python

- Understand `wl.function` objects 


To get the help on an expression use a `?` in front of the expression.
`?xTest`

Inspecting any `wl` expression one can see that it's just a class with two attributes: `head` and `args`, very similar to Julia expressions.

Very interesting intro to WL [Professor Richard J. Gaylord's Wolfram Language Fundamentals Part One (Video)](https://www.youtube.com/watch?v=H-rnezxOCA8) and it's [notebook](https://library.wolfram.com/infocenter/MathSource/5216)

So in WL the expressions are formed like

`head[arg1, arg2, ...,argn]`

