# CI 門番 test-lint.yml の充て先 (#30)。
# test = CONTRIBUTING「Running the tests」の正式手順そのまま (全 shell スイートを完走後に集計)。
# lint = tracked な shell スクリプト全ファイルの bash -n 構文スイープ +
#        ANSI-C quote の Bash 4.2+ Unicode escape 拒否 (bash 3.2+ 方針に整合。
#        shellcheck 全面採用は別 Issue 候補として本レーンでは見送り)。
#   - 対象 = *.sh 全域 + shebang が shell の拡張子なしファイル (scripts/attest-wrapper 等)。
#   - 検査対象が 0 件なら赤 (空振り緑の拒否 — fail-closed)。

.PHONY: test lint

test:
	@pass_count=0; fail_count=0; failed_suites=; \
	for test_file in tests/*.test.sh; do \
	  if bash "$$test_file"; then \
	    pass_count=$$((pass_count+1)); \
	  else \
	    fail_count=$$((fail_count+1)); \
	    failed_suites="$$failed_suites $${test_file##*/}"; \
	  fi; \
	done; \
	printf '\nSuite Summary: %s PASS, %s FAIL\n' "$$pass_count" "$$fail_count"; \
	if [ "$$fail_count" -ne 0 ]; then \
	  printf 'Failed suites:\n'; \
	  for failed_suite in $$failed_suites; do printf ' - %s\n' "$$failed_suite"; done; \
	  exit 1; \
	fi

lint:
	@set -e; count=0; \
	files=$$( { git ls-files '*.sh'; \
	            git ls-files | while IFS= read -r p; do \
	              case "$$p" in (*.sh) continue;; esac; \
	              head -n 1 "$$p" 2>/dev/null | grep -qE '^#!.*sh([[:space:]]|$$)' && echo "$$p"; \
	            done; } | sort -u ); \
	for f in $$files; do \
	  bash -n "$$f" || { echo "syntax error: $$f" >&2; exit 1; }; \
	  count=$$((count+1)); \
	done; \
	[ "$$count" -ge 1 ] || { echo "lint: zero shell files checked - refusing vacuous green (fail-closed)" >&2; exit 1; }; \
	python3 -B scripts/check-bash32-ansi-c-escapes $$files; \
	echo "lint: $$count shell files OK"
