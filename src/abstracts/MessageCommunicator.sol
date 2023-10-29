// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import "./Wormholebasecontracts.sol";

abstract contract Communicator is IWormholeReceiver {

    event TaskReceived(string task, uint16 sourceChain, address sender);

    uint16 targetChain;
    address targetContract;

    address deployer;

    mapping(bytes32 => bool) seenDeliveryVaaHashes;

    IWormholeRelayer wormholeRelayer;


    constructor(){
        deployer = msg.sender;
    }

    function init2(address target, address relayer, uint16 targetChainID) external {
        require(msg.sender == deployer,"Not Deployer");
        require(target != address(0) && relayer != address(0),"Null Addresses");
        require(targetChainID != 0,"Null Target Chain ID");
        targetChain = targetChainID;
        targetContract = target;
        wormholeRelayer = IWormholeRelayer(relayer);
    }

    
    function receiveWormholeMessages(
        bytes memory payload,
        bytes[] memory, // additionalVaas
        bytes32 sourceAddress, // address that called 'sendPayloadToEvm' (HelloWormhole contract address)
        uint16 sourceChain,
        bytes32 deliveryHash // this can be stored in a mapping deliveryHash => bool to prevent duplicate deliveries
    ) public payable override {
        require(msg.sender == address(wormholeRelayer), "Only relayer allowed");

        // Ensure no duplicate deliveries
        require(!seenDeliveryVaaHashes[deliveryHash], "Message already processed");
        seenDeliveryVaaHashes[deliveryHash] = true;

        // Parse the payload and do the corresponding actions!
        (string memory taskName, address effectedAddress, address sender) = abi.decode(payload, (string, address, address));
        emit TaskReceived(taskName, sourceChain, sender);

        _performTask(taskName,effectedAddress);
    }

    function _performTask(string memory task, address effectedAddress) internal virtual {}

    function Send(
        string memory message,
        address effectedAddress
    ) public payable {
        // Get a quote for the cost of gas for delivery
        (uint256 cost, ) = wormholeRelayer.quoteEVMDeliveryPrice(
            targetChain,
            0,
            500000//500k
        );

        //Check that the value sent is greater than or equal to the cost
        require(address(this).balance >= cost,"ERR:WC");

        bytes memory payload = abi.encode(message,effectedAddress,address(this));

        // Send the message
        wormholeRelayer.sendPayloadToEvm{value: cost}(
            targetChain,
            targetContract,
            payload,
            0, 
            500000 //500k
        );
    }
}