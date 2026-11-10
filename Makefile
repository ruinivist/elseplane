.PHONY: build deploy fmt preview run run-release

GIT_SHA := $(shell git rev-parse HEAD)
GITHUB_MEDIATOR_URL ?=

fmt:
	find lib -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -exec dart format {} +

run:
	flutter run -d chrome --dart-define=GIT_SHA=$(GIT_SHA) --dart-define=GITHUB_MEDIATOR_URL=$(GITHUB_MEDIATOR_URL)

run-release:
	flutter run --release -d chrome --dart-define=GIT_SHA=$(GIT_SHA) --dart-define=GITHUB_MEDIATOR_URL=$(GITHUB_MEDIATOR_URL)

preview:
	flutter widget-preview start

build:
	flutter build web --dart-define=GIT_SHA=$(GIT_SHA) --dart-define=GITHUB_MEDIATOR_URL=$(GITHUB_MEDIATOR_URL)

deploy: build
	wrangler deploy
