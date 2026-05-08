# vyakarana stand-in -- not from vidya. See docs/adr/0006-standin-corpus-policy.md.
# Re-sync when vidya adds a Makefile reference sample.
#
# Demonstrates GNU make: variable assignment forms, automatic
# variables, function calls, conditional / include directives,
# pattern rules, .PHONY targets, and a small build graph.

# ── Variables ───────────────────────────────────────────────────────

CC      ?= cc
AR      ?= ar
CFLAGS  := -O2 -Wall -Wextra -Wpedantic -std=c11
LDFLAGS  =
LIBS    +=

PREFIX  ?= /usr/local
BINDIR  := $(PREFIX)/bin
LIBDIR  := $(PREFIX)/lib

SRC_DIR := src
OBJ_DIR := build/obj
BIN_DIR := build/bin

SOURCES := $(wildcard $(SRC_DIR)/*.c)
OBJECTS := $(SOURCES:$(SRC_DIR)/%.c=$(OBJ_DIR)/%.o)
TARGET  := $(BIN_DIR)/concept

VERSION := $(shell cat VERSION 2>/dev/null || echo 0.0.0)

# ── Phony targets ──────────────────────────────────────────────────

.PHONY: all build clean install uninstall test bench help

all: build

# ── Build graph ────────────────────────────────────────────────────

build: $(TARGET)

$(TARGET): $(OBJECTS) | $(BIN_DIR)
	$(CC) $(LDFLAGS) -o $@ $^ $(LIBS)

$(OBJ_DIR)/%.o: $(SRC_DIR)/%.c | $(OBJ_DIR)
	$(CC) $(CFLAGS) -c -o $@ $<

$(OBJ_DIR) $(BIN_DIR):
	mkdir -p $@

clean:
	rm -rf build

# ── Install / uninstall ────────────────────────────────────────────

install: build
	install -d $(DESTDIR)$(BINDIR)
	install -m 0755 $(TARGET) $(DESTDIR)$(BINDIR)/

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/$(notdir $(TARGET))

# ── Test / benchmark ───────────────────────────────────────────────

test: build
	@echo "Running tests for v$(VERSION)..."
	$(MAKE) -C tests check

bench: build
	@for n in 1 10 100; do \
		printf "  size=%d: " $$n; \
		$(TARGET) --bench --size=$$n; \
	done

# ── Conditional flags ──────────────────────────────────────────────

ifeq ($(shell uname),Darwin)
    CFLAGS += -DDARWIN
endif

ifeq ($(DEBUG),1)
    CFLAGS += -g -O0 -DDEBUG
else
    CFLAGS += -DNDEBUG
endif

ifdef ASAN
    CFLAGS  += -fsanitize=address -fno-omit-frame-pointer
    LDFLAGS += -fsanitize=address
endif

ifndef NO_DEPS
    -include $(OBJECTS:.o=.d)
endif

# ── Help ───────────────────────────────────────────────────────────

help:
	@echo "Targets:"
	@echo "  build      Compile $(notdir $(TARGET))"
	@echo "  clean      Remove build artefacts"
	@echo "  install    Install to $(DESTDIR)$(BINDIR)"
	@echo "  test       Run test suite"
	@echo "  bench      Run benchmarks"
	@echo
	@echo "Variables:"
	@echo "  CC=<cmd>     C compiler (default: $(CC))"
	@echo "  PREFIX=<dir> Install prefix (default: $(PREFIX))"
	@echo "  DEBUG=1      Build with -g -O0 -DDEBUG"
	@echo "  ASAN=1       Build with AddressSanitizer"
