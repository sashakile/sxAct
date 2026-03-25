FROM wolframresearch/wolframengine:14.3.0

USER root

RUN apt-get update && apt-get install -y \
    python3 \
    python3-pip \
    curl \
    && rm -rf /var/lib/apt/lists/*

RUN pip3 install --no-cache-dir --break-system-packages \
    flask~=3.1.0 \
    wolframclient~=1.4.0

COPY kernel_manager.py /oracle/kernel_manager.py
COPY server.py /oracle/server.py
COPY init.wl /oracle/init.wl

WORKDIR /oracle

EXPOSE 8765

CMD ["python3", "server.py"]
