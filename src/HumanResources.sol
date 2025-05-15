// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

import "./IHumanResources.sol"; // Import IHumanResources interface given by Spec
import "./interface/ISwapRouter.sol";// Import Uniswap V3 router interface for AMM
import "./interface/AggregatorV3Interface.sol"; // Import Chainlink Oracle interface for real world ETH price
import "./interface/ReentrancyGuard.sol"; // Import OpenZeppelin ReentrancyGuard for reentrancy protection
import "./interface/IERC20.sol"; // Import IERC20 interface for USDC operation

contract HumanResources is IHumanResources, ReentrancyGuard {

    address private _hrManager;
   
    AggregatorV3Interface internal priceFeed; // Declaration of an interface variable for the Chainlink price feed to obtain the ETH price
    ISwapRouter internal uniswapRouter; //Declaration of an interface variable for UniSwap
    address public usdcAddress; 
    address public wethAddress;

    // Constructor for the HR contract
    constructor() {
        _hrManager = msg.sender; // Set the HR manager's address at contract creation
        priceFeed = AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5); // Set the address of the Chainlink feed contract
        uniswapRouter = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564); // Set the address of the Uniswap AMM contract
        usdcAddress = 0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85; // Set the USDC token address
        wethAddress = 0x4200000000000000000000000000000000000006; // Set the WETH token address
    }

   // Define the Employee struct to store employee information
    struct Employee {
        uint256 weeklyUsdSalary; // Employee's weekly salary in USD (18 decimals)
        uint256 employedSince; // Timestamp when the employee was registered, 0 means not employed
        uint256 terminatedAt; // Timestamp when the employee was terminated, 0 means still employed
        bool isPaidInETH; // Indicate whether the employee chooses to be paid in ETH
        uint256 lastWithdrawal; // Timestamp of the last salary withdrawal, for calculating the salary payble
        uint256 pendingSalary; // Store the pendingSalary when terminated
        bool everEmployed; // True if ever been employed
    }

    mapping(address => Employee) private employees; // Mapping of employee address to their corresponding Struct
    uint256 public activeEmployeeCount; // The number of active employees

    // Modifier to restrict functions to only be callable by HR manager
    modifier onlyHR() {
        if (msg.sender != _hrManager) {
            revert NotAuthorized();
        }
        _;
    }  
    
    // Modifier to restrict functions to only be callable by employee
    modifier onlyEmployee() {
        if (employees[msg.sender].everEmployed == false) { // employedSince == 0 means not employed
            revert NotAuthorized();
        }
        _;
     }

    // Modifier to restrict functions to only be callable by active employee
    modifier onlyActiveEmployee() {
        if (employees[msg.sender].employedSince == 0) { // EmployedSince == 0 means not employed
            revert NotAuthorized();
        }
        _;
     }

    // Register an employee, can only be called by HR manager
    function registerEmployee(address employee, uint256 weeklyUsdSalary) external override onlyHR {
        if (employees[employee].employedSince != 0 && employees[employee].terminatedAt == 0) { // Check if the employee is already registered and not terminated
            revert EmployeeAlreadyRegistered();
        }
        
        // Register or re-register an employee and initialize their information
        employees[employee].weeklyUsdSalary = weeklyUsdSalary; // Set the weekly salary (18 decimal)
        employees[employee].employedSince = block.timestamp; // Set the registration time to the current block timestamp
        employees[employee].terminatedAt = 0; // Set termination time to 0, indicating still employed
        employees[employee].isPaidInETH = false; // Default payment method is USDC
        employees[employee].lastWithdrawal = block.timestamp; // Set the last withdrawal time to the register timestamp as the starting point of the salary calculation
        employees[employee].everEmployed = true; // Indicate if a person is ever employed

        activeEmployeeCount++; // Increment the active employee count
        emit EmployeeRegistered(employee, weeklyUsdSalary);
    }

    // Terminate an employee, can only be called by HR manager
    function terminateEmployee(address employee) external override onlyHR {
        Employee storage emp = employees[employee];
        if (emp.employedSince == 0) { // Check if the employee exists
            revert EmployeeNotRegistered();
        }

        // Calculate the  pending salary for the terminated employee
        uint256 accruedSalary = (emp.weeklyUsdSalary * (block.timestamp- emp.lastWithdrawal)) / 7 days;
        emp.pendingSalary += accruedSalary;

        // Reset the timestamp
        emp.lastWithdrawal = block.timestamp;
        emp.terminatedAt = block.timestamp;
        emp.employedSince = 0;
        activeEmployeeCount--; // Decrement the active employee count

        emit EmployeeTerminated(employee);
    }

    // Calculate the USD salary available for an employee
    function UsdSalaryAvailable(address employee) public view returns (uint256){
        Employee storage emp = employees[employee]; 
        if (emp.everEmployed == false) { // Check if the employee has ever been registered
            return 0;
        }
        
        // Calculate the total available salary in USD
        uint256 endTime = emp.terminatedAt != 0 ? emp.terminatedAt : block.timestamp; // Define the ending time of the salary calculation
        // If the employee has withdrawl after terminated, no salary is available
        if(emp.terminatedAt != 0 && emp.terminatedAt < emp.lastWithdrawal){
            return 0;
        }
        uint256 timeElapsed = endTime - emp.lastWithdrawal; // Calculate the time elapsed since the last withdrawal
        uint256 accruedSalary = (emp.weeklyUsdSalary * timeElapsed) / 7 days; // Calculate the accrued salary based on the time elapsed
        uint256 totalAvailableSalary = accruedSalary + emp.pendingSalary; // Add up the pending salary calculated when last terminated
        return  totalAvailableSalary; // The total USD salary available for an employee
    }

    // Calculate the salary (USDC or ETH) available for withdrawal
    function _salaryAvailable(address employee) public view returns (uint256) {
        Employee storage emp = employees[employee]; 
        uint256 totalAvailableSalary = UsdSalaryAvailable(employee); // Get the total available salary in USD
        
        // Exchange USD to ETH or USDC based on the employee's preference
        if (emp.isPaidInETH) {
            uint256 ethPrice = getLatestETHPrice(); // Get the latest ETH price from the oracle (8 decimals)
            uint256 ethAmount = (totalAvailableSalary * 1e8) / ethPrice;
            return ethAmount;
        } else {
            uint256 usdcAmount = totalAvailableSalary / 1e12; // Convert accrued salary to USDC, scaled to 6 decimals
            return usdcAmount;
        }
    }

    // Function to get the latest ETH price from the oracle
    function getLatestETHPrice() public view returns (uint256) {
        (, int price, , ,) = priceFeed.latestRoundData();
        require(price > 0, "Invalid price");
        return uint256(price);
    }

    // Function to withdraw the accumulated salary, protected with nonReentrant tool
    function withdrawSalary() external override nonReentrant onlyEmployee { // Use nonReentrant to prevent from reentrance attack
        _withdrawSalary();
    }

    // Operation for withdrawing salary and currency swapping
    function _withdrawSalary() public onlyEmployee{
        Employee storage emp = employees[msg.sender];
        uint256 totalAvailableUsdSalary = UsdSalaryAvailable(msg.sender); // Get the accrued salary in terms of the USD
        emp.lastWithdrawal = block.timestamp; // Update the last withdrawal timestamp
        emp.pendingSalary = 0; // Update the pending salary for a terminated employee to 0

        if (emp.isPaidInETH) {
            uint256 ethPrice = getLatestETHPrice(); // Get the latest ETH price from Oracle in USD (8 decimals)
            uint256 estimatEthAmount = (totalAvailableUsdSalary * 1e8) / ethPrice; // Convert to ETH
            uint256 estimateUsdcInput = totalAvailableUsdSalary / 1e12; // Convert to USDC

            // Approve Uniswap to use the certain amount of USDC
            IERC20(usdcAddress).approve(address(uniswapRouter), estimateUsdcInput); 

            // Setting parameters for swapping USDC to WETH
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({ //Define a struct in the ISwapRouter interface
                tokenIn: usdcAddress, 
                tokenOut: wethAddress,
                fee: 3000, 
                recipient: address(this),
                deadline: block.timestamp+30,
                amountIn: estimateUsdcInput, // The amount of USDC to spend
                amountOutMinimum: estimatEthAmount*98/100, //The minimum amount of WETH to receive
                sqrtPriceLimitX96: 0
            });

            uint256 ethReceived = uniswapRouter.exactInputSingle(params); // Execute the swap to exchange USDC for WETH
            IWETH9(wethAddress).withdraw(ethReceived); // Convert WETH to ETH
            (bool success, ) = msg.sender.call{value:ethReceived}("");
            require(success, "transfer fail");
            emit SalaryWithdrawn(msg.sender, true, ethReceived);

        } else {
            // Transfer USDC to the employee
            uint256 usdcAmount = totalAvailableUsdSalary / 1e12; // Convert to USDC
            IERC20(usdcAddress).transfer(msg.sender, usdcAmount); // Transfer USDC to the employee using ERC20 interface
            emit SalaryWithdrawn(msg.sender, false, usdcAmount);
        }
    }

     // Function to switch the currency in which the employee receives their salary
    function switchCurrency() external override onlyActiveEmployee{ // Only callable by active employee
        Employee storage emp = employees[msg.sender];
        _withdrawSalary(); // Automatically withdraw the current pending salary before switching the payment method
        emp.isPaidInETH = !emp.isPaidInETH; // Toggle the isPaidInETH flag to switch between USDC and ETH

        emit CurrencySwitched(msg.sender, emp.isPaidInETH);
    }

    //View functions of the contract
    function hrManager() external view override returns (address) {
        return _hrManager;
    }

    function getActiveEmployeeCount() external view override returns (uint256) {
        return activeEmployeeCount;
    }
    
    function salaryAvailable(address employee) external view override returns (uint256) {
        return _salaryAvailable(employee);
    }

    function getEmployeeInfo(address employee) external view override returns (uint256, uint256, uint256) {
        Employee memory emp = employees[employee];
        return (emp.weeklyUsdSalary, emp.employedSince, emp.terminatedAt);
    }
    
    receive() external payable {}
}
