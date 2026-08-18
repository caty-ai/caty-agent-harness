from __future__ import annotations

from pathlib import Path
import json
import io
import hashlib
import tarfile

from analyze import main
from conftest import write_jsonl
from reexec import registered_image_id


PACK = Path(__file__).resolve().parents[3]


class FakeResult:
    def __init__(self, returncode=0, stdout=b"", stderr=b""):
        self.returncode = returncode
        self.stdout = stdout
        self.stderr = stderr


def _attempt_dir(fixture_tree, row):
    parts = Path(row["output"]).parts
    suffix = parts[parts.index(fixture_tree["out"].name) + 1:]
    return fixture_tree["out"].joinpath(*suffix)


def _write_valid_snapshot_archives(fixture_tree):
    for row in fixture_tree["ledger"]:
        attempt = _attempt_dir(fixture_tree, row)
        audit = [json.loads(line) for line in (attempt / "audit.jsonl").read_text().splitlines()]
        declaration = audit[1]
        payload = io.BytesIO()
        with tarfile.open(fileobj=payload, mode="w:gz") as archive:
            contents = f"retained tree for {row['run_id']}\n".encode()
            info = tarfile.TarInfo("result.txt")
            info.size = len(contents)
            info.mtime = 0
            archive.addfile(info, io.BytesIO(contents))
        snapshots = attempt / "snapshots"
        snapshots.mkdir()
        archive_path = snapshots / f"decl-1-{declaration['snapshot_sha'][:12]}.tar.gz"
        archive_path.write_bytes(payload.getvalue())
        (snapshots / "index.json").write_text(json.dumps({
            "protocol": 1,
            "run_id": row["run_id"],
            "entries": [{
                "seq": 1,
                "marker": declaration["marker"],
                "snapshot_sha": declaration["snapshot_sha"],
                "archive": archive_path.name,
                "archive_sha256": hashlib.sha256(archive_path.read_bytes()).hexdigest(),
            }],
        }))


def _extend_fixture_to_six_tasks(fixture_tree):
    rows = list(fixture_tree["ledger"])
    by_task_arm = {
        (row["task_id"], row["arm"]): row
        for row in rows
        if row["replicate"] == 1
    }
    slug_by_arm = {"W": "w", "B+": "b-plus", "B": "b"}
    template_by_task = {"t03": "t01", "t04": "t02", "t05": "t01", "t06": "t02"}
    extra_rows = []
    for task_id, template_task in template_by_task.items():
        task_dir = fixture_tree["tasks"] / task_id
        task_dir.mkdir(parents=True)
        (task_dir / "meta.json").write_text(json.dumps({
            "id": task_id, "source_repo": f"example/{task_id}", "pre_fix": "a" * 40,
            "fix": "b" * 40, "source_issue": 1, "synthetic": False, "timeout_s": 30,
        }))
        (task_dir / "donecheck.sh").write_text("#!/bin/bash\nexit 0\n")
        for replicate in (1, 2, 3):
            for arm_index, arm in enumerate(("W", "B+", "B")):
                template = by_task_arm[(template_task, arm)]
                template_attempt = _attempt_dir(fixture_tree, template)
                audit = [
                    json.loads(line)
                    for line in (template_attempt / "audit.jsonl").read_text().splitlines()
                ]
                slug = slug_by_arm[arm]
                run_id = f"main-{task_id}-k{replicate}-{slug}"
                block = f"{task_id}-k{replicate}"
                suffix = Path("runs") / block / slug / "attempt-001"
                attempt = fixture_tree["out"] / suffix
                sha = f"{replicate}{arm_index}".ljust(40, "a")
                audit[0]["run_id"] = run_id
                audit[0]["task_id"] = task_id
                audit[0]["block_id"] = block
                audit[1]["snapshot_sha"] = sha
                for event in audit:
                    if event.get("event") == "donecheck_invocation":
                        event["tree_sha"] = sha
                write_jsonl(attempt / "audit.jsonl", audit)
                extra_rows.append({
                    "run_id": run_id, "task_id": task_id, "arm": arm, "replicate": replicate,
                    "block_id": block, "rank": replicate - 1, "seat": "seat-01",
                    "slot_index": arm_index, "series": "main", "cell": "main", "attempt": 1,
                    "scoring_attempt": True, "completed": True, "void": False,
                    "void_reason": None, "output": f"/execution/host/{fixture_tree['out'].name}/{suffix}",
                    "start_ts": "x", "end_ts": "y", "exit_status": 0, "status_reason": "ok",
                })
    fixture_tree["ledger"].extend(extra_rows)
    write_jsonl(fixture_tree["out"] / "ledger.jsonl", fixture_tree["ledger"])


