USERS = {1: {"id": 1, "name": "Aina", "email": "aina@example.com", "password": "hunter22"}}


def fetchUser(user_id):
    return USERS.get(user_id)
