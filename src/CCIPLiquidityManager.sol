// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {CreditShaftCore} from "./CreditShaftCore.sol";

contract CCIPLiquidityManager is Ownable {
    IRouterClient private s_router;
    IERC20 private s_linkToken;
    IERC20 public immutable usdcToken;
    uint64 public s_destinationChainSelector;
    address public s_partnerManager;
    CreditShaftCore public s_creditShaftCore;
    uint256 public s_liquidityThreshold;
    uint256 public s_refillAmount;

    event LiquidityRequested(bytes32 indexed messageId, address indexed destination, uint256 amount);
    event LiquidityReceived(bytes32 indexed messageId, address indexed source, uint256 amount);

    constructor(address routerAddress, address linkAddress, address _usdcToken, address creditShaftCoreAddress)
        Ownable(msg.sender)
    {
        s_router = IRouterClient(routerAddress);
        s_linkToken = IERC20(linkAddress);
        usdcToken = IERC20(_usdcToken);
        if (creditShaftCoreAddress != address(0)) {
            s_creditShaftCore = CreditShaftCore(creditShaftCoreAddress);
        }
    }

    function _ccipReceive(Client.Any2EVMMessage memory message) internal {
        require(keccak256(message.sender) == keccak256(abi.encode(s_partnerManager)), "Unauthorized sender");

        if (address(s_creditShaftCore) == address(0)) {
            // On Fuji (Reserve Chain)
            uint256 amountToSend = abi.decode(message.data, (uint256));
            _sendLiquidity(amountToSend);
        } else {
            // On Sepolia (Home Chain)
            require(message.destTokenAmounts.length == 1, "Expected one token amount");
            require(message.destTokenAmounts[0].token == address(usdcToken), "Invalid token");

            uint256 receivedAmount = message.destTokenAmounts[0].amount;
            emit LiquidityReceived(message.messageId, s_partnerManager, receivedAmount);

            usdcToken.approve(address(s_creditShaftCore), receivedAmount);
            s_creditShaftCore.addUSDCLiquidity(receivedAmount);
        }
    }

    function checkAndRefillLiquidity() external {
        require(address(s_creditShaftCore) != address(0), "Not on home chain");
        uint256 currentLiquidity = s_creditShaftCore.getAvailableUSDCLiquidity();
        if (currentLiquidity < s_liquidityThreshold) {
            _requestLiquidity(s_refillAmount);
        }
    }

    function _requestLiquidity(uint256 amount) private {
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(s_partnerManager),
            data: abi.encode(amount),
            tokenAmounts: new Client.EVMTokenAmount[](0),
            // --- FIX #1: Use the correct helper function ---
            extraArgs: Client.encodeEVMExtraArgsV1(Client.EVMExtraArgsV1({gasLimit: 400_000, strict: false})),
            feeToken: address(s_linkToken)
        });

        uint256 fee = s_router.getFee(s_destinationChainSelector, message);
        require(s_linkToken.balanceOf(address(this)) >= fee, "Not enough LINK for fees");
        s_linkToken.approve(address(s_router), fee);
        bytes32 messageId = s_router.ccipSend(s_destinationChainSelector, message);
        emit LiquidityRequested(messageId, s_partnerManager, amount);
    }

    function _sendLiquidity(uint256 amount) private {
        require(usdcToken.balanceOf(address(this)) >= amount, "Insufficient reserve");
        Client.EVMTokenAmount[] memory tokenAmounts = new Client.EVMTokenAmount[](1);
        tokenAmounts[0] = Client.EVMTokenAmount({token: address(usdcToken), amount: amount});
        Client.EVM2AnyMessage memory message = Client.EVM2AnyMessage({
            receiver: abi.encode(s_partnerManager),
            data: "",
            tokenAmounts: tokenAmounts,
            // --- FIX #1: Use the correct helper function ---
            extraArgs: Client.encodeEVMExtraArgsV1(Client.EVMExtraArgsV1({gasLimit: 400_000, strict: false})),
            feeToken: address(s_linkToken)
        });
        uint256 fee = s_router.getFee(s_destinationChainSelector, message);
        require(s_linkToken.balanceOf(address(this)) >= fee, "Not enough LINK for fees");
        s_linkToken.approve(address(s_router), fee);
        usdcToken.approve(address(s_router), amount);
        bytes32 messageId = s_router.ccipSend(s_destinationChainSelector, message);
        emit LiquidityRequested(messageId, s_partnerManager, amount);
    }

    function setPartner(uint64 destinationChainSelector, address partnerManager) external onlyOwner {
        s_destinationChainSelector = destinationChainSelector;
        s_partnerManager = partnerManager;
    }

    function setLiquidityParameters(uint256 threshold, uint256 refill) external onlyOwner {
        require(address(s_creditShaftCore) != address(0), "Not on home chain");
        s_liquidityThreshold = threshold;
        s_refillAmount = refill;
    }

    function deposit(uint256 amount) external onlyOwner {
        usdcToken.transferFrom(msg.sender, address(this), amount);
    }

    function withdrawToken(address token, uint256 amount) external onlyOwner {
        require(token == address(usdcToken) || token == address(s_linkToken), "Invalid token");
        IERC20(token).transfer(msg.sender, amount);
    }
}
