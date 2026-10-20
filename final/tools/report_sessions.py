#!/usr/bin/env python3
"""Cross-session report for the VR Fall-Prevention Training Simulator.

Reads the `session_log.json` written by SessionManager and prints:
  * a per-session table (hazards, rails, balance, overall, change),
  * a per-test table -- hallway, bathroom, stairs, bedroom, balance, each
    scored 0-100 -- which is what the in-game performance board shows and what
    the adaptive focus is chosen from,
  * first-to-latest trends,
  * hazards missed in every session,
  * which test the app focused on, and what it will focus on next.

Usage:
    python3 report_sessions.py path/to/session_log.json
    python3 report_sessions.py path/to/session_log.json --csv out.csv
    python3 report_sessions.py path/to/session_log.json --participant P01

Finding the file (the path is also printed to the Godot console at session end):
    Windows  %APPDATA%\\Godot\\app_userdata\\VR Fall-Prevention Trainer\\
    macOS    ~/Library/Application Support/Godot/app_userdata/VR Fall-Prevention Trainer/
    Linux    ~/.local/share/godot/app_userdata/VR Fall-Prevention Trainer/

Reads both schema 1 (before per-room scoring) and schema 2 logs; for schema 1
sessions the per-room scores are derived from the hazard detail, exactly as the
game does when it looks back at old history.

No third-party dependencies.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from typing import Any

TEST_ORDER = [
    "hallway", "living_room", "kitchen", "bathroom", "staircase", "bedroom", "street",
    "street_crossing", "balance",
]
TEST_NAMES = {
    "hallway": "Hallway",
    "living_room": "Living",
    "kitchen": "Kitchen",
    "bathroom": "Bathroom",
    "staircase": "Stairs",
    "bedroom": "Bedroom",
    "street": "Street",
    "street_crossing": "Crossing",
    "balance": "Balance",
}
FOCUS_THRESHOLD = 90.0
FOCUS_WINDOW = 3


def load(path: str, participant: str | None) -> list[dict[str, Any]]:
    with open(os.path.expanduser(path), encoding="utf-8") as handle:
        doc = json.load(handle)
    sessions = doc.get("sessions", [])
    if participant:
        sessions = [s for s in sessions if s.get("participant_id") == participant]
    if not sessions:
        sys.exit("No sessions in the log yet." if not participant else
                 f"No sessions for participant {participant}.")
    return sessions


def tests_of(session: dict[str, Any]) -> dict[str, float | None]:
    """Per-test scores, derived for schema-1 sessions that predate them."""
    if "tests" in session:
        return session["tests"]
    per_room: dict[str, list[int]] = {}
    for hazard in session.get("hazards", {}).get("detail", []):
        room = hazard.get("room", "")
        if not room:
            continue
        entry = per_room.setdefault(room, [0, 0])
        entry[1] += 1
        if hazard.get("found", False):
            entry[0] += 1
    out: dict[str, float | None] = {
        room: round(100.0 * found / max(total, 1), 1) for room, (found, total) in per_room.items()
    }
    balance = session.get("balance", {})
    out["balance"] = balance.get("mean_stability") if balance.get("trials", 0) else None
    return out


def flatten(session: dict[str, Any], index: int) -> dict[str, Any]:
    hazards = session.get("hazards", {})
    handrail = session.get("handrail", {})
    balance = session.get("balance", {})
    score = session.get("score", {})
    street = session.get("street", {})
    tests = tests_of(session)
    row = {
        "n": index,
        "session_id": session.get("session_id", ""),
        "participant": session.get("participant_id", ""),
        "date": session.get("started_utc", "")[:16].replace("T", " "),
        "minutes": round(float(session.get("duration_seconds", 0.0)) / 60.0, 1),
        "seated": session.get("settings", {}).get("seated_mode", False),
        "xr": session.get("settings", {}).get("xr_active", ""),
        "focus": session.get("focus", {}).get("test", ""),
        "hazards_found": hazards.get("found", 0),
        "hazards_total": hazards.get("total", 0),
        "hazard_pct": float(score.get("hazard", 0.0)),
        "false_positives": hazards.get("false_positives", 0),
        "rail_complied": handrail.get("complied", 0),
        "rail_opportunities": handrail.get("opportunities", 0),
        "rail_pct": float(score.get("handrail", 0.0)),
        "balance_trials": balance.get("trials", 0),
        "balance_completed": balance.get("completed", balance.get("trials", 0)),
        "balance_stability": float(balance.get("mean_stability", 0.0)),
        "balance_time_s": float(balance.get("mean_completion_s", 0.0)),
        "max_sway_cm": float(balance.get("max_sway_cm", 0.0)),
        "near_misses": len(session.get("near_misses", [])),
        "crossings": street.get("crossings", 0),
        "crossed_at_crossing": street.get("used_crossing", 0),
        "looked_both_ways": street.get("looked_both_ways", 0),
        "safe_gap": street.get("safe_gap", 0),
        "crossing_quality": float(street.get("quality_pct", 0.0)),
        "overall": float(score.get("overall", 0.0)),
    }
    for test in TEST_ORDER:
        value = tests.get(test)
        row["test_" + test] = "" if value is None else round(float(value), 1)
    return row


def arrow(delta: float) -> str:
    if abs(delta) < 0.5:
        return "  ="
    return f"{delta:+5.1f}"


def cell(value: Any) -> str:
    return "  -" if value == "" or value is None else f"{float(value):3.0f}"


def print_table(rows: list[dict[str, Any]]) -> None:
    header = (
        f"{'#':>2}  {'date':<16} {'min':>4}  {'hazards':>9} {'haz%':>5}  "
        f"{'rail':>6} {'rail%':>6}  {'steady':>6} {'sway':>5}  {'overall':>7}  {'change':>6}"
    )
    print(header)
    print("-" * len(header))

    previous = None
    for row in rows:
        change = "     -" if previous is None else arrow(row["overall"] - previous["overall"])
        print(
            f"{row['n']:>2}  {row['date']:<16} {row['minutes']:>4}  "
            f"{row['hazards_found']:>4}/{row['hazards_total']:<4} {row['hazard_pct']:>5.0f}  "
            f"{row['rail_complied']:>2}/{row['rail_opportunities']:<3} {row['rail_pct']:>6.0f}  "
            f"{row['balance_stability']:>6.0f} {row['max_sway_cm']:>4.0f}c  "
            f"{row['overall']:>7.1f}  {change:>6}"
        )
        previous = row


def print_test_table(rows: list[dict[str, Any]]) -> None:
    """The per-test scores: the same numbers the in-game board shows."""
    print("\nScore per test (0-100, blank = not done that session)")
    header = f"{'#':>2}  {'date':<16}  " + "  ".join(f"{TEST_NAMES[t]:>8}" for t in TEST_ORDER) + "   focus"
    print(header)
    print("-" * len(header))
    for row in rows:
        cells = "  ".join(f"{cell(row['test_' + t]):>8}" for t in TEST_ORDER)
        focus = TEST_NAMES.get(row["focus"], "")
        print(f"{row['n']:>2}  {row['date']:<16}  {cells}   {focus}")


def print_crossings(rows: list[dict[str, Any]]) -> None:
    """How the road was crossed: the outdoor habit, session by session."""
    if not any(row["crossings"] for row in rows):
        return
    print("\nRoad crossings (of each session's crossings, how many were done well)")
    header = f"{'#':>2}  {'date':<16}  {'crossings':>9}  {'at markings':>11}  {'looked':>7}  {'safe gap':>8}  {'quality':>7}"
    print(header)
    print("-" * len(header))
    for row in rows:
        if not row["crossings"]:
            continue
        print(
            f"{row['n']:>2}  {row['date']:<16}  {row['crossings']:>9}  "
            f"{row['crossed_at_crossing']:>11}  {row['looked_both_ways']:>7}  "
            f"{row['safe_gap']:>8}  {row['crossing_quality']:>7.0f}"
        )


def print_trend(rows: list[dict[str, Any]]) -> None:
    if len(rows) < 2:
        print("\nOnly one session so far - nothing to compare against yet.")
        return

    first, last = rows[0], rows[-1]
    print(f"\nFirst to latest session ({len(rows)} sessions)")
    print("-" * 46)
    for label, key, unit in (
        ("Hazard recognition", "hazard_pct", "%"),
        ("Handrail compliance", "rail_pct", "%"),
        ("Balance steadiness", "balance_stability", "/100"),
        ("Overall", "overall", "/100"),
    ):
        delta = last[key] - first[key]
        print(f"  {label:<22} {first[key]:>5.1f} -> {last[key]:>5.1f}{unit:<4} ({delta:+.1f})")

    # Max sway falling is an improvement, so it reads the other way round.
    delta_sway = last["max_sway_cm"] - first["max_sway_cm"]
    print(
        f"  {'Peak sway':<22} {first['max_sway_cm']:>5.1f} -> "
        f"{last['max_sway_cm']:>5.1f}cm  ({delta_sway:+.1f}, lower is better)"
    )

    print("\n  Per test")
    for test in TEST_ORDER:
        values = [r["test_" + test] for r in rows if r["test_" + test] != ""]
        if not values:
            continue
        delta = float(values[-1]) - float(values[0])
        print(f"  {TEST_NAMES[test]:<22} {float(values[0]):>5.1f} -> {float(values[-1]):>5.1f}/100  ({delta:+.1f})")


def print_focus(sessions: list[dict[str, Any]], rows: list[dict[str, Any]]) -> None:
    """Recent average per test, and which one the app will focus on next."""
    recent = sessions[-FOCUS_WINDOW:]
    averages: dict[str, float] = {}
    for test in TEST_ORDER:
        values = [float(v) for v in (tests_of(s).get(test) for s in recent) if v is not None]
        if values:
            averages[test] = sum(values) / len(values)
    if not averages:
        return

    print(f"\nAverage over the last {len(recent)} session(s) - the focus is the lowest")
    print("-" * 46)
    for test, value in sorted(averages.items(), key=lambda item: item[1]):
        print(f"  {TEST_NAMES.get(test, test):<22} {value:>5.1f}/100")

    stored = sessions[-1].get("next_focus", {}).get("test", "")
    if stored:
        print(f"\n  Next session will focus on: {TEST_NAMES.get(stored, stored)}")
    else:
        lowest_test, lowest = min(averages.items(), key=lambda item: item[1])
        if lowest >= FOCUS_THRESHOLD:
            print(f"\n  Every test averages {FOCUS_THRESHOLD:.0f} or above - no focus, free exploration.")
        else:
            print(f"\n  Next session will focus on: {TEST_NAMES.get(lowest_test, lowest_test)}")


def print_persistent_misses(sessions: list[dict[str, Any]]) -> None:
    """Hazards missed in every single session -- the strongest training signal."""
    counts: dict[str, list[Any]] = {}
    for session in sessions:
        for hazard in session.get("hazards", {}).get("detail", []):
            entry = counts.setdefault(hazard["id"], [hazard.get("name", hazard["id"]), 0, 0])
            entry[2] += 1
            if not hazard.get("found", False):
                entry[1] += 1

    persistent = [(name, missed, seen) for name, missed, seen in counts.values() if missed == seen]
    if not persistent:
        return
    print("\nMissed in every session")
    print("-" * 46)
    for name, missed, _ in sorted(persistent, key=lambda item: -item[1]):
        print(f"  {name}  (missed {missed}x)")


def write_csv(rows: list[dict[str, Any]], path: str) -> None:
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"\nWrote {path}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("log", help="path to session_log.json")
    parser.add_argument("--csv", help="also write a tidy CSV here")
    parser.add_argument("--participant", help="only sessions for this participant id")
    args = parser.parse_args()

    sessions = load(args.log, args.participant)
    rows = [flatten(session, i + 1) for i, session in enumerate(sessions)]

    participant = rows[-1]["participant"] or "unknown"
    print(f"\nParticipant: {participant}\n")
    print_table(rows)
    print_test_table(rows)
    print_crossings(rows)
    print_trend(rows)
    print_focus(sessions, rows)
    print_persistent_misses(sessions)

    if args.csv:
        write_csv(rows, args.csv)
    print()


if __name__ == "__main__":
    main()
