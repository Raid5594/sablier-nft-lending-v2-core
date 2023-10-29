// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity >=0.8.19;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "@openzeppelin/contracts/token/ERC721/utils/ERC721Holder.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/Base64.sol";
import "./interfaces/ILoanNFT.sol";
import { ISablierV2LockupLinear } from "./interfaces/ISablierV2LockupLinear.sol";
import { IWNATIVE } from "./interfaces/IWNATIVE.SOL";
import { Broker, LockupLinear } from "./types/DataTypes.sol";
import { ud60x18 } from "./types/Math.sol";
import { IERC20 } from "./types/Tokens.sol";
import { IToken } from "./interfaces/IToken.sol";
import { Communicator } from "./abstracts/MessageCommunicator.sol";

//This contract is to mint NFTs that represent the status of a NFT loan
//This contract shall facilitate the utility of laoning NFTs
contract LoanNFT is ERC721Enumerable, ERC721Holder, Communicator {

    event NFTOfferedForLoan(address indexed minter, uint256 indexed tokenID, address indexed loaner, uint256 time);
    event NFTRetrieved(address indexed minter, uint256 indexed tokenID, address indexed loaner);
    event BorrowRequest(address indexed minter, uint256 indexed tokenID, address indexed borrower);
    event LoanApproved(
      address indexed minter, 
      uint256 indexed tokenID, 
      address indexed borrower, 
      uint256 fee, 
      uint256 collateral
    );
    event NFTBorrowed(address indexed minter, uint256 indexed tokenID, address indexed borrower, uint256 loanTokenID);
    event NFTReturned(address indexed minter, uint256 indexed tokenID, address indexed borrower);
    event CollateralClaimed(uint256 indexed tokenId, address indexed lender);

    error AddressIsZero();
    error NotInitiator();
    error NotInitiated();
    error NotLoaner();
    error MustBeLongerThanOneHour();
    error AlreadyBorrowed();
    error DoesNotOwnScoreNFT();
    error NotApprovedBorrower();
    error IncorrectFeeAmount();
    error NotAvailableForLoan();
    error PayoutError();
    error NotBorrower();
    error LoanNotActive();
    error LoanNotDefaulted();
    error NonexistentToken();
    error SoulboundToken();
    error WrongFeeAmount();
    error OfferTimeout();

    //This is using the functions within the counters library for a counter within in the contract
    using Counters for Counters.Counter;

    //This is using the Strings library functions for uint256 variables within the contract
    using Strings for uint256;

    //This is a decleration that we will be using the Counter struct within the
    //Counters library as the variable type for the private variable _tokenIds
    Counters.Counter private _tokenIds;

    //This is a way that we can define a status for a loan
    enum LoanStatus { Active, Successful, Defaulted }

    //These are all the details we would like to store about a loan that has been taken out 
    struct Loan {
        address borrower;
        address lender;
        uint256 collateral;
        uint256 fee;
        uint256 borrowTimeUntil;
        uint256 streamId;
        LoanStatus status;
    }

    //This mapping stores the Loan details for different NFTs that are being borrowed
    mapping(uint256 tokenId => Loan loan) public loans;

    //This stores a BorrowerDetails object for a given borrower address
    mapping(address borrower => ILoanNFT.BorrowerDetails borrowerDetails) public borrowerDetails;

    //These are the details for a NFT that is up for loaning but is not yet loaned out
    struct LoanerDetails {
        address loaner;
        address[] requestedBorrowers;
        address[] allowedBorrowersByLoaner;
        uint256 time;
        mapping(address => bool) allowedBorrowers;
        mapping(address => uint256) offerUntil;
        mapping(address => uint256) requiredCollateralAmount;
        mapping(address => uint256) requiredFeeAmount;
    }

    //For a given Minter & TokenID store an instance of the LoanerDetails struct
    mapping(address collection => mapping(uint256 tokenId => LoanerDetails loanerDetails)) public loanerDetails;

    //For a given Minter & TokenID store the token ID that represents the current loan 
    mapping(address collection => mapping(uint256 tokenId => uint256 counter)) public loanTokenIDs;

    //For a given lender address store an array of tokenIDs that they are lending out
    mapping(address lender => uint256[] tokenIDs) public lendersActiveTokens;

    //This is the deployer & will be able to call the init function once
    address private initiator;

    //This is the address that will receive the payouts of fees
    address private payee;

    //This is the address of the score NFT contract
    address public scoreNFT;

    ISablierV2LockupLinear public immutable sablier;

    IWNATIVE  public immutable wnative;

    IToken public token;

    //This function is only called on deployment of the contract
    //Initialize the ERC721 constructor
    constructor(ISablierV2LockupLinear sablier_, IWNATIVE wnative_) ERC721("LoanNFT", "LN") {
        sablier = sablier_;
        wnative = wnative_;
        initiator = msg.sender;
        payee = msg.sender;
    }

    //This function can only be called by the deployer once
    function init(address _scoreNFT, address _token) external {

         //Check that the given address is not null
        if(_scoreNFT == address(0)) revert AddressIsZero();

        //Check that the caller is the initiator
        if(msg.sender != initiator) revert NotInitiator();

        //Set the address of the scoreNFT
        scoreNFT = _scoreNFT;

        token = IToken(_token);

        //Delete the initiator address
        delete initiator; 
    }

    //A modifier to check that the contract has been initiated before any actions can begin
    modifier initiated{
        if(scoreNFT == address(0)) revert NotInitiated();
        _;
    }

    //This function will only be called by the owner of the given tokenID on the given NFT minter 
    function offerNFTForLoaning(address minter, uint256 tokenID, uint256 time) external initiated {

        //Build an instance of the IERC721 interface using the given minter address
        IERC721 minterContract = IERC721(minter);

        //Check that the time given is longer than 1 hour
        if(time <= 1 hours) revert MustBeLongerThanOneHour();

        //Transfer the token from the caller to this contract
        minterContract.safeTransferFrom(msg.sender, address(this), tokenID);

        //Retrieve a storage pointer to the LoanerDetails
        LoanerDetails storage details = loanerDetails[minter][tokenID];
        
        //Set the loaner as the caller
        details.loaner = msg.sender;

        //Set the time that the NFT can be borrowed for
        details.time = time;

        emit NFTOfferedForLoan(minter, tokenID, msg.sender, time);
    }

    //This function will only be called by the owner of the NFT up for loaning
    function retrieveNFT(address minter, uint256 tokenID) external initiated {
        // Retrieve a storage pointer to the LoanerDetails for the given minter & tokenId
        LoanerDetails storage details = loanerDetails[minter][tokenID];

        // Check that the caller is the loaner of the NFT
        if(msg.sender != details.loaner) revert NotLoaner();

        // Check that the NFT hasn't been borrowed
        if(loanTokenIDs[minter][tokenID] != 0) revert AlreadyBorrowed();

        // Transfer the NFT back to the loaner
        IERC721(minter).safeTransferFrom(address(this), msg.sender, tokenID);

        // Reset the loaner details for this NFT
        // delete loanerDetails[minter][tokenID];

        // Iterate over the approved borrowers, delete their approval to borrow
        for(uint256 i; i < details.allowedBorrowersByLoaner.length;){

            delete details.allowedBorrowers[details.allowedBorrowersByLoaner[i]];

            unchecked{
                i++;
            }
        }

        // Delete the array of requested Borrowers & Allowed Borrowers
        delete details.requestedBorrowers;
        delete details.allowedBorrowersByLoaner;

        emit NFTRetrieved(minter, tokenID, msg.sender);
    }

    //This function should be only called by a wallet looking to borrow the NFT
    function requestToBorrow(address minter, uint256 tokenID) external initiated {

        //Check that the caller has a score NFT
        if(IERC721(scoreNFT).balanceOf(msg.sender) == 0) revert DoesNotOwnScoreNFT();

        //Retrieve a storage pointer to the LoanerDetails for the given minter & tokenId
        LoanerDetails storage details = loanerDetails[minter][tokenID];

        //Check that the loaner is set
        if(details.loaner == address(0)) revert NotAvailableForLoan();

        //Check that the loaner is not the borrower
        if(details.loaner == msg.sender) revert NotApprovedBorrower();
        
        //Add the caller to the list of requested borrowers 
        details.requestedBorrowers.push(msg.sender);

        emit BorrowRequest(minter, tokenID, msg.sender);
    }

    //This allows a caller to retrieve a list of addresses that are requesting to borrow the NFT
    function viewLoanRequests(address minter, uint256 tokenID) external view returns (address[] memory) {
        return loanerDetails[minter][tokenID].requestedBorrowers;
    }

    //This allows the loaner to let a borrower borrow the NFT for a given fee & collateral amount
    function approveLoanRequest(
      address minter, 
      uint256 tokenID, 
      address borrower, 
      uint256 fee, 
      uint256 collateral
      ) external initiated {

        //Retrieve a storage pointer to the LoanerDetails for the given minter & tokenId
        LoanerDetails storage details = loanerDetails[minter][tokenID];

        if(fee <= 0.1 ether) revert WrongFeeAmount();

        //Check that the caller is the loaner
        if(msg.sender != details.loaner) revert NotLoaner();
        
        //Set the details for the borrower
        details.allowedBorrowers[borrower] = true;
        details.allowedBorrowersByLoaner.push(borrower);
        details.requiredCollateralAmount[borrower] = collateral;
        details.requiredFeeAmount[borrower] = fee;
        details.offerUntil[borrower] = block.timestamp + 1 days;

        emit LoanApproved(minter, tokenID, borrower, fee, collateral);
    }

    //This function will only be called by an approved borrower
    function borrowNFT(address minter, uint256 tokenID) external payable initiated {
        //Retrieve a storage pointer to the LoanerDetails
        LoanerDetails storage details = loanerDetails[minter][tokenID];

        //Check that the token has not already been borrowed
        require(loanTokenIDs[minter][tokenID] == 0, "AlreadyBorrowed");

        //The caller must be an approved borrower
        require(details.allowedBorrowers[msg.sender], "NotApprovedBorrower");

        //Check that the offer is still valid
        if(details.offerUntil[msg.sender] < block.timestamp) revert OfferTimeout();
         
        //Retrieve the fee amount from storage
        uint256 feeAmount = details.requiredFeeAmount[msg.sender];

        //The value sent must equal the total amount required to be sent
        if(msg.value != feeAmount + details.requiredCollateralAmount[msg.sender]) revert IncorrectFeeAmount();

        //Calculate 10% of the feeAmount
        uint256 percentageFee = feeAmount * 10 / 100;

        uint256 totalAmount;
        //If 0.1 eth is greater than 10% of the feeAmount then charge 0.1 ETH as the platform fee
        //Other wise if 10% of the feeAmount is greater than 0.1 ETH charge 10% of the feeAmount as the platform fee
        if(0.1 ether > percentageFee){
            // Transfer the fee to the loaner
            totalAmount = feeAmount - 0.1 ether;
            (bool success, ) = address(wnative).call{ value: totalAmount }(abi.encodeWithSignature("deposit()"));
            if(!success) revert PayoutError();
            wnative.approve(address(sablier), totalAmount);
            
            // Transfer the fee to the platform
            // (bool success2, ) = payee.call{value: 0.1 ether}("");
            // if(!success2) revert PayoutError();

        }else {
            totalAmount = feeAmount - percentageFee;
            // Transfer the fee to the loaner
            (bool success, ) 
              = address(wnative).call{ value: totalAmount }(abi.encodeWithSignature("deposit()"));
            if(!success) revert PayoutError();
            wnative.approve(address(sablier), totalAmount);
            
            // Transfer the fee to the platform
            // (bool success2, ) = payee.call{value: percentageFee}("");
            // if(!success2) revert PayoutError();
        }

        
        // Mint the LoanNFT to the borrower
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(msg.sender, newItemId);

        // Transfer the NFT back to the lender
        IERC721(minter).safeTransferFrom(address(this), msg.sender, tokenID);

        lendersActiveTokens[details.loaner].push(newItemId);

        // Update loan details
        Loan memory newLoan;
        newLoan.borrower = msg.sender;
        newLoan.lender = details.loaner;
        newLoan.collateral = details.requiredCollateralAmount[msg.sender];
        newLoan.fee = details.requiredFeeAmount[msg.sender];
        newLoan.borrowTimeUntil = block.timestamp + details.time;
        newLoan.status = LoanStatus.Active;

        LockupLinear.CreateWithDurations memory params;

        params.sender = msg.sender; // The sender will be able to cancel the stream
        params.recipient = address(details.loaner); // The recipient of the streamed assets
        params.totalAmount = uint128(totalAmount); // Total amount is the amount inclusive of all fees
        params.asset = wnative; // The streaming asset
        params.cancelable = true; // Whether the stream will be cancelable or not
        params.durations = LockupLinear.Durations({
            cliff: 0, // no cliff
            total: uint40(details.time) // Setting a total duration
         });
        params.broker = Broker(address(0), ud60x18(0)); // Optional parameter for charging a fee

        // Create the LockupLinear stream using a function that sets the start time to `block.timestamp`
        newLoan.streamId = sablier.createWithDurations(params);

        // Set the Loan struct for the tokenID in the loans mapping
        loans[newItemId] = newLoan;

        // Set the tokenID as the current tokenID for the minter & tokenID being borrowed
        loanTokenIDs[minter][tokenID] = newItemId; 

        // Update user loan history
        // borrowerLoans[msg.sender].push(newItemId);
        // activeLoans[msg.sender]++;
        // totalLoans[msg.sender]++;
        ILoanNFT.BorrowerDetails storage _borrowerDetails = borrowerDetails[msg.sender];
        _borrowerDetails.activeLoans++;
        _borrowerDetails.totalLoans++;
        _borrowerDetails.loanTokenIds.push(newItemId);

        // Iterate over the approved borrowers, delete their approval to borrow
        for(uint256 i; i < details.allowedBorrowersByLoaner.length;){

            delete details.allowedBorrowers[details.allowedBorrowersByLoaner[i]];

            unchecked{
                i++;
            }
        }

        // Delete the array of requested Borrowers & Allowed Borrowers
        delete details.requestedBorrowers;
        delete details.allowedBorrowersByLoaner;

        Send("NFTBorrowed",msg.sender);

        emit NFTBorrowed(minter, tokenID, msg.sender, _tokenIds.current());
    }

    // This function can only be called by the wallet that is borrowing the NFT
    function returnNFT(address minter, uint256 tokenID) external initiated {

        if(address(token) != address(0)){
            token.mintByLoan(msg.sender);
        }

        //Retrieve the loan Token ID
        uint256 loanTokenID = loanTokenIDs[minter][tokenID];

        //Retrieve a storage pointer to te Loan details
        Loan storage loan = loans[loanTokenID];

        //Check that the caller is the borrower
        if(loan.borrower != msg.sender) revert NotBorrower();

        //Check that the loan is still active
        if(loan.status != LoanStatus.Active) revert LoanNotActive();

        // Transfer the NFT back to the lender
        IERC721(minter).safeTransferFrom(msg.sender, loan.lender, tokenID);

        // Return the collateral to the borrower
        (bool success, ) = msg.sender.call{value:loan.collateral}("");
        if(!success) revert PayoutError();

        // Settle the stream if not depleted
        if (!sablier.isDepleted(loan.streamId)) {
          sablier.withdrawMax({ streamId: loan.streamId, to: loan.lender });
        }

        removeFromArray(lendersActiveTokens[loan.lender],loanTokenID);

        // Update loan status and user loan history
        loan.status = LoanStatus.Successful;
        // successfulLoans[msg.sender]++;
        // activeLoans[msg.sender]--;
        ILoanNFT.BorrowerDetails storage _borrowerDetails = borrowerDetails[msg.sender];
        _borrowerDetails.successfulLoans++;
        _borrowerDetails.activeLoans--;
        delete loanTokenIDs[minter][tokenID];

        Send("NFTClosedSuccessfully",msg.sender);

        emit NFTReturned(minter, tokenID, msg.sender);
    }

    // Exposing functionality for loaner to withdraw the accrued fees 
    // from the sablier stream
    function withdrawAccruedFee(address minter, uint256 tokenID) external {
        //Retrieve the loan Token ID
        uint256 loanTokenID = loanTokenIDs[minter][tokenID];

        //Retrieve a storage pointer to te Loan details
        Loan storage loan = loans[loanTokenID];

        //Check that the caller is the borrower
        if(loan.lender != msg.sender) revert NotLoaner();

        //Withdraw max stream available from stream if not depleted
        if (!sablier.isDepleted(loan.streamId)) {
          sablier.withdrawMax({ streamId: loan.streamId, to: loan.lender });
        }
    }

    function removeFromArray(uint256[] storage arr, uint256 toRemove) private {
        for(uint256 i; i < arr.length;){

            if(arr[i] == toRemove){
                arr[i] = arr[arr.length-1];
                arr.pop();
            }

            unchecked {
                i++;
            }
        }
    }


    //This function can only be called by the loaner
    function claimCollateral(uint256 tokenId) external initiated {

        //Retrieve a storage pointer to the Loan
        Loan storage loan = loans[tokenId];

        //Check that the caller is the loaner
        if(loan.lender != msg.sender) revert NotLoaner();

        //Check that the Loan is active
        if(loan.status != LoanStatus.Active) revert LoanNotActive();

        //Check that the loan has defaulted
        if(block.timestamp < loan.borrowTimeUntil) revert LoanNotDefaulted();

        // Transfer the collateral to the lender
        (bool success, ) = msg.sender.call{value:loan.collateral}("");
        if(!success) revert PayoutError();

        // Withdraw remaining stream
        sablier.withdrawMax({ streamId: loan.streamId, to: msg.sender });

        // Cancel rest of the stream
        sablier.cancel(loan.streamId);

        removeFromArray(lendersActiveTokens[loan.lender],tokenId);
        
        // Update loan status and user loan history
        loan.status = LoanStatus.Defaulted;
        // activeLoans[loan.borrower]--;
        // closedDefaults[loan.borrower]++;
        ILoanNFT.BorrowerDetails storage _borrowerDetails = borrowerDetails[loan.borrower];
        _borrowerDetails.activeLoans--;
        _borrowerDetails.closedDefaults++;

        emit CollateralClaimed(tokenId, msg.sender);

        Send("NFTClosedDefault",loan.borrower); 
    }

    //This function will be called by the Score NFT contract & also other wallets to read
    function getCurrentDefaults(address borrower) external view returns (uint256) {

        //Declare a null variable
        uint256 defaults = 0;

        //Retrieve the tokens that the borrower has borrowed currently
        uint256[] memory borrowerTokens = borrowerDetails[borrower].loanTokenIds;

        //Iterate through the loanTokens
        for (uint256 i; i < borrowerTokens.length; ) {
            
            //If the current time is greater than the time that the token was supposed to be borrowed until
            if (block.timestamp > loans[borrowerTokens[i]].borrowTimeUntil) {

                //Increment the number of defaults
                defaults++;
            }

            //Remove safe math wrapper
            unchecked{

                //Increment the counter
                i++;
            }
        }

        //Return the number of defaults
        return defaults;
    }

    function getBorrowerDetails(address _borrower) external view returns (ILoanNFT.BorrowerDetails memory details) {
        details = borrowerDetails[_borrower];
    }

    function getAmountToPay(
      address minter, 
      uint256 tokenID, 
      address query) external view returns(uint256 feeAmount, uint256 collateralAmount){
        //Retrieve a storage pointer to the LoanerDetails for the given minter & tokenId
        LoanerDetails storage details = loanerDetails[minter][tokenID];

        return(
            details.requiredFeeAmount[query],
            details.requiredCollateralAmount[query]
        );
    }


    //Returns the generated tokenURI metadata for a given token
    function tokenURI(uint256 tokenId) public view override returns (string memory) {

        //Check that the token exists
        if(!_exists(tokenId)) revert NonexistentToken();

        //Retrieve the Loan details
        Loan memory loan = loans[tokenId];

        //Get the status of the loan
        string memory status;
        if (loan.status == LoanStatus.Active) {
            status = "Active";
        } else if (loan.status == LoanStatus.Successful) {
            status = "Successful";
        } else {
            status = "Defaulted";
        }

        //Generate the json string
        string memory json = string(abi.encodePacked(
            "{\"tokenId\": ", tokenId.toString(), 
            ", \"borrower\": ", Strings.toHexString(uint160(loan.borrower)), 
            ", \"lender\": ", Strings.toHexString(uint160(loan.lender)), 
            ", \"collateral\": ", loan.collateral.toString(),
            ", \"fee\": ", loan.fee.toString(),
            ", \"timeUntil\": ", loan.borrowTimeUntil.toString(),
            ", \"status\": ", status,
            "}"
        ));

        //Convert the json string to base64 & prepend with the data encryption definition of base64 to json
        string memory output = string(abi.encodePacked("data:application/json;base64,", Base64.encode(bytes(json))));

        //Return the string
        return output;
    }

    // Make the NFT soulbound (non-transferable)
    function _beforeTokenTransfer(
      address from, 
      address to, 
      uint256 firstTokenId
      // uint256 batchSize
      ) internal virtual {
        super._beforeTokenTransfer(from, to, firstTokenId,1);
        if(from != address(0) && to != address(0)) revert SoulboundToken();
    }
    
    function _performTask(string memory task, address effectedAddress) internal override {
        bytes32 bytesTask = keccak256(abi.encode(task));

        ILoanNFT.BorrowerDetails storage details = borrowerDetails[effectedAddress];
        
        if(bytesTask == keccak256(abi.encode("NFTBorrowed"))){
            details.activeLoans++;
        }else if (bytesTask == keccak256(abi.encode("NFTClosedDefault"))){
            details.activeLoans--;
            details.closedDefaults++;
        }else if(bytesTask == keccak256(abi.encode("NFTClosedSuccessfully"))){
            details.activeLoans--;
            details.successfulLoans++;
            if(address(token) != address(0)){
                token.mintByLoan(effectedAddress);
            }
        }
    }
}
