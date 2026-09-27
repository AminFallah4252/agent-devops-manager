"""
DevOps Manager: Configuration Validation Test Suite
Invariant: [INV-005] Strict Configuration Validation

Tests config validation against schemas/config.schema.json.
Validates valid configs, missing safety flags, missing thresholds,
out-of-range ports/values, invalid data types, and CLI behavior.
"""

import copy
import json
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict

import pytest

# Add repository root to python path to import validate-config module
REPO_ROOT = Path(__file__).resolve().parent.parent.parent
SCRIPTS_DIR = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS_DIR))

# Dynamic import of validate-config module
import importlib.util

spec = importlib.util.spec_from_file_location("validate_config", SCRIPTS_DIR / "validate-config.py")
assert spec and spec.loader
validate_config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validate_config)


@pytest.fixture
def repo_root() -> Path:
    return REPO_ROOT


@pytest.fixture
def schema_path(repo_root: Path) -> Path:
    return repo_root / "schemas" / "config.schema.json"


@pytest.fixture
def schema_data(schema_path: Path) -> Dict[str, Any]:
    with open(schema_path, "r", encoding="utf-8") as f:
        return json.load(f)


@pytest.fixture
def template_config_path(repo_root: Path) -> Path:
    return repo_root / "config.template.json"


@pytest.fixture
def template_config_data(template_config_path: Path) -> Dict[str, Any]:
    with open(template_config_path, "r", encoding="utf-8") as f:
        return json.load(f)


@pytest.fixture
def fixture_config_path(repo_root: Path) -> Path:
    return repo_root / "tests" / "fixtures" / "test-config.json"


@pytest.fixture
def fixture_config_data(fixture_config_path: Path) -> Dict[str, Any]:
    with open(fixture_config_path, "r", encoding="utf-8") as f:
        return json.load(f)


# ==============================================================================
# 1. Valid Configuration Tests
# ==============================================================================

def test_template_config_valid(template_config_data: Dict[str, Any], schema_data: Dict[str, Any]):
    """Ensure config.template.json passes validation 100%."""
    report = validate_config.validate_data(template_config_data, schema_data)
    assert report.valid is True
    assert len(report.errors) == 0


def test_fixture_config_valid(fixture_config_data: Dict[str, Any], schema_data: Dict[str, Any]):
    """Ensure tests/fixtures/test-config.json passes validation 100%."""
    report = validate_config.validate_data(fixture_config_data, schema_data)
    assert report.valid is True
    assert len(report.errors) == 0


def test_validate_file_template(template_config_path: Path, schema_path: Path):
    """Ensure validate_file correctly handles disk files for config.template.json."""
    report = validate_config.validate_file(template_config_path, schema_path)
    assert report.valid is True
    assert len(report.errors) == 0


def test_validate_file_fixture(fixture_config_path: Path, schema_path: Path):
    """Ensure validate_file correctly handles disk files for test-config.json."""
    report = validate_config.validate_file(fixture_config_path, schema_path)
    assert report.valid is True
    assert len(report.errors) == 0


# ==============================================================================
# 2. Invalid Configuration: Missing Safety Flags
# ==============================================================================

@pytest.mark.parametrize(
    "flag_to_remove",
    [
        "enforce_docker_only",
        "protect_active_volumes",
        "require_preflight_checks",
        "dry_run_nginx_reload",
    ],
)
def test_missing_safety_flags(
    template_config_data: Dict[str, Any],
    schema_data: Dict[str, Any],
    flag_to_remove: str,
):
    """Ensure omitting any safety flag causes validation failure."""
    cfg = copy.deepcopy(template_config_data)
    profile = cfg["profiles"]["production"]
    del profile["safety"][flag_to_remove]

    report = validate_config.validate_data(cfg, schema_data)
    assert report.valid is False
    assert any(flag_to_remove in err.message for err in report.errors)
    assert any(err.constraint == "required" for err in report.errors)


def test_missing_safety_object(template_config_data: Dict[str, Any], schema_data: Dict[str, Any]):
    """Ensure omitting the safety section entirely fails validation."""
    cfg = copy.deepcopy(template_config_data)
    del cfg["profiles"]["production"]["safety"]

    report = validate_config.validate_data(cfg, schema_data)
    assert report.valid is False
    assert any("safety" in err.message for err in report.errors)


# ==============================================================================
# 3. Invalid Configuration: Missing Thresholds
# ==============================================================================

