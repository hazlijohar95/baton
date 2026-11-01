from .users import fetchUser

ORDERS = []


def createOrder(user_id, items):
    user = fetchUser(user_id)
    order = {"id": len(ORDERS) + 1, "user": user["id"], "items": items, "total": sum(i["price"] * i["qty"] for i in items)}
    ORDERS.append(order)
    return order
