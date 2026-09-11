APP := build/OpenBend.app

.PHONY: all build debug run install clean icon render-test trigger-test motion-test

all: build

build:
	@./scripts/build.sh

debug:
	@CONFIG=debug ./scripts/build.sh

run: build
	@open $(APP)

install: build
	@rm -rf /Applications/OpenBend.app
	@cp -R $(APP) /Applications/
	@echo "Installed /Applications/OpenBend.app"

icon:
	@mkdir -p build && swift scripts/make-icon.swift build/AppIcon.icns

clean:
	@rm -rf build .build

render-test:
	@mkdir -p build/render-test-src build/render-test-out
	@cp scripts/render-test.swift build/render-test-src/main.swift
	@swiftc -O Sources/OpenBend/Shaders.swift Sources/OpenBend/BendMath.swift Sources/OpenBend/BendRenderer.swift build/render-test-src/main.swift -o build/render-test
	@build/render-test build/render-test-out

trigger-test:
	@mkdir -p build
	@swiftc -module-cache-path build/ModuleCache Sources/OpenBend/LidMotionTrigger.swift scripts/trigger-test.swift -o build/trigger-test
	@build/trigger-test

motion-test:
	@mkdir -p build
	@swiftc -module-cache-path build/ModuleCache Sources/OpenBend/LidMotionTracker.swift scripts/motion-tracker-test.swift -o build/motion-test
	@build/motion-test
