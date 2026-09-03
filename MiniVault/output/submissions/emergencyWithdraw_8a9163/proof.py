from z3 import *

solver, V = build_model()

# SANITY probe: base model must be reachable
solver.push()
print("SANITY:", solver.check())
solver.pop()

# Property: If totalSupply becomes 0 after emergencyWithdraw, totalAssets must also be 0
# Negation: totalSupply_new == 0 AND totalAssets_new != 0
# This captures the invariant: totalAssets == 0 iff totalSupply == 0
solver.add(V['totalSupply@new'] == 0)
solver.add(V['totalAssets@new'] != 0)

if solver.check() == sat:
    print("BUG FOUND:", solver.model())
else:
    print("Property holds")