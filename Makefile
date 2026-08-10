# CI 門番 test-lint.yml の充て先 (#30)。
# test = CONTRIBUTING「Running the tests」の正式手順そのまま (全 shell スイート)。
# lint = tracked な shell スクリプト全ファイルの bash -n 構文スイープ (bash 3.2+ 方針に整合。
#        shellcheck 全面採用は別 Issue 候補として本レーンでは見送り)。
#   - 対象 = *.sh 全域 + shebang が shell の拡張子なしファイル (scripts/attest-wrapper 等)。
#   - 検査対象が 0 件なら赤 (空振り緑の拒否 — fail-closed)。

.PHONY: test lint

test:
	@set -e; for test_file in tests/*.test.sh; do bash "$$test_file"; done

lint:
	@set -e; count=0; \
	for f in $$( { git ls-files '*.sh'; \
	               git ls-files | while IFS= read -r p; do \
	                 case "$$p" in (*.sh) continue;; esac; \
	                 head -n 1 "$$p" 2>/dev/null | grep -qE '^#!.*sh([[:space:]]|$$)' && echo "$$p"; \
	               done; } | sort -u ); do \
	  bash -n "$$f" || { echo "syntax error: $$f" >&2; exit 1; }; \
	  count=$$((count+1)); \
	done; \
	[ "$$count" -ge 1 ] || { echo "lint: zero shell files checked - refusing vacuous green (fail-closed)" >&2; exit 1; }; \
	echo "lint: $$count shell files OK"
