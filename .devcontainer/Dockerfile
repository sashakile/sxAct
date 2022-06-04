# see https://hub.docker.com/r/wolframresearch/wolframengine
# Activate Using Node-Locked Licensing
FROM wolframresearch/wolframengine:13.0

ARG WOLFRAM_MATHPASS=""
# # Install needed packages and setup non-root user. Use a separate RUN statement to add your own dependencies.
USER root
RUN mkdir -p ~/.WolframEngine/Licensing
RUN echo -e ${WOLFRAM_MATHPASS} > ~/.WolframEngine/Licensing/mathpass


# from https://github.com/WolframResearch/AWSLambda-WolframLanguage/blob/c85d96b8625c5935b3bffe094cc456fd0b477ab2/Dockerfile#L5

# temporary workaround for bug(413167)
RUN apt-get update -y && \
    apt-get install -y libglib2.0-0
