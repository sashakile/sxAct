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
    input_sha = "036b90f24a7ffbbbd35ecb9d3ebc9ead1817f26580c237386e7f3840d5fe71b8"
    julia_version = "1.12.5"
-->

<div class="markdown"><h1 id="sxAct.jl-—-Interactive-Tutorial">sxAct.jl — Interactive Tutorial</h1><p>This Pluto notebook introduces the core workflow of <code>xAct.jl</code>: manifolds, metrics, canonicalization, and curvature.</p><p>Each cell is <strong>reactive</strong> — editing a definition automatically re-evaluates all dependent cells.</p></div>

<pre class='language-julia'><code class='language-julia'>begin
    import Pkg
    Pkg.activate(joinpath(@__DIR__, "..", ".."))
    using xAct
end</code></pre>



<div class="markdown"><h2 id="1.-Define-a-Manifold">1. Define a Manifold</h2></div>

<pre class='language-julia'><code class='language-julia'>begin
    reset_state!()
    M = def_manifold!(:M, 4, [:a, :b, :c, :d, :e, :f])
end</code></pre>
<pre class="code-output documenter-example-output" id="var-M">ManifoldObj(:M, 4, [:a, :b, :c, :d, :e, :f])</pre>


<div class="markdown"><h2 id="2.-Define-a-Metric">2. Define a Metric</h2><p>Lorentzian signature <span class="tex">\((-,+,+,+)\)</span>. This automatically creates Riemann, Ricci, RicciScalar, Weyl, Einstein, and Christoffel tensors.</p></div>

<pre class='language-julia'><code class='language-julia'>g = def_metric!(-1, "g[-a,-b]", :CD)</code></pre>
<pre class="code-output documenter-example-output" id="var-g">MetricObj(:g, :M, :CD, -1)</pre>


<div class="markdown"><h2 id="3.-Canonicalization">3. Canonicalization</h2><p>The Butler-Portugal algorithm brings tensor expressions to canonical form.</p></div>

<pre class='language-julia'><code class='language-julia'>ToCanonical("g[-b,-a] - g[-a,-b]")</code></pre>
<pre class="code-output documenter-example-output" id="var-hash744834">"0"</pre>

<pre class='language-julia'><code class='language-julia'>begin
    def_tensor!(:T, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
    ToCanonical("T[-b,-a] - T[-a,-b]")
end</code></pre>
<pre class="code-output documenter-example-output" id="var-hash147095">"0"</pre>


<div class="markdown"><h2 id="4.-Contraction">4. Contraction</h2><p>Lower an index with the metric — <span class="tex">\(V_b = V^a g_{ab}\)</span>:</p></div>

<pre class='language-julia'><code class='language-julia'>begin
    def_tensor!(:V, ["a"], :M)
    Contract("V[a] * g[-a,-b]")
end</code></pre>
<pre class="code-output documenter-example-output" id="var-hash165220">"V[a]"</pre>


<div class="markdown"><h2 id="5.-Riemann-Tensor-Identities">5. Riemann Tensor Identities</h2><p>First Bianchi identity — should vanish:</p></div>

<pre class='language-julia'><code class='language-julia'>ToCanonical("RiemannCD[-a,-b,-c,-d] + RiemannCD[-a,-c,-d,-b] + RiemannCD[-a,-d,-b,-c]")</code></pre>
<pre class="code-output documenter-example-output" id="var-hash668741">"0"</pre>


<div class="markdown"><h2 id="6.-Perturbation-Theory">6. Perturbation Theory</h2><p>Perturb the metric to first order:</p></div>

<pre class='language-julia'><code class='language-julia'>begin
    def_tensor!(:h, ["-a", "-b"], :M; symmetry_str="Symmetric[{-a,-b}]")
    def_perturbation!(:h, :g, 1)
    perturb("g[-a,-b]", 1)
end</code></pre>
<pre class="code-output documenter-example-output" id="var-hash414671">"h"</pre>

<!-- PlutoStaticHTML.End -->
```
