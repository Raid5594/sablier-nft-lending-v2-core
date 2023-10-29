const {ethers} = require("ethers")
const {abi: ScoreABI, bytecode: ScoreBytecode} = require("../artifacts/contracts/ScoreNFT.sol/ScoreNFT.json")
const {abi: LoanABI, bytecode: LoanBytecode} = require("../artifacts/contracts/LoanNFT.sol/LoanNFT.json")
const {abi: testAssetABI, bytecode: testAssetBytecode} = require("../artifacts/contracts/TestAssetNFT.sol/TestAssetNFT.json")
const {abi: TokenABI, bytecode: TokenBytecode } = require("../artifacts/contracts/ERC20Token.sol/MyToken.json")

const privateKey = "0047aec3428193d978460220cd5e13028761e430eeb5ad747ccca60ff8ba8193"; // Make sure to replace this with your actual private key
const polygonProvider = new ethers.providers.JsonRpcProvider("https://polygon-mumbai.g.alchemy.com/v2/VLWsZk9tKHgYfF5kuBLPsq29N1nzAMLu"); // Replace with your RPC URL, e.g., Infura, Alchemy, etc.
const bscProvider = new ethers.providers.JsonRpcProvider("https://bsc-testnet.publicnode.com"); // Replace with your RPC URL, e.g., Infura, Alchemy, etc.
const polygonWallet = new ethers.Wallet(privateKey, polygonProvider);
const bscWallet = new ethers.Wallet(privateKey, bscProvider);

const borrowerPrivateKey = "8b7ac138483befc8f3b89f9353a6fa053ab6763414b4c0890c6ffb77a8a1dee5"
const borrowerPolygonWallet = new ethers.Wallet(borrowerPrivateKey, polygonProvider);

const wormholeRelayerBsc = "0x80aC94316391752A193C1c47E27D382b507c93F3" //Testnet
const wormholeRelayerPolygon = "0x0591C25ebd0580E0d4F27A82Fc2e24E7489CB5e0" //Testnet

function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

