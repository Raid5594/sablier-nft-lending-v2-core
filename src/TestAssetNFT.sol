// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract TestAssetNFT is ERC721 {
    using Counters for Counters.Counter;
    using Strings for uint256;
    Counters.Counter private _tokenIds;

    constructor() ERC721("TestAssetNFT", "TAN") {
        _mint(msg.sender,20);
    }

    function mintNFT(address recipient) public returns (uint256) {
        _tokenIds.increment();

        uint256 newItemId = _tokenIds.current();
        _mint(recipient, newItemId);

        return newItemId;
    }

    function tokenURI(uint256 tokenId) public override pure returns(string memory) {
        return string(abi.encodePacked("ipfs://QmeSjSinHpPnmXmspMjwiXyN6zS4E9zccariGR3jxcaWtq/", tokenId.toString()));
    }
}
