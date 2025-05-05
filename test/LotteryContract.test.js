const { expect } = require("chai");
const { ethers } = require("hardhat");

describe("LotteryContract", function () {
  let LotteryContract, lottery, owner, addr1, addr2, addr3;

  // mock VRFCoordinator address & keyHash
  const mockVrfCoordinator = "0x0000000000000000000000000000000000000001";
  const mockKeyHash = "0x6c3699283bda56ad74f6b855546325b68d482e983852a7a82979cc4807b641f4";
  const mockSubscriptionId = 1;

  beforeEach(async function () {
    [owner, addr1, addr2, addr3] = await ethers.getSigners();
    LotteryContract = await ethers.getContractFactory("LotteryContract");
    lottery = await LotteryContract.deploy(
      mockSubscriptionId,
      mockVrfCoordinator,
      mockKeyHash
    );
    await lottery.waitForDeployment();
  });

  it("部署后初始状态应正确", async function () {
    expect(await lottery.currentLotteryId()).to.equal(0);
  });

  it("只有owner可以开启抽奖", async function () {
    await expect(
      lottery.connect(addr1).startLottery(60, ethers.parseEther("0.01"))
    ).to.be.revertedWith("Only callable by owner");
    await expect(
      lottery.startLottery(60, ethers.parseEther("0.01"))
    ).to.emit(lottery, "LotteryStarted");
    expect(await lottery.currentLotteryId()).to.equal(1);
  });

  it("参与抽奖需要正确的费用", async function () {
    await lottery.startLottery(60, ethers.parseEther("0.01"));
    await expect(
      lottery.connect(addr1).enterLottery({ value: ethers.parseEther("0.02") })
    ).to.be.revertedWith("参与费用不正确");
    await expect(
      lottery.connect(addr1).enterLottery({ value: ethers.parseEther("0.01") })
    ).to.emit(lottery, "PlayerJoined");
    const playersCount = await lottery.getCurrentPlayersCount();
    expect(playersCount).to.equal(1);
  });

  it("不能重复开启抽奖", async function () {
    await lottery.startLottery(60, ethers.parseEther("0.01"));
    await expect(
      lottery.startLottery(60, ethers.parseEther("0.01"))
    ).to.be.revertedWith("已有抽奖正在进行");
  });

  it("抽奖结束时必须有参与者", async function () {
    await lottery.startLottery(60, ethers.parseEther("0.01"));
    await expect(
      lottery.endLottery(false)
    ).to.be.revertedWith("没有参与者");
  });

//   it("抽奖流程：开启、参与、结束", async function () {
//     // 设置更长的时间窗口（1小时）以避免时间敏感性问题
//     await lottery.startLottery(3600, ethers.parseEther("0.01"));
    
//     // 参与者加入
//     await lottery.connect(addr1).enterLottery({ value: ethers.parseEther("0.01") });
//     await lottery.connect(addr2).enterLottery({ value: ethers.parseEther("0.01") });

//     // 结束抽奖（不需要快进时间）
//     await expect(lottery.endLottery(false))
//       .to.emit(lottery, "RequestedRandomness");
    
//     // 验证状态转换
//     const lotteryInfo = await lottery.getLottery(1);
//     expect(lotteryInfo.state).to.equal(2); // CALCULATING

//     // 验证结束后参与（此时应该因为状态不是OPEN而失败）
//     await expect(
//       lottery.connect(addr3).enterLottery({ value: ethers.parseEther("0.01") })
//     ).to.be.revertedWith("抽奖未开放");
//   });

  // 由于 fulfillRandomWords 只能由VRF Coordinator调用，且需要mock，实际链上测试
  // 这里只做接口存在性和状态变更的逻辑测试
});