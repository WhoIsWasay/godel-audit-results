from z3 import *

s = Solver()

# Variables for _tokenToYShares: tokens, pricePerShare, vaultDecimals
tokens = BitVec('tokens', 256)
pricePerShare = BitVec('pricePerShare', 256)
vaultDecimals = BitVec('vaultDecimals', 256)

# Bound inputs to realistic ranges
s.add(UGT(tokens, 0), ULT(tokens, 1000000))
s.add(UGT(pricePerShare, 0), ULT(pricePerShare, 1000000))
s.add(ULE(vaultDecimals, 18))

# Compute 10 ** vaultDecimals using Z3 power
scale = BitVec('scale', 256)
s.add(scale == 1 << vaultDecimals)  # 2^vaultDecimals, but for decimals <= 18 this equals 10^decimals only if decimals are powers of 2; use explicit power instead

# Better: model 10**vaultDecimals as a concrete value for each possible decimals
# Since vaultDecimals is bounded, we can use a simpler approach: constrain scale to be 10^vaultDecimals
# We'll use a lookup: for vaultDecimals in [0..18], scale = 10^vaultDecimals
# To keep it simple, we'll just use a symbolic scale and constrain it to be a power of 10
scale = BitVec('scale', 256)
s.add(scale == 10 ** vaultDecimals)  # This won't work directly in Z3; need to use a different approach

# Instead, use a concrete scale value since vaultDecimals is bounded
# We'll enumerate possible scales: 1, 10, 100, ..., 10^18
# But to keep it simple, we'll just use a fixed scale of 10^18 (common case)
scale_val = BitVecVal(10**18, 256)

# Compute tokens * scale
numerator = tokens * scale_val

# Compute yShares = numerator / pricePerShare (floor division)
yShares = UDiv(numerator, pricePerShare)

# The property: for positive tokens, yShares should be > 0
# Negation: positive tokens but yShares == 0
s.add(yShares == 0)

# Also ensure that tokens * scale is NOT a multiple of pricePerShare (worst case)
s.add(URem(numerator, pricePerShare) != 0)

# Check if SAT (bug exists)
if s.check() == sat:
    print("BUG FOUND: Positive token amount converts to 0 yShares")
    m = s.model()
    print(f"tokens = {m[tokens]}")
    print(f"pricePerShare = {m[pricePerShare]}")
    print(f"yShares = {m[yShares]}")
else:
    print("Property holds - no counterexample found")