@pytest.mark.parametrize(
    "threshold_to_remove",
    [
        "min_free_disk_gb",
        "max_disk_usage_percent",
        "max_ram_usage_percent",
    ],
)
def test_missing_threshold_fields(
    template_config_data: Dict[str, Any],
    schema_data: Dict[str, Any],
    threshold_to_remove: str,
):
    """Ensure omitting any required threshold causes validation failure."""
    cfg = copy.deepcopy(template_config_data)
    del cfg["profiles"]["production"]["thresholds"][threshold_to_remove]

    report = validate_config.validate_data(cfg, schema_data)
    assert report.valid is False
    assert any(threshold_to_remove in err.message for err in report.errors)


def test_missing_thresholds_object(template_config_data: Dict[str, Any], schema_data: Dict[str, Any]):
    """Ensure omitting thresholds section entirely fails validation."""
    cfg = copy.deepcopy(template_config_data)
    del cfg["profiles"]["production"]["thresholds"]

    report = validate_config.validate_data(cfg, schema_data)
    assert report.valid is False
    assert any("thresholds" in err.message for err in report.errors)


# ==============================================================================
# 4. Invalid Configuration: Out-of-Range Ports
# ==============================================================================

@pytest.mark.parametrize("invalid_port", [0, -1, 65536, 99999])
def test_out_of_range_ssh_port(
    template_config_data: Dict[str, Any],
    schema_data: Dict[str, Any],
    invalid_port: int,
):
    """Ensure SSH ports outside [1, 65535] are rejected."""
    cfg = copy.deepcopy(template_config_data)
    cfg["profiles"]["production"]["ssh_port"] = invalid_port

    report = validate_config.validate_data(cfg, schema_data)
    assert report.valid is False
    assert any("ssh_port" in err.path for err in report.errors)


@pytest.mark.parametrize("invalid_port", [0, -5, 70000])
def test_out_of_range_observability_ports(
    template_config_data: Dict[str, Any],
    schema_data: Dict[str, Any],
    invalid_port: int,
):
    """Ensure Prometheus and Grafana ports outside [1, 65535] are rejected."""
    cfg = copy.deepcopy(template_config_data)
    cfg["profiles"]["production"]["observability"]["prometheus_port"] = invalid_port
    cfg["profiles"]["production"]["observability"]["grafana_port"] = invalid_port

    report = validate_config.validate_data(cfg, schema_data)
    assert report.valid is False
    assert any("prometheus_port" in err.path for err in report.errors)
    assert any("grafana_port" in err.path for err in report.errors)


# ==============================================================================
# 5. Invalid Configuration: Out-of-Range Thresholds
# ==============================================================================

def test_min_free_disk_below_minimum(template_config_data: Dict[str, Any], schema_data: Dict[str, Any]):
    """Ensure min_free_disk_gb < 0.5 GB fails validation."""
    cfg = copy.deepcopy(template_config_data)
    cfg["profiles"]["production"]["thresholds"]["min_free_disk_gb"] = 0.2

    report = validate_config.validate_data(cfg, schema_data)
    assert report.valid is False
    assert any("min_free_disk_gb" in err.path for err in report.errors)
    assert any(err.constraint == "minimum" for err in report.errors)


@pytest.mark.parametrize("invalid_percent", [0.0, -10.0, 105.0, 200.0])
def test_disk_usage_percent_out_of_range(
    template_config_data: Dict[str, Any],
    schema_data: Dict[str, Any],
    invalid_percent: float,
):
    """Ensure max_disk_usage_percent outside [1, 100] fails validation."""
    cfg = copy.deepcopy(template_config_data)
    cfg["profiles"]["production"]["thresholds"]["max_disk_usage_percent"] = invalid_percent

    report = validate_config.validate_data(cfg, schema_data)
    assert report.valid is False
    assert any("max_disk_usage_percent" in err.path for err in report.errors)


@pytest.mark.parametrize("invalid_percent", [0.0, -5.0, 110.0])
def test_ram_usage_percent_out_of_range(
    template_config_data: Dict[str, Any],
    schema_data: Dict[str, Any],
    invalid_percent: float,
):
    """Ensure max_ram_usage_percent outside [1, 100] fails validation."""
    cfg = copy.deepcopy(template_config_data)
    cfg["profiles"]["production"]["thresholds"]["max_ram_usage_percent"] = invalid_percent

    report = validate_config.validate_data(cfg, schema_data)
    assert report.valid is False
    assert any("max_ram_usage_percent" in err.path for err in report.errors)


# ==============================================================================
# 6. Invalid Configuration: Invalid Types & Additional Properties
# ==============================================================================

