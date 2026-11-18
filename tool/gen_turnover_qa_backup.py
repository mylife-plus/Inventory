"""Generate ~26 months of Turnover QA backup (same schema as demo_shop).

Ends 2026-10-27 (seed created_at). Enables 2w…2y + All.

For expected averages use the app's own cent math (not this script's printout):
  dart run tool/recompute_qa_totals.dart

Load: Settings → Data → Upload App Data → pick sample_data/turnover_qa_26m.json
Remove: Settings → Reset App (keeps shop/settings) or Upload another backup.
"""

from __future__ import annotations

import json
import uuid
from calendar import monthrange
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
NOW = datetime(2026, 10, 27, 12, 0, 0)
START = datetime(2024, 8, 27)  # ~26 months

cats = [
    {"id": "cat-food", "name": "Food"},
    {"id": "cat-drink", "name": "Drinks"},
    {"id": "cat-other", "name": "Other"},
    {"id": "cat-dairy", "name": "Dairy"},
    {"id": "cat-bakery", "name": "Bakery"},
]

base_products = [
    ("Milk", "l", 1.25, "cat-dairy"),
    ("Bread", "", 2.5, "cat-bakery"),
    ("Cheese", "kg", 12.9, "cat-dairy"),
    ("Coffee", "kg", 18.0, "cat-drink"),
    ("Tea", "", 3.5, "cat-drink"),
    ("Apple", "kg", 2.8, "cat-food"),
    ("Banana", "kg", 1.9, "cat-food"),
    ("Rice", "kg", 2.2, "cat-food"),
    ("Pasta", "", 1.8, "cat-food"),
    ("Juice", "l", 2.4, "cat-drink"),
    ("Water", "l", 0.8, "cat-drink"),
    ("Soap", "", 1.5, "cat-other"),
    ("Eggs", "", 3.1, "cat-dairy"),
    ("Butter", "", 2.9, "cat-dairy"),
    ("Flour", "kg", 1.4, "cat-bakery"),
    ("Oil", "l", 5.5, "cat-food"),
    ("Chicken", "kg", 8.5, "cat-food"),
    ("Beef", "kg", 14.0, "cat-food"),
    ("Wine", "l", 9.5, "cat-drink"),
    ("Cookies", "", 2.3, "cat-bakery"),
]

items = []
for i, (title, unit, price, cat) in enumerate(base_products):
    items.append(
        {
            "id": f"item-{i + 1:03d}",
            "title": title,
            "price": price,
            "amount": 50 + i,
            "category_id": cat,
            "unit": unit or None,
            "photo_path": None,
            "alert_enabled": 0,
            "alert_amount": 0,
            "qr_title": None,
            "qr_subtitle": None,
            "qr_link": None,
            "created_at": (START + timedelta(days=i)).isoformat(timespec="seconds"),
            "updated_at": NOW.isoformat(timespec="seconds"),
        }
    )

customers = []
for i in range(40):
    customers.append(
        {
            "id": f"cust-{i + 1:03d}",
            "name": f"Cust{i + 1}",
            "last_name": "Demo",
            "short_name": None,
            "phone": f"+49170{3000000 + i}",
            "email": f"cust{i + 1}@example.com",
            "whatsapp": None,
            "facebook": None,
            "instagram": None,
            "linkedin": None,
            "telegram": None,
            "notes": None,
            "custom_fields": None,
            "photo_path": None,
            "created_at": (START + timedelta(days=i)).isoformat(timespec="seconds"),
        }
    )


def money_cents(price: float, qty: float) -> int:
    return int(round(price * qty * 100))


def calendar_months_before(dt: datetime, months: int) -> datetime:
    y, m, d = dt.year, dt.month - months, dt.day
    while m <= 0:
        m += 12
        y -= 1
    last = monthrange(y, m)[1]
    return datetime(y, m, min(d, last))


def calendar_years_before(dt: datetime, years: int) -> datetime:
    y = dt.year - years
    last = monthrange(y, dt.month)[1]
    return datetime(y, dt.month, min(dt.day, last))


def inclusive_days(a: datetime, b: datetime) -> int:
    aa = datetime(a.year, a.month, a.day)
    bb = datetime(b.year, b.month, b.day)
    return (bb - aa).days + 1


sales = []
lines = []
day = START
gap_weeks = {datetime(2024, 10, 1), datetime(2025, 3, 10), datetime(2025, 11, 3), datetime(2026, 6, 2)}
empty_days = set()