def _fake_docker_runner(calls):
    expected_image_id = registered_image_id(PACK)
    image_passwd = b"root:x:0:0:root:/root:/bin/bash\n"
    image_group = b"root:x:0:\n"

    def runner(command, timeout):
        calls.append((command, timeout))
        if command[:3] == ["docker", "image", "inspect"]:
            return FakeResult(stdout=(expected_image_id + "\n").encode())
        assert command[:2] == ["docker", "run"]
        if command[-2:] == ["cat", "/etc/passwd"]:
            return FakeResult(stdout=image_passwd)
        if command[-2:] == ["cat", "/etc/group"]:
            return FakeResult(stdout=image_group)
        passwd_mount = next(value for value in command if value.endswith(":/etc/passwd:ro"))
        group_mount = next(value for value in command if value.endswith(":/etc/group:ro"))
        assert Path(passwd_mount.split(":", 1)[0]).read_bytes() == (
            image_passwd + b"ev005:x:1000:1000:EV-005 agent:/home/ev005:/bin/bash\n"
        )
        assert Path(group_mount.split(":", 1)[0]).read_bytes() == (
            image_group + b"ev005:x:1000:\n"
        )
        return FakeResult(stdout=b"pipeline pass\n")

    return runner


def test_two_non_registered_dry_run_invocations_are_byte_identical(fixture_tree, tmp_path):
    first = tmp_path / "report-one"
    second = tmp_path / "report-two"
    common = [
        "--pack", str(PACK), "--series", "main",
        "--out-root", str(fixture_tree["out"]),
        "--tasks-dir", str(fixture_tree["tasks"]),
        "--reexec", "non-registered-dry-run",
    ]
    assert main(common + ["--report-dir", str(first)]) == 0
    assert main(common + ["--report-dir", str(second)]) == 0
    assert (first / "analysis-report.json").read_bytes() == (second / "analysis-report.json").read_bytes()
    assert (first / "analysis-report.md").read_bytes() == (second / "analysis-report.md").read_bytes()
    assert (first / "gaming-audit-sample.json").read_bytes() == (second / "gaming-audit-sample.json").read_bytes()
    assert (first / "crosscheck-sample.json").read_bytes() == (second / "crosscheck-sample.json").read_bytes()
    assert (first / "pipeline-reexec.jsonl").read_bytes() == b""

    report = json.loads((first / "analysis-report.json").read_text())
    assert set(report["sensitivity"]["execution_infrastructure"]["per_seat"]) == {
        "seat-01", "seat-02", "seat-04", "seat-05", "seat-06",
    }
    assert report["sensitivity"]["execution_infrastructure"]["distributions"]["W"][
        "gate_wallclock_timeout_fraction"
    ]["median"] == 0.1
    assert report["sensitivity"]["execution_infrastructure"]["distributions"]["W"][
        "wallclock_timeout_fraction_by_invoker"
    ]["pipeline"]["median"] == 0.3
    assert report["draws"]["crosscheck"]["sample_size"] == 10
    assert {row["adjudication_provenance"] for row in report["outcome_rows"]} == {"in-run-audit"}
    assert report["registered_adjudication"] is False
    assert report["primary"]["confirmed"] is False
    assert report["provenance"]["out_root"] == fixture_tree["out"].name
    markdown = (first / "analysis-report.md").read_text()
    assert "NON-REGISTERED DRY RUN" in markdown.splitlines()[0]
    assert "Not evaluated: adjudication mode 'non-registered-dry-run'" in markdown
    assert "H-primary is confirmed." not in markdown
    assert "n/a (no gate in this arm)" in markdown
    assert markdown.index("## Counter-evidence first") < markdown.index("## Primary W vs B+")


