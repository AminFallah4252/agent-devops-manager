#!/usr/bin/env python3
"""
DevOps Manager: Strict Configuration Validation CLI Tool
Invariant: [INV-005] Strict Configuration Validation

Validates configuration files (e.g. config.json, config.template.json) against
schemas/config.schema.json (JSON Schema Draft 2020-12 / Draft 7).
"""

import argparse
import json
import os
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import jsonschema
    from jsonschema import Draft202012Validator
except ImportError:
    jsonschema = None  # type: ignore
    Draft202012Validator = None  # type: ignore


@dataclass
class ValidationErrorItem:
    path: str
    constraint: str
    message: str
    remediation: str


@dataclass
class ValidationReport:
    valid: bool
    config_file: str
    schema_file: str
    errors: List[ValidationErrorItem]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "valid": self.valid,
            "config_file": self.config_file,
            "schema_file": self.schema_file,
            "error_count": len(self.errors),
            "errors": [
                {
                    "path": err.path,
                    "constraint": err.constraint,
                    "message": err.message,
                    "remediation": err.remediation,
                }
                for err in self.errors
            ],
        }


class Style:
    """ANSI color formatting helpers with automated terminal detection."""

    def __init__(self, enabled: bool):
        self.enabled = enabled

    @property
    def RESET(self) -> str:
        return "\033[0m" if self.enabled else ""

    @property
    def BOLD(self) -> str:
        return "\033[1m" if self.enabled else ""

    @property
    def RED(self) -> str:
        return "\033[91m" if self.enabled else ""

    @property
    def GREEN(self) -> str:
        return "\033[92m" if self.enabled else ""

    @property
    def YELLOW(self) -> str:
        return "\033[93m" if self.enabled else ""

    @property
    def BLUE(self) -> str:
        return "\033[94m" if self.enabled else ""

    @property
    def CYAN(self) -> str:
        return "\033[96m" if self.enabled else ""

    @property
    def GRAY(self) -> str:
        return "\033[90m" if self.enabled else ""


def _generate_remediation(
    validator_name: str,
    validator_value: Any,
    error_message: str,
    path: str,
    instance: Any,
) -> str:
    """Generate human-actionable remediation instructions for schema errors."""
    if validator_name == "required":
        prop = error_message.split("'")[1] if "'" in error_message else "property"
        if "safety" in path:
            return f"Add missing safety flag '{prop}: true' in '{path}'."
        if "thresholds" in path:
            return (
                f"Add missing threshold '{prop}' in '{path}' "
                "(e.g. min_free_disk_gb: 3.0, max_disk_usage_percent: 88.0, max_ram_usage_percent: 85.0)."
            )
        if "web_gateway" in path:
            return f"Add required gateway property '{prop}' in '{path}'."
        if "observability" in path:
            return f"Add required observability property '{prop}' in '{path}'."
        if "profiles" in path:
            return f"Add required profile property '{prop}' in '{path}'."
        return f"Add required property '{prop}' to '{path}'."

    if validator_name == "minimum":
        return f"Increase value to at least {validator_value} (current: {instance}) at '{path}'."

    if validator_name == "maximum":
        return f"Decrease value to at most {validator_value} (current: {instance}) at '{path}'."

    if validator_name == "type":
        curr_type = type(instance).__name__
        return f"Change value type to '{validator_value}' (current type: {curr_type}) at '{path}'."

    if validator_name == "additionalProperties":
        prop = error_message.split("'")[1] if "'" in error_message else "property"
        return f"Remove disallowed property '{prop}' from '{path}' or check for spelling errors."

    if validator_name == "minProperties":
        return f"Define at least {validator_value} property in '{path}'."

    if validator_name == "minLength":
        return f"Ensure value at '{path}' is not empty (minimum length: {validator_value})."

    return f"Update '{path}' to satisfy constraint '{validator_name}'."