while day.date() <= NOW.date():
    # Whole-week gaps
    in_gap = any(0 <= (day - g).days < 7 for g in gap_weeks)
    # Sparse empty days
    skip = in_gap or (day.day in (2, 15) and day.month % 3 == 0)
    if skip:
        empty_days.add(day.date())
        day += timedelta(days=1)
        continue

    n_receipts = 1 + (day.toordinal() % 3)
    # Month-end extra traffic
    if day.day >= monthrange(day.year, day.month)[1] - 1:
        n_receipts += 1

    for r in range(n_receipts):
        sid = str(uuid.uuid4())
        cust = customers[(day.toordinal() + r) % len(customers)]
        if r == 0 and day.day == 1:
            created = day.replace(hour=0, minute=0, second=0, microsecond=0)
        elif r == n_receipts - 1 and day.day >= 28:
            created = day.replace(hour=23, minute=59, second=0, microsecond=0)
        else:
            created = day.replace(
                hour=8 + (r * 3) % 12,
                minute=(r * 17 + day.day) % 60,
                second=0,
                microsecond=0,
            )
        n_lines = 1 + (day.day + r) % 4
        total_cents = 0
        for li in range(n_lines):
            it = items[(day.toordinal() + r + li) % len(items)]
            qty = 1.0 + ((day.day + li) % 5) * 0.5
            lt = money_cents(it["price"], qty)
            total_cents += lt
            lines.append(
                {
                    "sale_id": sid,
                    "item_id": it["id"],
                    "title": it["title"],
                    "unit_price": it["price"],
                    "quantity": qty,
                    "unit": it["unit"],
                }
            )
        sales.append(
            {
                "id": sid,
                "customer_id": cust["id"],
                "customer_name": f"{cust['name']} {cust['last_name']}",
                "total": round(total_cents / 100.0, 2),
                "created_at": created.isoformat(timespec="seconds"),
            }
        )
    day += timedelta(days=1)

# Ensure boundary sales today
if not any(s["created_at"].startswith("2026-10-27") for s in sales):
    sid = str(uuid.uuid4())
    it = items[0]
    qty = 2.0
    lt = money_cents(it["price"], qty)
    lines.append(
        {
            "sale_id": sid,
            "item_id": it["id"],
            "title": it["title"],
            "unit_price": it["price"],
            "quantity": qty,
            "unit": it["unit"],
        }
    )
    sales.append(
        {
            "id": sid,
            "customer_id": customers[0]["id"],
            "customer_name": f"{customers[0]['name']} {customers[0]['last_name']}",
            "total": round(lt / 100.0, 2),
            "created_at": "2026-10-27T23:59:00",
        }
    )

payload = {
    "format": "softthrive_inventory_backup",
    "version": 1,
    "exported_at": NOW.isoformat(timespec="seconds"),
    "shop_settings": [
        {
            "id": 1,
            "company_name": "Turnover QA Shop",
            "cashier": "",
            "manager": "",
            "street": "Hauptstrasse 12",
            "zip": "10115",
            "city": "Berlin",
            "phone": "+49301234567",
            "vat_rate": 19.0,
            "currency_symbol": "€",
            "decimal_separator": ",",
            "setup_complete": 1,
            "receipt_qr_link": "https://softthrive.com",
        }
    ],
    "categories": cats,
    "inventory_items": items,
    "customers": customers,
    "sales": sales,
    "sale_lines": lines,
    "photos": {},
}

text = json.dumps(payload, indent=2, ensure_ascii=False)
for name in ("turnover_qa_26m.json", "turnover_qa_26m.inventorybak"):
    out = ROOT / "sample_data" / name
    out.write_text(text, encoding="utf-8")
    print("wrote", out)

# Expected averages for chips (no category filter), matching app formula.
sale_by_id = {s["id"]: s for s in sales}
line_by_sale: dict[str, list] = {}
for ln in lines:
    line_by_sale.setdefault(ln["sale_id"], []).append(ln)


def period_total_cents(from_dt: datetime, to_dt: datetime) -> int:
    total = 0
    for s in sales:
        at = datetime.fromisoformat(s["created_at"])
        if at < from_dt or at > to_dt.replace(hour=23, minute=59, second=59):
            continue
        for ln in line_by_sale[s["id"]]:
            total += money_cents(ln["unit_price"], ln["quantity"])
    return total


def report(label: str, from_dt: datetime):
    to_dt = NOW
    days = inclusive_days(from_dt, to_dt)
    cents = period_total_cents(from_dt, to_dt)
    total = cents / 100.0
    day_avg = total / days
    print(
        f"{label}\t{from_dt.date()}–{to_dt.date()}\t{days}\t"
        f"{total:.2f}\t{day_avg:.2f}\t{day_avg * 30.44:.2f}\t{day_avg * 365.24:.2f}"
    )


print("\nFilter\tRange\tDays\tTotal\tDay\tMonth\tYear")
report("6m", calendar_months_before(NOW, 6))
report("1y", calendar_years_before(NOW, 1))
report("2y", calendar_years_before(NOW, 2))
print(f"\nsales={len(sales)} lines={len(lines)} empty_days~{len(empty_days)}")
print("Note: Feb 29 2024 is before the ~26m window (starts 2024-08-27).")
