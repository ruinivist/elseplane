.PHONY: build deploy fmt preview run run-release test-touch

GIT_SHA := $(shell git rev-parse HEAD)

fmt:
	find lib -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -exec dart format {} +

run:
	flutter run -d chrome --dart-define=GIT_SHA=$(GIT_SHA)

run-release:
	flutter run --release -d chrome --dart-define=GIT_SHA=$(GIT_SHA)

test-touch:
	CHROME_EXECUTABLE=$${CHROME_EXECUTABLE:-/usr/bin/chromium} flutter test --platform chrome --reporter expanded test/canvas/editor/canvas_navigation_test.dart test/canvas/editor/canvas_touch_test.dart

preview:
	flutter widget-preview start

build:
	flutter build web --dart-define=GIT_SHA=$(GIT_SHA)

deploy: build
	wrangler deploy
