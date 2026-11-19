// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.29;

import { Test } from "forge-std/Test.sol";
import { ISystemContract } from "@reactive/src/interfaces/ISystemContract.sol";
import { IPayable } from "@reactive/src/interfaces/IPayable.sol";
import { IReactive } from "@reactive/src/interfaces/IReactive.sol";
import { AbstractPayer } from "@reactive/src/base/AbstractPayer.sol";
import { AbstractCallback } from "@reactive/src/base/AbstractCallback.sol";
import { StopLossReactive } from "../src/StopLossReactive.sol";
import { StopLossVault } from "../src/StopLossVault.sol";
import { IERC20 } from "../src/interfaces/IERC20.sol";
import { IUniswapV3Pool, IUniswapV3SwapCallback } from "../src/interfaces/IUniswapV3Pool.sol";

// ---------------------------------------------------------------------------
// Mocks
// ---------------------------------------------------------------------------

/// @notice Minimal mintable ERC-20 for tests.
contract MockERC20 is IERC20 {
    mapping(address => uint256) public override balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function transfer(address to, uint256 amount) external override returns (bool) {
        require(balanceOf[msg.sender] >= amount, "insufficient");
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external override returns (bool) {
        require(allowance[from][msg.sender] >= amount, "allowance");
        require(balanceOf[from] >= amount, "insufficient");
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function approve(address spender, uint256 amount) external override returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }
}

/// @notice Mock Uniswap V3 pool: sells token1 (WETH) for token0 (USDC) at a fixed
///         rate of 2000 USDC per WETH. Collects payment via the swap callback
///         first (like the real pool), then pays out USDC to the recipient.
contract MockPool is IUniswapV3Pool {
    IERC20 public weth;
    IERC20 public usdc;
    uint256 public constant RATE_USDC_PER_WETH = 2000;
    uint160 public currentSqrtPrice = 1000;

    constructor(address weth_, address usdc_) {
        weth = IERC20(weth_);
        usdc = IERC20(usdc_);
    }

    function swap(address recipient, bool zeroForOne, int256 amountSpecified, uint160, bytes calldata data)
        external
        override
        returns (int256 amount0, int256 amount1)
    {
        require(!zeroForOne, "mock: only token1 -> token0");
        require(amountSpecified > 0, "mock: exact input only");
        uint256 wethIn = uint256(amountSpecified);
        uint256 usdcOut = wethIn * RATE_USDC_PER_WETH / 1e12; // 18 dec -> 6 dec

        // Collect the WETH owed via the callback (real pool behavior).
        IUniswapV3SwapCallback(msg.sender).uniswapV3SwapCallback(-int256(usdcOut), amountSpecified, data);
        // Pay out the USDC.
        require(usdc.transfer(recipient, usdcOut), "mock USDC payout failed");
        return (-int256(usdcOut), amountSpecified);
    }

    function slot0()
        external
        view
        override
        returns (uint160, int24, uint16, uint16, uint16, uint8, bool)
    {
        return (currentSqrtPrice, 0, 0, 0, 0, 0, true);
    }

    function token0() external view override returns (address) {
        return address(usdc);
    }

    function token1() external view override returns (address) {
        return address(weth);
    }

    function fee() external pure override returns (uint24) {
        return 3000;
    }
}

/// @notice Mock system contract / callback proxy, etched onto the real addresses
///         with vm.etch in tests. Records subscriptions and callback requests and
///         serves a configurable debt() for coverDebt tests.
contract MockSystemContract {
    struct Callback {
        uint256 chainId;
        address recipient;
        uint64 gasLimit;
        bytes payload;
    }

    Callback public lastCallback;
    uint256 public callbackCount;
    uint256 public subscribeCount;
    uint256 public debtAmount;

    function subscribe(uint256, address, uint256, uint256, uint256, uint256) external {
        subscribeCount++;
    }

    function unsubscribe(uint256, address, uint256, uint256, uint256, uint256) external {
        subscribeCount--;
    }

    function requestCallbackV_1_0(ISystemContract.CallbackConfiguration_V_1_0 memory config_) external {
        lastCallback = Callback(config_.chainId, config_.recipient, config_.gasLimit, config_.payload);
        callbackCount++;
    }

    function debt(address) external view returns (uint256) {
        return debtAmount;
    }

    function setDebt(uint256 debt_) external {
        debtAmount = debt_;
    }

    receive() external payable {}
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

contract StopLossTest is Test {
    address payable constant SYSTEM = payable(0x8888888888888888888888888888888888888888);
    address payable constant PROXY = payable(0x476F44b11F5C942c58f4c8E3d0300E5710743585); // real Base Sepolia callback proxy
    address constant POOL_ADDR = 0x46880b404CD35c165EDdefF7421019F8dD25F4Ad;
    uint256 constant SWAP_TOPIC0 = 0xc42079f94a6350d7e6235f29174924f928cc2ac818eb64fed8004e115fbcca67;
    uint256 constant TRANSFER_TOPIC0 = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef;

    uint160 constant THRESHOLD = 1000;
    address user = address(0xA11CE);

    MockERC20 weth;
    MockERC20 usdc;
    MockPool pool;
    StopLossReactive reactive;
    StopLossVault vault;

    function setUp() public {
        vm.deal(address(this), 100 ether);
        vm.deal(user, 100 ether);

        // Etch the mock system contract onto the real system + proxy addresses.
        MockSystemContract mock = new MockSystemContract();
        vm.etch(SYSTEM, address(mock).code);
        vm.etch(PROXY, address(mock).code);

        weth = new MockERC20();
        usdc = new MockERC20();
        pool = new MockPool(address(weth), address(usdc));
        weth.mint(user, 10 ether);
        usdc.mint(address(pool), 1_000_000e6);

        reactive = new StopLossReactive{ value: 1 ether }();
        vault = new StopLossVault{ value: 1 ether }(
            IPayable(PROXY), address(reactive), address(pool), address(weth), address(usdc)
        );

        reactive.setVault(address(vault));
        reactive.arm(0, THRESHOLD);
    }

    // -- helpers ---------------------------------------------------------------

    function _swapLog(uint160 sqrtPriceX96_) internal pure returns (IReactive.LogRecord memory) {
        return IReactive.LogRecord({
            chainId: 84532,
            contractAddress: POOL_ADDR,
            topic0: SWAP_TOPIC0,
            topic1: uint256(uint160(address(0xBEEF))),
            topic2: uint256(uint160(address(0xBEEF))),
            topic3: 0,
            data: abi.encode(int256(0), int256(0), sqrtPriceX96_, uint128(1000), int24(0)),
            blockNumber: 1,
            opCode: 3,
            blockHash: 0,
            txHash: 0,
            logIndex: 0
        });
    }

    function _react(IReactive.LogRecord memory log_) internal {
        vm.prank(SYSTEM);
        reactive.react(log_);
    }

    function _callbackCount() internal view returns (uint256) {
        return MockSystemContract(SYSTEM).callbackCount();
    }

    function _depositAndOrder(uint256 deposit_, uint256 orderAmount_) internal returns (uint256 orderId_) {
        vm.startPrank(user);
        weth.approve(address(vault), deposit_);
        vault.depositWETH(deposit_);
        orderId_ = vault.createOrder(orderAmount_, THRESHOLD);
        vm.stopPrank();
    }

    // -- reactive: threshold logic ---------------------------------------------

    function testIsBelowStop() public view {
        // WETH falling <=> sqrtPriceX96 rising above the threshold.
        assertTrue(reactive.isBelowStop(1001, 1000), "sqrtP above threshold = price below stop");
        assertFalse(reactive.isBelowStop(1000, 1000), "equal does not trigger");
        assertFalse(reactive.isBelowStop(999, 1000), "sqrtP below threshold = price above stop");
    }

    function testThresholdAboveTriggers() public {
        vm.expectEmit(true, false, false, true, address(reactive));
        emit StopLossReactive.StopTriggered(0, THRESHOLD + 1, THRESHOLD);

        _react(_swapLog(THRESHOLD + 1));

        assertEq(_callbackCount(), 1, "callback requested");
        assertFalse(reactive.armed(), "disarmed after trigger");
        (uint256 chainId, address recipient, uint64 gasLimit, bytes memory payload) =
            MockSystemContract(SYSTEM).lastCallback();
        assertEq(chainId, 84532, "callback chain");
        assertEq(recipient, address(vault), "callback recipient");
        assertEq(gasLimit, 1_000_000, "callback gas limit");
        assertEq(
            payload,
            abi.encodeWithSignature("executeStopLoss(address,uint256)", address(0), 0),
            "callback payload (address(0) placeholder + orderId)"
        );
    }

    function testThresholdBelowDoesNotTrigger() public {
        _react(_swapLog(THRESHOLD - 1));
        assertEq(_callbackCount(), 0, "no callback while price above stop");
        assertTrue(reactive.armed(), "still armed");
    }

    function testThresholdEqualDoesNotTrigger() public {
        _react(_swapLog(THRESHOLD));
        assertEq(_callbackCount(), 0, "no callback at exactly the threshold");
        assertTrue(reactive.armed(), "still armed");
    }

    // -- reactive: non-matching logs fall through silently ----------------------

    function testReactIgnoresNonSwapLog() public {
        IReactive.LogRecord memory log_ = _swapLog(THRESHOLD + 1); // would trigger if it were a Swap
        log_.topic0 = TRANSFER_TOPIC0; // an ERC-20 Transfer, not a Swap
        _react(log_);
        assertEq(_callbackCount(), 0, "no callback for non-Swap log");
        assertTrue(reactive.armed(), "still armed");
    }

    function testReactIgnoresWrongChainContractOpcodeShortData() public {
        IReactive.LogRecord memory log_;

        log_ = _swapLog(THRESHOLD + 1); // would trigger if it matched
        log_.chainId = 1; // wrong chain
        _react(log_);

        log_ = _swapLog(THRESHOLD + 1);
        log_.contractAddress = address(0xDEAD); // wrong contract
        _react(log_);

        log_ = _swapLog(THRESHOLD + 1);
        log_.opCode = 2; // not a LOG3
        _react(log_);

        log_ = _swapLog(THRESHOLD + 1);
        log_.data = abi.encode(int256(0)); // too short to hold a Swap
        _react(log_);

        assertEq(_callbackCount(), 0, "no callback for any non-matching log");
        assertTrue(reactive.armed(), "still armed after all ignored logs");
    }

    function testReactRevertsForNonSystem() public {
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), SYSTEM));
        reactive.react(_swapLog(THRESHOLD + 1));
    }

    function testConstructorSubscribes() public view {
        assertEq(MockSystemContract(SYSTEM).subscribeCount(), 1, "subscribed once in constructor");
    }

    function testOwnerSettersAndArmDisarm() public {
        reactive.disarm();
        assertFalse(reactive.armed());
        reactive.arm(7, 555);
        assertTrue(reactive.armed());
        assertEq(reactive.armedOrderId(), 7);
        assertEq(reactive.stopThreshold(), 555);

        reactive.setThreshold(777);
        assertEq(reactive.stopThreshold(), 777);

        reactive.setVault(address(0x1234));
        assertEq(reactive.vault(), address(0x1234));

        // Non-owner cannot manage the contract.
        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(StopLossReactive.NotOwner.selector, user));
        reactive.arm(1, 1);
    }

    function testCoverDebtPaysSystem() public {
        MockSystemContract(SYSTEM).setDebt(0.1 ether);
        uint256 before = address(SYSTEM).balance;
        reactive.coverDebt();
        assertEq(address(SYSTEM).balance, before + 0.1 ether, "debt paid to system contract");
    }

    // -- vault: order lifecycle -------------------------------------------------

    function testDepositAndCreateOrder() public {
        uint256 orderId = _depositAndOrder(1 ether, 0.5 ether);
        assertEq(orderId, 0, "first order id is 0");
        assertEq(vault.balances(user), 0.5 ether, "unallocated remainder");
        (address owner, uint256 amount, uint160 threshold, bool active) = vault.orders(0);
        assertEq(owner, user);
        assertEq(amount, 0.5 ether);
        assertEq(threshold, THRESHOLD);
        assertTrue(active);
    }

    function testExecuteStopLossHappyPath() public {
        uint256 orderId = _depositAndOrder(1 ether, 0.5 ether);

        vm.expectEmit(true, true, false, true, address(vault));
        emit StopLossVault.StopLossExecuted(orderId, user, 1000e6);

        vm.prank(PROXY);
        vault.executeStopLoss(address(reactive), orderId);

        // User received the USDC from the sale: 0.5 WETH x 2000 = 1000 USDC.
        assertEq(usdc.balanceOf(user), 1000e6, "user received sale proceeds");
        // Pool collected the 0.5 WETH via the swap callback.
        assertEq(weth.balanceOf(address(pool)), 0.5 ether, "pool paid in WETH");
        // Order is closed; vault keeps the unallocated 0.5 WETH.
        (, , , bool active) = vault.orders(orderId);
        assertFalse(active, "order inactive after execution");
        assertEq(weth.balanceOf(address(vault)), 0.5 ether, "unallocated WETH remains in vault");
    }

    function testExecuteStopLossRevertsNonProxy() public {
        _depositAndOrder(1 ether, 0.5 ether);
        vm.expectRevert(abi.encodeWithSelector(AbstractPayer.NotAuthorized.selector, address(this), PROXY));
        vault.executeStopLoss(address(reactive), 0);
    }

    function testExecuteStopLossRevertsWrongReactive() public {
        _depositAndOrder(1 ether, 0.5 ether);
        address wrongReactive = address(0x1234);
        vm.prank(PROXY);
        vm.expectRevert(
            abi.encodeWithSelector(
                AbstractCallback.CallbackNotAuthorized.selector, wrongReactive, address(reactive)
            )
        );
        vault.executeStopLoss(wrongReactive, 0);
    }

    function testSwapCallbackRevertsNonPool() public {
        vm.expectRevert(abi.encodeWithSelector(StopLossVault.NotPool.selector, address(this)));
        vault.uniswapV3SwapCallback(0, 1 ether, "");
    }

    function testCancelOrderReturnsWeth() public {
        uint256 orderId = _depositAndOrder(1 ether, 0.5 ether);
        vm.prank(user);
        vault.cancelOrder(orderId);
        (, , , bool active) = vault.orders(orderId);
        assertFalse(active);
        assertEq(vault.balances(user), 1 ether, "WETH back to unallocated balance");
    }

    function testVaultCoverDebtPaysProxy() public {
        MockSystemContract(PROXY).setDebt(0.05 ether);
        uint256 before = address(PROXY).balance;
        vault.coverDebt();
        assertEq(address(PROXY).balance, before + 0.05 ether, "debt paid to callback proxy");
    }
}
