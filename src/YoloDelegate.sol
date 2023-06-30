// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// import {mulDiv} from '@prb/math/src/Common.sol';
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IJBDirectory} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBDirectory.sol";
import {IJBFundingCycleDataSource} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBFundingCycleDataSource.sol";
import {IJBPayDelegate} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPayDelegate.sol";
import {IJBPaymentTerminal} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBPaymentTerminal.sol";
import {IJBRedemptionDelegate} from "@jbx-protocol/juice-contracts-v3/contracts/interfaces/IJBRedemptionDelegate.sol";
import {JBPayParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayParamsData.sol";
import {JBDidPayData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidPayData.sol";
import {JBTokens} from "@jbx-protocol/juice-contracts-v3/contracts/libraries/JBTokens.sol";
import {JBDidRedeemData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBDidRedeemData.sol";
import {JBRedeemParamsData} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedeemParamsData.sol";
import {JBPayDelegateAllocation} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBPayDelegateAllocation.sol";
import {JBRedemptionDelegateAllocation} from "@jbx-protocol/juice-contracts-v3/contracts/structs/JBRedemptionDelegateAllocation.sol";

/// @notice A contract that is a Data Source, a Pay Delegate, and a Redemption Delegate.
/// @dev This example implementation confines payments to an allow list.
contract YoloDelegate is IJBFundingCycleDataSource, IJBPayDelegate {
    error INVALID_PAYMENT_EVENT();

    /// @notice The Juicebox project ID this contract's functionality applies to.
    uint256 public projectId;

    /// @notice The Juicebox Project IDs that are candidates for receiving the payment.
    uint256[] public candidateProjectIds;

    /// @notice The directory of terminals and controllers for projects.
    IJBDirectory public directory;

    /// @notice This function gets called when the project receives a payment.
    /// @dev Part of IJBFundingCycleDataSource.
    /// @dev This implementation just sets this contract up to receive a `didPay` call.
    /// @param _data The Juicebox standard project payment data. See https://docs.juicebox.money/dev/api/data-structures/jbpayparamsdata/.
    /// @return weight The weight that project tokens should get minted relative to. This is useful for optionally customizing how many tokens are issued per payment.
    /// @return memo A memo to be forwarded to the event. Useful for describing any new actions that are being taken.
    /// @return delegateAllocations Amount to be sent to delegates instead of adding to local balance. Useful for auto-routing funds from a treasury as payment come in.
    function payParams(
        JBPayParamsData calldata _data
    )
        external
        view
        virtual
        override
        returns (
            uint256 weight,
            string memory memo,
            JBPayDelegateAllocation[] memory delegateAllocations
        )
    {
        // Forward the default weight received from the protocol.
        weight = _data.weight;
        // Forward the default memo received from the payer.
        memo = _data.memo;
        // Add `this` contract as a Pay Delegate so that it receives a `didPay` call.
        // Send all funds to the delegate (keep no funds in the treasury).
        delegateAllocations = new JBPayDelegateAllocation[](1);
        delegateAllocations[0] = JBPayDelegateAllocation(
            this,
            _data.amount.value
        );
    }

    function redeemParams(
        JBRedeemParamsData calldata _data
    )
        external
        view
        virtual
        override
        returns (
            uint256 reclaimAmount,
            string memory memo,
            JBRedemptionDelegateAllocation[] memory delegateAllocations
        )
    {}

    /// @notice Indicates if this contract adheres to the specified interface.
    /// @dev See {IERC165-supportsInterface}.
    /// @param _interfaceId The ID of the interface to check for adherence to.
    /// @return A flag indicating if the provided interface ID is supported.
    function supportsInterface(
        bytes4 _interfaceId
    ) public view virtual override returns (bool) {
        return
            _interfaceId == type(IJBFundingCycleDataSource).interfaceId ||
            _interfaceId == type(IJBPayDelegate).interfaceId;
    }

    constructor() {}

    /// @notice Initializes the clone contract with project details and a directory from which ecosystem payment terminals and controller can be found.
    /// @param _projectId The ID of the project this contract's functionality applies to.
    /// @param _directory The directory of terminals and controllers for projects.
    function initialize(uint256 _projectId, IJBDirectory _directory) external {
        // Stop re-initialization.
        if (projectId != 0) revert();

        // Store the basics.
        projectId = _projectId;
        directory = _directory;
    }

    // Add a number to the array
    function addCandidateProjectId(uint256 _projectId) external {
        candidateProjectIds.push(_projectId);
    }

    /// @notice Received hook from the payment terminal after a payment.
    /// @dev Reverts if the calling contract is not one of the project's terminals.
    /// @param _data Standard Juicebox project payment data. See https://docs.juicebox.money/dev/api/data-structures/jbdidpaydata/.
    function didPay(
        JBDidPayData calldata _data
    ) external payable virtual override {
        // Make sure the caller is a terminal of the project, and that the call is being made on behalf of an interaction with the correct project.
        if (
            !directory.isTerminalOf(
                projectId,
                IJBPaymentTerminal(msg.sender)
            ) || _data.projectId != projectId
        ) revert INVALID_PAYMENT_EVENT();

        uint256 newProjectId = _getRandomCandidateProjectId();
        IJBPaymentTerminal newTerminal = directory.primaryTerminalOf(
            newProjectId,
            JBTokens.ETH
        );
        newTerminal.pay{value: msg.value}(
            newProjectId,
            _data.amount.value,
            _data.amount.token,
            _data.beneficiary,
            0,
            _data.preferClaimedTokens,
            _data.memo,
            _data.metadata
        );

        _data;
    }

    // Internal functions //

    // Get a random number from the array
    function _getRandomCandidateProjectId() internal view returns (uint256) {
        require(candidateProjectIds.length > 0, "No candidate project IDs");
        uint256 randomProjectIdIdx = uint256(
            keccak256(abi.encodePacked(block.timestamp, block.basefee))
        ) % candidateProjectIds.length;
        return candidateProjectIds[randomProjectIdIdx];
    }
}
