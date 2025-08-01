const fs = require("fs");
const path = require("path");
const {
  SubscriptionManager,
  SecretsManager,
  simulateScript,
  ResponseListener,
  ReturnType,
  decodeResult,
  FulfillmentCode,
} = require("@chainlink/functions-toolkit");
const functionsConsumerAbi = require("../abi/functionsClient.json");
const ethers = require("ethers");
require("@chainlink/env-enc").config();

const consumerAddress = "0x8ef899face8e71058ce777400cf39e2b500f2049"; // REPLACE this with your Functions consumer address
const subscriptionId = 4986; // REPLACE this with your subscription ID

const makeRequestSepolia = async () => {
  // hardcoded for Ethereum Sepolia
  const routerAddress = "0xb83E47C2bC239B3bf370bc41e1459A34b41238D0";
  const linkTokenAddress = "0x779877A7B0D9E8603169DdbD7836e478b4624789";
  const donId = "fun-ethereum-sepolia-1";
  const explorerUrl = "https://sepolia.etherscan.io";
  const gatewayUrls = [
    "https://01.functions-gateway.testnet.chain.link/",
    "https://02.functions-gateway.testnet.chain.link/",
  ];

  // Initialize functions settings
  const source = fs
    .readFileSync(path.resolve(__dirname, "source.js"))
    .toString();

  // const args = ["pi_3RZk9m3PrM4sdLLb0xBSdETa", "1000"];
  const secrets = { STRIPE_SECRET_KEY: process.env.STRIPE_SECRET_KEY };
  const mockSecrets = {
    STRIPE_SECRET_KEY: "sk_test_mock_key_for_simulation_only",
  };
  const slotIdNumber = 0; // slot ID where to upload the secrets
  const expirationTimeMinutes = 3999; // expiration time in minutes of the secrets
  const gasLimit = 300000;

  // Initialize ethers signer and provider to interact with the contracts onchain
  const privateKey = process.env.PRIVATE_KEY; // fetch PRIVATE_KEY
  if (!privateKey)
    throw new Error(
      "private key not provided - check your environment variables"
    );

  const rpcUrl = process.env.SEPOLIA_RPC_URL; // fetch Sepolia RPC URL

  if (!rpcUrl)
    throw new Error(`rpcUrl not provided  - check your environment variables`);

  const provider = new ethers.providers.JsonRpcProvider(rpcUrl);

  const wallet = new ethers.Wallet(privateKey);
  const signer = wallet.connect(provider); // create ethers signer for signing transactions

  // ///////// START SIMULATION ////////////

  // console.log("Start simulation...");

  // const response = await simulateScript({
  //   source: source,
  //   args: args,
  //   bytesArgs: [], // bytesArgs - arguments can be encoded off-chain to bytes.
  //   secrets: mockSecrets,
  // });

  // console.log("Simulation result", response);
  // const errorString = response.errorString;
  // if (errorString) {
  //   console.log(`❌ Error during simulation: `, errorString);
  // } else {
  //   const returnType = ReturnType.string;
  //   const responseBytesHexstring = response.responseBytesHexstring;
  //   if (ethers.utils.arrayify(responseBytesHexstring).length > 0) {
  //     const decodedResponse = decodeResult(
  //       response.responseBytesHexstring,
  //       returnType
  //     );
  //     console.log(`✅ Decoded response to ${returnType}: `, decodedResponse);
  //   }
  // }

  // //////// ESTIMATE REQUEST COSTS ////////
  // console.log("\nEstimate request costs...");
  // // Initialize and return SubscriptionManager
  // const subscriptionManager = new SubscriptionManager({
  //   signer: signer,
  //   linkTokenAddress: linkTokenAddress,
  //   functionsRouterAddress: routerAddress,
  // });
  // await subscriptionManager.initialize();

  // // estimate costs in Juels

  // const gasPriceWei = await signer.getGasPrice(); // get gasPrice in wei

  // const estimatedCostInJuels =
  //   await subscriptionManager.estimateFunctionsRequestCost({
  //     donId: donId, // ID of the DON to which the Functions request will be sent
  //     subscriptionId: subscriptionId, // Subscription ID
  //     callbackGasLimit: gasLimit, // Total gas used by the consumer contract's callback
  //     gasPriceWei: BigInt(gasPriceWei), // Gas price in gWei
  //   });

  // console.log(
  //   `Fulfillment cost estimated to ${ethers.utils.formatEther(
  //     estimatedCostInJuels
  //   )} LINK`
  // );

  // //////// MAKE REQUEST ////////

  // console.log("\nMake request...");

  // First encrypt secrets and upload the encrypted secrets to the DON
  const secretsManager = new SecretsManager({
    signer: signer,
    functionsRouterAddress: routerAddress,
    donId: donId,
  });
  await secretsManager.initialize();

  // Encrypt secrets and upload to DON
  const encryptedSecretsObj = await secretsManager.encryptSecrets(secrets);

  console.log(
    `Upload encrypted secret to gateways ${gatewayUrls}. slotId ${slotIdNumber}. Expiration in minutes: ${expirationTimeMinutes}`
  );
  // Upload secrets
  const uploadResult = await secretsManager.uploadEncryptedSecretsToDON({
    encryptedSecretsHexstring: encryptedSecretsObj.encryptedSecrets,
    gatewayUrls: gatewayUrls,
    slotId: slotIdNumber,
    minutesUntilExpiration: expirationTimeMinutes,
  });

  if (!uploadResult.success)
    throw new Error(`Encrypted secrets not uploaded to ${gatewayUrls}`);

  console.log(
    `\n✅ Secrets uploaded properly to gateways ${gatewayUrls}! Gateways response: `,
    uploadResult
  );

  // const donHostedSecretsVersion = parseInt(uploadResult.version); // fetch the reference of the encrypted secrets

  // const functionsConsumer = new ethers.Contract(
  //   consumerAddress,
  //   functionsConsumerAbi,
  //   signer
  // );

  // // Actual transaction call
  // const transaction = await functionsConsumer.sendRequest(
  //   source, // source
  //   "0x", // user hosted secrets - encryptedSecretsUrls - empty in this example
  //   slotIdNumber, // slot ID of the encrypted secrets
  //   donHostedSecretsVersion, // version of the encrypted secrets
  //   args,
  //   [], // bytesArgs - arguments can be encoded off-chain to bytes.
  //   subscriptionId,
  //   gasLimit,
  //   ethers.utils.formatBytes32String(donId) // jobId is bytes32 representation of donId
  // );

  // // Log transaction details
  // console.log(
  //   `\n✅ Functions request sent! Transaction hash ${transaction.hash}. Waiting for a response...`
  // );

  // console.log(
  //   `See your request in the explorer ${explorerUrl}/tx/${transaction.hash}`
  // );

  // const responseListener = new ResponseListener({
  //   provider: provider,
  //   functionsRouterAddress: routerAddress,
  // }); // Instantiate a ResponseListener object to wait for fulfillment.
  // (async () => {
  //   try {
  //     const response = await new Promise((resolve, reject) => {
  //       responseListener
  //         .listenForResponseFromTransaction(transaction.hash)
  //         .then((response) => {
  //           resolve(response); // Resolves once the request has been fulfilled.
  //         })
  //         .catch((error) => {
  //           reject(error); // Indicate that an error occurred while waiting for fulfillment.
  //         });
  //     });

  //     const fulfillmentCode = response.fulfillmentCode;

  //     if (fulfillmentCode === FulfillmentCode.FULFILLED) {
  //       console.log(
  //         `\n✅ Request ${
  //           response.requestId
  //         } successfully fulfilled. Cost is ${ethers.utils.formatEther(
  //           response.totalCostInJuels
  //         )} LINK.Complete reponse: `,
  //         response
  //       );
  //     } else if (fulfillmentCode === FulfillmentCode.USER_CALLBACK_ERROR) {
  //       console.log(
  //         `\n⚠️ Request ${
  //           response.requestId
  //         } fulfilled. However, the consumer contract callback failed. Cost is ${ethers.utils.formatEther(
  //           response.totalCostInJuels
  //         )} LINK.Complete reponse: `,
  //         response
  //       );
  //     } else {
  //       console.log(
  //         `\n❌ Request ${
  //           response.requestId
  //         } not fulfilled. Code: ${fulfillmentCode}. Cost is ${ethers.utils.formatEther(
  //           response.totalCostInJuels
  //         )} LINK.Complete reponse: `,
  //         response
  //       );
  //     }

  //     const errorString = response.errorString;
  //     if (errorString) {
  //       console.log(`\n❌ Error during the execution: `, errorString);
  //     } else {
  //       const responseBytesHexstring = response.responseBytesHexstring;
  //       if (ethers.utils.arrayify(responseBytesHexstring).length > 0) {
  //         const decodedResponse = decodeResult(
  //           response.responseBytesHexstring,
  //           ReturnType.string
  //         );
  //         console.log(
  //           `\n✅ Decoded response to ${ReturnType.string}: `,
  //           decodedResponse
  //         );
  //       }
  //     }
  //   } catch (error) {
  //     console.error("Error listening for response:", error);
  //   }
  // })();
};

makeRequestSepolia().catch((e) => {
  console.error(e);
  process.exit(1);
});
