# CI 門番 test-lint.yml の充て先 (#30)。
# test = CONTRIBUTING「Running the tests」の正式手順そのまま (全 shell スイート)。
# lint = tracked な *.sh 全ファイルの bash -n 構文スイープ (bash 3.2+ 方針に整合。
#        shellcheck 全面採用は別 Issue 候補として本レーンでは見送り)。

.PHONY: test lint

test:
	@set -e; for test_file in tests/*.test.sh; do bash "$$test_file"; done

lint:
	@set -e; git ls-files '*.sh' | while IFS= read -r f; do bash -n "$$f" || { echo "syntax error: $$f" >&2; exit 1; }; done
