from z3 import *

s = Solver()

# Model the token balance of the contract before and after vault.withdraw()
previousBalance = BitVec('previousBalance', 256)
currentBalance = BitVec('currentBalance', 256)
receivedAmount = BitVec('receivedAmount', 256)

# Bound the values to realistic ranges for tractability
s.add(ULT(previousBalance, 1000000))
s.add(ULT(receivedAmount, 1000000))
s.add(UGT(receivedAmount, 0))  # non-zero successful withdrawal

# After vault.withdraw() transfers redeemed tokens into this contract,
# the balance increases: currentBalance = previousBalance + receivedAmount
s.add(currentBalance == previousBalance + receivedAmount)

# The function computes: return previousBalance - currentBalance
# Under Solidity 0.8 checked arithmetic, this underflows and reverts
# Encode the underflow condition: previousBalance - currentBalance < 0
# In EVM, this means the subtraction wraps around (unsigned underflow)
s.add(ULT(previousBalance, currentBalance))

# Check if the underflow condition is satisfiable
if s.check() == sat:
    print("BUG FOUND: Withdrawal balance delta is inverted, causing underflow revert")
    print(s.model())
else:
    print("Property holds - no counterexample found")