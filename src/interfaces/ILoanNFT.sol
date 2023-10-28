// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;
interface ILoanNFT{
    function getBorrowerDetails(address) external view returns (ILoanNFT.BorrowerDetails memory);
    function getCurrentDefaults(address borrower) external view returns (uint256);

    //This object defines the details for a given borrower
    struct BorrowerDetails {
        address borrower;
        uint256 successfulLoans;
        uint256 closedDefaults;
        uint256 activeLoans;
        uint256 totalLoans;
        uint256[] loanTokenIds;
    }
}