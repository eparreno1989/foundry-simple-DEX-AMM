// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {Test} from "forge-std/Test.sol";
import {SimpleAMM} from "../src/SimpleAMM.sol";
import {MockERC20} from "./Mocks/MockERC20.sol";
import {SimpleAMMHandler} from "./Handlers/SimpleAMMHandler.sol";

/// @title Invariant and Integration Tests for SimpleAMM
/// @author Erick
/// @notice Suite containing stateful invariant checks and end-to-end integration flow tests for SimpleAMM.
/// @dev Implements stateful fuzzing using Forge's target contract pattern (`SimpleAMMHandler`) to validate protocol rules across arbitrary action sequences.
contract SimpleAMMInvariantTest is Test {
    /// @notice Target SimpleAMM pool instance under test.
    SimpleAMM public amm;

    /// @notice Handler contract routing fuzzed calls to the AMM pool.
    SimpleAMMHandler public handler;

    /// @notice Mock ERC20 token 0 (lexicographically lower address).
    MockERC20 public token0;

    /// @notice Mock ERC20 token 1 (lexicographically higher address).
    MockERC20 public token1;

    /// @notice Sets up contract instances and configures the target handler for stateful fuzz testing.
    /// @dev Deploys mock tokens, sorts addresses deterministically, instantiates the AMM and Handler,
    ///      and registers the Handler as the sole target for Forge invariant calls.
    function setUp() public {
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

        amm = new SimpleAMM(address(token0), address(token1));
        handler = new SimpleAMMHandler(amm, token0, token1);

        // Instruct Foundry fuzzer to route stateful interactions through the Handler
        targetContract(address(handler));
    }

    // ------------------------------------------------------------------------
    // INVARIANT TESTS (STATEFUL FUZZING)
    // ------------------------------------------------------------------------

    /// @notice Invariant 1: Physical ERC20 token balances in the AMM contract must always be >= recorded reserves.
    /// @dev Protects against insolvency caused by unauthorized withdrawals or improper reserve accounting.
    function invariant_solvencyReservesMatchBalances() public view {
        assertGe(
            token0.balanceOf(address(amm)),
            amm.reserve0(),
            "Solvency violation: Token0 balance lower than reserve0"
        );
        assertGe(
            token1.balanceOf(address(amm)),
            amm.reserve1(),
            "Solvency violation: Token1 balance lower than reserve1"
        );
    }

    /// @notice Invariant 2: Constant product k (reserve0 * reserve1) must never decrease across swap operations.
    /// @dev Tracks ghost state `kLast` inside the Handler; due to the 0.3% protocol swap fee, k must strictly grow or remain equal.
    function invariant_constantProductIncreasesOrStaysSame() public view {
        uint256 kLast = handler.kLast();

        if (kLast > 0) {
            uint256 kCurrent = amm.reserve0() * amm.reserve1();
            assertGe(
                kCurrent,
                kLast,
                "Invariant violation: Constant product k decreased after swap"
            );
        }
    }

    /// @notice Invariant 3: Total LP share supply equal to zero strictly requires reserves to be zero.
    /// @dev Verifies that liquidity cannot remain trapped inside the pool when all LP tokens are burned.
    function invariant_zeroSupplyMeansZeroReserves() public view {
        if (amm.totalSupply() == 0) {
            assertEq(amm.reserve0(), 0, "Non-zero reserve0 with zero LP supply");
            assertEq(amm.reserve1(), 0, "Non-zero reserve1 with zero LP supply");
        }
    }
}