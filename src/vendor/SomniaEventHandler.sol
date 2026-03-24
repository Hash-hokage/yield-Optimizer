// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Somnia
pragma solidity ^0.8.20;

import {ISomniaEventHandler} from "@somnia-chain/reactivity-contracts/contracts/interfaces/ISomniaEventHandler.sol";
import {
    SomniaExtensions
} from "@somnia-chain/reactivity-contracts/contracts/interfaces/ISomniaReactivityPrecompile.sol";
import {IERC165} from "@somnia-chain/reactivity-contracts/contracts/interfaces/IERC165.sol";

abstract contract SomniaEventHandler is IERC165, ISomniaEventHandler {
    error OnlyReactivityPrecompile();

    function onEvent(address emitter, bytes32[] calldata eventTopics, bytes calldata data) external override {
        require(msg.sender == SomniaExtensions.SOMNIA_REACTIVITY_PRECOMPILE_ADDRESS, OnlyReactivityPrecompile());
        _onEvent(emitter, eventTopics, data);
    }

    function _onEvent(address emitter, bytes32[] calldata eventTopics, bytes calldata data) internal virtual;

    function supportsInterface(bytes4 interfaceId) external pure override returns (bool) {
        return type(IERC165).interfaceId == interfaceId || type(ISomniaEventHandler).interfaceId == interfaceId;
    }
}
