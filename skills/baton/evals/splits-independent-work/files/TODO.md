# TODO

1. billing: add `refund(invoice_id)` to `src/shop/billing.py`. Only paid invoices can be refunded; it sets status to "refunded". Add tests.
2. auth: `set_password` must reject passwords shorter than 12 characters or without a digit, raising `ValueError`. Add tests.
3. reports: add `export_csv(path)` to `src/shop/reports.py` that writes one row per invoice (id, user, amount, status) with a header. Add tests.