def validate_data(
    config_data: Any,
    schema_data: Dict[str, Any],
    config_label: str = "<config>",
    schema_label: str = "<schema>",
) -> ValidationReport:
    """Validate parsed configuration data against schema and business rules."""
    errors: List[ValidationErrorItem] = []

    if jsonschema is not None and Draft202012Validator is not None:
        try:
            Draft202012Validator.check_schema(schema_data)
            validator = Draft202012Validator(schema_data)
            schema_errors = sorted(validator.iter_errors(config_data), key=lambda e: str(e.path))

            for err in schema_errors:
                path = ".".join(str(p) for p in err.path) if err.path else "(root)"
                remediation = _generate_remediation(
                    err.validator or "unknown",
                    err.validator_value,
                    err.message,
                    path,
                    err.instance,
                )
                errors.append(
                    ValidationErrorItem(
                        path=path,
                        constraint=str(err.validator or "schema"),
                        message=err.message,
                        remediation=remediation,
                    )
                )
        except Exception as e:
            errors.append(
                ValidationErrorItem(
                    path="(schema)",
                    constraint="schema_validation",
                    message=f"Schema validation error: {e}",
                    remediation="Verify that the schema adheres to standard JSON Schema specifications.",
                )
            )
    else:
        # Fallback structural validation if jsonschema package is missing
        if not isinstance(config_data, dict):
            errors.append(
                ValidationErrorItem(
                    path="(root)",
                    constraint="type",
                    message="Configuration root must be a JSON object",
                    remediation="Wrap configuration settings inside a top-level JSON object {}.",
                )
            )
        else:
            if "active_profile" not in config_data:
                errors.append(
                    ValidationErrorItem(
                        path="(root)",
                        constraint="required",
                        message="'active_profile' is a required property",
                        remediation="Add 'active_profile' pointing to a key in 'profiles'.",
                    )
                )
            if "profiles" not in config_data or not isinstance(config_data.get("profiles"), dict):
                errors.append(
                    ValidationErrorItem(
                        path="(root)",
                        constraint="required",
                        message="'profiles' must be a non-empty object",
                        remediation="Define a 'profiles' object with at least one profile.",
                    )
                )

    # Invariant: active_profile must match a key in profiles
    if isinstance(config_data, dict):
        active_profile = config_data.get("active_profile")
        profiles = config_data.get("profiles")
        if isinstance(profiles, dict) and active_profile is not None:
            if active_profile not in profiles:
                available = ", ".join(f"'{k}'" for k in sorted(profiles.keys())) or "none"
                errors.append(
                    ValidationErrorItem(
                        path="active_profile",
                        constraint="active_profile_ref",
                        message=(
                            f"Active profile '{active_profile}' does not match any key in 'profiles' "
                            f"(available: {available})"
                        ),
                        remediation=(
                            f"Set 'active_profile' to one of [{available}], "
                            f"or define a matching profile '{active_profile}' under 'profiles'."
                        ),
                    )
                )

    return ValidationReport(
        valid=(len(errors) == 0),
        config_file=config_label,
        schema_file=schema_label,
        errors=errors,
    )


def validate_file(config_path: Path, schema_path: Path) -> ValidationReport:
    """Load and validate files from disk."""
    errors: List[ValidationErrorItem] = []

    # Check and load config file
    if not config_path.is_file():
        errors.append(
            ValidationErrorItem(
                path="(file)",
                constraint="file_exists",
                message=f"Configuration file not found: {config_path}",
                remediation=f"Verify that file exists or pass a valid path via --config <path>.",
            )
        )
        return ValidationReport(
            valid=False,
            config_file=str(config_path),
            schema_file=str(schema_path),
            errors=errors,
        )

    try:
        with open(config_path, "r", encoding="utf-8") as f:
            config_data = json.load(f)
    except json.JSONDecodeError as e:
        errors.append(
            ValidationErrorItem(
                path=f"line {e.lineno}, col {e.colno}",
                constraint="json_syntax",
                message=f"JSON syntax error: {e.msg}",
                remediation="Ensure file contains valid JSON without trailing commas or syntax mistakes.",
            )
        )
        return ValidationReport(
            valid=False,
            config_file=str(config_path),
            schema_file=str(schema_path),
            errors=errors,
        )
    except Exception as e:
        errors.append(
            ValidationErrorItem(
                path="(file)",
                constraint="file_read",
                message=f"Unable to read configuration file: {e}",
                remediation="Ensure proper file permissions and valid UTF-8 encoding.",
            )
        )
        return ValidationReport(
            valid=False,
            config_file=str(config_path),
            schema_file=str(schema_path),
            errors=errors,
        )

    # Check and load schema file
    if not schema_path.is_file():
        errors.append(
            ValidationErrorItem(
                path="(schema)",
                constraint="schema_exists",
                message=f"Schema file not found: {schema_path}",
                remediation=f"Verify that schema exists or pass a valid path via --schema <path>.",
            )
        )
        return ValidationReport(
            valid=False,
            config_file=str(config_path),
            schema_file=str(schema_path),
            errors=errors,
        )

    try:
        with open(schema_path, "r", encoding="utf-8") as f:
            schema_data = json.load(f)
    except json.JSONDecodeError as e:
        errors.append(
            ValidationErrorItem(
                path=f"line {e.lineno}, col {e.colno}",
                constraint="schema_syntax",
                message=f"Schema JSON syntax error: {e.msg}",
                remediation="Fix JSON syntax in the schema definition file.",
            )
        )
        return ValidationReport(
            valid=False,
            config_file=str(config_path),
            schema_file=str(schema_path),
            errors=errors,
        )
    except Exception as e:
        errors.append(
            ValidationErrorItem(
                path="(schema)",
                constraint="schema_read",
                message=f"Unable to read schema file: {e}",
                remediation="Ensure proper file permissions and valid UTF-8 encoding.",
            )
        )
        return ValidationReport(
            valid=False,
            config_file=str(config_path),
            schema_file=str(schema_path),
            errors=errors,
        )

    return validate_data(
        config_data=config_data,
        schema_data=schema_data,
        config_label=str(config_path),
        schema_label=str(schema_path),
    )


