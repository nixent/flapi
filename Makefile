# Makefile for flAPI project

# Compiler and flags
CXX := g++
CMAKE := cmake

# Check if Ninja is available
NINJA := $(shell which ninja)
CMAKE_GENERATOR := $(if $(NINJA),-G Ninja,)

# Build directories
BUILD_DIR := build
DEBUG_DIR := $(BUILD_DIR)/debug
RELEASE_DIR := $(BUILD_DIR)/release

# Docker image name
DOCKER_FILE := Dockerfile
DOCKER_IMAGE_NAME := ghcr.io/datazoode/flapi

# Cross compilation settings
CROSS_COMPILE ?= 
ifeq ($(CROSS_COMPILE),aarch64)
    CMAKE_TOOLCHAIN_FILE := cmake/aarch64-linux-gnu.cmake
    VCPKG_TARGET_TRIPLET := arm64-linux
    CMAKE_EXTRA_FLAGS := \
        -DCMAKE_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN_FILE) \
        -DVCPKG_TARGET_TRIPLET=$(VCPKG_TARGET_TRIPLET) \
        -DVCPKG_CHAINLOAD_TOOLCHAIN_FILE=$(CMAKE_TOOLCHAIN_FILE)
endif

# Default target
all: debug release

# Debug build
ifeq ($(shell uname),Darwin)
    # Detect host architecture
    HOST_ARCH := $(shell uname -m)
    
    debug:
	@echo "Building debug version for $(HOST_ARCH)..."
	@mkdir -p $(DEBUG_DIR)
	@cd $(DEBUG_DIR) && \
	VCPKG_DEFAULT_TRIPLET=$(if $(filter arm64,$(HOST_ARCH)),arm64-osx,x64-osx) \
	$(CMAKE) \
		-DCMAKE_BUILD_TYPE=Debug \
		-DCMAKE_OSX_ARCHITECTURES=$(HOST_ARCH) \
		-DVCPKG_TARGET_TRIPLET=$(if $(filter arm64,$(HOST_ARCH)),arm64-osx,x64-osx) \
		$(CMAKE_GENERATOR) ../..
	@$(CMAKE) --build $(DEBUG_DIR) --config Debug
else
    # Original debug target for non-macOS platforms
    debug: $(DEBUG_DIR)/build.ninja
	@echo "Building debug version..."
	@$(CMAKE) --build $(DEBUG_DIR) --config Debug
endif

$(DEBUG_DIR)/build.ninja:
	@mkdir -p $(DEBUG_DIR)
	@cd $(DEBUG_DIR) && $(CMAKE) -DCMAKE_BUILD_TYPE=Debug $(CMAKE_GENERATOR) $(CMAKE_EXTRA_FLAGS) ../..

# macOS specific variables
ifeq ($(shell uname),Darwin)
    BUILD_UNIVERSAL := build/universal
    
    release-universal: release-x86_64 release-arm64
	@echo "Creating universal binary..."
	@mkdir -p $(BUILD_UNIVERSAL)
	@lipo -create \
		$(RELEASE_DIR)-x86_64/flapi \
		$(RELEASE_DIR)-arm64/flapi \
		-output $(BUILD_UNIVERSAL)/flapi
	@echo "Universal binary created at $(BUILD_UNIVERSAL)/flapi"

    release-x86_64:
	@echo "Building release version for x86_64..."
	@mkdir -p $(RELEASE_DIR)-x86_64
	@cd $(RELEASE_DIR)-x86_64 && \
	VCPKG_DEFAULT_TRIPLET=x64-osx \
	$(CMAKE) \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_OSX_ARCHITECTURES=x86_64 \
		-DVCPKG_TARGET_TRIPLET=x64-osx \
		-DBUILD_TESTING=OFF \
		$(CMAKE_GENERATOR) ../..
	@$(CMAKE) --build $(RELEASE_DIR)-x86_64 --config Release

    release-arm64:
	@echo "Building release version for arm64..."
	@mkdir -p $(RELEASE_DIR)-arm64
	@cd $(RELEASE_DIR)-arm64 && \
	VCPKG_DEFAULT_TRIPLET=arm64-osx \
	$(CMAKE) \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_OSX_ARCHITECTURES=arm64 \
		-DVCPKG_TARGET_TRIPLET=arm64-osx \
		-DBUILD_TESTING=OFF \
		$(CMAKE_GENERATOR) ../..
	@$(CMAKE) --build $(RELEASE_DIR)-arm64 --config Release

    # Override the default release target on macOS
    release: release-universal
