.PHONY: build deploy fmt preview run run-release

GIT_SHA := $(shell git rev-parse HEAD)

fmt:
	find lib -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -exec dart format {} +

run:
	flutter run -d chrome --dart-define=GIT_SHA=$(GIT_SHA)

run-release:
	flutter run --release -d chrome --dart-define=GIT_SHA=$(GIT_SHA)

preview:
	flutter widget-preview start

build:
	flutter build web --dart-define=GIT_SHA=$(GIT_SHA)

deploy: build
	wrangler deploy
