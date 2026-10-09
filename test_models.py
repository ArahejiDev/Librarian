# Compare Codiv text-only models on a few labelled samples (nothing is moved).
# Usage: CODIV_API_KEY=... python test_models.py [model ...]
#        python test_models.py jevk5-0.2 laya-1.0 verdict-1.4 clm-v0.1
import os
import sys

import requests

from lb_classifier import API_KEY, API_URL, CATEGORIES, QUESTIONS, THRESHOLD

if not API_KEY:
    sys.exit("Missing environment variable CODIV_API_KEY")

MODELS = sys.argv[1:] or [os.getenv("MODEL", "jevk5-0.2")]

# (text, expected category)
CASES = [
    ("Hi team, attached is the quarterly sales report. Please review it before Thursday's client meeting.", "work"),
    ("Reminder: the project delivery is on Friday. We still need to finish testing and update the Jira ticket.", "work"),
    ("Invoice 2024-118 for consulting services. Due in 30 days. Please confirm receipt.", "work"),
    ("Production server incident: the service went down at 03:00. It was restarted and is stable now.", "work"),
    ("Last night we watched the season finale and did not see that ending coming. Next season starts tomorrow.", "leisure"),
    ("On Saturday we are playing a tabletop RPG session and then having dinner together.", "leisure"),
    ("I am planning the summer trip to Italy: Rome, Florence and a few beach days.", "leisure"),
    ("I signed up for climbing classes. This weekend we try the new climbing gym.", "leisure"),
    ("Electricity bill for September. Amount: 63.40 EUR. It will be charged on the 5th.", "other"),
    ("Book a doctor's appointment, renew the ID card and buy batteries for the remote.", "other"),
    ("Shopping list: milk, eggs, bread, laundry detergent, paper towels.", "other"),
    ("Appointment at the tax advisor on Tuesday at 10:00 for the income tax return.", "other"),
]


def classify(model, text):
    resp = requests.post(
        API_URL,
        headers={"Authorization": f"Bearer {API_KEY}", "Content-Type": "application/json"},
        json={"model": model, "state": text, "questions": QUESTIONS},
        timeout=60,
    )
    resp.raise_for_status()
    answer = resp.json()["answers"]["category"]
    return answer["choice"], answer["confidence"]


expected_categories = {exp for _, exp in CASES}
if not expected_categories <= set(CATEGORIES):
    print(f"Note: your categories {sorted(CATEGORIES)} do not match the sample labels "
          f"{sorted(expected_categories)}; accuracy numbers will be meaningless.")

for model in MODELS:
    print(f"\n===== {model} =====")
    hits = unsure = errors = 0
    for text, expected in CASES:
        try:
            category, confidence = classify(model, text)
        except Exception as e:
            errors += 1
            print(f"ERROR | {text[:45]!r}... -> {e}")
            continue
        is_unsure = confidence < THRESHOLD
        ok = category == expected
        hits += ok
        unsure += is_unsure
        status = "OK   " if ok else "WRONG"
        note = " (would go to manual review)" if is_unsure else ""
        print(f"{status} | expected={expected:8} got={category:8} conf={confidence:.2f} | {text[:45]!r}{note}")
    total = len(CASES) - errors
    print(f"-> Correct: {hits}/{total} | Unsure (conf < {THRESHOLD}): {unsure} | API errors: {errors}")
