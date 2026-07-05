#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import os
import re
from pathlib import Path


PRESET_RE = re.compile(r"^\[preset\.(\d+)\]\s*$")
OPTIONS_RE = re.compile(r"^\[preset\.(\d+)\.options\]\s*$")
NAME_RE = re.compile(r'^name="(.+)"\s*$')


def q(value: str) -> str:
	return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def bool_value(value: str, default: bool) -> str:
	if not value:
		return "true" if default else "false"
	return "true" if value.strip().lower() in {"1", "true", "yes", "on"} else "false"


def version_from_tag(tag: str) -> str:
	tag = tag.strip()
	if tag.startswith("v") and len(tag) > 1 and tag[1].isdigit():
		return tag[1:]
	return tag or "0.0.0"


def int_env(name: str, fallback: int) -> int:
	try:
		return int(os.getenv(name, "").strip())
	except ValueError:
		return fallback


def load_sections(lines: list[str]) -> tuple[dict[str, str], dict[str, str]]:
	preset_numbers: dict[str, str] = {}
	options_sections: dict[str, str] = {}
	current_preset = ""
	for line in lines:
		preset = PRESET_RE.match(line)
		if preset:
			current_preset = preset.group(1)
			continue
		options = OPTIONS_RE.match(line)
		if options:
			current_preset = ""
			continue
		name = NAME_RE.match(line)
		if current_preset and name:
			preset_numbers[name.group(1)] = current_preset
	for name, number in preset_numbers.items():
		options_sections[name] = f"preset.{number}.options"
	return preset_numbers, options_sections


def set_updates_for_section(updates: dict[str, dict[str, str]], section: str, values: dict[str, str]) -> None:
	target = updates.setdefault(section, {})
	for key, value in values.items():
		if value != "":
			target[key] = value


def apply_updates(text: str, updates: dict[str, dict[str, str]]) -> str:
	lines = text.splitlines()
	out: list[str] = []
	current_section = ""
	seen: dict[str, set[str]] = {section: set() for section in updates}

	def flush_missing() -> None:
		if current_section in updates:
			for key, value in updates[current_section].items():
				if key not in seen[current_section]:
					out.append(f"{key}={value}")
					seen[current_section].add(key)

	for line in lines:
		if line.startswith("[") and line.endswith("]"):
			flush_missing()
			current_section = line[1:-1]
			out.append(line)
			continue
		if current_section in updates and "=" in line and not line.lstrip().startswith(";"):
			key = line.split("=", 1)[0]
			if key in updates[current_section]:
				out.append(f"{key}={updates[current_section][key]}")
				seen[current_section].add(key)
				continue
		out.append(line)
	flush_missing()
	return "\n".join(out).rstrip() + "\n"


def main() -> None:
	parser = argparse.ArgumentParser(description="Patch Godot export presets for CI.")
	parser.add_argument("--tag", required=True)
	parser.add_argument("--path", default="export_presets.cfg")
	args = parser.parse_args()

	path = Path(args.path)
	text = path.read_text(encoding="utf-8")
	lines = text.splitlines()
	_, options_sections = load_sections(lines)

	version_name = os.getenv("PRODUCT_VERSION", version_from_tag(args.tag))
	version_code = int_env("ANDROID_VERSION_CODE", int_env("GITHUB_RUN_NUMBER", 1))
	apple_team_id = os.getenv("APPLE_TEAM_ID", "ABCDE12345").strip() or "ABCDE12345"
	updates: dict[str, dict[str, str]] = {}

	if "Android" in options_sections:
		set_updates_for_section(updates, options_sections["Android"], {
			"version/code": str(max(version_code, 1)),
			"version/name": q(version_name),
			"package/unique_name": q(os.getenv("ANDROID_PACKAGE_NAME", "com.wangchaozhi.threedchinesemahjong")),
			"package/name": q(os.getenv("ANDROID_APP_NAME", "3D Chinese Mahjong")),
		})
	if "macOS" in options_sections:
		set_updates_for_section(updates, options_sections["macOS"], {
			"application/bundle_identifier": q(os.getenv("MACOS_BUNDLE_ID", "com.wangchaozhi.3dchinesemahjong.macos")),
			"application/short_version": q(version_name),
			"application/version": q(version_name),
			"codesign/codesign": os.getenv("MACOS_CODESIGN_MODE", "1"),
			"codesign/apple_team_id": q(os.getenv("APPLE_TEAM_ID", "")),
		})
	if "iOS" in options_sections:
		set_updates_for_section(updates, options_sections["iOS"], {
			"application/app_store_team_id": q(apple_team_id),
			"application/bundle_identifier": q(os.getenv("IOS_BUNDLE_ID", "com.wangchaozhi.3dchinesemahjong.ios")),
			"application/short_version": q(version_name),
			"application/version": q(version_name),
			"application/export_project_only": bool_value(os.getenv("IOS_EXPORT_PROJECT_ONLY", "true"), True),
			"application/export_method_release": os.getenv("IOS_EXPORT_METHOD_RELEASE", "2"),
			"application/provisioning_profile_uuid_release": q(os.getenv("IOS_PROFILE_UUID_RELEASE", "")),
			"application/provisioning_profile_specifier_release": q(os.getenv("IOS_PROFILE_SPECIFIER_RELEASE", "")),
		})

	path.write_text(apply_updates(text, updates), encoding="utf-8")


if __name__ == "__main__":
	main()
