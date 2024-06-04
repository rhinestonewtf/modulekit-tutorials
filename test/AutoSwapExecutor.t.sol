// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import { Test } from "forge-std/Test.sol";
import {
    RhinestoneModuleKit,
    ModuleKitHelpers,
    ModuleKitUserOp,
    AccountInstance,
    UserOpData
} from "modulekit/ModuleKit.sol";
import { MODULE_TYPE_EXECUTOR } from "modulekit/external/ERC7579.sol";
import { AutoSwapExecutor } from "src/AutoSwapExecutor.sol";
import { IERC20 } from "forge-std/interfaces/IERC20.sol";

address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
address constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;

contract AutoSwapExecutorTest is RhinestoneModuleKit, Test {
    using ModuleKitHelpers for *;
    using ModuleKitUserOp for *;

    // Account and modules
    AccountInstance internal instance;
    AutoSwapExecutor internal executor;

    // Tokens to swap betweem
    IERC20 usdc = IERC20(USDC);
    IERC20 weth = IERC20(WETH);

    // Foundry fork id for fork testing
    uint256 mainnetFork;

    // Executor job id
    uint256 jobId;

    function setUp() public {
        // Create the fork
        string memory mainnetUrl = vm.envString("MAINNET_RPC_URL");
        mainnetFork = vm.createFork(mainnetUrl);
        vm.selectFork(mainnetFork);
        vm.rollFork(19_274_877);

        // Initialize the RhinestoneModuleKit
        init();

        // Create the executor
        executor = new AutoSwapExecutor();
        vm.label(address(executor), "AutoSwapExecutor");

        // Label tokens
        vm.label(WETH, "weth");
        vm.label(USDC, "usdc");

        // Create the account and deal tokens
        instance = makeAccountInstance("Account");
        vm.deal(instance.account, 10 ether);
        deal(address(usdc), instance.account, 10 ether);

        // Create the execution data to initialize the executor
        bytes memory executionData = abi.encode(address(usdc), address(weth), 1 ether, uint160(0));

        // Install the executor
        instance.installModule({
            moduleTypeId: MODULE_TYPE_EXECUTOR,
            module: address(executor),
            data: abi.encode(uint48(1 days), uint16(10), uint48(0), executionData)
        });
    }

    function testExec() public {
        // Get the current balance of the target
        uint256 prevBalance = weth.balanceOf(instance.account);

        // Execute the call
        // EntryPoint -> Account -> Executor -> Account -> Swap
        UserOpData memory userOpData = instance.getExecOps({
            target: address(executor),
            value: 0,
            callData: abi.encodeWithSelector(AutoSwapExecutor.executeOrder.selector, jobId),
            txValidator: address(instance.defaultValidator)
        });

        // Increase the default gas limit to ensure there is enough gas for the swap
        userOpData.userOp.accountGasLimits = bytes32(abi.encodePacked(uint128(2e6), uint128(10e6)));

        // Execute the userOp
        userOpData.execUserOps();

        // Check if the balance of the target has increased in the target token
        assertGt(weth.balanceOf(instance.account), prevBalance);
    }

    function testExecMultiple() public {
        // Execute the swap
        testExec();

        // Skip 1 day to the next execution time
        vm.warp(1 days);

        // Execute the swap again
        testExec();
    }
}
