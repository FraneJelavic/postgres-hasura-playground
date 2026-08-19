FROM postgres:16.14-bookworm

USER 0

ENV PATH="/opt/patroni-venv/bin:${PATH}" \
    PGDATA=/var/lib/postgresql/data/pgdata \
    PATRONI_CONFIG_FILE=/etc/patroni/patroni.yml \
    PATRONICTL_CONFIG_FILE=/etc/patroni/patroni.yml \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Debian security updates are intentionally consumed when the image is rebuilt.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl python3 python3-venv \
    && python3 -m venv /opt/patroni-venv \
    && rm -rf /var/lib/apt/lists/*

COPY images/postgres-patroni/requirements.txt /tmp/requirements.txt
RUN /opt/patroni-venv/bin/pip install --no-cache-dir --require-hashes -r /tmp/requirements.txt \
    && /opt/patroni-venv/bin/pip uninstall --yes setuptools \
    && rm /tmp/requirements.txt /usr/local/bin/gosu

COPY config/patroni/patroni.yml /etc/patroni/patroni.yml
COPY images/postgres-patroni/entrypoint.sh /usr/local/bin/patroni-entrypoint

RUN chmod 0755 /usr/local/bin/patroni-entrypoint \
    && mkdir -p /var/lib/postgresql/data \
    && chown -R postgres:postgres /var/lib/postgresql /opt/patroni-venv /etc/patroni

USER 999:999

EXPOSE 5432 8008
ENTRYPOINT ["patroni-entrypoint"]
CMD ["patroni", "/etc/patroni/patroni.yml"]
