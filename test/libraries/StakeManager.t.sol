// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {StakeManager} from "../../src/libraries/StakeManager.sol";
import {Checkpoints} from "../../src/libraries/Checkpoints.sol";
import {Constants} from "../../src/libraries/Constants.sol";
import {console} from "forge-std/console.sol";

/**
 * @title StakeManager Library Test
 * @notice Simple unit tests for StakeManager library
 */
contract StakeManagerTest is Test {
    
    MockERC20 internal mockToken;
    address internal user = address(0x1);
    uint256 internal constant AMOUNT = 1000 * 10**18;
    uint256 internal constant WEEK = 7 days;
    
    function setUp() public {
        mockToken = new MockERC20();
        mockToken.mint(user, AMOUNT * 10);
    }
    
    function testGetWeekExpiry() public view {
        // Minimum
        uint256 minExpiry = StakeManager.getWeekExpiry(0);
        assertGe(minExpiry, vm.getBlockTimestamp() + Constants.MIN_STAKE_TIME_S);
        assertEq(minExpiry % WEEK, 0);
        
        // Maximum
        uint256 maxExpiry = StakeManager.getWeekExpiry(type(uint256).max);
        assertLe(maxExpiry, vm.getBlockTimestamp() + Constants.MAX_STAKE_TIME_S);
        assertEq(maxExpiry % WEEK, 0);
        
        // Specific time
        uint256 target = vm.getBlockTimestamp() + 10 weeks;
        uint256 expiry = StakeManager.getWeekExpiry(target);
        assertEq(expiry, Checkpoints.timestampFloorToWeek(target));
    }
    
    function testTimestampFloorToWeek() public view {
        // Unix epoch (Jan 1, 1970) was a Thursday at 00:00 UTC
        // So week boundaries occur every Thursday at 00:00 UTC
        uint256 weekStart = 1609372800; // Thursday Dec 31, 2020 00:00 UTC (week boundary)
        uint256 midWeek = weekStart + 3 days;
        
        assertEq(Checkpoints.timestampFloorToWeek(weekStart), weekStart);
        assertEq(Checkpoints.timestampFloorToWeek(midWeek), weekStart);
    }
    
    /// forge-config: default.allow_internal_expect_revert = true
    function testValidateLockExtension() public {
        Checkpoints.LockInfo memory lock = Checkpoints.LockInfo({
            amount: AMOUNT,
            lockEnd: vm.getBlockTimestamp() + 6 weeks
        });
        
        // Valid extension
        uint256 newEnd = vm.getBlockTimestamp() + 8 weeks;
        uint256 validated = StakeManager.validateLockExtension(lock, newEnd);
        assertGt(validated, lock.lockEnd);
        
        // Cannot decrease
        uint256 newEnd2 = vm.getBlockTimestamp() + 5 weeks;
        vm.expectRevert(StakeManager.CanOnlyIncreaseLockEndTime.selector);
        StakeManager.validateLockExtension(lock, newEnd2);
    }
    
    function testLockCreation() public view {
        // Create lock
        Checkpoints.LockInfo memory lock = StakeManager.createLock(AMOUNT, vm.getBlockTimestamp() + 8 weeks);
        assertEq(lock.amount, AMOUNT);
        
        // Extend lock
        Checkpoints.LockInfo memory extended = StakeManager.extendLock(lock, vm.getBlockTimestamp() + 12 weeks);
        assertEq(extended.amount, AMOUNT);
        assertEq(extended.lockEnd, vm.getBlockTimestamp() + 12 weeks);
        
        // Add to lock
        Checkpoints.LockInfo memory added = StakeManager.addToLock(lock, AMOUNT);
        assertEq(added.amount, AMOUNT * 2);
        assertEq(added.lockEnd, lock.lockEnd);
        
        // Empty lock
        Checkpoints.LockInfo memory empty = StakeManager.emptyLock();
        assertEq(empty.amount, 0);
        assertEq(empty.lockEnd, 0);
    }
    
    /// forge-config: default.allow_internal_expect_revert = true
    function testValidations() public {
        // Stake validation
        vm.expectRevert(StakeManager.ZeroAmount.selector);
        StakeManager.validateStake(0, 0);
        
        vm.expectRevert(StakeManager.UserAlreadyHasActivePosition.selector);
        StakeManager.validateStake(AMOUNT, 123);
        
        // Add to stake validation
        Checkpoints.LockInfo memory expiredLock = Checkpoints.LockInfo({
            amount: AMOUNT,
            lockEnd: vm.getBlockTimestamp() - 1
        });
        
        vm.expectRevert(StakeManager.CannotAddToExpiredPosition.selector);
        StakeManager.validateAddToStake(AMOUNT, expiredLock);
        
        // Unstake validation
        Checkpoints.LockInfo memory activeLock = Checkpoints.LockInfo({
            amount: AMOUNT,
            lockEnd: vm.getBlockTimestamp() + 8 weeks
        });
        
        vm.expectRevert(StakeManager.LockHasNotExpiredYet.selector);
        StakeManager.validateUnstake(123, activeLock);
    }
    
    function testTokenTransfers() public {
        // Transfer in
        vm.prank(user);
        mockToken.approve(address(this), AMOUNT);
        
        uint256 balanceBefore = mockToken.balanceOf(user);
        StakeManager.transferTokensIn(IERC20(address(mockToken)), user, AMOUNT);
        assertEq(mockToken.balanceOf(user), balanceBefore - AMOUNT);
        
        // Transfer out
        StakeManager.transferTokensOut(IERC20(address(mockToken)), user, AMOUNT);
        assertEq(mockToken.balanceOf(user), balanceBefore);
    }
}

contract MockERC20 is ERC20 {
    constructor() ERC20("Mock", "MOCK") {}
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}