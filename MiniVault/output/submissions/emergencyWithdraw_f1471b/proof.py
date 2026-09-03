from z3 import *

def build_model():
    a_shares = Int('a_shares')
    msg_sender = Int('msg_sender')
    msg_value = Int('msg_value')
    block_timestamp = Int('block_timestamp')
    address_this = Int('address_this')
    balances__old = Int('balances__old')
    balances__new = Int('balances__new')
    balances__GEN = Int('balances__GEN')
    balances__GEN_new = Int('balances__GEN_new')
    totalAssets__old = Int('totalAssets__old')
    totalAssets__new = Int('totalAssets__new')
    totalSupply__old = Int('totalSupply__old')
    totalSupply__new = Int('totalSupply__new')
    balances__S = Int('balances__S')
    balances__S_new = Int('balances__S_new')
    l_assets = Int('l_assets')
    l_penaltyBps = Int('l_penaltyBps')
    l_netAssets = Int('l_netAssets')
    _bounds = [a_shares >= 0, a_shares <= 2**256 - 1, msg_sender >= 0, msg_sender <= 2**256 - 1, msg_value >= 0, msg_value <= 2**256 - 1, block_timestamp >= 0, block_timestamp <= 2**256 - 1, balances__old >= 0, balances__old <= 2**256 - 1, balances__new >= 0, balances__new <= 2**256 - 1, balances__GEN >= 0, balances__GEN <= 2**256 - 1, balances__GEN_new >= 0, balances__GEN_new <= 2**256 - 1, totalAssets__old >= 0, totalAssets__old <= 2**256 - 1, totalAssets__new >= 0, totalAssets__new <= 2**256 - 1, totalSupply__old >= 0, totalSupply__old <= 2**256 - 1, totalSupply__new >= 0, totalSupply__new <= 2**256 - 1, balances__S >= 0, balances__S <= 2**256 - 1, balances__S_new >= 0, balances__S_new <= 2**256 - 1]
    _guards = []
    _transitions = [l_assets == ((a_shares * totalAssets__old) / totalSupply__old), l_penaltyBps == (500), balances__S_new == ((balances__S) - (a_shares)), totalSupply__new == ((totalSupply__old) - (a_shares))]
    _unbound_locals = ['loc_netAssets']
    solver = Solver()
    solver.add(_bounds + _guards + _transitions)
    V = {'arg_shares': a_shares, 'msg_sender': msg_sender, 'msg_value': msg_value, 'block_timestamp': block_timestamp, 'address_this': address_this, 'balances': balances__old, 'balances@new': balances__new, 'balances[#]': balances__GEN, 'balances[#]@new': balances__GEN_new, 'totalAssets': totalAssets__old, 'totalAssets@new': totalAssets__new, 'totalSupply': totalSupply__old, 'totalSupply@new': totalSupply__new, 'balances[S]': balances__S, 'balances[S]@new': balances__S_new, 'loc_assets': l_assets, 'loc_penaltyBps': l_penaltyBps, 'loc_netAssets': l_netAssets}
    return solver, V

solver, V = build_model()

solver.push()
print("SANITY:", solver.check())
solver.pop()

# Property: netAssets should equal assets * 9500 / 10000 (5% penalty)
# The buggy code computes netAssets = assets - 500 (flat subtraction)
# We assert the negation: netAssets != assets * 9500 / 10000
# Since loc_netAssets is havocked, we express the violation via the inline arithmetic
# that the contract actually performs: assets - 500
# We check if there exists a state where assets - 500 != assets * 9500 / 10000
# and assets >= 500 (to avoid underflow revert)

solver.add(V['loc_assets'] >= 500)
solver.add(V['loc_assets'] - 500 != (V['loc_assets'] * 9500) / 10000)

if solver.check() == sat:
    print("BUG FOUND:", solver.model())
else:
    print("Property holds")