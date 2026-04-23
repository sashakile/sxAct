```@raw html
<style>
    #documenter-page table {
        display: table !important;
        margin: 2rem auto !important;
        border-top: 2pt solid rgba(0,0,0,0.2);
        border-bottom: 2pt solid rgba(0,0,0,0.2);
    }

    #documenter-page pre, #documenter-page div {
        margin-top: 1.4rem !important;
        margin-bottom: 1.4rem !important;
    }

    .code-output {
        padding: 0.7rem 0.5rem !important;
    }

    .admonition-body {
        padding: 0em 1.25em !important;
    }
</style>

<!-- PlutoStaticHTML.Begin -->
<!--
    # This information is used for caching.
    [PlutoStaticHTML.State]
    input_sha = "b5733c5661549418bb04fb9700d61b6cf6107e22c372719299f656e33f10713c"
    julia_version = "1.12.5"
-->

<div class="markdown"><h1 id="XAct.jl-—-Interactive-Tutorial">XAct.jl — Interactive Tutorial</h1><p>This Pluto notebook introduces the core workflow of <code>XAct.jl</code>: manifolds, metrics, canonicalization, and curvature.</p><p>Expressions are written using the <strong>typed API</strong> — <code>@indices</code> declares index objects, <code>tensor()</code> looks up handles, and <code>T[-a,-b]</code> builds expressions with slot-count and manifold validation at construction time.</p><p>Each cell is <strong>reactive</strong> — editing a definition automatically re-evaluates all dependent cells.</p></div>

<pre class='language-julia'><code class='language-julia'>begin
    import Pkg
    Pkg.activate(joinpath(@__DIR__, "..", ".."))
    using XAct
end</code></pre>



<div class="markdown"><h2 id="1.-Define-a-Manifold">1. Define a Manifold</h2></div>

<pre class='language-julia'><code class='language-julia'>begin
    reset_state!()
    M = def_manifold!(:M, 4, [:a, :b, :c, :d, :e, :f])
    @indices M a b c d e f
end</code></pre>



<div class="markdown"><h2 id="2.-Define-a-Metric">2. Define a Metric</h2><p>Lorentzian signature <span class="tex">\((-,+,+,+)\)</span>. This automatically creates Riemann, Ricci, RicciScalar, Weyl, Einstein, and Christoffel tensors.</p></div>

<pre class='language-julia'><code class='language-julia'>begin
    g = def_metric!(-1, "g[-a,-b]", :CD)
    Riem = tensor(:RiemannCD)
    Ric  = tensor(:RicciCD)
    g_h  = tensor(:g)
end</code></pre>
<pre class="code-output documenter-example-output" id="var-Ric">TensorHead(:g)</pre>


<div class="markdown"><h2 id="3.-Canonicalization">3. Canonicalization</h2><p>The Butler-Portugal algorithm brings tensor expressions to canonical form. Expressions are built with <code>[]</code> — wrong slot count or manifold raises an error immediately, before reaching the engine.</p></div>

<pre class='language-julia'><code class='language-julia'>ToCanonical(g_h[-b,-a] - g_h[-a,-b])</code></pre>
<p class="tex">$$0$$</p>

<pre class='language-julia'><code class='language-julia'>begin
    def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
    T_h = tensor(:T)
    ToCanonical(T_h[-b,-a] - T_h[-a,-b])
end</code></pre>
<p class="tex">$$0$$</p>


<div class="markdown"><h2 id="4.-Contraction">4. Contraction</h2><p>Lower an index with the metric — <span class="tex">\(V_b = V^a g_{ab}\)</span>:</p></div>

<pre class='language-julia'><code class='language-julia'>begin
    def_tensor!(:V, ["a"], :M)
    V_h = tensor(:V)
    Contract(V_h[a] * g_h[-a,-b])
end</code></pre>
<p class="tex">$$\V_{\b}$$</p>


<div class="markdown"><h2 id="5.-Riemann-Tensor-Identities">5. Riemann Tensor Identities</h2><p>The Riemann tensor satisfies well-known symmetries that the canonicalizer automatically recognizes.</p></div>

<pre class='language-julia'><code class='language-julia'># First Bianchi identity — R_{abcd} + R_{acdb} + R_{adbc} = 0
ToCanonical(Riem[-a,-b,-c,-d] + Riem[-a,-c,-d,-b] + Riem[-a,-d,-b,-c])</code></pre>
<p class="tex">$$0$$</p>

<pre class='language-julia'><code class='language-julia'># Antisymmetry in the first pair — R_{abcd} + R_{bacd} = 0
ToCanonical(Riem[-a,-b,-c,-d] + Riem[-b,-a,-c,-d])</code></pre>
<p class="tex">$$0$$</p>

<pre class='language-julia'><code class='language-julia'># Pair symmetry — R_{abcd} = R_{cdab}
ToCanonical(Riem[-a,-b,-c,-d] - Riem[-c,-d,-a,-b])</code></pre>
<p class="tex">$$0$$</p>


<div class="markdown"><h2 id="6.-Perturbation-Theory">6. Perturbation Theory</h2><p>Perturb the metric to first order:</p></div>

<pre class='language-julia'><code class='language-julia'>begin
    def_tensor!(:h, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
    def_perturbation!(:h, :g, 1)
    perturb(g_h[-a,-b], 1)
end</code></pre>
<p class="tex">$$\h$$</p>


<div class="markdown"><h2 id="7.-Validation">7. Validation</h2><p>The typed API raises errors at construction time — before the expression reaches the engine:</p></div>

<pre class='language-julia'><code class='language-julia'>try
    Riem[-a,-b]     # ERROR: RiemannCD has 4 slots, got 2
catch e
    e
end</code></pre>
<pre class="code-output documenter-example-output" id="var-hash904103">ErrorException("RiemannCD has 4 slots, got 2")</pre>

<!-- PlutoStaticHTML.End -->
```