def test_incomplete_operator_run_is_reported_and_counts_toward_cap(fixture_tree, tmp_path):
    target = fixture_tree["ledger"][0]
    target["completed"] = False
    target["status_reason"] = "quota abort before ledger completion marker"
    audit_path = _attempt_dir(fixture_tree, target) / "audit.jsonl"
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
    audit[-1]["end_reason"] = "operator"
    write_jsonl(audit_path, audit)
    write_jsonl(fixture_tree["out"] / "ledger.jsonl", fixture_tree["ledger"])

    report_dir = tmp_path / "ledger-incomplete-report"
    assert main([
        "--pack", str(PACK), "--series", "main",
        "--out-root", str(fixture_tree["out"]),
        "--tasks-dir", str(fixture_tree["tasks"]),
        "--report-dir", str(report_dir),
        "--reexec", "non-registered-dry-run",
    ]) == 0

    report = json.loads((report_dir / "analysis-report.json").read_text())
    outcome = next(row for row in report["outcome_rows"] if row["run_id"] == target["run_id"])
    assert len(report["outcome_rows"]) == 18
    assert outcome["outcome"] == "operator_abort"
    assert outcome["ledger_incomplete"] is True
    assert report["caps"]["operator_abort_rates"][target["arm"]] == 1 / 6
    assert report["caps"]["compromised_flags"]["operator_abort_over_10pct_any_arm"] is True
    assert report["ledger_incomplete"] == [{
        "run_id": target["run_id"],
        "seat": target["seat"],
        "arm": target["arm"],
        "ledger_status_reason": target["status_reason"],
        "coded_as": "operator_abort",
        "how_coded": "operator_abort (audit end_reason='operator')",
    }]
    markdown = (report_dir / "analysis-report.md").read_text()
    assert "### Ledger-incomplete scoring runs" in markdown
    assert target["run_id"] in markdown
    assert target["status_reason"] in markdown
    assert "operator_abort (audit end_reason='operator')" in markdown


def test_report_dir_inside_out_root_is_rejected(fixture_tree):
    result = main([
        "--pack", str(PACK), "--series", "main",
        "--out-root", str(fixture_tree["out"]),
        "--tasks-dir", str(fixture_tree["tasks"]),
        "--report-dir", str(fixture_tree["out"] / "bad-report"),
        "--reexec", "non-registered-dry-run",
    ])
    assert result == 2
    assert not (fixture_tree["out"] / "bad-report").exists()


def test_non_registered_dry_run_never_modifies_out_root(fixture_tree, tmp_path):
    before = {
        path.relative_to(fixture_tree["out"]): path.read_bytes()
        for path in fixture_tree["out"].rglob("*") if path.is_file()
    }
    assert main([
        "--pack", str(PACK), "--series", "main",
        "--out-root", str(fixture_tree["out"]),
        "--tasks-dir", str(fixture_tree["tasks"]),
        "--report-dir", str(tmp_path / "report"),
        "--reexec", "non-registered-dry-run",
    ]) == 0
    after = {
        path.relative_to(fixture_tree["out"]): path.read_bytes()
        for path in fixture_tree["out"].rglob("*") if path.is_file()
    }
    assert after == before


def test_crossover_report_makes_no_alpha_decision(fixture_tree, tmp_path):
    rows = fixture_tree["ledger"]
    for row in rows:
        row["series"] = "crossover"
        row["cell"] = "crossover"
        parts = Path(row["output"]).parts
        suffix = parts[parts.index(fixture_tree["out"].name) + 1:]
        audit_path = fixture_tree["out"].joinpath(*suffix) / "audit.jsonl"
        audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
        audit[0]["cell"] = "crossover"
        write_jsonl(audit_path, audit)
    write_jsonl(fixture_tree["out"] / "ledger.jsonl", rows)
    report_dir = tmp_path / "crossover-report"
    assert main([
        "--pack", str(PACK), "--series", "crossover",
        "--out-root", str(fixture_tree["out"]),
        "--tasks-dir", str(fixture_tree["tasks"]),
        "--report-dir", str(report_dir), "--reexec", "non-registered-dry-run",
    ]) == 0
    report = json.loads((report_dir / "analysis-report.json").read_text())
    assert report["primary"]["confirmatory"] is False
    assert report["primary"]["decision_rule"] is None
    markdown = (report_dir / "analysis-report.md").read_text()
    assert "descriptive only, no α, no pooling with the main series" in markdown
    assert "## Primary W vs B+" not in markdown
    assert "H-primary is confirmed" not in markdown


