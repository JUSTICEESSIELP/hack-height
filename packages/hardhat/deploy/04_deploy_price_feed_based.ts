import { HardhatRuntimeEnvironment } from "hardhat/types";
import { DeployFunction } from "hardhat-deploy/types";
import { deployPriceFeedBased } from "../helpers/contract-deployments";
import { FEE, JOB_ID, REGISTRAR, UPDATEINTERVAL } from "../helpers/constants";

/**
 * Deploys a contract named "PriceFeedBased" using the deployer account and
 * constructor arguments set to the deployer address
 *
 * @param hre HardhatRuntimeEnvironment object.
 */
const deployPriceFeedBasedContract: DeployFunction = async function ({ deployments }: HardhatRuntimeEnvironment) {
  const { log } = deployments;

  const oracleAddress = "0x09635F643e140090A9A8Dcd712eD6285858ceBef"; //The oracle price address
  const fee = FEE; //Vary depending to the network
  const link = "0x5FC8d32690cc91D4c39d9d3abcBD16989F875707"; //Link token address
  const jobId = JOB_ID; //adjust with the correct value
  const oracleId = "0x09635F643e140090A9A8Dcd712eD6285858ceBef"; //The DinamikoPriceOracle deployment address
  const registrar = REGISTRAR; ////The address of the Chainlink Automation registry contract
  const updateInterval = UPDATEINTERVAL;
  const baseCurrency = "0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"; //USDC smart contract address

  log("Deploying Price Feed Based ...");
  console.log(
    "Oracle address:",
    oracleAddress,
    "\n",
    "Fee:",
    fee.toString(),
    "\n",
    "Job Id:",
    jobId,
    "\n",
    "Oracle Id:",
    oracleId,
    "\n",
    "Link address:",
    link,
    "\n",
    "Keeper registry:",
    registrar,
    "\n",
    "Update time interval:",
    updateInterval,
    "\n",
    "Base currency:",
    baseCurrency,
    "\n",
  );
  await deployPriceFeedBased(oracleAddress, fee, oracleId, link, baseCurrency);
  log("Done \n \n");
};

export default deployPriceFeedBasedContract;

// Tags are useful if you have multiple deploy files and only want to run one of them.
// e.g. yarn deploy --tags YourContract
deployPriceFeedBasedContract.tags = ["PriceFeedBased"];