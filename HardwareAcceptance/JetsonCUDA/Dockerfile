FROM modular/max-nvidia-base@sha256:4566cb6f9ff3b51dc71542066f9dc72de27a823ea7b5c4613bd883ad71c1c57e

ARG TARGETARCH

LABEL org.opencontainers.image.source="https://github.com/1amageek/kuyu-mojo"
LABEL org.opencontainers.image.title="Kuyu Mojo canonical CUDA acceptance"

USER root
RUN test "$TARGETARCH" = "arm64" \
    && test "$(uname -m)" = "aarch64"

WORKDIR /opt/kuyu
COPY validate_handoff.py /opt/kuyu/validate_handoff.py
COPY container-accept.sh /opt/kuyu/container-accept.sh
COPY Handoff /opt/kuyu/handoff

RUN chmod 0555 /opt/kuyu/validate_handoff.py /opt/kuyu/container-accept.sh \
    && test "$(mojo --version)" = "Mojo 1.0.0 (ed45d567)" \
    && python3 /opt/kuyu/validate_handoff.py --handoff /opt/kuyu/handoff

ENTRYPOINT ["/usr/bin/dumb-init", "--", "/opt/kuyu/container-accept.sh"]
