.PHONY: build deploy fmt preview run run-release debug-start debug-status debug-reload debug-restart debug-stop

GIT_SHA := $(shell git rev-parse HEAD)
GITHUB_MEDIATOR_URL ?=
GITHUB_APP_SLUG ?=

# overwrites some of these vars so other checkouts don't need to get the whole mediator setup unless needed
-include local-mediator/run.mk

WEB_LAUNCH_URL ?= http://localhost:3000
RUN_GITHUB_MEDIATOR_URL ?= $(GITHUB_MEDIATOR_URL)
RUN_GITHUB_APP_SLUG ?= $(GITHUB_APP_SLUG)
FLUTTER_RUN_ARGS ?=
export TASK

fmt:
	find lib -type f -name '*.dart' ! -name '*.g.dart' ! -name '*.freezed.dart' -exec dart format {} +

run:
	flutter run -d chrome --web-hostname=127.0.0.1 --web-port=3000 --web-launch-url=$(WEB_LAUNCH_URL) --dart-define=GIT_SHA=$(GIT_SHA) --dart-define=GITHUB_MEDIATOR_URL=$(RUN_GITHUB_MEDIATOR_URL) --dart-define=GITHUB_APP_SLUG=$(RUN_GITHUB_APP_SLUG) $(FLUTTER_RUN_ARGS)

run-release:
	flutter run --release -d chrome --web-hostname=127.0.0.1 --web-port=3000 --web-launch-url=$(WEB_LAUNCH_URL) --dart-define=GIT_SHA=$(GIT_SHA) --dart-define=GITHUB_MEDIATOR_URL=$(RUN_GITHUB_MEDIATOR_URL) --dart-define=GITHUB_APP_SLUG=$(RUN_GITHUB_APP_SLUG)

debug-start:
	@python3 .agents/skills/elseplane-debug/scripts/debug.py start

debug-status:
	@python3 .agents/skills/elseplane-debug/scripts/debug.py status

debug-reload:
	@python3 .agents/skills/elseplane-debug/scripts/debug.py reload

debug-restart:
	@python3 .agents/skills/elseplane-debug/scripts/debug.py restart

debug-stop:
	@python3 .agents/skills/elseplane-debug/scripts/debug.py stop

preview:
	flutter widget-preview start

build:
	flutter build web --dart-define=GIT_SHA=$(GIT_SHA) --dart-define=GITHUB_MEDIATOR_URL=$(GITHUB_MEDIATOR_URL) --dart-define=GITHUB_APP_SLUG=$(GITHUB_APP_SLUG)

deploy: build
	wrangler deploy
