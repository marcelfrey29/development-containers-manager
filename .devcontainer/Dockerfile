FROM debian:13.7

# Set Locale
ENV LANG="C.UTF-8"
ENV LC_ALL="C.UTF-8"

# Install Core Packages
RUN apt-get update && \
    apt-get install --no-install-recommends -y \
    ca-certificates \
    zsh \
    git \
    curl \
    vim \
    tree

# Create Mount Points
RUN mkdir -p ~/.devcontainer/cmd-history

# Install Trivy
ARG TRIVY_VERSION=0.76.0
RUN curl -sfL https://raw.githubusercontent.com/aquasecurity/trivy/main/contrib/install.sh | sh -s -- -b /usr/local/bin v$TRIVY_VERSION