def test_docker_cli_verifies_image_requires_archives_reexecutes_and_decides(fixture_tree, tmp_path):
    _write_valid_snapshot_archives(fixture_tree)
    calls = []
    report_dir = tmp_path / "docker-report"
    assert main([
        "--pack", str(PACK), "--series", "main",
        "--out-root", str(fixture_tree["out"]),
        "--tasks-dir", str(fixture_tree["tasks"]),
        "--report-dir", str(report_dir), "--reexec", "docker",
    ], command_runner=_fake_docker_runner(calls)) == 0

    assert calls[0][0] == [
        "docker", "image", "inspect", "ev005-validate:v3-amd64",
        "--format", "{{.Id}}",
    ]
    docker_runs = [command for command, _ in calls if command[:2] == ["docker", "run"]]
    assert docker_runs[:2] == [
        [
            "docker", "run", "--rm", "--network", "none", "ev005-validate:v3-amd64",
            "cat", "/etc/passwd",
        ],
        [
            "docker", "run", "--rm", "--network", "none", "ev005-validate:v3-amd64",
            "cat", "/etc/group",
        ],
    ]
    reexecution_commands = docker_runs[2:]
    assert len(reexecution_commands) == 18
    identity_mount_pairs = {
        tuple(value for value in command if value.endswith((":/etc/passwd:ro", ":/etc/group:ro")))
        for command in reexecution_commands
    }
    assert len(identity_mount_pairs) == 1
    for command in reexecution_commands:
        passwd_index = next(i for i, value in enumerate(command) if value.endswith(":/etc/passwd:ro"))
        group_index = next(i for i, value in enumerate(command) if value.endswith(":/etc/group:ro"))
        tree_index = next(i for i, value in enumerate(command) if value.endswith(":/work/replica:rw"))
        assert passwd_index < group_index < tree_index
    reexec_rows = [
        json.loads(line)
        for line in (report_dir / "pipeline-reexec.jsonl").read_text().splitlines()
    ]
    assert len(reexec_rows) == 18
    assert {row["invoker"] for row in reexec_rows} == {"pipeline"}
    report = json.loads((report_dir / "analysis-report.json").read_text())
    assert report["registered_adjudication"] is True
    assert report["provenance"]["image_id_verified_in_this_run"] is True
    assert {row["adjudication_provenance"] for row in report["outcome_rows"]} == {"reexec"}
    markdown = (report_dir / "analysis-report.md").read_text()
    assert "NON-REGISTERED DRY RUN" not in markdown.splitlines()[0]
    assert f"**{report['primary']['decision_sentence']}**" in markdown


def test_docker_cli_identity_provision_failure_aborts_before_reexecution(fixture_tree, tmp_path):
    _write_valid_snapshot_archives(fixture_tree)
    calls = []
    expected_image_id = registered_image_id(PACK)

    def runner(command, timeout):
        calls.append((command, timeout))
        if command[:3] == ["docker", "image", "inspect"]:
            return FakeResult(stdout=(expected_image_id + "\n").encode())
        if command[-2:] == ["cat", "/etc/passwd"]:
            return FakeResult(returncode=1, stderr=b"synthetic passwd failure")
        raise AssertionError(f"unexpected command after provisioning failure: {command}")

    report_dir = tmp_path / "failed-identity-report"
    assert main([
        "--pack", str(PACK), "--series", "main",
        "--out-root", str(fixture_tree["out"]),
        "--tasks-dir", str(fixture_tree["tasks"]),
        "--report-dir", str(report_dir), "--reexec", "docker",
    ], command_runner=runner) == 2
    assert len(calls) == 2
    assert not report_dir.exists()


def test_docker_retention_failure_uses_in_run_audit_and_is_published(fixture_tree, tmp_path):
    _extend_fixture_to_six_tasks(fixture_tree)
    _write_valid_snapshot_archives(fixture_tree)
    target = fixture_tree["ledger"][0]
    snapshots = _attempt_dir(fixture_tree, target) / "snapshots"
    failure = {
        "protocol": 1,
        "run_id": target["run_id"],
        "stage": "validate",
        "error": "synthetic retention validation failure",
    }
    (snapshots / "export-error.json").write_text(json.dumps(failure))
    calls = []
    report_dir = tmp_path / "retention-report"
    assert main([
        "--pack", str(PACK), "--series", "main",
        "--out-root", str(fixture_tree["out"]),
        "--tasks-dir", str(fixture_tree["tasks"]),
        "--report-dir", str(report_dir), "--reexec", "docker",
    ], command_runner=_fake_docker_runner(calls)) == 0

    assert len([command for command, _ in calls if command[:2] == ["docker", "run"]]) == 55
    report = json.loads((report_dir / "analysis-report.json").read_text())
    outcome = next(row for row in report["outcome_rows"] if row["run_id"] == target["run_id"])
    assert outcome["adjudication_provenance"] == "in-run-audit"
    published = report["retention_failures"][target["arm"]]
    assert published == [{"task_id": target["task_id"], **failure}]
    assert report["caps"]["retention_failure_rates"][target["arm"]] == 1 / 18
    assert report["caps"]["compromised_flags"]["retention_failures_over_10pct_any_arm"] is False
    assert report["experiment_status"] == "not_compromised"
    assert report["counter_evidence"]["retention_failures"] == report["retention_failures"]
    markdown = (report_dir / "analysis-report.md").read_text()
    assert "synthetic retention validation failure" in markdown


