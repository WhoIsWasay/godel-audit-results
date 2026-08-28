from z3 import *

s = Solver()

# State variables
totalSupply_0 = BitVec('totalSupply_0', 256)
totalTokens_0 = BitVec('totalTokens_0', 256)
tokens = BitVec('tokens', 256)

# Bound variables to realistic ranges
s.add(UGT(totalSupply_0, 0), ULT(totalSupply_0, 1000000))
s.add(UGT(totalTokens_0, 0), ULT(totalTokens_0, 1000000))
s.add(UGT(tokens, 0), ULT(tokens, 1000000))

# Compute shares with floor division
shares = UDiv(tokens * totalSupply_0, totalTokens_0)

# Edge case: tokens * totalSupply < totalTokens causes shares == 0
s.add(ULT(tokens * totalSupply_0, totalTokens_0))
s.add(shares == 0)

# Check if SAT (bug exists)
if s.check() == sat:
    print("BUG FOUND: Nonzero deposit mints zero shares")
    print(s.model())
else:
    print("Property holds - no counterexample found")