from z3 import *

def build_model(witness_bound=None):
    a_assets = Int('a_assets')
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
    l_shares = Int('l_shares')
    balances__S = Int('balances__S')
    balances__S_new = Int('balances__S_new')
    _bounds = [a_assets >= 0, a_assets <= 2**256 - 1, msg_sender >= 0, msg_sender <= 2**256 - 1, msg_value >= 0, msg_value <= 2**256 - 1, block_timestamp >= 0, block_timestamp <= 2**256 - 1, balances__old >= 0, balances__old <= 2**256 - 1, balances__new >= 0, balances__new <= 2**256 - 1, balances__GEN >= 0, balances__GEN <= 2**256 - 1, balances__GEN_new >= 0, balances__GEN_new <= 2**256 - 1, totalAssets__old >= 0, totalAssets__old <= 2**256 - 1, totalAssets__new >= 0, totalAssets__new <= 2**256 - 1, totalSupply__old >= 0, totalSupply__old <= 2**256 - 1, totalSupply__new >= 0, totalSupply__new <= 2**256 - 1, balances__S >= 0, balances__S <= 2**256 - 1, balances__S_new >= 0, balances__S_new <= 2**256 - 1]
    _capped = [a_assets, msg_sender, msg_value, block_timestamp, balances__old, balances__new, balances__GEN, balances__GEN_new, totalAssets__old, totalAssets__new, totalSupply__old, totalSupply__new, balances__S, balances__S_new]
    if witness_bound is not None:
        _bounds = _bounds + [_s <= witness_bound for _s in _capped]
    _guards = [a_assets > 0]
    _transitions = [Implies(And(totalSupply__old == 0), l_shares == (a_assets)), Implies(And(Not(totalSupply__old == 0)), l_shares == ((a_assets * totalSupply__old) / totalAssets__old)), totalAssets__new == ((totalAssets__old) + (a_assets))]
    _unbound_locals = []
    solver = Solver()
    solver.add(_bounds + _guards + _transitions)
    V = {'arg_assets': a_assets, 'msg_sender': msg_sender, 'msg_value': msg_value, 'block_timestamp': block_timestamp, 'address_this': address_this, 'balances': balances__old, 'balances@new': balances__new, 'balances[#]': balances__GEN, 'balances[#]@new': balances__GEN_new, 'totalAssets': totalAssets__old, 'totalAssets@new': totalAssets__new, 'totalSupply': totalSupply__old, 'totalSupply@new': totalSupply__new, 'loc_shares': l_shares, 'balances[S]': balances__S, 'balances[S]@new': balances__S_new}
    return solver, V

solver, V = build_model()

# SANITY probe: base model must be reachable
solver.push()
print("SANITY:", solver.check())
solver.pop()

# Property: assets > 0 => shares > 0
# Negation: assets > 0 AND shares == 0
# shares = (assets * totalSupply) / totalAssets when totalSupply != 0
# Encode violation using bound symbols and inline arithmetic
solver.add(V['totalSupply'] != 0)
solver.add(V['totalAssets'] > 0)
solver.add(V['arg_assets'] > 0)
solver.add((V['arg_assets'] * V['totalSupply']) / V['totalAssets'] == 0)

if solver.check() == sat:
    print("BUG FOUND:", solver.model())
else:
    print("Property holds")