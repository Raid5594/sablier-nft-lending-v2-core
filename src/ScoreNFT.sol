// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./interfaces/ILoanNFT.sol";

//This contract is used to keep track of a users entire score
//A user must mint a score NFT before being able to take a loan out
contract ScoreNFT is ERC721Enumerable {

    //This is using the functions within the counters library for a counter within in the contract
    using Counters for Counters.Counter;

    //This is a decleration that we will be using the Counter
    //struct within the Counters library as the variable type for the private variable _tokenIds
    Counters.Counter private _tokenIds;

    //This is an instance of the ILoanNFT interface
    ILoanNFT private loanNFTContract;

    //This will store the highest credit score & is claimable when your credit score is higher than the current highest
    uint256 public highestCreditScore = 1; // Initialized to 1 to avoid division by zero

    //This will store the address of the highest scoring credit score scorer
    address public highestScorer;

    //This constructor will only be called on the deployment of this contract
    //The ERC721 constructor will be created
    constructor(address _loanNFTAddress) ERC721("ScoreNFT", "SN") {
        
        //Check that the given address is not null
        require(_loanNFTAddress != address(0),"This address can not be null");

        //Build & Set the loan NFT interface in storage
        loanNFTContract = ILoanNFT(_loanNFTAddress);
    }

    //This function will be called a user that is looking to borrow NFTs
    function mintNFT() external payable {

        //Check that the user has sent exactly 0.2 ETH
        require(msg.value == 0.2 ether, "Minting a ScoreNFT requires 0.2 ETH");

        require(balanceOf(msg.sender) == 0, "The caller has already minted a token");

        //Mint a score NFT
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(msg.sender, newItemId);
    
    }

    //This function is used for calculating the credit score of a borrower
    function calculateScore(address borrower) public view returns (uint256) {

        //Retrieve the information from the Loan NFT contract
        ILoanNFT.BorrowerDetails memory details = loanNFTContract.getBorrowerDetails(borrower);
        uint256 successfulLoans = details.successfulLoans;
        uint256 currentDefaults = loanNFTContract.getCurrentDefaults(borrower);
        uint256 closedDefaults = details.closedDefaults;
        uint256 activeLoans = details.activeLoans;
        uint256 totalLoans = details.totalLoans;

        //If the scores caused by the defaults are greater than the number of successful loans the return a score of 0
        if (currentDefaults * 50 + closedDefaults * 200 >= successfulLoans) {
            return 0;
        } else {
            //Otherwise perform this calculation

            //Successful loans = 1 point
            //Current Default = - 50 points
            //Closed Default = - 200 points

            //Calculate the subtotalScore as
            //successfulLoan score(The number of successful loans)
            //minus the current default score minus the closedDefault score
            uint256 subtotalScore = successfulLoans - (currentDefaults * 50) - (closedDefaults * 200);

            //The rugpullRiskPercentage is a percentage score that will take into 
            //account the number of active laons a user has in comparison to the total number of loans taken out 
            uint256 rugpullRiskPercentage = (activeLoans * 100) / totalLoans;

            //NegariveRiskScore is calculated as the rugpullRiskPercentage of the subtotalScore 
            uint256 negativeRiskScore = (subtotalScore * rugpullRiskPercentage) / 100;

            //The total Score is the subtotalScore minus the negativeRiskScore
            uint256 totalScore = subtotalScore - negativeRiskScore;

            //The actual credit score is calculated between 0 & 1000
            //The total Score multiplied by 1000 then divided by the highestCreditScore
            return (totalScore * 1000) / highestCreditScore;
        }
    }

    //This function can be called by any borrower
    function claimHighestScore() external {

        //This will calculate the current score of the highest scorer as 
        //this may have dropped by the last time that highest score was claimed
        uint256 currentHighScore = calculateScore(highestScorer);

        //This will calculate the current score of the caller
        uint256 userScore = calculateScore(msg.sender);

        //Check that the callers score is higher than the current highest scorers score
        require(userScore > currentHighScore, "Your score is not higher than the current highest score");

        //Set the highest scorer details
        highestCreditScore = userScore;
        highestScorer = msg.sender;
    }

    // Make the NFT soulbound (non-transferable)
    function _beforeTokenTransfer(
      address from, 
      address to, 
      uint256 firstTokenId
      // uint256 batchSize
      ) internal virtual {
        super._beforeTokenTransfer(from, to, firstTokenId,1);
        require(from == address(0) || to == address(0), "ScoreNFT: Transfers are disabled.");
    }
}