else
    # Linux release builds with cross-compilation support
    release: $(RELEASE_DIR)/build.ninja
	@echo "Building release version $(if $(CROSS_COMPILE),for $(CROSS_COMPILE),native)..."
	@$(CMAKE) --build $(RELEASE_DIR) --config Release

    # Setup cross-compilation environment
    setup-cross-compile:
	@if [ "$(CROSS_COMPILE)" = "aarch64" ]; then \
		mkdir -p cmake; \
		echo "set(CMAKE_SYSTEM_NAME Linux)" > cmake/aarch64-linux-gnu.cmake; \
		echo "set(CMAKE_SYSTEM_PROCESSOR aarch64)" >> cmake/aarch64-linux-gnu.cmake; \
		echo "set(CMAKE_C_COMPILER aarch64-linux-gnu-gcc)" >> cmake/aarch64-linux-gnu.cmake; \
		echo "set(CMAKE_CXX_COMPILER aarch64-linux-gnu-g++)" >> cmake/aarch64-linux-gnu.cmake; \
		echo "set(CMAKE_FIND_ROOT_PATH /usr/aarch64-linux-gnu)" >> cmake/aarch64-linux-gnu.cmake; \
		echo "set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)" >> cmake/aarch64-linux-gnu.cmake; \
		echo "set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)" >> cmake/aarch64-linux-gnu.cmake; \
		echo "set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)" >> cmake/aarch64-linux-gnu.cmake; \
		echo "set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)" >> cmake/aarch64-linux-gnu.cmake; \
		if [ ! -f vcpkg/triplets/community/arm64-linux.cmake ]; then \
			mkdir -p vcpkg/triplets/community; \
			echo "set(VCPKG_TARGET_ARCHITECTURE arm64)" > vcpkg/triplets/community/arm64-linux.cmake; \
			echo "set(VCPKG_CRT_LINKAGE dynamic)" >> vcpkg/triplets/community/arm64-linux.cmake; \
			echo "set(VCPKG_LIBRARY_LINKAGE static)" >> vcpkg/triplets/community/arm64-linux.cmake; \
			echo "set(VCPKG_CMAKE_SYSTEM_NAME Linux)" >> vcpkg/triplets/community/arm64-linux.cmake; \
			echo "set(VCPKG_CHAINLOAD_TOOLCHAIN_FILE \$${CMAKE_CURRENT_LIST_DIR}/../../cmake/aarch64-linux-gnu.cmake)" >> vcpkg/triplets/community/arm64-linux.cmake; \
		fi; \
	fi
endif

$(RELEASE_DIR)/build.ninja: setup-cross-compile
	@mkdir -p $(RELEASE_DIR)
	@cd $(RELEASE_DIR) && $(CMAKE) -DCMAKE_BUILD_TYPE=Release $(CMAKE_GENERATOR) $(CMAKE_EXTRA_FLAGS) ../..

# Clean build directories
clean:
	@echo "Cleaning build directories..."
	cd duckdb && make clean
	@rm -rf $(BUILD_DIR)

# Run debug version
run-debug: debug
	@echo "Running debug version..."
	@$(DEBUG_DIR)/flapi --config examples/flapi.yaml --log-level debug

# Run debug tests
run-debug-tests: debug
	@echo "Running debug tests..."
	@$(DEBUG_DIR)/test/cpp/flapi_tests

# Run release version
run-release: release
	@echo "Running release version..."
	@$(RELEASE_DIR)/flapi --config examples/flapi.yaml --log-level info

# Run release tests
run-release-tests: release
	@echo "Running release tests..."
	@$(RELEASE_DIR)/test/cpp/flapi_tests

# Run integration tests
run-integration-tests: debug
	@echo "Running integration tests..."
	@$(CMAKE) --build $(DEBUG_DIR) --target integration_tests

# Build Docker image
docker: release
	@echo "Building Docker image..."
	docker build -t $(DOCKER_IMAGE_NAME):latest -f $(DOCKER_FILE) .

# Add a test target
test: release
	@echo "Running tests..."
	@cd $(RELEASE_DIR)-$(shell uname -m | sed 's/x86_64/x86_64/' | sed 's/arm64/arm64/') && \
	ctest --output-on-failure

# Phony targets
.PHONY: all debug release clean run-debug run-release run-integration-tests docker-build setup-cross-compile
