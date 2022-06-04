# see https://hub.docker.com/r/wolframresearch/wolframengine
# Activate Using Node-Locked Licensing
FROM wolframresearch/wolframengine:13.0

ARG WOLFRAM_MATHPASS=""
# # Install needed packages and setup non-root user. Use a separate RUN statement to add your own dependencies.
RUN mkdir ~/.WolframEngine/Licensing
RUN echo ${WOLFRAM_MATHPASS} > ~/.WolframEngine/Licensing/mathpass


# from https://github.com/WolframResearch/AWSLambda-WolframLanguage/blob/c85d96b8625c5935b3bffe094cc456fd0b477ab2/Dockerfile#L5
USER root

# temporary workaround for bug(413167)
RUN apt-get update -y && \
    apt-get install -y libglib2.0-0