def resolve_default_config(repo_root: Path) -> Path:
    """Determine default config path: config.json if present, else config.template.json."""
    cwd_config = Path.cwd() / "config.json"
    if cwd_config.is_file():
        return cwd_config

    repo_config = repo_root / "config.json"
    if repo_config.is_file():
        return repo_config

    cwd_template = Path.cwd() / "config.template.json"
    if cwd_template.is_file():
        return cwd_template

    repo_template = repo_root / "config.template.json"
    if repo_template.is_file():
        return repo_template

    return repo_config


def resolve_default_schema(repo_root: Path) -> Path:
    """Determine default schema path: schemas/config.schema.json."""
    cwd_schema = Path.cwd() / "schemas" / "config.schema.json"
    if cwd_schema.is_file():
        return cwd_schema

    return repo_root / "schemas" / "config.schema.json"


def print_report(report: ValidationReport, style: Style) -> None:
    """Render human-friendly ANSI report."""
    border = "=" * 70
    print(border)
    print(f"  {style.BOLD}DevOps Manager: Configuration Validation{style.RESET}")
    print(border)
    print(f"  {style.CYAN}Config Path:{style.RESET} {report.config_file}")
    print(f"  {style.CYAN}Schema Path:{style.RESET} {report.schema_file}")

    if report.valid:
        print(f"  {style.CYAN}Status:{style.RESET}      {style.GREEN}{style.BOLD}PASSED (Configuration is valid){style.RESET}")
        print(border)
        return

    print(
        f"  {style.CYAN}Status:{style.RESET}      "
        f"{style.RED}{style.BOLD}FAILED ({len(report.errors)} error(s) detected){style.RESET}"
    )
    print("-" * 70)

    for i, err in enumerate(report.errors, 1):
        print(f"{style.RED}{style.BOLD}[ERROR {i}]{style.RESET} At: {style.CYAN}{err.path}{style.RESET}")
        print(f"  {style.BOLD}Violation:{style.RESET}   {err.message}")
        print(f"  {style.BOLD}Constraint:{style.RESET}  {err.constraint}")
        print(f"  {style.YELLOW}{style.BOLD}Remediation:{style.RESET} {err.remediation}")
        if i < len(report.errors):
            print()

    print(border)


def build_parser() -> argparse.ArgumentParser:
    """Build CLI argument parser."""
    parser = argparse.ArgumentParser(
        description="Validate DevOps Manager configurations against schemas/config.schema.json."
    )
    parser.add_argument(
        "-c",
        "--config",
        dest="config_path",
        help="Path to configuration file (default: config.json or config.template.json)",
    )
    parser.add_argument(
        "-s",
        "--schema",
        dest="schema_path",
        help="Path to JSON Schema file (default: schemas/config.schema.json)",
    )
    parser.add_argument(
        "-q",
        "--quiet",
        action="store_true",
        help="Suppress output, returning exit code only (0=valid, 1=invalid)",
    )
    parser.add_argument(
        "--json",
        dest="output_json",
        action="store_true",
        help="Output machine-readable validation report in JSON format",
    )
    parser.add_argument(
        "--no-color",
        dest="no_color",
        action="store_true",
        help="Disable ANSI colored output",
    )
    return parser


def main(argv: Optional[List[str]] = None) -> int:
    """Main CLI entrypoint."""
    if os.name == "nt":
        # Enable VT100 escape sequences on Windows consoles
        os.system("")

    parser = build_parser()
    args = parser.parse_args(argv)

    script_dir = Path(__file__).resolve().parent
    repo_root = script_dir.parent

    config_path = (
        Path(args.config_path).resolve()
        if args.config_path
        else resolve_default_config(repo_root)
    )

    schema_path = (
        Path(args.schema_path).resolve()
        if args.schema_path
        else resolve_default_schema(repo_root)
    )

    report = validate_file(config_path, schema_path)

    if args.output_json:
        print(json.dumps(report.to_dict(), indent=2))
    elif not args.quiet:
        color_enabled = not args.no_color and not os.environ.get("NO_COLOR")
        style = Style(enabled=color_enabled)
        print_report(report, style)

    return 0 if report.valid else 1


if __name__ == "__main__":
    sys.exit(main())
