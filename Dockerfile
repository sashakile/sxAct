# Multi-stage Dockerfile for XAct.jl Binder / standalone Jupyter image.
#
# Stage 1 (builder): install Julia packages and precompile XAct so the
#   compiled cache is baked in. This stage is fat — we strip it down next.
#
# Stage 2 (final): debian:bookworm-slim + copied Julia binary + depot.
#   test/ docs/ .git/ inside depot packages are removed to save ~100 MB.
#
# Target compressed size: ~1.0–1.3 GB
# Julia version: 1.10 (matches Project.toml compat and juliapkg.json)

# ── builder ────────────────────────────────────────────────────────────────────
FROM julia:1.10 AS builder

# System deps needed for Python / Jupyter build step
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-pip python3-venv \
        curl ca-certificates git \
    && rm -rf /var/lib/apt/lists/*

# Install uv for fast Python package management
RUN curl -Ls https://astral.sh/uv/install.sh | sh
ENV PATH="/root/.cargo/bin:/root/.local/bin:$PATH"

# Install Jupyter + IJulia kernel dependencies into a system venv
RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"
RUN pip install --no-cache-dir \
        jupyterlab==4.* \
        notebook==7.* \
        jupytext \
        xact

# Install Julia packages and precompile in the builder depot
ENV JULIA_DEPOT_PATH="/opt/julia-depot"
ENV JULIA_PKG_PRECOMPILE_AUTO=1

# Instantiate XAct.jl and all its dependencies from the General registry,
# then warm the compiled cache so Binder sessions start in seconds.
RUN julia --project=/opt/julia-depot -e 'using Pkg; Pkg.add(["XAct", "IJulia", "Plots"]); Pkg.precompile(); using XAct; println("XAct loaded OK, version: ", pkgversion(XAct))'

# Register the IJulia kernel so Jupyter can find it
RUN julia -e 'using IJulia; IJulia.installkernel("Julia", "--project=/opt/julia-depot")'

# Strip test/, docs/, .git/ from pre-installed depot packages to save space
RUN find /opt/julia-depot/packages -mindepth 4 -maxdepth 4 \
        \( -name "test" -o -name "docs" -o -name ".git" \) \
        -type d -exec rm -rf {} + 2>/dev/null; \
    find /opt/julia-depot/packages -name "*.md" -o -name "*.rst" | xargs rm -f 2>/dev/null; \
    echo "Depot stripped."

# ── final ──────────────────────────────────────────────────────────────────────
FROM debian:bookworm-slim AS final

# System runtime deps (no build tools)
RUN apt-get update && apt-get install -y --no-install-recommends \
        python3 python3-venv \
        libgfortran5 libgomp1 libatomic1 \
        curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Copy Julia binary from the official julia image (same version as builder)
COPY --from=julia:1.10 /usr/local/julia /usr/local/julia
ENV PATH="/usr/local/julia/bin:$PATH"

# Copy the precompiled depot from builder
COPY --from=builder /opt/julia-depot /opt/julia-depot
ENV JULIA_DEPOT_PATH="/opt/julia-depot"

# Copy the Python venv (Jupyter + xact-py + IJulia)
COPY --from=builder /opt/venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH"

# Non-root user for Binder / security
RUN useradd --create-home --shell /bin/bash jovyan
USER jovyan
WORKDIR /home/jovyan

# Copy notebooks so users have examples ready to run
COPY --chown=jovyan:jovyan notebooks/ /home/jovyan/notebooks/

# Expose Jupyter port
EXPOSE 8888

# Default: launch JupyterLab (Binder overrides this via its own mechanism)
CMD ["jupyter", "lab", \
     "--ip=0.0.0.0", \
     "--port=8888", \
     "--no-browser", \
     "--NotebookApp.token=''", \
     "--NotebookApp.password=''"]
