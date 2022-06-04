# see https://hub.docker.com/r/wolframresearch/wolframengine
# Activate Using Node-Locked Licensing
FROM wolframresearch/wolframengine:13.0

ARG WOLFRAM_MATHPASS=""
# # Install needed packages and setup non-root user. Use a separate RUN statement to add your own dependencies.
RUN mkdir ~/.WolframEngine/Licensing
RUN echo ${WOLFRAM_MATHPASS} > ~/.WolframEngine/Licensing/mathpass
