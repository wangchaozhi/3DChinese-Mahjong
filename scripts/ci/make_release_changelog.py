#!/usr/bin/env python3
# -*- coding: utf-8 -*-
from __future__ import annotations

import argparse
import datetime as dt
import re
import subprocess
from pathlib import Path


PROJECT_NAME = "3D 中国麻将"


def run_git(args: list[str]) -> str:
	try:
		return subprocess.check_output(
			["git", *args],
			encoding="utf-8",
			errors="replace",
			stderr=subprocess.DEVNULL,
		).strip()
	except (subprocess.CalledProcessError, FileNotFoundError):
		return ""


def tag_exists(tag: str) -> bool:
	return bool(run_git(["rev-parse", "--verify", "--quiet", f"refs/tags/{tag}"]))


def release_date(ref: str) -> str:
	date = run_git(["log", "-1", "--format=%cs", ref])
	if date:
		return date
	return dt.date.today().isoformat()


def previous_tag(tag: str) -> str:
	ref = tag if tag_exists(tag) else "HEAD"
	return run_git(["describe", "--tags", "--abbrev=0", f"{ref}^"])


def changelog_section(path: Path, tag: str) -> str:
	if not path.exists():
		return ""
	text = path.read_text(encoding="utf-8", errors="replace")
	aliases = {tag, tag.lstrip("v"), f"[{tag}]", f"[{tag.lstrip('v')}]"}
	headings = list(re.finditer(r"^(#{2,6})\s+(.+?)\s*$", text, re.MULTILINE))
	for index, match in enumerate(headings):
		level = len(match.group(1))
		title = match.group(2).strip()
		title_key = re.split(r"\s+-\s+|\s+\(", title, maxsplit=1)[0].strip()
		if title_key not in aliases:
			continue
		start = match.end()
		end = len(text)
		for next_heading in headings[index + 1:]:
			if len(next_heading.group(1)) <= level:
				end = next_heading.start()
				break
		return text[start:end].strip()
	return ""


def cleaned_subject(subject: str) -> str:
	subject = re.sub(r"^[a-zA-Z]+(?:\([^)]+\))?!?:\s*", "", subject).strip()
	return subject.rstrip(".")


def commit_updates(tag: str, prev: str) -> list[str]:
	ref = tag if tag_exists(tag) else "HEAD"
	revision_range = f"{prev}..{ref}" if prev else ref
	log = run_git(["log", "--no-merges", "--pretty=format:%s", revision_range])
	updates: list[str] = []
	for line in log.splitlines():
		subject = cleaned_subject(line)
		if subject:
			updates.append(subject)
	return updates


def build_document(tag: str, source_changelog: Path) -> str:
	ref = tag if tag_exists(tag) else "HEAD"
	prev = previous_tag(tag)
	section = changelog_section(source_changelog, tag)
	lines = [
		f"# {PROJECT_NAME} 产品更新日志",
		"",
		f"- 版本: {tag}",
		f"- 发布日期: {release_date(ref)}",
		f"- 构建来源: {run_git(['rev-parse', '--short', ref]) or ref}",
	]
	if prev:
		lines.append(f"- 变更范围: {prev}..{tag}")
	lines.append("")
	lines.append("## 本次更新")
	lines.append("")
	if section:
		lines.append(section)
	else:
		updates = commit_updates(tag, prev)
		if updates:
			for update in updates:
				lines.append(f"- {update}")
		else:
			lines.append("- 本次版本未检测到可自动汇总的提交信息。")
	lines.extend(
		[
			"",
			"## 构建说明",
			"",
			"- Windows 与 Linux 是必需发布构建。",
			"- Web 是允许失败的补充平台；如果 release 中缺少该资产，请查看同名构建日志。",
			"- 每个平台压缩包内都包含本文件，release 资产区也会单独附带一份产品更新日志。",
		]
	)
	return "\n".join(lines).strip() + "\n"


def main() -> None:
	parser = argparse.ArgumentParser(description="Generate product-facing release changelog.")
	parser.add_argument("--tag", required=True, help="Tag or ref name for the release.")
	parser.add_argument("--changelog", default="CHANGELOG.md", help="Source changelog file.")
	parser.add_argument("--output", required=True, help="Product changelog output path.")
	parser.add_argument("--release-notes", help="Optional GitHub release body output path.")
	args = parser.parse_args()

	document = build_document(args.tag, Path(args.changelog))
	output = Path(args.output)
	output.parent.mkdir(parents=True, exist_ok=True)
	output.write_text(document, encoding="utf-8")
	if args.release_notes:
		notes = Path(args.release_notes)
		notes.parent.mkdir(parents=True, exist_ok=True)
		notes.write_text(document, encoding="utf-8")


if __name__ == "__main__":
	main()
