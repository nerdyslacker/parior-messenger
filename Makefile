ODIN ?= odin
SKALD_ROOT ?= vendor/skald
BAREV_ROOT ?= vendor/barev-odin
BUILD_DIR := build
APP := $(BUILD_DIR)/parior
ODIN_FLAGS := -collection:gui=$(SKALD_ROOT) -collection:barev=$(BAREV_ROOT) -define:ODIN_NBIO_QUEUE_SIZE=128

.PHONY: build release check style run clean

build:
	mkdir -p $(BUILD_DIR)
	$(ODIN) build src $(ODIN_FLAGS) -debug -out:$(APP)

release:
	mkdir -p $(BUILD_DIR)
	$(ODIN) build src $(ODIN_FLAGS) -o:speed -out:$(APP)

check:
	$(ODIN) check src $(ODIN_FLAGS)

style:
	$(ODIN) check src $(ODIN_FLAGS) -strict-style -strict-style-packages:parior_messenger

run: build
	./$(APP)

clean:
	rm -f $(APP)