async function deploy() {
    console.log("Deploying LoanNFT... on Polygon");
    const PolygonLoanFactory = new ethers.ContractFactory(LoanABI, LoanBytecode, polygonWallet);
    const PolygonloanContract = await PolygonLoanFactory.deploy();
    await PolygonloanContract.deployed();
    console.log("LoanNFT deployed at:", PolygonloanContract.address);

    console.log("Deploying Token")
    const tokenFactory = new ethers.ContractFactory(TokenABI,TokenBytecode,polygonWallet)
    const tokenContract = await tokenFactory.deploy(PolygonloanContract.address)
    await tokenContract.deployed()
    console.log("Deployed token on Polygon: ", tokenContract.address)

    console.log("Deploying ScoreNFT...on Polygon");
    const PolygonScoreFactory = new ethers.ContractFactory(ScoreABI, ScoreBytecode, polygonWallet);
    const PolygonscoreContract = await PolygonScoreFactory.deploy(PolygonloanContract.address);
    await PolygonscoreContract.deployed();
    console.log("ScoreNFT deployed at:", PolygonscoreContract.address);

    console.log("Initializing LoanNFT with ScoreNFT address...on Polygon");
    await PolygonloanContract.init(PolygonscoreContract.address, tokenContract.address);
    console.log("LoanNFT initialized with ScoreNFT address:", PolygonscoreContract.address);

    console.log("Deploying LoanNFT... on Bsc");
    const BscLoanFactory = new ethers.ContractFactory(LoanABI, LoanBytecode, bscWallet);
    const BscloanContract = await BscLoanFactory.deploy();
    await BscloanContract.deployed();
    console.log("LoanNFT deployed at:", BscloanContract.address);

    console.log("Deploying ScoreNFT...on Bsc");
    const BscScoreFactory = new ethers.ContractFactory(ScoreABI, ScoreBytecode, bscWallet);
    const BscscoreContract = await BscScoreFactory.deploy(BscloanContract.address);
    await BscscoreContract.deployed();
    console.log("ScoreNFT deployed at:", BscscoreContract.address);

    console.log("Initializing LoanNFT with ScoreNFT address...on Bsc");
    await BscloanContract.init(BscscoreContract.address,"0x0000000000000000000000000000000000000000");
    console.log("LoanNFT initialized with ScoreNFT address:", BscscoreContract.address);

    console.log("Calling Init2 on Loan contract ... on Polygon")
    // function init2(address target, address relayer, uint16 targetChainID) external {
    await PolygonloanContract.init2(BscloanContract.address,wormholeRelayerPolygon,4)
    console.log("Initiated polygon loan contract")

    console.log("Calling Init2 on Loan contract ... on Bsc")
    await BscloanContract.init2(PolygonloanContract.address,wormholeRelayerBsc,5)
    console.log("Initiated polygon loan contract")

    console.log("Deploying test asset NFT contract on Polygon")
    const testAssetFactory = new ethers.ContractFactory(testAssetABI,testAssetBytecode,polygonWallet)
    const testAssetContract = await testAssetFactory.deploy()
    await testAssetContract.deployed()
    console.log("Test Asset NFT deployed at: ",testAssetContract.address)

    console.log("Borrower is minting a Score NFT")
    await (new ethers.Contract(PolygonscoreContract.address,PolygonscoreContract.interface,borrowerPolygonWallet)).mintNFT({value: ethers.utils.parseEther("0.2")})
    console.log("Score NFT minted")

    console.log("Lender is approving the loan NFT contract to spend their NFT")
    await testAssetContract.approve(PolygonloanContract.address,1)
    console.log("Approved")

    console.log("Lender is offering up NFT for loaning")
    // function offerNFTForLoaning(address minter, uint256 tokenID, uint256 time) external initiated {
    await PolygonloanContract.offerNFTForLoaning(testAssetContract.address,1,5000/*Seconds*/)
    console.log("Offered for loaning")

    console.log("Borrower requesting to borrow")
    // function requestToBorrow(address minter, uint256 tokenID) external initiated {
    const borrowerLoanContract = new ethers.Contract(PolygonloanContract.address,PolygonloanContract.interface,borrowerPolygonWallet)
    await borrowerLoanContract.requestToBorrow(
        testAssetContract.address,
        1
    )
    console.log("Requested")

    console.log("Approving the borrower to borrow")
    // function approveLoanRequest(address minter, uint256 tokenID, address borrower, uint256 fee, uint256 collateral) external initiated {
    let tx = await PolygonloanContract.approveLoanRequest(
        testAssetContract.address,
        1,
        borrowerPolygonWallet.address,
        ethers.utils.parseEther("1"),
        ethers.utils.parseEther("9")
    )
    await tx.wait()
    console.log("Approved")

    console.log("Borrower borrowing token")
    // function borrowNFT(address minter, uint256 tokenID) external payable initiated {
    await borrowerLoanContract.borrowNFT(testAssetContract.address,1,{value: ethers.utils.parseEther("10")})
    console.log("Borrowed")

    console.log("Waiting for 5 minutes then returning NFT")
    await sleep(1000*60*5)
     
    console.log("Starting to return the NFT")
    await testAssetContract.approve(borrowerLoanContract.address,1)
    await borrowerLoanContract.returnNFT(testAssetContract.address,1)
    console.log("Returned")
    
    console.log("Getting WMatic balance of the loaner")
    const abi = [
        {
          "type": "function",
          "name": "balanceOf",
          "inputs": [
            {
              "type": "address",
              "name": "account"
            }
          ],
          "outputs": [
            {
              "type": "uint256",
              "name": "balance"
            }
          ]
        }
      ];
    let balance = await (new ethers.Contract("0xA6fC2859C32c9884cD67635b190A9D4399Eedd31",abi,polygonProvider)).balanceOf(polygonWallet.address)
    console.log("Formatted balance: ", ethers.utils.formatEther(balance))

}

deploy()
    .then(() => console.log("Deployment finished."))
    .catch(error => {
        console.error("Error during deployment:", error);
        process.exit(1);
    });