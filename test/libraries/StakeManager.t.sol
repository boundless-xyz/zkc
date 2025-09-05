// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/interfaces/IERC20.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {StakeManager} from "../../src/libraries/StakeManager.sol";
import {Checkpoints} from "../../src/libraries/Checkpoints.sol";
import {Constants} from "../../src/libraries/Constants.sol";
import {IStaking} from "../../src/interfaces/IStaking.sol";
import {console} from "forge-std/console.sol";

/**
 * @title StakeManager Library Test
 * @notice Simple unit tests for StakeManager library
 */
contract StakeManagerTest is Test {
    MockERC20 internal mockToken;
    address internal user = address(0x1);
    uint256 internal constant AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        mockToken = new MockERC20();
        mockToken.mint(user, AMOUNT * 10);
    }

    function testCreateStake() public view {
        // Create stake
        Checkpoints.StakeInfo memory stake = StakeManager.createStake(AMOUNT);
        assertEq(stake.amount, AMOUNT);
        assertEq(stake.withdrawalRequestedAt, 0);
    }

    function testAddToStake() public view {
        // Create initial stake
        Checkpoints.StakeInfo memory stake = StakeManager.createStake(AMOUNT);

        // Add to stake
        Checkpoints.StakeInfo memory newStake = StakeManager.addToStake(stake, AMOUNT);
        assertEq(newStake.amount, AMOUNT * 2);
        assertEq(newStake.withdrawalRequestedAt, 0);
    }

    function testInitiateWithdrawal() public {
        // Create stake
        Checkpoints.StakeInfo memory stake = StakeManager.createStake(AMOUNT);

        // Initiate withdrawal
        Checkpoints.StakeInfo memory withdrawingStake = StakeManager.initiateWithdrawal(stake);
        assertEq(withdrawingStake.amount, AMOUNT);
        assertEq(withdrawingStake.withdrawalRequestedAt, vm.getBlockTimestamp());
    }

    function testCanCompleteWithdrawal() public {
        // Create withdrawing stake
        Checkpoints.StakeInfo memory stake =
            Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: vm.getBlockTimestamp()});

        // Cannot complete immediately
        assertFalse(StakeManager.canCompleteWithdrawal(stake));

        // Can complete after withdrawal period
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD + 1);
        assertTrue(StakeManager.canCompleteWithdrawal(stake));
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testValidateStake() public {
        // Zero amount validation
        vm.expectRevert(IStaking.ZeroAmount.selector);
        StakeManager.validateStake(0, 0);

        // User already has active position
        vm.expectRevert(IStaking.UserAlreadyHasActivePosition.selector);
        StakeManager.validateStake(AMOUNT, 123);

        // Valid stake
        StakeManager.validateStake(AMOUNT, 0); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testValidateAddToStake() public {
        // Zero amount validation
        Checkpoints.StakeInfo memory activeStake = Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: 0});

        vm.expectRevert(IStaking.ZeroAmount.selector);
        StakeManager.validateAddToStake(0, activeStake);

        // Cannot add to withdrawing position
        Checkpoints.StakeInfo memory withdrawingStake =
            Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: vm.getBlockTimestamp()});

        vm.expectRevert(IStaking.CannotAddToWithdrawingPosition.selector);
        StakeManager.validateAddToStake(AMOUNT, withdrawingStake);

        // Valid add to stake
        StakeManager.validateAddToStake(AMOUNT, activeStake); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testValidateWithdrawalInitiation() public {
        // Already withdrawing
        Checkpoints.StakeInfo memory withdrawingStake =
            Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: vm.getBlockTimestamp()});

        vm.expectRevert(IStaking.WithdrawalAlreadyInitiated.selector);
        StakeManager.validateWithdrawalInitiation(withdrawingStake);

        // Valid withdrawal initiation (zero amount is OK for this function)
        Checkpoints.StakeInfo memory activeStake = Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: 0});
        StakeManager.validateWithdrawalInitiation(activeStake); // Should not revert

        // Even zero amount is OK if not withdrawing
        Checkpoints.StakeInfo memory emptyStake = Checkpoints.StakeInfo({amount: 0, withdrawalRequestedAt: 0});
        StakeManager.validateWithdrawalInitiation(emptyStake); // Should not revert
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function testValidateUnstakeCompletion() public {
        // Zero token ID validation
        Checkpoints.StakeInfo memory stake =
            Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: vm.getBlockTimestamp()});

        vm.expectRevert(IStaking.NoActivePosition.selector);
        StakeManager.validateUnstakeCompletion(0, stake);

        // Not withdrawing validation
        Checkpoints.StakeInfo memory activeStake = Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: 0});

        vm.expectRevert(IStaking.WithdrawalNotInitiated.selector);
        StakeManager.validateUnstakeCompletion(123, activeStake);

        // Withdrawal period not elapsed
        Checkpoints.StakeInfo memory recentWithdrawal =
            Checkpoints.StakeInfo({amount: AMOUNT, withdrawalRequestedAt: vm.getBlockTimestamp()});

        vm.expectRevert(IStaking.WithdrawalPeriodNotComplete.selector);
        StakeManager.validateUnstakeCompletion(123, recentWithdrawal);

        // Valid unstake completion
        vm.warp(vm.getBlockTimestamp() + Constants.WITHDRAWAL_PERIOD + 1);
        StakeManager.validateUnstakeCompletion(123, recentWithdrawal); // Should not revert
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
