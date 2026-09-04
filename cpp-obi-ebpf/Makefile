# cpp-obi-ebpf — build and run the sample.
#
# The two C++ binaries contain no instrumentation of any kind: no OpenTelemetry
# SDK, no agent, nothing linked at build time. OBI attaches from outside with
# eBPF. Nothing in this Makefile compiles anything observability-related.

SHELL := /bin/bash
.DEFAULT_GOAL := help

CXX      ?= g++
CXXFLAGS ?= -std=c++17 -O2 -g -pthread -Wall -Wextra

SRC_DIR := src
BIN_DIR := bin
# OBI matches processes by absolute executable path, so the generated config
# needs this resolved rather than relative.
ABS_BIN := $(abspath $(BIN_DIR))

PRICING   := $(BIN_DIR)/pricing-api
INVENTORY := $(BIN_DIR)/inventory-api
OBI       := $(BIN_DIR)/obi

OBI_VERSION ?= 0.12.2
OBI_ARCH    ?= amd64
OBI_TARBALL := obi-v$(OBI_VERSION)-linux-$(OBI_ARCH).tar.gz
OBI_URL     := https://github.com/open-telemetry/opentelemetry-ebpf-instrumentation/releases/download/v$(OBI_VERSION)/$(OBI_TARBALL)

CONFIG          := obi-config.yaml
CONFIG_TEMPLATE := obi-config.yaml.template

.PHONY: help build check install-obi config run stop obi loadgen clean

help:
	@echo "cpp-obi-ebpf — zero-code eBPF instrumentation of native C++"
	@echo
	@echo "  make build         compile both services into $(BIN_DIR)/"
	@echo "  make check         verify this host can run OBI (Linux, kernel, BTF)"
	@echo "  make install-obi   download OBI $(OBI_VERSION) into $(BIN_DIR)/"
	@echo "  make config        generate $(CONFIG) from .env + $(CONFIG_TEMPLATE)"
	@echo "  make run           start both services and the load generator"
	@echo "  make obi           run OBI in the foreground (needs sudo)"
	@echo "  make stop          stop the services and the load generator"
	@echo "  make clean         remove $(BIN_DIR)/ and the generated config"
	@echo
	@echo "Typical first run:"
	@echo "  cp .env.example .env && \$$EDITOR .env"
	@echo "  make check build install-obi config run"
	@echo "  make obi"

# ---------- build ----------

build: $(PRICING) $(INVENTORY)

$(BIN_DIR):
	@mkdir -p $(BIN_DIR)

$(PRICING): $(SRC_DIR)/pricing-api.cpp | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -o $@ $<
	@echo "built $@"

$(INVENTORY): $(SRC_DIR)/inventory-api.cpp | $(BIN_DIR)
	$(CXX) $(CXXFLAGS) -o $@ $<
	@echo "built $@"

$(OBI):
	@echo "bin/obi missing — run: make install-obi" >&2
	@exit 1

# ---------- OBI ----------

check:
	@scripts/check-prereqs.sh

install-obi: | $(BIN_DIR)
	@scripts/install-obi.sh "$(OBI_URL)" "$(OBI_TARBALL)" "$(BIN_DIR)"

# Regenerated whenever the template or .env changes. .env holds the token, so
# the generated config is gitignored.
config: $(CONFIG)

$(CONFIG): $(CONFIG_TEMPLATE) .env
	@scripts/gen-config.sh "$(CONFIG_TEMPLATE)" "$@" "$(ABS_BIN)"

.env:
	@echo "no .env found — copy it first:  cp .env.example .env" >&2
	@exit 1

# ---------- run ----------

run: build
	@scripts/start_all.sh

stop:
	@scripts/stop_all.sh

# Foreground so you can watch it attach and see export errors immediately.
# OBI needs root for the eBPF probes; the token comes from .env via the script.
obi: $(OBI) $(CONFIG)
	@scripts/run-obi.sh

loadgen:
	@scripts/loadgen.sh

# ---------- housekeeping ----------

clean: 
	@rm -rf $(BIN_DIR) $(CONFIG)
	@echo "removed $(BIN_DIR)/ and $(CONFIG)"
