from .billing import INVOICES


def revenue():
    return sum(i["amount"] for i in INVOICES.values() if i["status"] == "paid")


def open_invoices():
    return [i for i in INVOICES.values() if i["status"] == "open"]
