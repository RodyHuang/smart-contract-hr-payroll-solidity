// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.24;

/// @notice
import {Test, console, stdStorage, StdStorage} from "../lib/forge-std/src/Test.sol";
import {HumanResources, IHumanResources} from "../src/HumanResources.sol";
import {IERC20} from "../src/interface/IERC20.sol";
import {AggregatorV3Interface} from "../src/interface/AggregatorV3Interface.sol";
import "../lib/forge-std/src/console.sol"; 

contract HumanResourcesTest is Test {
    using stdStorage for StdStorage;

    address internal constant _WETH =
        0x4200000000000000000000000000000000000006;
    address internal constant _USDC =
        0x0b2C639c533813f4Aa9D7837CAf62653d097Ff85;
    AggregatorV3Interface internal constant _ETH_USD_FEED =
    AggregatorV3Interface(0x13e3Ee699D1909E989722E753853AE30b17e08c5);

    HumanResources public humanResources;
    address public hrManager;
    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");
    address public unauthorizedUser = address(0xABC);

    uint256 public aliceSalary = 2100e18;
    uint256 public bobSalary = 700e18;
    uint256 ethPrice;

    function setUp() public {
        vm.createSelectFork(vm.envString("PRD_ETH_RPC_URL"));
        humanResources = HumanResources(payable(vm.envAddress("PRD_HR_CONTRACT")));
        (, int256 answer, , , ) = _ETH_USD_FEED.latestRoundData();
        uint256 feedDecimals = _ETH_USD_FEED.decimals();
        ethPrice = uint256(answer) * 10 ** (18 - feedDecimals);
        hrManager = humanResources.hrManager();
        deal(_USDC, address(humanResources), 1_000_000 * 1e20); 
    }

    // Test registering new employees and verifying their employment details
    function test_registerEmployee() public {
        _registerEmployee(alice, aliceSalary);
        assertEq(humanResources.getActiveEmployeeCount(), 1);

        uint256 currentTime = block.timestamp;

        (
            uint256 weeklySalary,
            uint256 employedSince,
            uint256 terminatedAt
        ) = humanResources.getEmployeeInfo(alice);
        assertEq(weeklySalary, aliceSalary);
        assertEq(employedSince, currentTime);
        assertEq(terminatedAt, 0);

        skip(10 hours);

        _registerEmployee(bob, bobSalary);

        (weeklySalary, employedSince, terminatedAt) = humanResources
            .getEmployeeInfo(bob);
        assertEq(humanResources.getActiveEmployeeCount(), 2);

        assertEq(weeklySalary, bobSalary);
        assertEq(employedSince, currentTime + 10 hours);
        assertEq(terminatedAt, 0);
    }

    // Test that an unauthorized user cannot register an employee
    function testRegisterEmployee_Unauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        humanResources.registerEmployee(alice, aliceSalary);
    }

    // Test attempting to register an employee who is already registered, which should fail
    function testRegisterEmployeeTwice() public {
        _registerEmployee(alice, aliceSalary);
        vm.expectRevert(IHumanResources.EmployeeAlreadyRegistered.selector);
        _registerEmployee(alice, aliceSalary);
    }

    // Test that the HR manager cannot register an already registered employee
    function testRegisterEmployee_AlreadyRegistered() public {
        vm.prank(hrManager);
        humanResources.registerEmployee(alice, aliceSalary);

        vm.prank(hrManager);
        vm.expectRevert(IHumanResources.EmployeeAlreadyRegistered.selector);
        humanResources.registerEmployee(alice, aliceSalary);
    }

    // Test that non-employees cannot call employee-only functions
    function testOnlyEmployeeFunctions_Unauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        humanResources.withdrawSalary();
    }
   
    // Test terminating an employee successfully by the HR manager
    function testTerminateEmployee_Success() public {
        vm.prank(hrManager);
        humanResources.registerEmployee(alice, aliceSalary);

        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);

        (, , uint256 terminatedAt) = humanResources.getEmployeeInfo(alice);
        assertGt(terminatedAt, 0);
    }

    // Test that an unauthorized user cannot terminate an employee
    function testTerminateEmployee_Unauthorized() public {
        vm.prank(hrManager);
        humanResources.registerEmployee(alice, aliceSalary);

        vm.prank(unauthorizedUser);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        humanResources.terminateEmployee(alice);
    }

    // Test the salary available to an employee in USDC after a certain period of time
    function testSalaryAvailableUsdc() public {
        _registerEmployee(alice, aliceSalary);
        skip(2 days);
        assertEq(
            humanResources.salaryAvailable(alice),
            ((aliceSalary / 1e12) * 2) / 7
        );

        skip(5 days);
        assertEq(humanResources.salaryAvailable(alice), aliceSalary / 1e12);
    }

    // Test the salary available to an employee in ETH after a certain period of time
    function testSalaryAvailableEth() public {
        _registerEmployee(alice, aliceSalary);
        uint256 expectedSalary = (aliceSalary * 1e18 * 2) / ethPrice / 7;
        vm.prank(alice);
        humanResources.switchCurrency();
        skip(2 days);
        assertApproxEqRel(
            humanResources.salaryAvailable(alice),
            expectedSalary,
            0.01e18
        );
        skip(5 days);
        expectedSalary = (aliceSalary * 1e18) / ethPrice;
        assertApproxEqRel(
            humanResources.salaryAvailable(alice),
            expectedSalary,
            0.01e18
        );
    }

    // Test withdrawing salary in USDC for an employee after a certain period of time
    function testWithdrawSalary_USDC() public {
        vm.prank(hrManager);
        humanResources.registerEmployee(alice, aliceSalary);
        uint256 USDCiniBalance = IERC20(_USDC).balanceOf(alice);
        console.log("Initial USDC Balance", USDCiniBalance);
        vm.warp(block.timestamp + 7 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 USDCBalance = IERC20(_USDC).balanceOf(alice);
        console.log("Final USDC Balance", USDCBalance);
        assertGt(USDCBalance, USDCiniBalance);
    }

    // Test withdrawing salary in USDC multiple times for an employee
    function testWithdrawSalary_usdc() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);
        skip(2 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertEq(
            IERC20(_USDC).balanceOf(address(alice)),
            ((aliceSalary / 1e12) * 2) / 7
        );
        skip(5 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertEq(IERC20(_USDC).balanceOf(address(alice)), aliceSalary / 1e12);
    }

    /// Test withdrawing salary in ETH for an employee
    function testWithdrawSalary_ETH() public {
        vm.prank(hrManager);
        humanResources.registerEmployee(bob, bobSalary);
        vm.warp(block.timestamp + 7 days);
        vm.prank(bob);
        humanResources.switchCurrency();
        uint256 initialBalance = bob.balance;
        console.log("Initial ETH Balance", initialBalance);
        vm.warp(block.timestamp + 7 days);
        vm.prank(bob);
        humanResources.withdrawSalary();
        uint256 balance = bob.balance;
        console.log("Final ETH Balance", balance);
        assertGt(balance, initialBalance);
    }

    // Another test of withdrawing salary in ETH for an employee
    function testWithdrawSalary_eth() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);
        uint256 expectedSalary = (aliceSalary * 1e18 * 2) / ethPrice / 7;
        vm.prank(alice);
        humanResources.switchCurrency();
        skip(2 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        assertApproxEqRel(alice.balance, expectedSalary, 0.01e18);
        skip(5 days);
        expectedSalary = (aliceSalary * 1e18) / ethPrice;
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 balance = alice.balance;
        console.log("ETH balance", balance );
        assertApproxEqRel(alice.balance, expectedSalary, 0.01e18);
    }

    // Test that an unauthorized user cannot withdraw salary
    function testWithdrawSalary_Unauthorized() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        humanResources.withdrawSalary();
    }

    // Test that an unregistered employee cannot switch currency
    function testSwitchCurrency_NotRegistered() public {
        vm.prank(unauthorizedUser);
        vm.expectRevert(IHumanResources.NotAuthorized.selector);
        humanResources.switchCurrency();
    }

    // Test re-registering an employee after termination, and ensure salary accrual is correct
    function testReregisterEmployee() public {
        _mintTokensFor(_USDC, address(humanResources), 10_000e6);
        _registerEmployee(alice, aliceSalary);
        skip(2 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);
        skip(1 days);
        _registerEmployee(alice, aliceSalary * 2);
        skip(5 days);
        uint256 salary = humanResources.salaryAvailable(alice);
        emit log_uint(salary); 
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 expectedSalary = ((aliceSalary * 2) / 7) +
            ((aliceSalary * 2 * 5) / 7);
        assertEq(
            IERC20(_USDC).balanceOf(address(alice)),
            expectedSalary / 1e12
        );
    }

    // Test an employee after termination, and ensure salary accrual is correct
    function testBalanceAfWithdrawUsdc() public {
        // if employee is registered
        vm.prank(hrManager);
        humanResources.registerEmployee(alice, aliceSalary);
        skip(3 weeks); 
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);
        skip(1 weeks);
        vm.prank(hrManager);
        humanResources.registerEmployee(alice, aliceSalary);
        skip(2 weeks);
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 employee_balance = IERC20(_USDC).balanceOf(alice);
        console.log("The employee balance is :", employee_balance);
        assertEq(employee_balance, 10500 * 1e6, "Employee should deposit five weeks' salary");
        uint256 contract_balance = IERC20(_USDC).balanceOf(address(humanResources));
        console.log("The contract balance is:", contract_balance);
    }


    // Test that an employee can withdraw salary beyond the termination date
    function testWithdrawSalary_AfterTermination() public {
        vm.prank(hrManager);
        humanResources.registerEmployee(alice, aliceSalary);
        vm.warp(block.timestamp + 3 days);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);
        vm.warp(block.timestamp + 4 days);
        vm.prank(alice);
        humanResources.withdrawSalary();
        uint256 availableSalary = humanResources.salaryAvailable(alice);
        assertEq(availableSalary, 0);
    }

    // Test getting the HR manager address
    function testHrManager() public view {
        address manager = humanResources.hrManager();
        assertEq(manager, hrManager);
    }

    // Test getting employee information
    function testGetEmployeeInfo() public {
        vm.prank(hrManager);
        humanResources.registerEmployee(alice, aliceSalary);
        (uint256 salary, uint256 employedSince, uint256 terminatedAt) = humanResources.getEmployeeInfo(alice);
        assertEq(salary, aliceSalary);
        assertGt(employedSince, 0);
        assertEq(terminatedAt, 0);
        vm.prank(hrManager);
        humanResources.terminateEmployee(alice);
        (, , terminatedAt) = humanResources.getEmployeeInfo(alice);
        assertGt(terminatedAt, 0);
    }

    // Internal function to register an employee with the provided address and salary
    function _registerEmployee(address employeeAddress, uint256 salary) public {
        vm.prank(hrManager);
        humanResources.registerEmployee(employeeAddress, salary);
    }

    function _mintTokensFor(
        address token_,
        address account_,
        uint256 amount_
    ) internal {
        stdstore
            .target(token_)
            .sig(IERC20(token_).balanceOf.selector)
            .with_key(account_)
            .checked_write(amount_);
    }
}