def test_invalid_types_rejected(template_config_data: Dict[str, Any], schema_data: Dict[str, Any]):
    """Ensure passing wrong data types triggers type constraint violations."""
    cfg = copy.deepcopy(template_config_data)
    cfg["profiles"]["production"]["ssh_port"] = "22"  # Should be integer
    cfg["profiles"]["production"]["safety"]["protect_active_volumes"] = "true"  # Should be boolean
    cfg["profiles"]["production"]["thresholds"]["min_free_disk_gb"] = "5.0"  # Should be number

    report = validate_config.validate_data(cfg, schema_data)
    assert report.valid is False
    assert any(err.constraint == "type" for err in report.errors)


def test_disallowed_additional_properties(template_config_data: Dict[str, Any], schema_data: Dict[str, Any]):
    """Ensure unknown properties in strict objects are rejected."""
    cfg = copy.deepcopy(template_config_data)
    cfg["profiles"]["production"]["safety"]["unknown_unsafe_option"] = True

    report = validate_config.validate_data(cfg, schema_data)
    assert report.valid is False
    assert any(err.constraint == "additionalProperties" for err in report.errors)


# ==============================================================================
# 7. Semantic Invariant: Active Profile Reference
# ==============================================================================

def test_active_profile_not_in_profiles(template_config_data: Dict[str, Any], schema_data: Dict[str, Any]):
    """Ensure active_profile must match an existing key in profiles."""
    cfg = copy.deepcopy(template_config_data)
    cfg["active_profile"] = "non_existent_profile"

    report = validate_config.validate_data(cfg, schema_data)
    assert report.valid is False
    assert any(err.constraint == "active_profile_ref" for err in report.errors)


# ==============================================================================
# 8. CLI Execution Tests
# ==============================================================================

def test_cli_validate_template(template_config_path: Path):
    """Test CLI returns exit code 0 on config.template.json."""
    cmd = [sys.executable, str(SCRIPTS_DIR / "validate-config.py"), "--config", str(template_config_path)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    assert res.returncode == 0
    assert "PASSED" in res.stdout


def test_cli_validate_fixture(fixture_config_path: Path):
    """Test CLI returns exit code 0 on tests/fixtures/test-config.json."""
    cmd = [sys.executable, str(SCRIPTS_DIR / "validate-config.py"), "--config", str(fixture_config_path)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    assert res.returncode == 0
    assert "PASSED" in res.stdout


def test_cli_quiet_mode(template_config_path: Path):
    """Test CLI --quiet outputs nothing and exits with code 0."""
    cmd = [
        sys.executable,
        str(SCRIPTS_DIR / "validate-config.py"),
        "--config",
        str(template_config_path),
        "-q",
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    assert res.returncode == 0
    assert res.stdout == ""
    assert res.stderr == ""


def test_cli_json_mode(template_config_path: Path):
    """Test CLI --json returns valid parseable JSON."""
    cmd = [
        sys.executable,
        str(SCRIPTS_DIR / "validate-config.py"),
        "--config",
        str(template_config_path),
        "--json",
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    assert res.returncode == 0
    payload = json.loads(res.stdout)
    assert payload["valid"] is True
    assert payload["error_count"] == 0
    assert isinstance(payload["errors"], list)


def test_cli_invalid_config_exits_code_1(tmp_path: Path, schema_path: Path):
    """Test CLI exits with code 1 and descriptive error when config is invalid."""
    bad_config = tmp_path / "bad_config.json"
    bad_config.write_text(
        json.dumps({
            "active_profile": "staging",
            "profiles": {
                "staging": {
                    "name": "Staging",
                    "host": "127.0.0.1",
                    "user": "ubuntu",
                    "ssh_port": 99999,  # invalid
                }
            }
        }),
        encoding="utf-8",
    )

    cmd = [
        sys.executable,
        str(SCRIPTS_DIR / "validate-config.py"),
        "--config",
        str(bad_config),
        "--schema",
        str(schema_path),
    ]
    res = subprocess.run(cmd, capture_output=True, text=True)
    assert res.returncode == 1
    assert "FAILED" in res.stdout
    assert "ssh_port" in res.stdout
    assert "Remediation" in res.stdout


def test_cli_missing_file_exits_code_1(tmp_path: Path):
    """Test CLI exits with code 1 when target configuration file does not exist."""
    missing_file = tmp_path / "does_not_exist.json"
    cmd = [sys.executable, str(SCRIPTS_DIR / "validate-config.py"), "--config", str(missing_file)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    assert res.returncode == 1
    assert "Configuration file not found" in res.stdout
