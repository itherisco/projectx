# Rust Warden Type-1 Hypervisor Build System
# Cross-compilation and testing automation

# Configuration
TARGET := x86_64-unknown-none
HOST := x86_64-unknown-linux-gnu
CARGO := cargo
RUSTUP := rustup

# Directories
SRC_DIR := src
BUILD_DIR := target/$(TARGET)/release
DEBUG_DIR := target/$(TARGET)/debug
DOC_DIR := target/doc

# Binaries
KERNEL := rust-warden.bin
DEBUG_KERNEL := rust-warden-debug.bin

# Default target
.PHONY: all
all: release

# Debug build
.PHONY: debug
debug:
	$(CARGO) build --target $(TARGET) --debug
	$(CARGO) objcopy --target $(TARGET) $(DEBUG_DIR)/rust-warden \
		--binary -O binary $(DEBUG_DIR)/$(DEBUG_KERNEL)

# Release build (optimized for size)
.PHONY: release
release:
	$(CARGO) build --target $(TARGET) --release
	$(CARGO) objcopy --target $(TARGET) $(BUILD_DIR)/rust-warden \
		--binary -O binary $(BUILD_DIR)/$(KERNEL)

# Build with custom linker script
.PHONY: linked
linked: LDFLAGS = -T linker_script.ld
linked: release

# Install target tools
.PHONY: install-target
install-target:
	$(RUSTUP) target add $(TARGET)
	@echo "Target $(TARGET) installed"

# Install cross-compilation toolchain
.PHONY: install-toolchain
install-toolchain:
	$(RUSTUP) install stable
	$(RUSTUP) default stable
	@echo "Cross-compilation toolchain ready"

# Run unit tests (with mocks)
.PHONY: test
test:
	$(CARGO) test --target $(TARGET) --lib

# Run tests with verbose output
.PHONY: test-verbose
test-verbose:
	$(CARGO) test --target $(TARGET) --lib -- --nocapture

# Run tests in hosted mode (for development)
.PHONY: test-hosted
test-hosted:
	$(CARGO) test --lib --features "mock std"

# Run integration tests
.PHONY: test-integration
test-integration:
	$(CARGO) test --target $(TARGET) --test integration_test --features mock

# Run all tests
.PHONY: test-all
test-all: test test-integration

# Generate documentation
.PHONY: docs
docs:
	$(CARGO) doc --target $(TARGET) --no-deps --document-private-items
	@echo "Documentation generated in $(DOC_DIR)"

# View documentation in browser
.PHONY: docs-serve
docs-serve: docs
	@echo "Open $(DOC_DIR)/rust_warden/index.html in your browser"

# Clean build artifacts
.PHONY: clean
clean:
	$(CARGO) clean

# Full clean including target
.PHONY: dist-clean
dist-clean: clean
	rm -rf target/

# Check code formatting
.PHONY: fmt
fmt:
	$(CARGO) fmt --check

# Format code
.PHONY: fmt-fix
fmt-fix:
	$(CARGO) fmt

# Run clippy lints
.PHONY: lint
lint:
	$(CARGO) clippy --target $(TARGET) -- -D warnings

# Run clippy in hosted mode
.PHONY: lint-hosted
lint-hosted:
	$(CARGO) clippy --features "mock std" -- -D warnings

# Security audit
.PHONY: audit
audit:
	$(CARGO) audit || true

# Build with address sanitizer (hosted only)
.PHONY: asan
asan:
	$(CARGO) build --target x86_64-unknown-linux-gnu --features "mock std" -Z address-sanitizer

# Build with thread sanitizer (hosted only)
.PHONY: tsan
tsan:
	$(CARGO) build --target x86_64-unknown-linux-gnu --features "mock std" -Z thread-sanitizer

# Generate build report
.PHONY: report
report:
	$(CARGO) build --target $(TARGET) --release --message-format=json \
		| python3 -c "import json, sys; data = json.load(sys.stdin); print('Build artifacts:', [x['filename'] for x in data if x['reason'] == 'build-script-execute'])" 2>/dev/null || \
	$(CARGO) build --target $(TARGET) --release -v

# Size analysis
.PHONY: size
size:
	@echo "=== Binary Size Analysis ==="
	ls -lh $(BUILD_DIR)/$(KERNEL) 2>/dev/null || echo "Run 'make release' first"
	@echo "=== Section Sizes ==="
	$(CARGO) size --target $(TARGET) --release -- -A 2>/dev/null || \
		size $(BUILD_DIR)/$(KERNEL) 2>/dev/null || echo "size tool not available"

# Run in QEMU (requires installed hypervisor)
.PHONY: qemu
qemu:
	@echo "Running in QEMU..."
	qemu-system-x86_64 \
		-kernel $(BUILD_DIR)/$(KERNEL) \
		-m 2G \
		-enable-kvm \
		-nographic \
		-append "console=ttyS0" || \
	qemu-system-x86_64 \
		-kernel $(BUILD_DIR)/$(KERNEL) \
		-m 2G \
		-nographic \
		-append "console=ttyS0"

# Create bootable USB image
.PHONY: usb
usb: release
	dd if=$(BUILD_DIR)/$(KERNEL) of=/dev/sdX bs=1M status=progress
	@echo "WARNING: Replace /dev/sdX with your actual USB device"

# Burn to disk image
.PHONY: disk
disk: release
	dd if=/dev/zero of=rust-warden.img bs=1M count=64
	dd if=$(BUILD_DIR)/$(KERNEL) of=rust-warden.img bs=1M conv=notrunc
	@echo "Disk image created: rust-warden.img"

# Help
.PHONY: help
help:
	@echo "Rust Warden Type-1 Hypervisor Build System"
	@echo ""
	@echo "Targets:"
	@echo "  all           - Default release build"
	@echo "  debug         - Debug build"
	@echo "  release       - Optimized release build"
	@echo "  linked        - Build with custom linker script"
	@echo ""
	@echo "Testing:"
	@echo "  test          - Run unit tests"
	@echo "  test-verbose  - Run tests with output"
	@echo "  test-hosted   - Run tests in hosted mode"
	@echo "  test-integration - Run integration tests"
	@echo "  test-all      - Run all tests"
	@echo ""
	@echo "Quality:"
	@echo "  fmt           - Check code formatting"
	@echo "  fmt-fix       - Fix code formatting"
	@echo "  lint          - Run clippy lints"
	@echo "  audit         - Run security audit"
	@echo ""
	@echo "Documentation:"
	@echo "  docs          - Generate documentation"
	@echo "  docs-serve    - Generate and view docs"
	@echo ""
	@echo "Utilities:"
	@echo "  clean         - Clean build artifacts"
	@echo "  dist-clean    - Full clean"
	@echo "  size          - Binary size analysis"
	@echo "  qemu          - Run in QEMU"
	@echo "  help          - Show this help"

# CI/CD targets
.PHONY: ci-check
ci-check: fmt lint test

.PHONY: ci-build
ci-build: release

.PHONY: ci-test
ci-test: test-all
