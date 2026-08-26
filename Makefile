.PHONY: build test app package check verify-package ci clean

build:
	swift build -Xswiftc -warnings-as-errors

test:
	swift build -c debug -Xswiftc -warnings-as-errors
	.build/debug/SnapMark --self-test

app:
	SNAPMARK_UNIVERSAL=1 ./scripts/build-app.sh release

package:
	SNAPMARK_SIGNING_MODE=adhoc SNAPMARK_UNIVERSAL=1 ./scripts/build-app.sh release

check:
	./scripts/check-repository.sh

verify-package:
	./scripts/verify-release.sh

ci: check test package verify-package

clean:
	swift package clean
