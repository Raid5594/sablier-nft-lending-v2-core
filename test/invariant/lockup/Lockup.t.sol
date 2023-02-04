// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13 <0.9.0;

import { SablierV2FlashLoan } from "src/abstracts/SablierV2FlashLoan.sol";
import { ISablierV2Lockup } from "src/interfaces/ISablierV2Lockup.sol";
import { ISablierV2LockupLinear } from "src/interfaces/ISablierV2LockupLinear.sol";
import { SablierV2LockupLinear } from "src/SablierV2LockupLinear.sol";

import { Invariant_Test } from "../Invariant.t.sol";
import { FlashLoanHandler } from "../handlers/FlashLoanHandler.t.sol";
import { LockupHandler } from "../handlers/LockupHandler.t.sol";
import { LockupHandlerStore } from "../handlers/LockupHandlerStore.t.sol";

/// @title Lockup_Invariant_Test
/// @notice Common invariant test logic needed across contracts that inherit from {SablierV2Lockup}.
abstract contract Lockup_Invariant_Test is Invariant_Test {
    /*//////////////////////////////////////////////////////////////////////////
                                   TEST CONTRACTS
    //////////////////////////////////////////////////////////////////////////*/

    FlashLoanHandler internal flashLoanHandler;
    ISablierV2Lockup internal lockup;
    LockupHandler internal lockupHandler;
    LockupHandlerStore internal lockupHandlerStore;

    /*//////////////////////////////////////////////////////////////////////////
                                  SET-UP FUNCTION
    //////////////////////////////////////////////////////////////////////////*/

    function setUp() public virtual override {
        Invariant_Test.setUp();

        // Deploy the lockup lockupHandler lockupHandlerStore.
        lockupHandlerStore = new LockupHandlerStore();
    }

    /*//////////////////////////////////////////////////////////////////////////
                                     INVARIANTS
    //////////////////////////////////////////////////////////////////////////*/

    // solhint-disable max-line-length
    function invariant_ContractBalance() external {
        uint256 contractBalance = DEFAULT_ASSET.balanceOf(address(lockup));
        uint256 protocolRevenues = lockup.getProtocolRevenues(DEFAULT_ASSET);
        uint256 returnedAmountsSum = lockupHandlerStore.returnedAmountsSum();

        uint256 lastStreamId = lockupHandlerStore.lastStreamId();
        uint256 depositAmountsSum;
        uint256 withdrawnAmountsSum;
        for (uint256 i = 0; i < lastStreamId; ) {
            uint256 streamId = lockupHandlerStore.streamIds(i);
            depositAmountsSum += uint256(lockup.getDepositAmount(streamId));
            withdrawnAmountsSum += uint256(lockup.getWithdrawnAmount(streamId));
            unchecked {
                i += 1;
            }
        }

        assertGte(
            contractBalance,
            depositAmountsSum + protocolRevenues - returnedAmountsSum - withdrawnAmountsSum,
            unicode"Invariant violated: contract balances < Σ deposit amounts + protocol revenues - Σ returned amounts - Σ withdrawn amounts"
        );
    }

    function invariant_DepositAmountGteStreamedAmount() external {
        uint256 lastStreamId = lockupHandlerStore.lastStreamId();
        for (uint256 i = 0; i < lastStreamId; ) {
            uint256 streamId = lockupHandlerStore.streamIds(i);
            assertGte(
                lockup.getDepositAmount(streamId),
                lockup.streamedAmountOf(streamId),
                "Invariant violated: deposit amount < streamed amount"
            );
            unchecked {
                i += 1;
            }
        }
    }

    function invariant_DepositAmountGteWithdrawableAmount() external {
        uint256 lastStreamId = lockupHandlerStore.lastStreamId();
        for (uint256 i = 0; i < lastStreamId; ) {
            uint256 streamId = lockupHandlerStore.streamIds(i);
            assertGte(
                lockup.getDepositAmount(streamId),
                lockup.withdrawableAmountOf(streamId),
                "Invariant violated: deposit amount < withdrawable amount"
            );
            unchecked {
                i += 1;
            }
        }
    }

    function invariant_DepositAmountGteWithdrawnAmount() external {
        uint256 lastStreamId = lockupHandlerStore.lastStreamId();
        for (uint256 i = 0; i < lastStreamId; ) {
            uint256 streamId = lockupHandlerStore.streamIds(i);
            assertGte(
                lockup.getDepositAmount(streamId),
                lockup.getWithdrawnAmount(streamId),
                "Invariant violated: deposit amount < withdrawn amount"
            );
            unchecked {
                i += 1;
            }
        }
    }

    function invariant_EndTimeGteStartTime() external {
        uint256 lastStreamId = lockupHandlerStore.lastStreamId();
        for (uint256 i = 0; i < lastStreamId; ) {
            uint256 streamId = lockupHandlerStore.streamIds(i);
            assertGte(
                lockup.getEndTime(streamId),
                lockup.getStartTime(streamId),
                "Invariant violated: end time < start time"
            );
            unchecked {
                i += 1;
            }
        }
    }

    function invariant_NextStreamIdIncrement() external {
        uint256 lastStreamId = lockupHandlerStore.lastStreamId();
        for (uint256 i = 1; i < lastStreamId; ) {
            uint256 nextStreamId = lockup.nextStreamId();
            assertEq(nextStreamId, lastStreamId + 1, "Invariant violated: nonce did not increment");
            unchecked {
                i += 1;
            }
        }
    }

    function invariant_StreamedAmountGteWithdrawableAmount() external {
        uint256 lastStreamId = lockupHandlerStore.lastStreamId();
        for (uint256 i = 0; i < lastStreamId; ) {
            uint256 streamId = lockupHandlerStore.streamIds(i);
            assertGte(
                lockup.streamedAmountOf(streamId),
                lockup.withdrawableAmountOf(streamId),
                "Invariant violated: streamed amount < withdrawable amount"
            );
            unchecked {
                i += 1;
            }
        }
    }

    function invariant_StreamedAmountGteWithdrawnAmount() external {
        uint256 lastStreamId = lockupHandlerStore.lastStreamId();
        for (uint256 i = 0; i < lastStreamId; ) {
            uint256 streamId = lockupHandlerStore.streamIds(i);
            assertGte(
                lockup.streamedAmountOf(streamId),
                lockup.getWithdrawnAmount(streamId),
                "Invariant violated: streamed amount < withdrawn amount"
            );
            unchecked {
                i += 1;
            }
        }
    }
}
