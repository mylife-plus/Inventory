// Cent-safe money helpers for Turnover totals (year/month/chart/averages).

/// Round a money amount to integer cents (half-away-from-zero via [.round]).
int moneyToCents(double amount) => (amount * 100).round();

/// Cents back to a decimal money value.
double centsToMoney(int cents) => cents / 100.0;

/// Line total in cents: unit price × qty, rounded once (avoids 0.01 drift).
int lineTotalCents({required double unitPrice, required double quantity}) =>
    moneyToCents(unitPrice * quantity);
