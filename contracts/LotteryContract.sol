// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {VRFConsumerBaseV2Plus} from "@chainlink/contracts/src/v0.8/vrf/dev/VRFConsumerBaseV2Plus.sol";
import {VRFV2PlusClient} from "@chainlink/contracts/src/v0.8/vrf/dev/libraries/VRFV2PlusClient.sol";
// 移除 Ownable 导入，因为 VRFConsumerBaseV2Plus 已经包含了所有权功能
// import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title 基于Chainlink VRF的抽奖合约
 * @notice 这个合约使用Chainlink VRF来生成可验证的随机数，用于公平地选择抽奖获胜者
 * @dev 基于Chainlink VRF V2.5+实现
 */
contract LotteryContract is VRFConsumerBaseV2Plus {
    // 抽奖相关事件
    event LotteryStarted(uint256 lotteryId, uint256 startTime, uint256 endTime, uint256 entryFee);
    event PlayerJoined(uint256 lotteryId, address player);
    event RequestedRandomness(uint256 lotteryId, uint256 requestId);
    event WinnerSelected(uint256 lotteryId, address winner, uint256 prize);
    
    // VRF相关事件
    event RequestSent(uint256 requestId, uint32 numWords);
    event RequestFulfilled(uint256 requestId, uint256[] randomWords);

    // 抽奖状态枚举
    enum LotteryState {
        CLOSED,     // 抽奖未开始
        OPEN,       // 抽奖开放中
        CALCULATING // 正在计算结果
    }

    // 抽奖信息结构
    struct Lottery {
        uint256 lotteryId;      // 抽奖ID
        uint256 startTime;      // 开始时间
        uint256 endTime;        // 结束时间
        uint256 entryFee;       // 参与费用
        address[] players;      // 参与者列表
        address winner;         // 获胜者
        LotteryState state;     // 抽奖状态
        uint256 prize;          // 奖池金额
    }

    // VRF请求状态结构
    struct RequestStatus {
        bool fulfilled;         // 请求是否已完成
        bool exists;            // 请求ID是否存在
        uint256[] randomWords;  // 随机数结果
        uint256 lotteryId;      // 关联的抽奖ID
    }

    // 抽奖ID到抽奖信息的映射
    mapping(uint256 => Lottery) public lotteries;
    // 请求ID到请求状态的映射
    mapping(uint256 => RequestStatus) public s_requests;
    // 当前抽奖ID
    uint256 public currentLotteryId;
    // Chainlink VRF订阅ID
    uint256 public s_subscriptionId;
    // 过去的请求ID列表
    uint256[] public requestIds;
    // 最近的请求ID
    uint256 public lastRequestId;

    // Chainlink VRF配置参数
    // Sepolia测试网的gas lane
    bytes32 public keyHash;
    uint32 public callbackGasLimit = 200000; // 回调函数的gas限制
    uint16 public requestConfirmations = 3;  // 请求确认数
    uint32 public numWords = 1;              // 请求的随机数数量

    /**
     * @notice 构造函数
     * @param subscriptionId Chainlink VRF订阅ID
     * @param vrfCoordinator VRF协调器地址
     * @param _keyHash VRF keyHash
     */
    constructor(
        uint256 subscriptionId,
        address vrfCoordinator,
        bytes32 _keyHash
    ) VRFConsumerBaseV2Plus(vrfCoordinator) {
        s_subscriptionId = subscriptionId;
        keyHash = _keyHash;
    }

    /**
     * @notice 开始一个新的抽奖
     * @param _duration 抽奖持续时间（秒）
     * @param _entryFee 参与费用（wei）
     */
    function startLottery(uint256 _duration, uint256 _entryFee) external onlyOwner {
        require(_duration > 0, unicode"持续时间必须大于0");
        require(_entryFee >= 0, unicode"参与费用不能为负数");
        
        // 确保没有正在进行的抽奖
        if (currentLotteryId > 0) {
            Lottery storage lastLottery = lotteries[currentLotteryId];
            require(lastLottery.state != LotteryState.OPEN, unicode"已有抽奖正在进行");
        }
        
        currentLotteryId++;
        uint256 startTime = block.timestamp;
        uint256 endTime = startTime + _duration;
        
        lotteries[currentLotteryId] = Lottery({
            lotteryId: currentLotteryId,
            startTime: startTime,
            endTime: endTime,
            entryFee: _entryFee,
            players: new address[](0),
            winner: address(0),
            state: LotteryState.OPEN,
            prize: 0
        });
        
        emit LotteryStarted(currentLotteryId, startTime, endTime, _entryFee);
    }

    /**
     * @notice 参与抽奖
     * @dev 用户需要支付参与费用
     */
    function enterLottery() external payable {
        require(currentLotteryId > 0, unicode"没有正在进行的抽奖");
        
        Lottery storage lottery = lotteries[currentLotteryId];
        
        require(lottery.state == LotteryState.OPEN, unicode"抽奖未开放");
        require(block.timestamp < lottery.endTime, unicode"抽奖已结束");
        require(msg.value == lottery.entryFee, unicode"参与费用不正确");
        
        lottery.players.push(msg.sender);
        lottery.prize += msg.value;
        
        emit PlayerJoined(currentLotteryId, msg.sender);
    }

    /**
     * @notice 结束抽奖并请求随机数
     * @param enableNativePayment 是否使用原生代币支付VRF费用
     */
    function endLottery(bool enableNativePayment) external onlyOwner {
        require(currentLotteryId > 0, unicode"没有抽奖可以结束");
        
        Lottery storage lottery = lotteries[currentLotteryId];
        
        require(lottery.state == LotteryState.OPEN, unicode"抽奖未开放");
        require(
            block.timestamp >= lottery.endTime || 
            msg.sender == owner(), 
            unicode"抽奖尚未结束或非所有者调用"
        );
        require(lottery.players.length > 0, unicode"没有参与者");
        
        lottery.state = LotteryState.CALCULATING;
        
        // 请求随机数
        uint256 requestId = requestRandomWords(enableNativePayment, currentLotteryId);
        emit RequestedRandomness(currentLotteryId, requestId);
    }

    /**
     * @notice 请求随机数
     * @param enableNativePayment 是否使用原生代币支付VRF费用
     * @param lotteryId 关联的抽奖ID
     * @return requestId 请求ID
     */
    function requestRandomWords(
        bool enableNativePayment,
        uint256 lotteryId
    ) internal returns (uint256 requestId) {
        // 请求随机数
        requestId = s_vrfCoordinator.requestRandomWords(
            VRFV2PlusClient.RandomWordsRequest({
                keyHash: keyHash,
                subId: s_subscriptionId,
                requestConfirmations: requestConfirmations,
                callbackGasLimit: callbackGasLimit,
                numWords: numWords,
                extraArgs: VRFV2PlusClient._argsToBytes(
                    VRFV2PlusClient.ExtraArgsV1({
                        nativePayment: enableNativePayment
                    })
                )
            })
        );
        
        s_requests[requestId] = RequestStatus({
            randomWords: new uint256[](0),
            exists: true,
            fulfilled: false,
            lotteryId: lotteryId
        });
        
        requestIds.push(requestId);
        lastRequestId = requestId;
        
        emit RequestSent(requestId, numWords);
        return requestId;
    }

    /**
     * @notice 处理随机数回调
     * @param _requestId 请求ID
     * @param _randomWords 随机数数组
     */
    function fulfillRandomWords(
        uint256 _requestId,
        uint256[] calldata _randomWords
    ) internal override {
        require(s_requests[_requestId].exists, unicode"请求不存在");
        
        s_requests[_requestId].fulfilled = true;
        s_requests[_requestId].randomWords = _randomWords;
        
        uint256 lotteryId = s_requests[_requestId].lotteryId;
        Lottery storage lottery = lotteries[lotteryId];
        
        // 确保抽奖状态正确
        require(lottery.state == LotteryState.CALCULATING, unicode"抽奖状态错误");
        
        // 选择获胜者
        uint256 winnerIndex = _randomWords[0] % lottery.players.length;
        address winner = lottery.players[winnerIndex];
        
        // 更新抽奖信息
        lottery.winner = winner;
        lottery.state = LotteryState.CLOSED;
        
        // 发送奖金
        uint256 prize = lottery.prize;
        (bool success, ) = winner.call{value: prize}("");
        require(success, unicode"奖金发送失败");
        
        emit WinnerSelected(lotteryId, winner, prize);
        emit RequestFulfilled(_requestId, _randomWords);
    }

    /**
     * @notice 获取抽奖信息
     * @param _lotteryId 抽奖ID
     * @return lotteryId 抽奖ID
     * @return startTime 开始时间
     * @return endTime 结束时间
     * @return entryFee 参与费用
     * @return players 参与者列表
     * @return winner 获胜者
     * @return state 抽奖状态
     * @return prize 奖池金额
     */
    function getLottery(uint256 _lotteryId) external view returns (
        uint256 lotteryId,
        uint256 startTime,
        uint256 endTime,
        uint256 entryFee,
        address[] memory players,
        address winner,
        LotteryState state,
        uint256 prize
    ) {
        require(_lotteryId > 0 && _lotteryId <= currentLotteryId, unicode"抽奖ID无效");
        
        Lottery storage lottery = lotteries[_lotteryId];
        
        return (
            lottery.lotteryId,
            lottery.startTime,
            lottery.endTime,
            lottery.entryFee,
            lottery.players,
            lottery.winner,
            lottery.state,
            lottery.prize
        );
    }

    /**
     * @notice 获取当前抽奖的参与者数量
     * @return 参与者数量
     */
    function getCurrentPlayersCount() external view returns (uint256) {
        if (currentLotteryId == 0) return 0;
        return lotteries[currentLotteryId].players.length;
    }

    /**
     * @notice 获取随机数请求状态
     * @param _requestId 请求ID
     * @return fulfilled 是否已完成
     * @return randomWords 随机数数组
     */
    function getRequestStatus(
        uint256 _requestId
    ) external view returns (bool fulfilled, uint256[] memory randomWords) {
        require(s_requests[_requestId].exists, unicode"请求不存在");
        RequestStatus memory request = s_requests[_requestId];
        return (request.fulfilled, request.randomWords);
    }
}