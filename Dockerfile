FROM docker.io/library/golang:1.20-buster as golang

FROM ubuntu:22.04

ARG TARGETPLATFORM
ARG RUNNER_VERSION=2.313.0
ARG RUNNER_CONTAINER_HOOKS_VERSION=v0.5.1
ARG DOCKER_CHANNEL=stable
ARG DOCKER_VERSION=20.10.17
ARG DUMB_INIT_VERSION=1.2.5
ARG BUILDX_VERSION=v0.12.1
ARG DOCKER_COMPOSE_VERSION=v2.24.6

RUN test -n "$TARGETPLATFORM" || (echo "TARGETPLATFORM must be set" && false)

ENV DEBIAN_FRONTEND=noninteractive
RUN apt update -y \
    && apt-get install -y software-properties-common \
    && add-apt-repository -y ppa:git-core/ppa \
    && apt-get update -y \
    && apt-get install -y --no-install-recommends \
    build-essential \
    curl \
    ca-certificates \
    dnsutils \
    ftp \
    git \
    iproute2 \
    iputils-ping \
    jq \
    libunwind8 \
    locales \
    netcat \
    openssh-client \
    parallel \
    python3-pip \
    rsync \
    shellcheck \
    sudo \
    telnet \
    time \
    tzdata \
    unzip \
    upx \
    wget \
    zip \
    zstd \
    libsodium-dev \
    libaio-dev \
    && ln -sf /usr/bin/python3 /usr/bin/python \
    && ln -sf /usr/bin/pip3 /usr/bin/pip \
    && rm -rf /var/lib/apt/lists/*

# arch command on OS X reports "i386" for Intel CPUs regardless of bitness
RUN export ARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) \
    && if [ "$ARCH" = "arm64" ]; then export ARCH=aarch64 ; fi \
    && if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "i386" ]; then export ARCH=x86_64 ; fi \
    && curl -f -L -o /usr/local/bin/dumb-init https://github.com/Yelp/dumb-init/releases/download/v${DUMB_INIT_VERSION}/dumb-init_${DUMB_INIT_VERSION}_${ARCH} \
    && chmod +x /usr/local/bin/dumb-init

# Docker download supports arm64 as aarch64 & amd64 / i386 as x86_64
RUN set -vx; \
    export ARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) \
    && if [ "$ARCH" = "arm64" ]; then export ARCH=aarch64 ; fi \
    && if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "i386" ]; then export ARCH=x86_64 ; fi \
    && curl -f -L -o docker.tgz https://download.docker.com/linux/static/${DOCKER_CHANNEL}/${ARCH}/docker-${DOCKER_VERSION}.tgz \
    && tar zxvf docker.tgz \
    && install -o root -g root -m 755 docker/docker /usr/local/bin/docker \
    && rm -rf docker docker.tgz \
    && adduser --disabled-password --gecos "" --uid 1000 runner \
    && groupadd docker \
    && usermod -aG sudo runner \
    && usermod -aG sudo root \
    && usermod -aG docker runner \
    && echo "%sudo   ALL=(ALL:ALL) NOPASSWD:ALL" > /etc/sudoers

# Docker Plugins
RUN mkdir -p "${HOME}/.docker/cli-plugins" \
  && curl -SsL "https://github.com/docker/buildx/releases/download/${BUILDX_VERSION}/buildx-${BUILDX_VERSION}.linux-amd64" -o "${HOME}/.docker/cli-plugins/docker-buildx" \
  && curl -SsL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-linux-x86_64" -o "${HOME}/.docker/cli-plugins/docker-compose" \
  && chmod +x "${HOME}/.docker/cli-plugins/docker-buildx" \
  && chmod +x "${HOME}/.docker/cli-plugins/docker-compose"

# GH Actions
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt update -y  \
    && apt-get install -y gh

# Node
RUN curl -fsSL https://deb.nodesource.com/setup_18.x | bash - \
    && apt-get install -y nodejs \
    && npm install -g yarn

RUN npm cache clean --force

# Uncomment the below COPY to use your own custom build of actions-runner.
#
# To build a custom runner:
# - Clone the actions/runner repo `git clone git@github.com:actions/runner.git $repo`
# - Run `cd $repo/src`
# - Run `./dev.sh layout Release linux-x64`
# - Run `./dev.sh package Release linux-x64`
# - Run cp ../_package/actions-runner-linux-x64-2.280.3.tar.gz ../../actions-runner-controller/runner/
#   - Beware that `2.280.3` might change across versions
#
# See https://github.com/actions/runner/blob/main/.github/workflows/release.yml for more informatino on how you can use dev.sh
#
# If you're willing to uncomment the following line, you'd also need to comment-out the
#   && curl -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz \
# line in the next `RUN` command in this Dockerfile, to avoid overwiting this runner.tar.gz with a remote one.

# COPY actions-runner-linux-x64-2.280.3.tar.gz /runnertmp/runner.tar.gz

# Runner download supports amd64 as x64. Externalstmp is needed for making mount points work inside DinD.
#
# libyaml-dev is required for ruby/setup-ruby action.
# It is installed after installdependencies.sh and before removing /var/lib/apt/lists
# to avoid rerunning apt-update on its own.
ENV RUNNER_ASSETS_DIR=/runnertmp
RUN export ARCH=$(echo ${TARGETPLATFORM} | cut -d / -f2) \
    && if [ "$ARCH" = "amd64" ] || [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "i386" ]; then export ARCH=x64 ; fi \
    && mkdir -p "$RUNNER_ASSETS_DIR" \
    && cd "$RUNNER_ASSETS_DIR" \
    # Comment-out the below curl invocation when you use your own build of actions/runner
    && curl -f -L -o runner.tar.gz https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/actions-runner-linux-${ARCH}-${RUNNER_VERSION}.tar.gz \
    && tar xzf ./runner.tar.gz \
    && rm runner.tar.gz \
    && ./bin/installdependencies.sh \
    && mv ./externals ./externalstmp \
    && apt-get install -y libyaml-dev \
    && rm -rf /var/lib/apt/lists/*

RUN cd "$RUNNER_ASSETS_DIR" \
    && curl -f -L -o runner-container-hooks.zip https://github.com/actions/runner-container-hooks/releases/download/${RUNNER_CONTAINER_HOOKS_VERSION}/actions-runner-hooks-k8s-$(echo $RUNNER_CONTAINER_HOOKS_VERSION| cut -d "v" -f 2).zip \
    && unzip ./runner-container-hooks.zip -d ./k8s \
    && rm runner-container-hooks.zip

ENV RUNNER_TOOL_CACHE=/opt/hostedtoolcache
RUN mkdir /opt/hostedtoolcache \
    && chgrp docker /opt/hostedtoolcache \
    && chmod g+rwx /opt/hostedtoolcache

COPY --from=golang "/usr/local/go/" "/usr/local/go/"

# We place the scripts in `/usr/bin` so that users who extend this image can
# override them with scripts of the same name placed in `/usr/local/bin`.
COPY entrypoint.sh logger.bash update-status /usr/bin/

# Configure hooks folder structure.
COPY hooks /etc/arc/hooks/

ENV HOME=/root
ENV PATH="${PATH}:${HOME}/.local/bin"
ENV PATH="${PATH}:${HOME}/node_modules/.bin"
ENV PATH="/usr/local/go/bin:${PATH}"
ENV ImageOS=ubuntu20
ENV RUNNER_ALLOW_RUNASROOT="1"

RUN echo "PATH=${PATH}" > /etc/environment \
    && echo "ImageOS=${ImageOS}" >> /etc/environment

USER root
WORKDIR /root/

ENTRYPOINT ["/usr/local/bin/dumb-init", "--"]
CMD ["entrypoint.sh"]
