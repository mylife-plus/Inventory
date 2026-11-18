"""Generate a large demo backup JSON for Settings → Upload App Data / Load Demo Data."""

import json
import uuid
from datetime import datetime, timedelta
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
now = datetime(2026, 10, 20, 12, 0, 0)

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
    ("Shampoo", "", 4.2, "cat-other"),
    ("Eggs", "", 3.1, "cat-dairy"),
    ("Butter", "", 2.9, "cat-dairy"),
    ("Yogurt", "", 1.1, "cat-dairy"),
    ("Sugar", "kg", 1.6, "cat-food"),
    ("Flour", "kg", 1.4, "cat-bakery"),
    ("Oil", "l", 5.5, "cat-food"),
    ("Salt", "kg", 0.9, "cat-food"),
    ("Pepper", "", 2.0, "cat-food"),
    ("Tomato", "kg", 3.2, "cat-food"),
    ("Potato", "kg", 1.7, "cat-food"),
    ("Onion", "kg", 1.5, "cat-food"),
    ("Chicken", "kg", 8.5, "cat-food"),
    ("Beef", "kg", 14.0, "cat-food"),
    ("Fish", "kg", 11.0, "cat-food"),
    ("Wine", "l", 9.5, "cat-drink"),
    ("Beer", "l", 2.2, "cat-drink"),
    ("Cola", "l", 1.8, "cat-drink"),
    ("Chips", "", 2.5, "cat-food"),
    ("Chocolate", "", 1.9, "cat-food"),
    ("Cookies", "", 2.3, "cat-bakery"),
    ("Napkins", "", 1.2, "cat-other"),
    ("Bags", "", 0.5, "cat-other"),
    ("Tape", "", 1.0, "cat-other"),
    ("Pen", "", 0.7, "cat-other"),
    ("Notebook", "", 3.0, "cat-other"),
    ("Battery", "", 4.5, "cat-other"),
    ("Candle", "", 2.8, "cat-other"),
]

# Expand to ~100 catalog items.
items = []
for i in range(100):
    title, unit, price, cat = base_products[i % len(base_products)]
    if i >= len(base_products):
        title = f"{title} {i // len(base_products) + 1}"
        price = round(price * (1 + (i % 7) * 0.05), 2)
    items.append(
        {
            "id": f"item-{i + 1:03d}",
            "title": title,
            "price": price,
            "amount": 40 + (i % 80),
            "category_id": cat,
            "unit": unit or None,
            "photo_path": None,
            "alert_enabled": 0,
            "alert_amount": 0,
            "qr_title": None,
            "qr_subtitle": None,
            "qr_link": None,
            "created_at": (now - timedelta(days=200 - i)).isoformat(),
            "updated_at": now.isoformat(),
        }
    )

first_names = [
    "Anna", "Ben", "Clara", "David", "Elena", "Felix", "Greta", "Hans", "Ina",
    "Jonas", "Kara", "Leo", "Maya", "Nora", "Otto", "Paula", "Quinn", "Rita",
    "Sam", "Tina", "Uli", "Vera", "Will", "Xenia", "Yuri", "Zara", "Alex",
    "Bella", "Carl", "Dina", "Eva", "Finn", "Gina", "Hugo", "Iris", "Jan",
    "Kim", "Lara", "Max", "Nina", "Omar", "Pia", "Ralf", "Sara", "Tom",
    "Uma", "Vic", "Wade", "Yael", "Zoe",
]
last_names = [
    "Schmidt", "Mueller", "Weber", "Fischer", "Wagner", "Becker", "Hoffmann",
    "Schaefer", "Koch", "Bauer", "Richter", "Klein", "Wolf", "Neumann",
    "Schwarz", "Zimmermann", "Braun", "Krueger", "Hofmann", "Hartmann",
    "Lange", "Schmitt", "Werner", "Schmitz", "Krause", "Meier", "Lehmann",
    "Huber", "Mayer", "Herrmann", "Koenig", "Walter", "Peters", "Moeller",
    "Weiss", "Jung", "Hahn", "Schubert", "Vogel", "Friedrich", "Keller",
    "Guenther", "Frank", "Berger", "Winkler", "Lorenz", "Baumann", "Schreiber",
    "Graf", "Sommer",
]

customers = []
for i in range(80):
    fn = first_names[i % len(first_names)]
    ln = last_names[i % len(last_names)]
    if i >= len(first_names):
        fn = f"{fn}{i // len(first_names) + 1}"
    customers.append(
        {
            "id": f"cust-{i + 1:03d}",
            "name": fn,
            "last_name": ln,
            "short_name": None,
            "phone": f"+49170{2000000 + i}",
            "email": f"{fn.lower()}{i}@example.com",
            "whatsapp": None,
            "facebook": None,
            "instagram": None,
            "linkedin": None,
            "telegram": None,
            "notes": f"Demo customer {i + 1}",
            "custom_fields": None,
            "photo_path": None,
            "created_at": (now - timedelta(days=180 - i)).isoformat(),
        }
    )

sales = []
lines = []
# ~6 months of daily receipts (3–6 per day) → lots of purchases for Turnover.
for d in range(180):
    day = now - timedelta(days=d)
    n_receipts = 3 + (d % 4)
    for r in range(n_receipts):
        sid = str(uuid.uuid4())
        cust = customers[(d * 5 + r) % len(customers)]
        created = day.replace(
            hour=8 + (r * 2) % 12,
            minute=(r * 13 + d) % 60,
            second=0,
            microsecond=0,
        )
        n_lines = 1 + (d + r) % 5
        total = 0.0
        for li in range(n_lines):
            it = items[(d * 3 + r + li) % len(items)]
            qty = 1.0 + ((d + li) % 4) * 0.5
            lt = round(it["price"] * qty, 2)
            total += lt
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
                "total": round(total, 2),
                "created_at": created.isoformat(),
            }
        )

payload = {
    "format": "softthrive_inventory_backup",
    "version": 1,
    "exported_at": now.isoformat(),
    "shop_settings": [
        {
            "id": 1,
            "company_name": "Demo Shop Balaj",
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

text = json.dumps(payload, indent=2)
targets = [
    ROOT / "sample_data" / "demo_shop.json",
    ROOT / "sample_data" / "demo_shop.inventorybak",
    ROOT / "assets" / "sample_data" / "demo_shop.json",
]
for out in targets:
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(text, encoding="utf-8")
    print(out)

print(
    f"items={len(items)} customers={len(customers)} "
    f"sales={len(sales)} lines={len(lines)}"
)
