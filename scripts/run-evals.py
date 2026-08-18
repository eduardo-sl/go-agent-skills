#!/usr/bin/env python3
"""Run skill evaluations against an agent command.

Each case file under evals/cases/ declares prompts and the assertions an
answer must satisfy. The runner shells out to whatever agent command you
pass, so it works with any CLI that takes a prompt and prints an answer.

    scripts/run-evals.py --cmd 'claude -p "{prompt}"'
    scripts/run-evals.py --cmd 'claude -p "{prompt}"' --skill go-defensive-coding
    scripts/run-evals.py --dry-run

Compare a run with the skills installed against a run without them. A skill
that does not move the score is a skill that is not earning its context.
"""

import argparse
import json
import pathlib
import re
import shlex
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
CASES_DIR = ROOT / "evals" / "cases"

GREEN, RED, YELLOW, DIM, NC = "\033[0;32m", "\033[0;31m", "\033[1;33m", "\033[2m", "\033[0m"


def load_cases(skill_filter):
    files = sorted(CASES_DIR.glob("*.json"))
    if not files:
        sys.exit(f"no case files in {CASES_DIR}")
    suites = []
    for f in files:
        data = json.loads(f.read_text())
        if skill_filter and data["skill"] != skill_filter:
            continue
        suites.append((f, data))
    if not suites:
        sys.exit(f"no case file matches skill {skill_filter!r}")
    return suites


def run_prompt(cmd_template, prompt, timeout):
    if "{prompt}" in cmd_template:
        cmd = cmd_template.replace("{prompt}", prompt.replace('"', '\\"'))
        proc = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=timeout)
    else:
        proc = subprocess.run(shlex.split(cmd_template), input=prompt,
                              capture_output=True, text=True, timeout=timeout)
    return proc.stdout + proc.stderr


def grade(answer, case):
    flags = 0 if case.get("case_sensitive") else re.IGNORECASE
    failures = []
    for pattern in case.get("expect_all", []):
        if not re.search(pattern, answer, flags):
            failures.append(f"missing: {pattern}")
    for pattern in case.get("expect_none", []):
        if re.search(pattern, answer, flags):
            failures.append(f"forbidden: {pattern}")
    return failures


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--cmd", help="agent command; {prompt} is substituted, else the prompt goes to stdin")
    ap.add_argument("--skill", help="run only this skill's cases")
    ap.add_argument("--timeout", type=int, default=300, help="seconds per case (default 300)")
    ap.add_argument("--dry-run", action="store_true", help="print the prompts, run nothing")
    ap.add_argument("--json", dest="as_json", action="store_true", help="emit machine-readable results")
    ap.add_argument("--label", default="run", help="label for this run, e.g. with-skills / baseline")
    args = ap.parse_args()

    if not args.cmd and not args.dry_run:
        ap.error("--cmd is required unless --dry-run is given")

    suites = load_cases(args.skill)
    results, total, passed = [], 0, 0

    for path, data in suites:
        skill = data["skill"]
        if not args.as_json:
            print(f"\n{skill} {DIM}({path.name}){NC}")
        for case in data["cases"]:
            total += 1
            if args.dry_run:
                print(f"  {DIM}[{case['id']}]{NC} {case['prompt']}")
                continue
            try:
                answer = run_prompt(args.cmd, case["prompt"], args.timeout)
                failures = grade(answer, case)
            except subprocess.TimeoutExpired:
                failures = [f"timeout after {args.timeout}s"]
            ok = not failures
            passed += ok
            results.append({"skill": skill, "id": case["id"], "passed": ok, "failures": failures})
            if not args.as_json:
                mark = f"{GREEN}PASS{NC}" if ok else f"{RED}FAIL{NC}"
                print(f"  {mark} {case['id']}")
                for f in failures:
                    print(f"       {YELLOW}{f}{NC}")

    if args.dry_run:
        print(f"\n{total} case(s) across {len(suites)} suite(s).")
        return 0

    if args.as_json:
        print(json.dumps({"label": args.label, "total": total, "passed": passed,
                          "results": results}, indent=2))
    else:
        pct = (100 * passed // total) if total else 0
        print(f"\n{'=' * 40}\n{args.label}: {passed}/{total} ({pct}%)\n{'=' * 40}")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
