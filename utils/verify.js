const { run } = require("hardhat")

const verify = async (contractAddress, args) => {
    console.log("验证合约...")
    try {
        await run("verify:verify", {
            address: contractAddress,
            constructorArguments: args,
        })
    } catch (e) {
        if (e.message.toLowerCase().includes("already verified")) {
            console.log("合约已经验证过")
        } else {
            console.log(e)
        }
    }
}

module.exports = { verify }