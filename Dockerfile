FROM summerwind/actions-runner:latest

ARG BUILDX_VERSION=v0.8.2
ARG DOCKER_COMPOSE_VERSION=v2.6.0

# Docker Plugins
RUN mkdir -p "${HOME}/.docker/cli-plugins" \
  && curl -SsL "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-amd64" -o "${HOME}/.docker/cli-plugins/docker-buildx" \
  && curl -SsL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" -o "${HOME}/.docker/cli-plugins/docker-compose" \
  && chmod +x "${HOME}/.docker/cli-plugins/docker-buildx" \
  && chmod +x "${HOME}/.docker/cli-plugins/docker-compose"
