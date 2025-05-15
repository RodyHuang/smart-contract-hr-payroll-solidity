# Principles of Distributed Ledgers: Coursework--Human Resources Smart Contract

---

## Overview

The **HumanResources** smart contract is a decentralized payroll management system designed for managing employee registration, salary payments, and contract termination. Employees can choose to receive their salaries in USDC or ETH. The contract integrates Uniswap AMM for swapping between USDC and ETH, and utilizes Chainlink Oracles for real-time ETH/USD price feeds.

---

## Implementation of IHumanResources Interface

### HR Manager Functions

- **`registerEmployee(address employee, uint256 weeklyUsdSalary)`**
  - **Description**: Registers an employee with a weekly salary denominated in USD. The function sets the weekly salary, marks the employee's employment start time, and initializes default values for other attributes.
  - **Access Control**: Only callable by the HR manager.
  - **Logic**:
    - Sets the employee's weekly salary.
    - Sets the employment timestamp to the current block time.
    - Initializes the employee as receiving salary in USDC.
    - Increments the active employee count.
  
- **`terminateEmployee(address employee)`**
  - **Description**: Terminates an employee, which stops any further salary accrual.
  - **Access Control**: Only callable by the HR manager.
  - **Logic**:
    - Sets the employee's termination timestamp to the current block time.
    - Decrements the active employee count.

- **`hrManager()`**
  - **Description**: Returns the address of the HR manager, which is the contract deployer.
  

### Employee Functions

- **`salaryAvailable(address employee)`**
  - **Description**: Returns the amount of salary available for withdrawal in the employee's preferred currency. It calls an internal `_salaryAvailable` function to handle the actual calucaltion logic.

- **`UsdSalaryAvailable()`**
  - **Description**: Calculates the available USD salary for an employee, considering employment status, last withdrawal, and pending salary.
  - **Logic**:
    - Returns 0 if the employee is not registered
    - Calculates time elapsed since last withdrawal and accrued salary.
    - Returns the total available USD salary.

- **`_salaryAvailable()`**
  - **Description**: Calculates available salary in the employee's preferred currency (USDC or ETH).
  - **Logic**:
    - Calls `UsdSalaryAvailable()` to get available USD salary.
    - Converts to ETH if preferred, using the latest ETH price.
    - Converts to USDC if preferred.
    - Returns the equivalent amount in the chosen currency.

- **`withdrawSalary()`**
  - **Description**: Allows an employee to withdraw their accumulated salary, either in USDC or ETH, based on their current preference. It calls an internal `_withdrawSalary` function to handle the actual withdrawal logic.
  - **Access Control**: Only callable by employees.

- **`_withdrawSalary()` (internal function)**
  - **Description**: Performs the core logic for salary withdrawal, determining the correct amount and currency to transfer.
  - **Logic**:
    - Accrued salary is calculated from the `salaryAvailable()` in the employee's preferred currency.
    - If paid in ETH, the contract uses Uniswap to swap USDC for ETH at the current market price fetched from Chainlink Oracles.
    - If paid in USDC, the equivalent USDC is transferred to the employee's address.

- **`switchCurrency()`**
  - **Description**: Switches the currency in which the employee receives their salary between USDC and ETH. By default, salary is paid in USDC. Before switching, any currently accrued salary is automatically withdrawn in the current currency.
  - **Access Control**: Only callable by employees.
  - **Logic**:
    - Calls `_withdrawSalary()` to withdraw any pending salary before switching.
    - Toggles the employee's payment preference to the opposite currency.

- **`getEmployeeInfo(address employee)`**
  - **Description**: Provides detailed information about an employee, including their weekly salary, employment start date, and termination date (if applicable).

- **`getActiveEmployeeCount()`**
  - **Description**: Returns the current count of active employees. This is maintained by incrementing when registering and decrementing when terminating employees.
---

## Integration of AMM and Oracle

- **Oracle Integration**: The contract uses Chainlink's ETH/USD oracle to obtain real-time ETH prices, ensuring accurate exchange rates when calculating the accrued salary

- **AMM Integration**: When an employee chooses to receive their salary in ETH, the contract uses Uniswap's AMM to swap USDC for WETH.

---

## Summary

This contract implements all functions defined in the IHumanResources interface to manage employee registration, payroll, and termination effectively. By integrating Chainlink Oracles and Uniswap AMM, it ensures reliable and flexible salary payments.