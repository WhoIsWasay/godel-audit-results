from z3 import *

s = Solver()

# State variables
totalSupply_old = Int('totalSupply_old')
idleBalance_old = Int('idleBalance_old')
userShares_old = Int('userShares_old')
price_old = Int('price_old')
redeemAmount = Int('redeemAmount')
redeemedShare = Int('redeemedShare')
ONE_IDLE_TOKEN = 10**18

# Bounds
s.add(totalSupply_old > 0, totalSupply_old <= 10**6)
s.add(idleBalance_old > 0, idleBalance_old <= 10**6)
s.add(userShares_old > 0, userShares_old <= 10**6)
s.add(price_old > 0, price_old <= 10**6)
s.add(redeemAmount > 0, redeemAmount <= 10**6)

# Donation scenario: idle balance exceeds total supply
s.add(idleBalance_old > totalSupply_old)

# User's fair proportional value
s.add(redeemAmount <= (userShares_old * idleBalance_old * price_old) / (totalSupply_old * ONE_IDLE_TOKEN))

# _tokenToShares calculation
s.add(redeemedShare == (redeemAmount * ONE_IDLE_TOKEN) / price_old)

# Bug condition: redeemedShare exceeds user's share balance
s.add(redeemedShare > userShares_old)

if s.check() == sat:
    print("BUG FOUND:")
    print(s.model())
else:
    print("Property holds - no counterexample found")