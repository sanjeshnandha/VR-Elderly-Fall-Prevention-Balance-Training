#!/usr/bin/env python3
"""Cross-session report for the VR Fall-Prevention Training Simulator.

Reads the `session_log.json` written by SessionManager and prints a per-session
table plus session-over-session change, which is the whole point of keeping an
array of sessions rather than overwriting one.

Usage:
    python3 report_sessions.py path/to/session_log.json
    python3 report_sessions.py path/to/session_log.json --csv out.csv

Finding the file (the path is also printed to the Godot console at session end):
    Windows  %APPDATA%\\Godot\\app_userdata\\VR Fall-Prevention Trainer\\
    macOS    ~/Library/Application Support/Godot/app_userdata/VR Fall-Prevention Trainer/
    Linux    ~/.local/share/godot/app_userdata/VR Fall-Prevention Trainer/

No third-party dependencies.
"""

from __future__ import annotations

import argparse
import csv
import json
import os
import sys
from typing import Any


def load(path: str) -> list[dict[str, Any]]:
    with open(os.path.expanduser(path), encoding="utf-8") as handle:
        doc = json.load(handle)
    sessions = doc.get("sessions", [])
    if not sessions:
        sys.exit("No sessions in the log yet.")
    return sessions


def flatten(session: dict[str, Any], index: int) -> dict[str, Any]:
    hazards = session.get("hazards", {})
    handrail = session.get("handrail", {})
    balance = session.get("balance", {})
    score = session.get("score", {})
    return {
        "n": index,
        "session_id": session.get("session_id", ""),
        "participant": session.get("participant_id", ""),
        "date": session.get("started_utc", "")[:16].replace("T", " "),
        "minutes": round(float(session.get("duration_seconds", 0.0)) / 60.0, 1),
        "seated": session.get("settings", {}).get("seated_mode", False),
        "hazards_found": hazards.get("found", 0),
        "hazards_total": hazards.get("total", 0),
        "hazard_pct": float(score.get("hazard", 0.0)),
        "false_positives": hazards.get("false_positives", 0),
        "rail_complied": handrail.get("complied", 0),
        "rail_opportunities": handrail.get("opportunities", 0),
        "rail_pct": float(score.get("handrail", 0.0)),
        "balance_trials": balance.get("trials", 0),
        "balance_stability": float(balance.get("mean_stability", 0.0)),
        "balance_time_s": float(balance.get("mean_completion_s", 0.0)),
        "max_sway_cm": float(balance.get("max_sway_cm", 0.0)),
        "overall": float(score.get("overall", 0.0)),
    }


def arrow(delta: float) -> str:
    if abs(delta) < 0.5:
        return "  ="
    return f"{delta:+5.1f}"


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


def print_trend(rows: list[dict[str, Any]]) -> None:
    if len(rows) < 2:
        print("\nOnly one session so far — nothing to compare against yet.")
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


def print_persistent_misses(sessions: list[dict[str, Any]]) -> None:
    """Hazards missed in every single session — the strongest training signal."""
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
    args = parser.parse_args()

    sessions = load(args.log)
    rows = [flatten(session, i + 1) for i, session in enumerate(sessions)]

    participant = rows[-1]["participant"] or "unknown"
    print(f"\nParticipant: {participant}\n")
    print_table(rows)
    print_trend(rows)
    print_persistent_misses(sessions)

    if args.csv:
        write_csv(rows, args.csv)
    print()


if __name__ == "__main__":
    main()
