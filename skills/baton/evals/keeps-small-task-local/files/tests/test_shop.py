from shop import billing, reports, orders, auth


def test_invoice_flow():
    billing.create_invoice("i1", 1, 50)
    billing.pay("i1")
    assert reports.revenue() == 50


def test_order_total():
    assert orders.createOrder(1, [{"price": 5, "qty": 2}])["total"] == 10


def test_login():
    assert auth.login(1, "hunter22")
