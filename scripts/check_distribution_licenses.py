#!/usr/bin/env python3
"""Check the recorded distribution-license evidence against a resolved checkout.

This is an offline, fail-closed engineering gate, not a legal or App Store
certification. It checks the complete resolved production dependency graph,
including transitive dependencies, and the target's recorded native components.
It does not infer a native payload's license from its Flutter wrapper.

Run `flutter pub get` before checking. Updating a lockfile never approves a new
license: a reviewer must update licensing/dependencies.json and the native
evidence explicitly. --report is deliberately nonblocking; --enforce fails when
any evidence is missing, stale, unreviewed, or forbidden by the policy.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path
from urllib.parse import urlparse
from urllib.request import url2pathname


PLATFORMS = {"android", "ios", "macos", "linux", "windows"}
ALLOWED_LICENSES = {
    "MIT", "Apache-2.0", "BSD-2-Clause", "BSD-3-Clause", "0BSD", "ISC",
    "Zlib", "Unlicense", "CC0-1.0", "BSL-1.0", "MPL-2.0",
    "LGPL-2.0-only", "LGPL-2.0-or-later", "LGPL-2.1-only",
    "LGPL-2.1-or-later", "LGPL-3.0-only", "LGPL-3.0-or-later",
    "Unicode-3.0", "Unicode-DFS-2016", "OFL-1.1", "blessing",
}
SHA256 = re.compile(r"^[0-9a-f]{64}$")
SPDX_TOKEN = re.compile(r"[A-Za-z0-9][A-Za-z0-9.+:-]*|[()]")


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def tree_digest(root: Path) -> str:
    """Pin local vendored package content, excluding generated build/cache files."""
    ignored = {".git", ".dart_tool", ".build", "build", "__pycache__"}
    h = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if any(part in ignored for part in relative.parts):
            continue
        if path.is_symlink():
            raise ValueError(f"Vendored package contains a symlink: {relative}")
        if not path.is_file():
            continue
        h.update(relative.as_posix().encode())
        h.update(b"\0")
        h.update(path.read_bytes())
        h.update(b"\0")
    return h.hexdigest()


def read_json(path: Path) -> dict:
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError(f"Expected a JSON object: {path}")
    return value


def _scalar(value: str):
    value = value.strip()
    if value.startswith('"'):
        return json.loads(value)
    if value.startswith("'") and value.endswith("'"):
        return value[1:-1].replace("''", "'")
    if value in {"true", "false"}:
        return value == "true"
    return value


def read_pub_lock(path: Path) -> dict[str, dict]:
    """Read pub's generated scalar-map lock format without a YAML dependency.

    Unsupported structures fail rather than silently dropping source metadata.
    This parser is deliberately for pubspec.lock, not arbitrary YAML.
    """
    packages: dict[str, dict] = {}
    current = None
    in_packages = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line == "packages:":
            in_packages = True
            continue
        if in_packages and not line.startswith(" "):
            break
        if not in_packages:
            continue
        match = re.fullmatch(r"  ([A-Za-z0-9_]+):", line)
        if match:
            name = match[1]
            if name in packages:
                raise ValueError(f"Duplicate lockfile package: {name}")
            current = packages[name] = {}
            continue
        match = re.fullmatch(r"    ([A-Za-z0-9_-]+):(?: (.*))?", line)
        if match and current is not None:
            key, raw = match.groups()
            if key in current:
                raise ValueError(f"Duplicate lockfile field: {key}")
            current[key] = {} if raw is None else _scalar(raw)
            continue
        match = re.fullmatch(r"      ([A-Za-z0-9_-]+): (.*)", line)
        if match and current is not None and isinstance(current.get("description"), dict):
            key, raw = match.groups()
            if key in current["description"]:
                raise ValueError(f"Duplicate lockfile description: {key}")
            current["description"][key] = _scalar(raw)
            continue
        raise ValueError(f"Unsupported pubspec.lock structure: {line.strip()}")
    if not packages:
        raise ValueError("pubspec.lock contains no packages; run flutter pub get")
    return packages


def source_pin(lock: dict) -> dict:
    source = lock.get("source")
    description = lock.get("description")
    if source == "hosted" and isinstance(description, dict):
        pin = {"type": source, **{key: description.get(key) for key in ("name", "url", "sha256")}}
        if not all(isinstance(value, str) and value for value in pin.values()) or not SHA256.fullmatch(pin["sha256"]):
            raise ValueError("Hosted dependency is missing its exact archive SHA-256")
        return pin
    if source == "git" and isinstance(description, dict):
        pin = {"type": source, **{key: description.get(key) for key in ("url", "path", "resolved-ref")}}
        if not all(isinstance(value, str) and value for value in pin.values()) or not re.fullmatch(r"[0-9a-f]{40}", pin["resolved-ref"]):
            raise ValueError("Git dependency is missing its exact resolved commit")
        return pin
    if source == "path" and isinstance(description, dict):
        if not isinstance(description.get("path"), str):
            raise ValueError("Path dependency has no path")
        return {"type": source, "path": description["path"], "relative": description.get("relative") is True}
    if source == "sdk" and isinstance(description, str):
        return {"type": source, "sdk": description}
    raise ValueError(f"Unrecognized dependency source: {source}")


def license_problem(expression: object) -> str | None:
    """Validate explicit SPDX metadata, never grep the license's legal prose.

    A GPL text incorporated by LGPL-3.0 is not a separate GPL component. Actual
    GPL/AGPL identifiers are forbidden. Mixed dual-license grants need an
    explicit reviewed selection of an allowed grant in the inventory.
    """
    if not isinstance(expression, str) or not expression.strip():
        return "No reviewed license expression is recorded"
    tokens = SPDX_TOKEN.findall(expression)
    if "".join(tokens) != re.sub(r"\s+", "", expression):
        return "Malformed SPDX license expression"
    position = 0
    identifiers = []

    def atom():
        nonlocal position
        if position >= len(tokens):
            raise ValueError()
        token = tokens[position]
        position += 1
        if token == "(":
            expr()
            if position >= len(tokens) or tokens[position] != ")":
                raise ValueError()
            position += 1
        elif token in {"AND", "OR", "WITH", ")"}:
            raise ValueError()
        else:
            identifiers.append(token)
            if position < len(tokens) and tokens[position] == "WITH":
                # Exceptions need an explicit policy decision; none are
                # automatically approved by this project's current policy.
                position += 1
                if position >= len(tokens) or tokens[position] in {"AND", "OR", "WITH", "(", ")"}:
                    raise ValueError()
                identifiers.append("Exception:" + tokens[position])
                position += 1

    def expr():
        nonlocal position
        atom()
        while position < len(tokens) and tokens[position] in {"AND", "OR"}:
            position += 1
            atom()

    try:
        expr()
        if position != len(tokens):
            raise ValueError()
    except ValueError:
        return "Malformed SPDX license expression"
    forbidden = [value for value in identifiers if re.match(r"^(?:AGPL|GPL)(?:-|$)", value, re.IGNORECASE)]
    if forbidden:
        return "Forbidden license: " + ", ".join(forbidden)
    unknown = [value for value in identifiers if value not in ALLOWED_LICENSES]
    if unknown:
        return "License requires explicit policy review: " + ", ".join(unknown)
    return None


def runtime_closure(graph: dict, root_name: str) -> tuple[set[str], dict[str, dict]]:
    rows = graph.get("packages")
    if not isinstance(rows, list) or root_name not in graph.get("roots", []):
        raise ValueError("Resolved package graph has no expected application root")
    packages = {}
    for row in rows:
        if not isinstance(row, dict) or not isinstance(row.get("name"), str) or row["name"] in packages:
            raise ValueError("Malformed or duplicate resolved package graph entry")
        packages[row["name"]] = row
    pending, seen = [root_name], set()
    while pending:
        name = pending.pop()
        if name in seen:
            continue
        row = packages.get(name)
        if row is None:
            raise ValueError(f"Resolved graph is missing transitive package {name}")
        dependencies = row.get("dependencies", [])
        if not isinstance(dependencies, list) or not all(isinstance(item, str) for item in dependencies):
            raise ValueError(f"Invalid dependencies for {name}")
        seen.add(name)
        pending.extend(dependencies)
    return seen, packages


def local_uri_path(uri: str, relative_base: Path | None = None) -> Path:
    parsed = urlparse(uri)
    if parsed.scheme not in {"", "file"} or parsed.netloc not in {"", "localhost"} or parsed.query or parsed.fragment:
        raise ValueError(f"Unsupported local package URI: {uri}")
    path = Path(url2pathname(parsed.path))
    if parsed.scheme == "file":
        if not path.is_absolute():
            raise ValueError(f"File URI must contain an absolute path: {uri}")
        return path.resolve()
    if parsed.netloc or relative_base is None:
        raise ValueError(f"Relative package URI has no local base: {uri}")
    return (relative_base / path).resolve()


def package_roots(config: dict, config_path: Path) -> dict[str, Path]:
    roots = {}
    for row in config.get("packages", []):
        name, uri = row["name"], row["rootUri"]
        if name in roots:
            raise ValueError(f"Duplicate package-config entry: {name}")
        roots[name] = local_uri_path(uri, config_path.parent)
    return roots


def audit(root: Path, platform: str = "all") -> dict:
    report = {
        "schema_version": 1,
        "platform": platform,
        "scope": "Resolved production Dart graph, exact package/source pins and license-file hashes, plus recorded native evidence for the selected platform. No legal or App Store certification; no inspection of a supplied IPA/APK/executable.",
        "runtime_package_count": 0,
        "native_component_count": 0,
        "findings": [],
    }
    findings = report["findings"]

    def issue(code, component, message):
        findings.append({"severity": "blocker", "code": code, "component": component, "message": message})

    try:
        if platform not in {"all", *PLATFORMS}:
            raise ValueError(f"Unsupported platform: {platform}")
        inventory = read_json(root / "licensing/dependencies.json")
        if inventory.get("schema_version") != 1:
            raise ValueError("Unsupported dependency inventory schema")
        if digest(root / "pubspec.yaml") != inventory.get("root_pubspec_sha256"):
            issue("root_manifest_changed", "pubspec.yaml", "Dependency declarations changed since review; resolve and review the inventory")
        config_path = root / ".dart_tool/package_config.json"
        config = read_json(config_path)
        graph = read_json(root / ".dart_tool/package_graph.json")
        locks = read_pub_lock(root / "pubspec.lock")
        root_name = inventory["root_package"]
        runtime, resolved = runtime_closure(graph, root_name)
        roots = package_roots(config, config_path)
        report["runtime_package_count"] = len(runtime)
        entries = inventory.get("packages", [])
        if not isinstance(entries, list):
            raise ValueError("Dependency inventory packages must be a list")
        recorded = {}
        for entry in entries:
            name = entry["name"]
            if name in recorded:
                raise ValueError(f"Duplicate inventory entry: {name}")
            recorded[name] = entry
        for name in sorted(runtime):
            entry = recorded.get(name)
            if entry is None:
                issue("unreviewed_package", name, "Runtime dependency has no reviewed inventory entry")
                continue
            package_root = roots.get(name)
            if package_root is None or not package_root.is_dir():
                issue("missing_package", name, "Resolved package source is unavailable; run flutter pub get")
                continue
            if resolved[name].get("version") != entry.get("version"):
                issue("version_changed", name, f"Resolved {resolved[name].get('version')} differs from reviewed {entry.get('version')}")
            if digest(package_root / "pubspec.yaml") != entry.get("pubspec_sha256"):
                issue("package_manifest_changed", name, "Package metadata/dependency declarations differ from the reviewed source")
            actual_pin = {"type": "root"} if name == root_name else source_pin(locks.get(name, {}))
            expected_pin = entry.get("source")
            if actual_pin != expected_pin:
                issue("source_changed", name, "Lockfile source/archive/commit differs from reviewed pin")
            if name != root_name and locks.get(name, {}).get("version") != resolved[name].get("version"):
                issue("stale_resolution", name, "Package graph and pubspec.lock disagree; run flutter pub get")
            if actual_pin["type"] == "path":
                expected_tree = entry.get("source_tree_sha256")
                if not isinstance(expected_tree, str) or not SHA256.fullmatch(expected_tree) or tree_digest(package_root) != expected_tree:
                    issue("local_source_changed", name, "Vendored package content differs from its reviewed source tree")
            problem = license_problem(entry.get("license_expression"))
            if problem:
                issue("license_policy", name, problem)
            if entry.get("review_status") != "reviewed":
                issue("review_required", name, f"Recorded review status is {entry.get('review_status', 'missing')}")
            evidence = entry.get("license_files", [])
            if not isinstance(evidence, list) or not evidence:
                issue("missing_license_evidence", name, "No exact license-file evidence was recorded")
                continue
            for item in evidence:
                evidence_package = item.get("package", name)
                base = roots.get(evidence_package)
                relative = item.get("path")
                expected_hash = item.get("sha256")
                if base is None or not isinstance(relative, str) or Path(relative).is_absolute() or ".." in Path(relative).parts or not isinstance(expected_hash, str) or not SHA256.fullmatch(expected_hash):
                    issue("invalid_license_evidence", name, "License evidence must name a package-relative file and SHA-256")
                    continue
                path = (base / relative).resolve()
                if not path.is_relative_to(base) or not path.is_file() or digest(path) != expected_hash:
                    issue("license_evidence_changed", name, f"Missing or changed license file: {evidence_package}/{relative}")
        for name in sorted(set(recorded) - runtime):
            issue("stale_inventory", name, "Recorded package is no longer in the runtime graph; review the inventory")
        for item in inventory.get("native_build_inputs", []):
            targets = item.get("platforms", [])
            if not targets or not set(targets).issubset(PLATFORMS):
                raise ValueError("Native build input has invalid target platforms")
            if platform != "all" and platform not in targets:
                continue
            package = item["package"]
            base = roots.get(package)
            relative = Path(item["path"])
            if base is None or relative.is_absolute() or ".." in relative.parts:
                issue("invalid_native_build_input", package, "Native recipe must be a package-relative path")
                continue
            path = (base / relative).resolve()
            if not path.is_relative_to(base) or not path.is_file() or digest(path) != item.get("sha256"):
                issue("native_build_input_changed", package, f"Missing or changed native dependency recipe: {relative}")
        sdk = inventory.get("sdk", {})
        for key, actual in (("flutter_version", config.get("flutterVersion")), ("dart_version", config.get("generatorVersion"))):
            if sdk.get(key) != actual:
                issue("sdk_changed", "Flutter/Dart SDK", f"{key}: reviewed {sdk.get(key)}, resolved {actual}")
        flutter_uri = config.get("flutterRoot")
        if flutter_uri:
            flutter_root = local_uri_path(flutter_uri)
            version = read_json(flutter_root / "bin/cache/flutter.version.json")
            for key in ("frameworkRevision", "engineRevision", "engineContentHash"):
                if sdk.get(key) != version.get(key):
                    issue("sdk_changed", "Flutter/Dart SDK", f"{key} differs from the recorded SDK build")
        else:
            issue("missing_sdk", "Flutter/Dart SDK", "Resolved SDK location is unavailable")

        native = read_json(root / "licensing/native_artifacts.json")
        if native.get("schema_version") != 1 or not isinstance(native.get("components"), list):
            raise ValueError("Unsupported native inventory schema")
        components = {}
        for entry in native["components"]:
            component = entry["id"]
            if component in components:
                raise ValueError(f"Duplicate native component: {component}")
            components[component] = entry
        required = inventory.get("required_native_components")
        if not isinstance(required, list) or not required:
            raise ValueError("Native coverage requirements are missing from the inventory")
        for requirement in required:
            targets = requirement.get("platforms", [])
            if platform != "all" and platform not in targets:
                continue
            component = requirement["id"]
            entry = components.get(component)
            if entry is None:
                issue("missing_native_component", component, "Required native evidence is missing")
                continue
            if not set(targets).issubset(set(entry.get("platforms", []))):
                issue("native_platform_mismatch", component, "Native evidence omits a required target platform")
        for component, entry in components.items():
            targets = entry.get("platforms")
            if not isinstance(targets, list) or not targets or not set(targets).issubset(PLATFORMS):
                issue("invalid_native_platform", component, "Native evidence has invalid target platforms")
                continue
            if platform != "all" and platform not in targets:
                continue
            report["native_component_count"] += 1
            problem = license_problem(entry.get("license_expression"))
            if problem:
                issue("native_license_policy", component, problem)
            if entry.get("review_status") != "reviewed":
                issue("native_review_required", component, f"Recorded review status is {entry.get('review_status', 'missing')}")
            blockers = entry.get("blockers", [])
            if not isinstance(blockers, list):
                raise ValueError(f"Invalid blockers for {component}")
            for blocker in blockers:
                issue("native_provenance", component, str(blocker))
            if entry.get("review_status") == "reviewed":
                artifact = entry.get("artifact", {})
                artifacts = entry.get("artifacts", [artifact])
                if not artifacts or any(not isinstance(a.get("sha256"), str) or not SHA256.fullmatch(a["sha256"]) for a in artifacts):
                    issue("missing_native_hash", component, "Reviewed native artifacts require exact SHA-256 hashes")
                if not entry.get("source", {}).get("revision") or not entry.get("evidence"):
                    issue("missing_native_provenance", component, "Reviewed native artifacts require source revision and evidence")
            for item in entry.get("evidence", []):
                if "path" not in item:
                    continue
                relative = Path(item["path"])
                path = (root / relative).resolve()
                if relative.is_absolute() or not path.is_relative_to(root.resolve()) or not path.is_file() or digest(path) != item.get("sha256"):
                    issue("native_evidence_changed", component, f"Native evidence file is missing or changed: {relative}")
    except (OSError, ValueError, KeyError, TypeError, AttributeError) as error:
        issue("audit_incomplete", "inventory", str(error))
    report["result"] = "blocked" if findings else "recorded_checks_passed"
    return report


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--report", action="store_true", help="Report blockers without failing CI (default)")
    mode.add_argument("--enforce", action="store_true", help="Fail distribution when any blocker remains")
    parser.add_argument("--platform", choices=["all", *sorted(PLATFORMS)], default="all")
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, help="Also write the full machine-readable JSON report")
    args = parser.parse_args(argv)
    report = audit(args.root.resolve(), args.platform)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(f"Distribution license evidence: {report['result']} ({args.platform})")
    print(f"Checked {report['runtime_package_count']} runtime packages and {report['native_component_count']} native components.")
    for finding in report["findings"]:
        print(f"BLOCKER [{finding['code']}] {finding['component']}: {finding['message']}")
    print(report["scope"])
    if not args.enforce:
        print("Report mode: blockers above remain unresolved; this command does not approve distribution.")
    return 1 if args.enforce and report["findings"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
