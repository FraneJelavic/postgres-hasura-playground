SHELL := /bin/bash

.DEFAULT_GOAL := up

.PHONY: up status verify failover switchover logs down reset check diagrams check-diagrams

up:
	./scripts/up.sh

status:
	./scripts/status.sh

verify:
	./scripts/verify.sh

failover:
	./scripts/failover.sh

switchover:
	./scripts/switchover.sh

logs:
	./scripts/compose.sh logs --follow --tail=100

down:
	./scripts/compose.sh down --remove-orphans

reset:
	./scripts/reset.sh

check:
	./scripts/check.sh

diagrams:
	./scripts/render-diagrams.sh

check-diagrams:
	./scripts/render-diagrams.sh --check
