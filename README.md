# Inventory App

Offline inventory & sales for small shops (Flutter · iOS/Android).  
Free · open source · no login · works fully offline.

## Testing build (ready)

### Run
```bash
cd /Users/mc/Developer/inventory-app
flutter pub get
flutter run
```

### Quick QA path
1. Complete first-launch shop setup (or Settings → **Load demo data**)
2. **Inventory** — add item (photo, category, price, amount, unit, alert) → save ✓ → QR label → share/print
3. **Sell** — scan QR or Add from list → adjust qty → ✓ → Guest or customer → send receipt
4. **Customers** — list, detail, WhatsApp/call, purchase history
5. **Receipts** — Settings → Receipts (transaction history)
6. **Turnover** — period filters, chart, items sold, share Excel export
7. **Settings** — language (EN/DE/ES/FR/PT), dark mode, decimal, currency, PIN lock, erase all

### Milestone status
| Area | Status |
|------|--------|
| First launch / receipt details | Done |
| Inventory + QR labels | Done |
| Selling + receipts history | Done |
| Customers | Done |
| Turnover + Excel export | Done |
| Settings + 5 languages | Done |
| Dark mode + PIN lock | Done |
| Device sync (encrypted) | Next milestone (UI placeholder) |

### Design
Client frames: `docs/client-ui/`  
Theme: navy `#001830`, black cards, neon `#4BE000`, square FAB `#003362`
