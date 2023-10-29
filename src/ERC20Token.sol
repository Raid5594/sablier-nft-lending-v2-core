// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MyToken is ERC20 {

    address loanContract;

    constructor(address loanContract_) ERC20("My Token", "MTK") {
        loanContract = loanContract_;
    }

    function mintByLoan(address to) external {
        require(msg.sender == loanContract,"ERR: Not allowed");
        _mint(to,1);
    }
}
