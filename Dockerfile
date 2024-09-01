# syntax=docker/dockerfile:1

ARG BASE_IMAGE_NAME
ARG BASE_IMAGE_TAG

ARG GO_IMAGE_NAME
ARG GO_IMAGE_TAG
FROM ${GO_IMAGE_NAME}:${GO_IMAGE_TAG} AS builder

ARG NVM_VERSION
ARG NVM_SHA256_CHECKSUM
ARG IMAGE_NODEJS_VERSION
ARG PROMETHEUS_VERSION

COPY scripts/start-prometheus.sh /scripts/
COPY patches /patches

# hadolint ignore=DL4006,SC3009,SC3040
RUN \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    && homelab install build-essential git \
    && homelab install-node \
        ${NVM_VERSION:?} \
        ${NVM_SHA256_CHECKSUM:?} \
        ${IMAGE_NODEJS_VERSION:?} \
    # Download prometheus repo. \
    && homelab download-git-repo \
        https://github.com/prometheus/prometheus \
        ${PROMETHEUS_VERSION:?} \
        /root/prometheus-build \
    && pushd /root/prometheus-build \
    # Apply the patches. \
    && (find /patches -iname *.diff -print0 | sort -z | xargs -0 -r -n 1 patch -p2 -i) \
    && source /opt/nvm/nvm.sh \
    # Build prometheus. \
    && make build \
    && popd \
    # Copy the build artifacts. \
    && mkdir -p /output/{bin,scripts,configs} \
    && cp /root/prometheus-build/{prometheus,promtool} /output/bin \
    && cp /root/prometheus-build/documentation/examples/prometheus.yml /output/configs \
    && cp -rf /root/prometheus-build/{consoles,console_libraries} /output/ \
    && cp /scripts/* /output/scripts

FROM ${BASE_IMAGE_NAME}:${BASE_IMAGE_TAG}

ARG USER_NAME
ARG GROUP_NAME
ARG USER_ID
ARG GROUP_ID
ARG PROMETHEUS_VERSION

# hadolint ignore=DL4006,SC2086,SC3009
RUN --mount=type=bind,target=/prometheus-build,from=builder,source=/output \
    set -E -e -o pipefail \
    && export HOMELAB_VERBOSE=y \
    # Create the user and the group. \
    && homelab add-user \
        ${USER_NAME:?} \
        ${USER_ID:?} \
        ${GROUP_NAME:?} \
        ${GROUP_ID:?} \
        --create-home-dir \
    && mkdir -p /opt/prometheus-${PROMETHEUS_VERSION:?}/bin /data/prometheus/{config,data} \
    && cp /prometheus-build/bin/{prometheus,promtool} /opt/prometheus-${PROMETHEUS_VERSION:?}/bin \
    && cp /prometheus-build/configs/prometheus.yml /data/prometheus/config/ \
    && cp -rf /prometheus-build/{consoles,console_libraries} /data/prometheus/ \
    && ln -sf /opt/prometheus-${PROMETHEUS_VERSION:?} /opt/prometheus \
    && ln -sf /opt/prometheus/bin/prometheus /opt/bin/prometheus \
    && ln -sf /opt/prometheus/bin/promtool /opt/bin/promtool \
    # Copy the start-prometheus.sh script. \
    && cp /prometheus-build/scripts/start-prometheus.sh /opt/prometheus/ \
    && ln -sf /opt/prometheus/start-prometheus.sh /opt/bin/start-prometheus \
    # Set up the permissions. \
    && chown -R ${USER_NAME:?}:${GROUP_NAME:?} /opt/prometheus-${PROMETHEUS_VERSION:?} /opt/prometheus /opt/bin/{prometheus,promtool,start-prometheus} /data/prometheus \
    # Clean up. \
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
