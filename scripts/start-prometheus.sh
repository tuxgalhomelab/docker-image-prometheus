#!/usr/bin/env bash
set -E -e -o pipefail

prometheus_config="/data/prometheus/config/prometheus.yml"

start_prometheus() {
    echo "Starting Prometheus ..."
    echo

    local config="${PROMETHEUS_CONFIG:-${prometheus_config:?}}"
    unset PROMETHEUS_CONFIG
    unset prometheus_config

    exec prometheus \
        --config.file ${config:?} \
        --storage.tsdb.path /data/prometheus/data \
        --web.console.libraries /data/prometheus/console_libraries \
        --web.console.templates /data/prometheus/consoles \
        "$@"
}

start_prometheus "$@"
