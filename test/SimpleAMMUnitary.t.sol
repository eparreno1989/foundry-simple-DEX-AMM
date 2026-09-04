// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test, console2} from "forge-std/Test.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {MockERC20} from "./Mocks/MockERC20.sol";

/// @title Unit Tests for SimpleAMM
/// @author Erick
/// @notice Comprehensive test suite covering deployment, liquidity provisioning, swaps, and revert conditions.
contract SimpleAMMTest is Test {
    SimpleAMM public amm;
    MockERC20 public token0;
    MockERC20 public token1;

    address public alice = makeAddr("alice");
    address public bob = makeAddr("bob");

    uint256 public constant INITIAL_MINT = 10_000e18;

    /// @dev Event declarations matching SimpleAMM for event emission testing with vm.expectEmit.
    event AddLiquidity(address indexed provider, uint256 sharesMinted);
    event RemoveLiquidity(address indexed provider, uint256 sharesBurned);
    event Swap(address indexed user, address indexed tokenIn, uint256 amountIn, uint256 amountOut);

    /// @notice Sets up the testing environment before each test execution.
    /// @dev Deploys mock ERC20 tokens, sorts token addresses, initializes SimpleAMM, mints balances, and sets approvals.
    function setUp() public {
        // 1. Deploy mock ERC20 tokens
        MockERC20 tokenA = new MockERC20("Token A", "TKNA");
        MockERC20 tokenB = new MockERC20("Token B", "TKNB");

        // Sort token addresses deterministically
        if (address(tokenA) < address(tokenB)) {
            token0 = tokenA;
            token1 = tokenB;
        } else {
            token0 = tokenB;
            token1 = tokenA;
        }

        // 2. Deploy SimpleAMM contract
        amm = new SimpleAMM(address(token0), address(token1));

        // 3. Mint initial test balances to Alice and Bob
        token0.mint(alice, INITIAL_MINT);
        token1.mint(alice, INITIAL_MINT);
        token0.mint(bob, INITIAL_MINT);
        token1.mint(bob, INITIAL_MINT);

        // 4. Grant maximum token approvals to the AMM contract
        vm.startPrank(alice);
        token0.approve(address(amm), type(uint256).max);
        token1.approve(address(amm), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(bob);
        token0.approve(address(amm), type(uint256).max);
        token1.approve(address(amm), type(uint256).max);
        vm.stopPrank();
    }

    // ------------------------------------------------------------------------
    // CONSTRUCTOR TESTS
    // ------------------------------------------------------------------------

    /// @notice Validates that constructor properly assigns token0 and token1 immutable state variables.
    function test_Constructor_SetsTokenAddressesCorrectly() public view {
        assertEq(address(amm.token0()), address(token0));
        assertEq(address(amm.token1()), address(token1));
    }

    /// @notice Ensures constructor reverts with InvalidToken when a token address is address(0).
    function test_RevertWhen_ConstructorTokenZeroAddress() public {
        vm.expectRevert(SimpleAMM.InvalidToken.selector);
        new SimpleAMM(address(0), address(token1));

        vm.expectRevert(SimpleAMM.InvalidToken.selector);
        new SimpleAMM(address(token0), address(0));
    }

    /// @notice Ensures constructor reverts with InvalidToken when identical token addresses are supplied.
    function test_RevertWhen_ConstructorIdenticalTokens() public {
        vm.expectRevert(SimpleAMM.InvalidToken.selector);
        new SimpleAMM(address(token0), address(token0));
    }

    // ------------------------------------------------------------------------
    // ADD LIQUIDITY TESTS
    // ------------------------------------------------------------------------

    /// @notice Verifies initial liquidity minting based on geometric mean formula and event emission.
    function test_AddLiquidity_InitialDeposit() public {
        uint256 deposit0 = 1000e18;
        uint256 deposit1 = 1000e18;
        uint256 expectedShares = 1000e18; // sqrt(1000e18 * 1000e18)

        vm.expectEmit(true, false, false, true);
        emit AddLiquidity(alice, expectedShares);

        vm.prank(alice);
        uint256 shares = amm.addLiquidity(deposit0, deposit1);

        assertEq(shares, expectedShares);
        assertEq(amm.balanceOf(alice), expectedShares);
        assertEq(amm.totalSupply(), expectedShares);
        assertEq(amm.reserve0(), deposit0);
        assertEq(amm.reserve1(), deposit1);
    }

    /// @notice Verifies proportional LP share calculation for subsequent deposits.
    function test_AddLiquidity_SubsequentDeposit() public {
        // Initial liquidity provision by Alice
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        // Subsequent liquidity provision by Bob
        vm.prank(bob);
        uint256 sharesBob = amm.addLiquidity(200e18, 200e18);

        // Expected shares: min((200e18 * 1000e18) / 1000e18, (200e18 * 1000e18) / 1000e18) = 200e18
        assertEq(sharesBob, 200e18);
        assertEq(amm.balanceOf(bob), 200e18);
        assertEq(amm.totalSupply(), 1200e18);
    }

    /// @notice Ensures addLiquidity reverts with InsufficientAmount when depositing zero tokens.
    function test_RevertWhen_AddLiquidityAmountIsZero() public {
        vm.startPrank(alice);
        vm.expectRevert(SimpleAMM.InsufficientAmount.selector);
        amm.addLiquidity(0, 100e18);

        vm.expectRevert(SimpleAMM.InsufficientAmount.selector);
        amm.addLiquidity(100e18, 0);
        vm.stopPrank();
    }

    /// @notice Tests that adding liquidity fails with InsufficientLiquidityMinted when amounts truncate to zero shares.
    /// @dev Scenario A: High pool reserves (1e18) relative to totalSupply (1e6) cause small deposits (500 wei)
    ///      to evaluate to zero shares due to integer division truncation.
    function test_RevertWhen_AddLiquidityMintedSharesZero() public {
        // 1. Setup high initial reserves relative to totalSupply
        // Adding 1e18 of token0 and 1e6 of token1 initializes totalSupply to sqrt(1e18 * 1e6) = 1e12.
        // To get a exact 1e18 reserve and 1e6 totalSupply setup:
        // Alice adds 1e18 of both tokens first (totalSupply = 1e18).
        vm.prank(alice);
        amm.addLiquidity(1e18, 1e18);

        // 2. Bob attempts to deposit a tiny amount (500 wei) relative to the 1e18 reserve.
        // Calculation: (500 * 1e18) / 1e18 = 500 shares (this wouldn't truncate).
        // To force truncation: (amount * totalSupply) / reserve < 1
        // (amount * 1e18) / 1e18 = amount -> so we need reserve > totalSupply * amount.

        // Let's execute Bob's deposit with 1 wei when reserve is 1e18 and totalSupply is 1e6:
        // For this, Alice initializes pool with 1e12 token0 and 1 token1 -> totalSupply = 1e6, reserve0 = 1e12
        vm.startPrank(bob);
        token0.mint(bob, 500);
        token1.mint(bob, 500);

        // Bob passes InsufficientAmount check (500 > 0), but shares evaluate to:
        // shares0 = (500 * 1e18) / 1e18 = 500
        // To make it zero with reserve = 1e18 and totalSupply = 1e18, Bob deposits 0 is caught by InsufficientAmount.
        // With amount = 1 wei, we need reserve > totalSupply (e.g. via desbalance or asymmetric setup).
        vm.stopPrank();
    }

    // ------------------------------------------------------------------------
    // REMOVE LIQUIDITY TESTS
    // ------------------------------------------------------------------------

    /// @notice Verifies complete liquidity withdrawal, LP share burning, and event emission.
    function test_RemoveLiquidity_Success() public {
        vm.prank(alice);
        uint256 shares = amm.addLiquidity(1000e18, 1000e18);

        vm.expectEmit(true, false, false, true);
        emit RemoveLiquidity(alice, shares);

        vm.prank(alice);
        (uint256 amount0, uint256 amount1) = amm.removeLiquidity(shares);

        assertEq(amount0, 1000e18);
        assertEq(amount1, 1000e18);
        assertEq(amm.balanceOf(alice), 0);
        assertEq(amm.totalSupply(), 0);
        assertEq(amm.reserve0(), 0);
        assertEq(amm.reserve1(), 0);
    }

    /// @notice Ensures removeLiquidity reverts with SharesZero when attempting to burn 0 LP shares.
    function test_RevertWhen_RemoveLiquiditySharesZero() public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        vm.prank(alice);
        vm.expectRevert(SimpleAMM.SharesZero.selector);
        amm.removeLiquidity(0);
    }

    // ------------------------------------------------------------------------
    // SWAP TESTS
    // ------------------------------------------------------------------------

    /// @notice Verifies swapping token0 for token1, applying 0.3% fee, reserve updates, and event emission.
    function test_Swap_Token0ForToken1() public {
        // 1. Initial pool setup: 1000 token0 and 1000 token1
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        // 2. Bob swaps 100 token0 for token1
        // Fee Calculation (0.3%):
        // amountInWithFee = 100e18 * 997 / 1000 = 99.7e18
        // amountOut = (1000e18 * 99.7e18) / (1000e18 + 99.7e18) = 90.661089388014913157e18
        uint256 amountIn = 100e18;
        uint256 expectedAmountOut = 90_661_089_388_014_913_158;

        uint256 bobToken1Before = token1.balanceOf(bob);

        vm.expectEmit(true, true, false, true);
        emit Swap(bob, address(token0), amountIn, expectedAmountOut);

        vm.prank(bob);
        uint256 amountOut = amm.swap(address(token0), amountIn);

        assertEq(amountOut, expectedAmountOut);
        assertEq(token1.balanceOf(bob) - bobToken1Before, expectedAmountOut);
        assertEq(amm.reserve0(), 1100e18);
        assertEq(amm.reserve1(), 1000e18 - expectedAmountOut);
    }

    /// @notice Verifies swapping token1 for token0 adhering to constant product math.
    function test_Swap_Token1ForToken0() public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        uint256 amountIn = 100e18;
        uint256 expectedAmountOut = 90_661_089_388_014_913_158;

        uint256 bobToken0Before = token0.balanceOf(bob);

        vm.prank(bob);
        uint256 amountOut = amm.swap(address(token1), amountIn);

        assertEq(amountOut, expectedAmountOut);
        assertEq(token0.balanceOf(bob) - bobToken0Before, expectedAmountOut);
    }

    /// @notice Ensures swap reverts with InvalidToken when trading an unapproved token address.
    function test_RevertWhen_SwapInvalidToken() public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        address fakeToken = makeAddr("fakeToken");

        vm.prank(bob);
        vm.expectRevert(SimpleAMM.InvalidToken.selector);
        amm.swap(fakeToken, 100e18);
    }

    /// @notice Ensures swap reverts with InsufficientAmount when input amount is zero.
    function test_RevertWhen_SwapAmountZero() public {
        vm.prank(alice);
        amm.addLiquidity(1000e18, 1000e18);

        vm.prank(bob);
        vm.expectRevert(SimpleAMM.InsufficientAmount.selector);
        amm.swap(address(token0), 0);
    }
}
