// 部署脚本 - 用于部署LotteryContract合约
const hre = require("hardhat");

async function main() {
  // 获取网络配置
  const network = hre.network.name;
  
  // 根据不同网络设置不同的订阅ID
  let subscriptionId;
  
  if (network === "sepolia") {
    // Sepolia测试网的订阅ID - 需要替换为您的实际订阅ID
    subscriptionId = process.env.SEPOLIA_SUBSCRIPTION_ID || "1";
    console.log(`使用Sepolia测试网的订阅ID: ${subscriptionId}`);
  } else if (network === "mainnet") {
    // 主网的订阅ID - 需要替换为您的实际订阅ID
    subscriptionId = process.env.MAINNET_SUBSCRIPTION_ID;
    if (!subscriptionId) {
      throw new Error("部署到主网时必须提供MAINNET_SUBSCRIPTION_ID环境变量");
    }
    console.log(`使用主网的订阅ID: ${subscriptionId}`);
  } else {
    // 本地开发网络使用模拟订阅ID
    subscriptionId = "1";
    console.log(`使用本地开发网络的模拟订阅ID: ${subscriptionId}`);
  }

  // 部署LotteryContract合约
  console.log("开始部署LotteryContract合约...");
  const vrfCoordinator = process.env.SEPOLIA_VRF_COORDINATOR;
  const keyHash = process.env.SEPOLIA_KEY_HASH;

  const LotteryContract = await hre.ethers.getContractFactory("LotteryContract");
  const lotteryContract = await LotteryContract.deploy(subscriptionId, vrfCoordinator, keyHash);

  await lotteryContract.waitForDeployment();
  
  const address = await lotteryContract.getAddress();
  console.log(`LotteryContract已部署到地址: ${address}`);

  // 等待几个区块确认以确保合约已正确部署
  console.log("等待区块确认...");
  if (network !== "hardhat" && network !== "localhost") {
    await lotteryContract.deploymentTransaction().wait(5);
    console.log("合约部署已确认");
    
    // 验证合约（如果不是本地网络）
    console.log("开始验证合约...");
    try {
      await hre.run("verify:verify", {
        address: address,
        constructorArguments: [subscriptionId],
      });
      console.log("合约验证成功");
    } catch (error) {
      console.error("合约验证失败:", error);
    }
  }

  console.log("部署完成!");
  console.log("合约地址:", address);
  console.log("订阅ID:", subscriptionId);
}

// 执行部署脚本
main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });