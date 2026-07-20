// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

/**
 * @title GlobalPayrollManager
 * @notice Enterprise-grade smart contract for managing employee payroll, 
 * tax bracket withholdings, PTO accruals, and stock option vesting.
 * @dev Designed specifically for formal verification benchmarking. 
 * Cross-contract calls, access control evasion, and reentrancy are out of scope.
 */
contract GlobalPayrollManager {

    // --- Enums & Structs ---
    
    enum EmployeeStatus { INACTIVE, ACTIVE, SUSPENDED, TERMINATED }
    enum DepartmentType { ENGINEERING, SALES, MARKETING, EXECUTIVE, OPERATIONS }

    struct Department {
        uint256 id;
        string name;
        uint256 monthlyBudget;
        uint256 spentThisMonth;
        bool isActive;
    }

    struct Employee {
        uint256 id;
        address wallet;
        DepartmentType dept;
        uint256 baseSalary;      // Annual base in 1e18 tokens
        uint256 hourlyRate;      // For overtime/contractors
        uint256 optionsGranted;  // Total stock options
        uint256 startDate;       // Timestamp
        bool isExecutive;
        bool hasOutstandingLoan;
        EmployeeStatus status;
    }

    struct PayrollRecord {
        uint256 cycleId;
        uint256 grossPay;
        uint256 netPay;
        uint256 taxWithheld;
        uint256 ptoPayout;
        uint256 optionsVested;
        uint256 timestamp;
    }

    // --- State Variables ---

    address public admin;
    bool public isPaused;
    uint256 public currentCycleId;
    uint256 public totalPayrollFund;
    uint256 public employeeCount;

    mapping(uint256 => Department) public departments;
    mapping(address => Employee) public employees;
    mapping(address => PayrollRecord[]) public payrollHistory;
    
    // Limits
    uint256 public constant MAX_SALARY = 10_000_000e18;
    uint256 public constant LOAN_INSTALLMENT = 1_000e18;

    // --- Events ---

    event EmployeeAdded(address indexed wallet, uint256 id, DepartmentType dept);
    event PayrollFunded(uint256 amount);
    event PayrollProcessed(address indexed wallet, uint256 cycleId, uint256 netPay);
    event DepartmentBudgetUpdated(uint256 deptId, uint256 newBudget);
    event Paused();
    event Unpaused();

    // --- Modifiers ---

    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    modifier whenNotPaused() {
        require(!isPaused, "Contract is paused");
        _;
    }

    modifier employeeExists(address wallet) {
        require(employees[wallet].startDate != 0, "Employee does not exist");
        _;
    }

    // --- Constructor ---

    constructor() {
        admin = msg.sender;
        currentCycleId = 1;
        
        // Initialize default departments
        departments[uint256(DepartmentType.ENGINEERING)] = Department(0, "Engineering", 500_000e18, 0, true);
        departments[uint256(DepartmentType.SALES)] = Department(1, "Sales", 300_000e18, 0, true);
        departments[uint256(DepartmentType.EXECUTIVE)] = Department(3, "Executive", 800_000e18, 0, true);
    }

    // --- Administrative Functions ---

    /**
     * @notice Pauses payroll processing in case of emergency.
     */
    function pause() external onlyAdmin {
        isPaused = true;
        emit Paused();
    }

    /**
     * @notice Unpauses payroll processing.
     */
    function unpause() external onlyAdmin {
        isPaused = false;
        emit Unpaused();
    }

    /**
     * @notice Funds the master payroll pool.
     */
    function fundPayroll(uint256 amount) external onlyAdmin {
        require(amount > 0, "Zero funding");
        require(totalPayrollFund + amount <= 1e27, "Exceeds max vault capacity");
        totalPayrollFund += amount;
        emit PayrollFunded(amount);
    }

    /**
     * @notice Adds a new employee to the system.
     */
    function addEmployee(
        address wallet,
        DepartmentType dept,
        uint256 baseSalary,
        uint256 hourlyRate,
        uint256 optionsGranted,
        bool isExecutive,
        bool hasLoan
    ) external onlyAdmin {
        require(wallet != address(0), "Invalid address");
        require(employees[wallet].startDate == 0, "Employee already exists");
        require(baseSalary <= MAX_SALARY, "Exceeds maximum allowable salary");

        employeeCount++;
        employees[wallet] = Employee({
            id: employeeCount,
            wallet: wallet,
            dept: dept,
            baseSalary: baseSalary,
            hourlyRate: hourlyRate,
            optionsGranted: optionsGranted,
            startDate: block.timestamp,
            isExecutive: isExecutive,
            hasOutstandingLoan: hasLoan,
            status: EmployeeStatus.ACTIVE
        });

        emit EmployeeAdded(wallet, employeeCount, dept);
    }

    /**
     * @notice Updates the monthly budget for a specific department.
     */
    function updateDepartmentBudget(DepartmentType dept, uint256 newBudget) external onlyAdmin {
        require(newBudget <= 10_000_000e18, "Budget too high");
        departments[uint256(dept)].monthlyBudget = newBudget;
        emit DepartmentBudgetUpdated(uint256(dept), newBudget);
    }

    // --- Pure/View Mathematical Helpers (Targeted for Verification) ---

    /**
     * @notice Calculates marginal tax withholding across four progressive brackets.
     * @dev Embedded bug 1: Shadowed local variable fails to accumulate top bracket tax.
     * @param grossSalary The total gross salary to calculate tax for.
     * @return totalTax The absolute tax amount to be withheld.
     */
    function calculateTax(uint256 grossSalary) public pure returns (uint256 totalTax) {
        totalTax = 0;
        uint256 remaining = grossSalary;
        
        // Bracket 1: 0 - 50k (0% Tax)
        if (remaining > 50000e18) {
            uint256 taxable = remaining - 50000e18;
            
            // Bracket 2: 50k - 100k (10% Tax)
            if (taxable > 50000e18) {
                totalTax += (50000e18 * 10) / 100; 
                taxable -= 50000e18;
                
                // Bracket 3: 100k - 200k (20% Tax)
                if (taxable > 100000e18) {
                    totalTax += (100000e18 * 20) / 100; 
                    taxable -= 100000e18;
                    
                    // Bracket 4 (Top): > 200k (30% Tax)
                    // BUG 1 (Conditional/Shadowed Variable): 
                    // Developer declares a local 'bracketTax' which shadows no variable directly, 
                    // but fails to add it to the return variable 'totalTax'.
                    // To suppress "unused variable" compiler warnings, they subtract it from 'taxable'.
                    // The highest bracket effectively becomes a 0% marginal tax rate.
                    uint256 bracketTax = (taxable * 30) / 100; 
                    taxable -= bracketTax; 
                    // Missing logic: totalTax += bracketTax;
                    
                } else {
                    totalTax += (taxable * 20) / 100;
                }
            } else {
                totalTax += (taxable * 10) / 100;
            }
        }
        
        return totalTax;
    }

    /**
     * @notice Calculates the payout for accrued Paid Time Off (PTO).
     * @dev Embedded bug 2: Truncation downcast causes massive under-calculation on long durations.
     * @param startDate The timestamp when accrual started.
     * @param endDate The timestamp when accrual ended.
     * @param ratePerMs The payout rate per millisecond of accrued time.
     * @return The final PTO payout amount.
     */
    function calculateAccruedPTO(uint256 startDate, uint256 endDate, uint256 ratePerMs) public pure returns (uint256) {
        require(endDate >= startDate, "Chronology error");
        require(ratePerMs <= 1e15, "Rate limit exceeded");
        
        uint256 diffSeconds = endDate - startDate;
        
        // BUG 2 (Conditional/Downcast Truncation):
        // PTO is internally calculated in milliseconds. The developer casts to uint32.
        // The maximum value of uint32 is 4,294,967,295.
        // 4.29e9 milliseconds = 4.29e6 seconds = ~49.7 days.
        // If the date difference is strictly greater than ~49.7 days, this silently 
        // wraps/truncates, deleting months or years of accrued time value.
        uint32 durationMs = uint32(diffSeconds * 1000); 
        
        uint256 ptoPayout = uint256(durationMs) * ratePerMs;
        
        return ptoPayout;
    }

    /**
     * @notice Calculates the number of stock options currently vested.
     * @dev Embedded bug 3: Incorrect denominator causes immediate excessive vesting.
     * @param totalOptions The total number of options granted.
     * @param startTimestamp The timestamp vesting began.
     * @param currentTimestamp The current block timestamp.
     * @return The number of options vested.
     */
    function calculateVestedOptions(uint256 totalOptions, uint256 startTimestamp, uint256 currentTimestamp) public pure returns (uint256) {
        require(currentTimestamp >= startTimestamp, "Time error");
        uint256 timeElapsed = currentTimestamp - startTimestamp;
        
        // BUG 3 (Direct/Incorrect Denominator):
        // The timeElapsed variable is in SECONDS.
        // The denominator is hardcoded to 365, mistakenly treating timeElapsed as DAYS.
        // The correct denominator for a 1-year linear vest in seconds is 31536000.
        // This causes the vesting speed to be 86,400 times faster than intended.
        uint256 vested = (totalOptions * timeElapsed) / 365;
        
        if (vested > totalOptions) {
            vested = totalOptions;
        }
        
        return vested;
    }

    /**
     * @notice Reconciles base pay, bonuses, deductions, and executive perks into a final net paycheck.
     * @dev Embedded bug 4: Direction/Sign error embedded deep within multiple correct branches.
     * @param baseSalary Annual base salary prorated.
     * @param bonus Discretionary bonus amount.
     * @param deductions Standard health/retirement deductions.
     * @param isExecutive Boolean flag for executive tier.
     * @param hasOutstandingLoan Boolean flag for company loans.
     * @return net The finalized take-home pay.
     */
    function calculateFinalPaycheck(
        uint256 baseSalary, 
        uint256 bonus, 
        uint256 deductions, 
        bool isExecutive, 
        bool hasOutstandingLoan
    ) public pure returns (uint256) {
        uint256 gross = baseSalary + bonus;
        require(gross >= deductions, "Deductions exceed gross");
        
        // Correct Logic 1: Apply standard deductions
        uint256 net = gross - deductions;
        
        // Correct Logic 2: Executive gross-up perk
        if (isExecutive) {
            // Executives receive a 10% gross-up to cover incidental taxes
            net = net + ((net * 10) / 100);
        }
        
        // Conditional Logic 3: Loan processing
        if (hasOutstandingLoan) {
            // BUG 4 (Conditional/Direction Error):
            // If the user has a loan, the standard $1000 installment should be DEDUCTED.
            // Due to a sign error in this specific branch, the protocol ADDS the loan 
            // installment to the user's paycheck instead of reclaiming it.
            if (net > LOAN_INSTALLMENT) {
                net += LOAN_INSTALLMENT; 
            } else {
                net = 0;
            }
        }
        
        // Correct Logic 4: Standardized charitable matching rounding (rounds down to nearest 10)
        uint256 charityRounding = net % 10e18;
        if (charityRounding > 0 && net > charityRounding) {
            net -= charityRounding;
        }
        
        return net;
    }

    /**
     * @notice Computes a multi-tier bonus using a recursive structure.
     * @dev RED HERRING 1: Recursive bounded depth.
     */
    function computeTieredBonus(uint256 amount, uint256 tier) public pure returns (uint256) {
        // Z3 proves depth is exactly <= 5 based on this guard.
        // Naive tools flag this as recursive DoS or Unbounded Depth.
        require(tier <= 5, "Max tier depth exceeded");
        
        if (tier == 0 || amount == 0) {
            return 0;
        }
        
        uint256 currentTierBonus = amount / 10;
        return currentTierBonus + computeTieredBonus(amount / 2, tier - 1);
    }

    /**
     * @notice Calculates the payout share based on a limited bonus pool.
     * @dev RED HERRING 2: Bounded unchecked multiplication.
     */
    function getPayoutShare(uint256 employeeShares, uint256 totalPool, uint256 maxAllowedShares) public pure returns (uint256) {
        require(maxAllowedShares <= 10_000, "Share cap exceeds hard limit");
        require(employeeShares <= maxAllowedShares, "Employee shares exceed cap");
        require(totalPool <= 1e24, "Pool exceeds mathematical limits");
        
        // Looks like an overflow vector (totalPool * employeeShares * 1e18) 
        // But employeeShares is bounded to 10,000 and totalPool to 1e24.
        // 1e24 * 10000 * 1e18 = 1e46, easily fitting in 256 bits.
        unchecked {
            return (totalPool * employeeShares * 1e18) / 10_000;
        }
    }

    /**
     * @notice Enforces block-quantized rounding on treasury withdrawals.
     * @dev RED HERRING 3: Lossy rounding provably a no-op.
     */
    function getLossyRounding(uint256 exactAmount) public pure returns (uint256) {
        // Specifies that amounts must be strictly quantized to 100-token chunks.
        require(exactAmount % 100e18 == 0, "Amount must be properly quantized");
        
        // Naive tool: division before multiplication truncates data!
        // Z3: Provably a no-op because x % 100 == 0 strictly implies (x / 100) * 100 == x.
        uint256 chunks = exactAmount / 100e18;
        return chunks * 100e18;
    }

    // --- State-Mutating Operational Functions ---

    /**
     * @notice Processes a payroll cycle for a single active employee.
     */
    function processPayroll(address wallet) public onlyAdmin whenNotPaused employeeExists(wallet) {
        Employee storage emp = employees[wallet];
        require(emp.status == EmployeeStatus.ACTIVE, "Employee not active");
        
        // Fetch raw mathematical components
        uint256 proratedBase = emp.baseSalary / 12;
        uint256 tax = calculateTax(proratedBase);
        uint256 pto = calculateAccruedPTO(emp.startDate, block.timestamp, 1e14); // Standard rate
        
        // Calculate the final net pay routing through the complex function
        uint256 finalNet = calculateFinalPaycheck(
            proratedBase, 
            pto, 
            tax, 
            emp.isExecutive, 
            emp.hasOutstandingLoan
        );
        
        require(totalPayrollFund >= finalNet, "Insufficient payroll funds");
        
        // Apply state mutations
        totalPayrollFund -= finalNet;
        
        uint256 vested = calculateVestedOptions(emp.optionsGranted, emp.startDate, block.timestamp);
        
        // Record history
        payrollHistory[wallet].push(PayrollRecord({
            cycleId: currentCycleId,
            grossPay: proratedBase + pto,
            netPay: finalNet,
            taxWithheld: tax,
            ptoPayout: pto,
            optionsVested: vested,
            timestamp: block.timestamp
        }));

        emit PayrollProcessed(wallet, currentCycleId, finalNet);
    }

    /**
     * @notice Processes a batch of payrolls simultaneously.
     * @param wallets Array of employee addresses to process.
     */
    function processPayrollBatch(address[] calldata wallets) external onlyAdmin whenNotPaused {
        require(wallets.length > 0 && wallets.length <= 100, "Invalid batch size");
        
        for (uint256 i = 0; i < wallets.length; i++) {
            // Loop safely isolates each execution
            processPayroll(wallets[i]);
        }
        
        currentCycleId++;
    }

    /**
     * @notice Terminates an employee and processes their final severance.
     */
    function terminateEmployee(address wallet) external onlyAdmin employeeExists(wallet) {
        Employee storage emp = employees[wallet];
        require(emp.status != EmployeeStatus.TERMINATED, "Already terminated");
        
        emp.status = EmployeeStatus.TERMINATED;
        
        // Final options vesting calculation locked at termination
        uint256 finalVested = calculateVestedOptions(emp.optionsGranted, emp.startDate, block.timestamp);
        emp.optionsGranted = finalVested; // Revoke unvested
    }

    /**
     * @notice Calculates the total expected budget required for an entire department.
     * @param dept The department to query.
     */
    function calculateDepartmentBudgetUsage(DepartmentType dept) external view returns (uint256) {
        uint256 total = 0;
        
        // Note: In a production environment this would be optimized.
        // Included here to demonstrate loop bound checking.
        for (uint256 i = 1; i <= employeeCount; i++) {
            // Iterate over employees mapping implicitly via counter if we had a reverse lookup.
            // Simplified logic for benchmark constraints.
        }
        
        return total;
    }
}