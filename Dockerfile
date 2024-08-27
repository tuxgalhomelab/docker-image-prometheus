# syntax=docker/dockerfile:1

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG} AS with-scripts

COPY scripts/start-prometheus.sh /scripts/

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG
FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

SHELL ["/bin/bash", "-c"]

ARG USER_NAME
ARG GROUP_NAME
ARG USER_ID
ARG GROUP_ID
ARG PROMETHEUS_VERSION

# hadolint ignore=DL4006,SC2086
RUN --mount=type=bind,target=/scripts,from=with-scripts,source=/scripts \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    # Create the user and the group. \
    && homelab add-user \
        ${USER_NAME:?} \
        ${USER_ID:?} \
        ${GROUP_NAME:?} \
        ${GROUP_ID:?} \
        --create-home-dir \
    # Download and install the release. \
    && mkdir -p /tmp/prometheus \
    && PKG_ARCH="$(dpkg --print-architecture)" \
    && homelab download-file-to \
        https://github.com/prometheus/prometheus/releases/download/${PROMETHEUS_VERSION:?}/prometheus-${PROMETHEUS_VERSION#v}.linux-${PKG_ARCH:?}.tar.gz \
        /tmp/prometheus \
    && homelab download-file-to \
        "https://github.com/prometheus/prometheus/releases/download/${PROMETHEUS_VERSION:?}/sha256sums.txt" \
        /tmp/prometheus \
    && pushd /tmp/prometheus \
    && grep "prometheus-${PROMETHEUS_VERSION#v}.linux-${PKG_ARCH:?}.tar.gz" sha256sums.txt | sha256sum -c \
    && tar xvf prometheus-${PROMETHEUS_VERSION#v}.linux-${PKG_ARCH:?}.tar.gz \
    && pushd prometheus-${PROMETHEUS_VERSION#v}.linux-${PKG_ARCH:?} \
    && mkdir -p /opt/prometheus-${PROMETHEUS_VERSION:?}/bin /data/prometheus/{config,data} \
    && mv promtool /opt/prometheus-${PROMETHEUS_VERSION:?}/bin \
    && mv prometheus /opt/prometheus-${PROMETHEUS_VERSION:?}/bin \
    && mv prometheus.yml /data/prometheus/config/ \
    && mv console_libraries /data/prometheus/ \
    && mv consoles /data/prometheus/ \
    && ln -sf /opt/prometheus-${PROMETHEUS_VERSION:?} /opt/prometheus \
    && ln -sf /opt/prometheus/bin/prometheus /opt/bin/prometheus \
    && ln -sf /opt/prometheus/bin/promtool /opt/bin/promtool \
    && popd \
    && popd \
    # Copy the start-prometheus.sh script. \
    && cp /scripts/start-prometheus.sh /opt/prometheus/ \
    && ln -sf /opt/prometheus/start-prometheus.sh /opt/bin/start-prometheus \
    # Set up the permissions. \
    && chown -R ${USER_NAME:?}:${GROUP_NAME:?} /opt/prometheus-${PROMETHEUS_VERSION:?} /opt/prometheus /opt/bin/{prometheus,promtool,start-prometheus} /data/prometheus \
    # Clean up. \
    && rm -rf /tmp/prometheus \
    && homelab cleanup

# Expose the HTTP server port used by Prometheus.
EXPOSE 9090

# Use the healthcheck command part of prometheus as the health checker.
HEALTHCHECK \
    --start-period=15s --interval=30s --timeout=3s \
    CMD homelab healthcheck-service http://localhost:9090/-/healthy

ENV USER=${USER_NAME}
USER ${USER_NAME}:${GROUP_NAME}
WORKDIR /home/${USER_NAME}

CMD ["start-prometheus"]
STOPSIGNAL SIGTERM
