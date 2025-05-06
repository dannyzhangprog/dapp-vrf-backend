const { ethers } = require("hardhat")

const networkConfig = {
    11155111: {
        name: "sepolia",
        vrfCoordinatorV2: "0x9DdfaCa8183c41ad55329BdeeD9F6A8d53168B1B", // Sepolia VRF Coordinator V2.5
        entranceFee: ethers.parseEther("0.01"),
        gasLane: "0x787d74caea10b2b357790d5b5247c2f63d1d91572a9846f780606e4d953677ae", // 30 gwei Key Hash
        subscriptionId: "33353626133254534267399828428732433525161695266383663716191155877818018779534", // 需要您在Chainlink VRF网站上创建
        callbackGasLimit: "500000", // 500,000 gas
        interval: "30", // 30秒
    },
    31337: {
        name: "hardhat",
        entranceFee: ethers.parseEther("0.01"),
        gasLane: "0x474e34a077df58807dbe9c96d3c009b23b3c6d0cce433e59bbf5b34f823bc56c", // 不重要，因为我们使用模拟
        callbackGasLimit: "500000", // 500,000 gas
        interval: "30", // 30秒
    },
}

const developmentChains = ["hardhat", "localhost"]

module.exports = {
    networkConfig,
    developmentChains,
}