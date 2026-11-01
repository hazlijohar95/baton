from .users import fetchUser


def login(user_id, password):
    user = fetchUser(user_id)
    return user is not None and user["password"] == password


def set_password(user_id, password):
    user = fetchUser(user_id)
    user["password"] = password
