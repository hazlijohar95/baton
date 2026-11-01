from .users import fetchUser

INVOICES = {}


def create_invoice(invoice_id, user_id, amount):
    user = fetchUser(user_id)
    if user is None:
        raise ValueError("unknown user")
    INVOICES[invoice_id] = {"id": invoice_id, "user": user_id, "amount": amount, "status": "open"}
    return INVOICES[invoice_id]


def pay(invoice_id):
    INVOICES[invoice_id]["status"] = "paid"
    return INVOICES[invoice_id]
