#!/usr/bin/env python3
"""headless E2E 결과(journey.json)가 기능 목록 전체를 통과 시나리오로 덮는지 확인한다(기준 E6·E7).

    python3 check_e2e_coverage.py --inventory docs/qa/feature-inventory.json --journey build/e2e/journey.json

실패한 시나리오, 덮지 못한 기능, 기능 목록에 없는 기능 ID가 있으면 exit 1이다.
"""
import argparse
import json
import sys


def problems(inventory: dict, journey: dict) -> list[str]:
    raw = inventory.get("features") if isinstance(inventory, dict) else None
    if not isinstance(raw, list) or not raw or not all(isinstance(f, dict) and isinstance(f.get("id"), str) and f["id"].strip() for f in raw):
        return ["기능 목록의 features가 없거나 형식이 맞지 않다"]
    features = [f["id"] for f in raw]
    scenarios = journey.get("scenarios")
    if not isinstance(scenarios, list) or not scenarios:
        return ["journey.json에 시나리오가 없다"]
    found = []
    covered = set()
    for scenario in scenarios:
        sid = scenario.get("id", "?")
        ids = scenario.get("featureIds") if isinstance(scenario.get("featureIds"), list) else []
        if scenario.get("status") != "passed":
            failed = [s.get("name", "?") for s in scenario.get("steps", []) if not s.get("ok")]
            found.append(f"시나리오 실패 {sid}: {', '.join(failed) or 'status=' + str(scenario.get('status'))}")
            continue
        for fid in ids:
            if fid not in features:
                found.append(f"기능 목록에 없는 기능 {sid}: {fid}")
            covered.add(fid)
    found += [f"덮지 못한 기능: {fid}" for fid in features if fid not in covered]
    return found


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--inventory", required=True)
    parser.add_argument("--journey", required=True)
    args = parser.parse_args()
    with open(args.inventory, encoding="utf-8") as f:
        inventory = json.load(f)
    with open(args.journey, encoding="utf-8") as f:
        journey = json.load(f)
    found = problems(inventory, journey)
    for line in found:
        print(line, file=sys.stderr)
    if not found:
        print(f"E2E 커버리지 통과: 기능 {len(inventory.get('features', []))}개, 시나리오 {len(journey['scenarios'])}개")
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main())