def test_docker_retention_failures_over_ten_percent_compromise_experiment(fixture_tree, tmp_path):
    _extend_fixture_to_six_tasks(fixture_tree)
    _write_valid_snapshot_archives(fixture_tree)
    targets = [row for row in fixture_tree["ledger"] if row["arm"] == "W"][:2]
    for target in targets:
        snapshots = _attempt_dir(fixture_tree, target) / "snapshots"
        snapshots.joinpath("export-error.json").write_text(json.dumps({
            "protocol": 1,
            "run_id": target["run_id"],
            "stage": "validate",
            "error": f"synthetic retention validation failure for {target['run_id']}",
        }))
    calls = []
    report_dir = tmp_path / "retention-cap-report"
    assert main([
        "--pack", str(PACK), "--series", "main",
        "--out-root", str(fixture_tree["out"]),
        "--tasks-dir", str(fixture_tree["tasks"]),
        "--report-dir", str(report_dir), "--reexec", "docker",
    ], command_runner=_fake_docker_runner(calls)) == 0

    assert len([command for command, _ in calls if command[:2] == ["docker", "run"]]) == 54
    report = json.loads((report_dir / "analysis-report.json").read_text())
    assert report["caps"]["retention_failure_rates"]["W"] == 2 / 18
    assert report["caps"]["compromised_flags"]["retention_failures_over_10pct_any_arm"] is True
    assert report["caps"]["compromised"] is True
    assert report["experiment_status"] == "compromised"
    markdown = (report_dir / "analysis-report.md").read_text()
    assert "retention_failures_over_10pct_any_arm | True" in markdown
    assert "Experiment status: **compromised**" in markdown


def test_non_registered_dry_run_retention_failure_cap_stays_false_with_note(fixture_tree, tmp_path):
    target = fixture_tree["ledger"][0]
    snapshots = _attempt_dir(fixture_tree, target) / "snapshots"
    snapshots.mkdir()
    snapshots.joinpath("export-error.json").write_text(json.dumps({
        "protocol": 1,
        "run_id": target["run_id"],
        "stage": "validate",
        "error": "synthetic retention validation failure",
    }))
    report_dir = tmp_path / "dry-run-retention-cap-report"
    assert main([
        "--pack", str(PACK), "--series", "main",
        "--out-root", str(fixture_tree["out"]),
        "--tasks-dir", str(fixture_tree["tasks"]),
        "--report-dir", str(report_dir), "--reexec", "non-registered-dry-run",
    ]) == 0

    report = json.loads((report_dir / "analysis-report.json").read_text())
    assert report["caps"]["retention_failure_rates"][target["arm"]] == 1 / 6
    assert report["caps"]["compromised_flags"]["retention_failures_over_10pct_any_arm"] is False
    assert report["caps"]["retention_failure_cap_note"] == (
        "Not evaluated: adjudication mode 'non-registered-dry-run' uses in-run adjudication by "
        "mode, so the retention-failure cap is not registered here."
    )
    markdown = (report_dir / "analysis-report.md").read_text()
    assert (
        "Not evaluated: adjudication mode 'non-registered-dry-run' uses in-run adjudication by "
        "mode, so the retention-failure cap is not registered here."
    ) in markdown


