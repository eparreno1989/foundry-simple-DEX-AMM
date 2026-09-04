// SPDX-License-Identifier: MIT
pragma solidity ^0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/// @title Simple Constant Product Automated Market Maker (AMM)
/// @notice Implements a basic Uniswap V2-style AMM with a 0.3% swap fee and LP token minting.
/// @dev Uses OpenZeppelin's SafeERC20 for safe token transfers and standard x * y = k constant product math.
contract SimpleAMM {
    using SafeERC20 for IERC20;

    // ------------------------------------------------------------------------
    // STATE VARIABLES
    // ------------------------------------------------------------------------

    /// @notice The first token of the pool pair.
    IERC20 public immutable token0;

    /// @notice The second token of the pool pair.
    IERC20 public immutable token1;

    /// @notice Internal reserve balance of token0.
    uint256 public reserve0;

    /// @notice Internal reserve balance of token1.
    uint256 public reserve1;

    /// @notice Total supply of liquidity provider (LP) shares issued.
    uint256 public totalSupply;

    /// @notice Mapping tracking the LP share balance of each account.
    mapping(address account => uint256) public balanceOf;

    // ------------------------------------------------------------------------
    // EVENTS
    // ------------------------------------------------------------------------

    /// @notice Emitted when liquidity is added to the pool.
    /// @param provider The address of the account providing liquidity.
    /// @param sharesMinted The number of LP tokens minted.
    event AddLiquidity(address indexed provider, uint256 sharesMinted);

    /// @notice Emitted when liquidity is removed from the pool.
    /// @param provider The address of the account burning LP tokens.
    /// @param sharesBurned The number of LP tokens burned.
    event RemoveLiquidity(address indexed provider, uint256 sharesBurned);

    /// @notice Emitted when a token swap occurs.
    /// @param user The address of the trader executing the swap.
    /// @param tokenIn The address of the token deposited into the pool.
    /// @param amountIn The amount of tokenIn deposited.
    /// @param amountOut The amount of the destination token returned to the user.
    event Swap(
        address indexed user,
        address indexed tokenIn,
        uint256 amountIn,
        uint256 amountOut
    );

    // ------------------------------------------------------------------------
    // CUSTOM ERRORS
    // ------------------------------------------------------------------------

    /// @notice Thrown when zero LP shares are minted during liquidity provisioning.
    error InsufficientLiquidityMinted();

    /// @notice Thrown when input token amounts or liquidity share requests are zero.
    error InsufficientAmount();

    /// @notice Thrown when an invalid token address is provided or pair addresses are identical.
    error InvalidToken();

    /// @notice Thrown when attempting to burn zero liquidity shares.
    error SharesZero();

    // ------------------------------------------------------------------------
    // CONSTRUCTOR
    // ------------------------------------------------------------------------

    /// @notice Initializes the AMM pair with two ERC20 token addresses.
    /// @param _token0 Address of the first ERC20 token.
    /// @param _token1 Address of the second ERC20 token.
    /// @dev Reverts with `InvalidToken` if either address is zero or if both addresses are equal.
    constructor(address _token0, address _token1) {
        if (_token0 == address(0) || _token1 == address(0)) revert InvalidToken();
        if (_token0 == _token1) revert InvalidToken();

        token0 = IERC20(_token0);
        token1 = IERC20(_token1);
    }

    // ------------------------------------------------------------------------
    // INTERNAL HELPER FUNCTIONS
    // ------------------------------------------------------------------------

    /// @dev Internal function to mint LP shares to a specific account.
    /// @param _to Receiver address of the LP shares.
    /// @param _amount Quantity of LP shares to mint.
    function _mint(address _to, uint256 _amount) private {
        balanceOf[_to] += _amount;
        totalSupply += _amount;
    }

    /// @dev Internal function to burn LP shares from a specific account.
    /// @param _from Address holding the LP shares to burn.
    /// @param _amount Quantity of LP shares to burn.
    function _burn(address _from, uint256 _amount) private {
        balanceOf[_from] -= _amount;
        totalSupply -= _amount;
    }

    /// @dev Internal function to update state reserves.
    /// @param _reserve0 New reserve amount for token0.
    /// @param _reserve1 New reserve amount for token1.
    function _update(uint256 _reserve0, uint256 _reserve1) private {
        reserve0 = _reserve0;
        reserve1 = _reserve1;
    }

    /// @dev Computes the floor square root of a given non-negative integer using Babylonian method.
    /// @param y The value for which to calculate the square root.
    /// @return z The integer square root result.
    function _sqrt(uint256 y) private pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    /// @dev Returns the smaller of two unsigned integers.
    /// @param x The first integer.
    /// @param y The second integer.
    /// @return The smaller integer of the two inputs.
    function _min(uint256 x, uint256 y) private pure returns (uint256) {
        return x < y ? x : y;
    }

    // ------------------------------------------------------------------------
    // CORE / EXTERNAL FUNCTIONS
    // ------------------------------------------------------------------------

    /// @notice Allows users to add liquidity by depositing both token0 and token1 into the pool.
    /// @dev Mints LP tokens based on geometric mean for initial deposit, or proportional ratio for subsequent deposits.
    /// @param _amount0 Amount of token0 to deposit.
    /// @param _amount1 Amount of token1 to deposit.
    /// @return shares The amount of LP tokens minted to the caller.
    function addLiquidity(uint256 _amount0, uint256 _amount1) external returns (uint256 shares) {
        if (_amount0 == 0 || _amount1 == 0) revert InsufficientAmount();

        token0.safeTransferFrom(msg.sender, address(this), _amount0);
        token1.safeTransferFrom(msg.sender, address(this), _amount1);

        if (totalSupply == 0) {
            shares = _sqrt(_amount0 * _amount1);
        } else {
            shares = _min(
                (_amount0 * totalSupply) / reserve0,
                (_amount1 * totalSupply) / reserve1
            );
        }

        if (shares == 0) revert InsufficientLiquidityMinted();

        _mint(msg.sender, shares);
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));

        emit AddLiquidity(msg.sender, shares);
    }

    /// @notice Allows users to remove liquidity by burning LP tokens to receive proportional pool assets.
    /// @param _shares Amount of LP tokens to burn.
    /// @return amount0 The amount of token0 returned to the caller.
    /// @return amount1 The amount of token1 returned to the caller.
    function removeLiquidity(uint256 _shares) external returns (uint256 amount0, uint256 amount1) {
        if (_shares == 0) revert SharesZero();

        amount0 = (_shares * reserve0) / totalSupply;
        amount1 = (_shares * reserve1) / totalSupply;

        if (amount0 == 0 || amount1 == 0) revert InsufficientAmount();

        _burn(msg.sender, _shares);
        _update(reserve0 - amount0, reserve1 - amount1);

        token0.safeTransfer(msg.sender, amount0);
        token1.safeTransfer(msg.sender, amount1);

        emit RemoveLiquidity(msg.sender, _shares);
    }

    /// @notice Swaps a specified amount of one pool token for the other, deducting a 0.3% fee.
    /// @dev Calculates output using constant product formula: (x + dx) * (y - dy) = k.
    /// @param _tokenIn Address of the token being transferred into the pool by the caller.
    /// @param _amountIn Amount of tokenIn to swap.
    /// @return amountOut The output amount of the output token sent to the caller.
    function swap(address _tokenIn, uint256 _amountIn) external returns (uint256 amountOut) {
        if (_tokenIn != address(token0) && _tokenIn != address(token1)) revert InvalidToken();
        if (_amountIn == 0) revert InsufficientAmount();

        bool isToken0 = _tokenIn == address(token0);
        (
            IERC20 tokenIn,
            IERC20 tokenOut,
            uint256 reserveIn,
            uint256 reserveOut  
        ) = isToken0
            ? (token0, token1, reserve0, reserve1)
            : (token1, token0, reserve1, reserve0);

        // 1. Transfer input token from user wallet to the contract
        tokenIn.safeTransferFrom(msg.sender, address(this), _amountIn);

        // 2. Apply 0.3% swap fee (Multiply by 997 / 1000)
        uint256 amountInWithFee = (_amountIn * 997) / 1000;

        // 3. Compute output amount enforcing constant product invariant (x * y = k)
        // dx * y / (x + dx)
        amountOut = (reserveOut * amountInWithFee) / (reserveIn + amountInWithFee);

        // 4. Transfer output tokens to the user
        tokenOut.safeTransfer(msg.sender, amountOut);

        // 5. Update internal pool reserves
        _update(token0.balanceOf(address(this)), token1.balanceOf(address(this)));

        emit Swap(msg.sender, _tokenIn, _amountIn, amountOut);
    }
}