def test_double_void_stops_whole_block_adjusts_denominators_and_compromises(fixture_tree, tmp_path):
    block_rows = [row for row in fixture_tree["ledger"] if row["block_id"] == "t01-k1"]
    retry_rows = []
    for row in block_rows:
        row["scoring_attempt"] = False
        row["void"] = True
        row["void_reason"] = "first-wave infrastructure void"
        source = _attempt_dir(fixture_tree, row)
        retry = dict(row)
        retry["run_id"] = row["run_id"] + "-retry"
        retry["attempt"] = 2
        retry["scoring_attempt"] = True
        retry["void"] = row["arm"] == "W"
        retry["void_reason"] = "second-wave infrastructure void" if retry["void"] else None
        retry["output"] = row["output"].replace("attempt-001", "attempt-002")
        destination = _attempt_dir(fixture_tree, retry)
        audit = [json.loads(line) for line in (source / "audit.jsonl").read_text().splitlines()]
        audit[0]["run_id"] = retry["run_id"]
        write_jsonl(destination / "audit.jsonl", audit)
        retry_rows.append(retry)
    write_jsonl(
        fixture_tree["out"] / "ledger.jsonl",
        fixture_tree["ledger"] + retry_rows,
    )

    report_dir = tmp_path / "double-void-report"
    assert main([
        "--pack", str(PACK), "--series", "main",
        "--out-root", str(fixture_tree["out"]),
        "--tasks-dir", str(fixture_tree["tasks"]),
        "--report-dir", str(report_dir),
        "--reexec", "non-registered-dry-run",
    ]) == 0
    report = json.loads((report_dir / "analysis-report.json").read_text())
    assert report["task_arm_denominators"]["t01"] == {"W": 2, "B+": 2, "B": 2}
    assert report["task_arm_denominators"]["t02"] == {"W": 3, "B+": 3, "B": 3}
    assert report["tango_run_level_w_vs_bplus"]["pairs"] == 5
    assert report["caps"]["compromised_flags"]["double_voided_blocks_present"] is True
    assert report["caps"]["voided_attempts_per_arm"] == {"W": 2, "B+": 1, "B": 1}
    assert report["caps"]["stopped_blocks"][0]["block_id"] == "t01-k1"
    assert report["experiment_status"] == "compromised"
    assert report["counter_evidence"]["experiment_status"] == "compromised"
    markdown = (report_dir / "analysis-report.md").read_text()
    assert "Experiment status: **compromised**" in markdown
    assert "Per §5 the experiment is reported as compromised; no unqualified primary claim is made." in markdown


def test_w_rejected_gate_but_docker_green_is_false_done_and_listed(fixture_tree, tmp_path):
    target = next(row for row in fixture_tree["ledger"] if row["arm"] == "W")
    audit_path = _attempt_dir(fixture_tree, target) / "audit.jsonl"
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
    gate = next(
        event for event in audit
        if event.get("event") == "donecheck_invocation" and event.get("invoker") == "gate"
    )
    gate["exit"] = 1
    audit[-1]["end_reason"] = "session_end"
    write_jsonl(audit_path, audit)
    _write_valid_snapshot_archives(fixture_tree)
    report_dir = tmp_path / "w-disagreement-report"
    assert main([
        "--pack", str(PACK), "--series", "main",
        "--out-root", str(fixture_tree["out"]),
        "--tasks-dir", str(fixture_tree["tasks"]),
        "--report-dir", str(report_dir), "--reexec", "docker",
    ], command_runner=_fake_docker_runner([])) == 0
    report = json.loads((report_dir / "analysis-report.json").read_text())
    outcome = next(row for row in report["outcome_rows"] if row["run_id"] == target["run_id"])
    assert outcome["outcome"] == "false_done"
    assert report["disagreements"]["w_gate"] == [target["run_id"]]


def test_removed_task_codes_every_sibling_check_bug_in_published_rows(fixture_tree, tmp_path):
    target = next(row for row in fixture_tree["ledger"] if row["task_id"] == "t01")
    audit_path = _attempt_dir(fixture_tree, target) / "audit.jsonl"
    audit = [json.loads(line) for line in audit_path.read_text().splitlines()]
    declaration = audit[1]
    declaration["snapshot_sha"] = None
    declaration["snapshot_failure"] = "synthetic demonstrable donecheck defect candidate"
    for event in audit[2:-1]:
        if event.get("event") == "donecheck_invocation":
            event["tree_sha"] = None
    write_jsonl(audit_path, audit)
    report_dir = tmp_path / "check-bug-report"
    assert main([
        "--pack", str(PACK), "--series", "main",
        "--out-root", str(fixture_tree["out"]),
        "--tasks-dir", str(fixture_tree["tasks"]),
        "--report-dir", str(report_dir),
        "--reexec", "non-registered-dry-run",
        "--check-bug-removals", "t01",
    ]) == 0
    report = json.loads((report_dir / "analysis-report.json").read_text())
    removed_rows = [row for row in report["outcome_rows"] if row["task_id"] == "t01"]
    assert len(removed_rows) == 9
    assert {row["outcome"] for row in removed_rows} == {"check_bug"}
    assert all(row["excluded_by_check_bug_removal"] for row in removed_rows)
