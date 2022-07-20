//SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/interfaces/IERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "hardhat/console.sol";

contract LasmStaking is Ownable,ReentrancyGuard{

    IERC20 Token;

    uint public rewardTokenSupply;
    uint public totalStakedToken;

    struct info{
        uint amount;
        uint lastClaim;
        uint stakeTime;
        uint durationCode;
        uint position;
        uint earned;
    }

    uint[4] public durations = [30 days, 180 days, 365 days, 730 days];
    uint[4] public rates = [1, 7, 15, 32];

    mapping(address=>mapping(uint=>info)) public userStaked; //USER > ID > INFO
    mapping(address=>uint) public userId;
    mapping(address=>uint) public userTotalEarnedReward;
    mapping(address=>uint) public userTotalStaked;
    mapping(address=>uint[]) public stakedIds;

    bool public paused;

    event StakeAdded(
        address indexed _usr,
        uint _amount,
        uint startStakingTime,
        uint8 _durationCode,
        uint _stakedIndex
    );
    event Unstaked(address indexed _usr, uint _stakeIndex);
    event ClaimReward(address indexed _from, uint _claimedTime, uint _stakeIndex);
    event ClaimRewardAll(address indexed _from, uint _claimedTime, uint _amount);
    event Paused();
    event Unpaused();
    event RewardTokenRewardAdded(address indexed _from, uint256 _amount);
    event RewardTokenRewardRemoved(address indexed _to, uint256 _amount);
    event UpdateDuration(address indexed _from);
    event UpdateRate(address indexed _from);

    constructor(address _token) {
        Token = IERC20(_token);
    }

    function addStakedTokenReward(uint256 _amount)
        external
        onlyOwner
    {
        //transfer from (need allowance)
        rewardTokenSupply += _amount;

        Token.transferFrom(msg.sender, address(this), _amount);

        emit RewardTokenRewardAdded(msg.sender, _amount);
    }

    function removeStakedTokenReward(uint256 _amount)
        external
        onlyOwner
    {
        require(_amount <= rewardTokenSupply, "you cannot withdraw this amount");
        rewardTokenSupply -= _amount;

        Token.transfer(msg.sender, _amount);
        emit RewardTokenRewardRemoved(msg.sender, _amount);
    }

    function updateDuration(uint[4] memory _durations) external onlyOwner {
        durations = _durations;
        emit UpdateDuration(msg.sender);
    }

    function updateRate(uint[4] memory _rates) external onlyOwner {
        rates = _rates;
        emit UpdateRate(msg.sender);
    }

    function stake(uint _amount, uint8 _durationCode) external {
        require(!paused,"Execution paused");
        require(_durationCode < 4,"Invalid duration");

        userId[msg.sender]++;
        userStaked[msg.sender][userId[msg.sender]] = info(_amount, block.timestamp, block.timestamp,
                                                _durationCode, stakedIds[msg.sender].length, 0);

        stakedIds[msg.sender].push(userId[msg.sender]);

        require(Token.transferFrom(msg.sender, address(this), _amount), "Amount not sent");

        totalStakedToken += _amount;
        userTotalStaked[msg.sender] += _amount;
        emit StakeAdded(
            msg.sender,
            _amount,
            block.timestamp,
            _durationCode,
            stakedIds[msg.sender].length - 1
        );
    }

    function getReward(address _user, uint _id) public view returns(uint) {
        info storage userInfo = userStaked[_user][_id];
        uint timeDiff = block.timestamp - userInfo.lastClaim;

        uint reward = userInfo.amount * timeDiff * rates[userInfo.durationCode] / 
                        (durations[userInfo.durationCode] * 100);

        return reward;
    }

    function getAllReward(address _user) public view returns(uint) {
        uint amount = 0;
        uint length = stakedIds[_user].length;
        for(uint i=0; i<length; i++){
            info storage userInfo = userStaked[_user][stakedIds[_user][i]];
            if (userInfo.amount == 0)
                continue;

            uint amountIndex = getReward(_user, stakedIds[_user][i]);
            amount += amountIndex;
        }

        return amount;
    }

    function getStakedInfo(address _user) public view 
        returns (info[] memory infors, uint[] memory claimable, uint[] memory pending) {
        uint length = stakedIds[_user].length;
        infors = new info[](length);
        claimable = new uint[](length);
        pending = new uint[](length);

        for(uint i=0; i<length; i++){
            info storage userInfo = userStaked[_user][stakedIds[_user][i]];
            infors[i] = userInfo;
            pending[i] = getReward(_user, stakedIds[_user][i]);
            claimable[i] = claimableReward(_user, stakedIds[_user][i]);
        }
    }

    function claimableReward(address _user, uint _id) public view returns(uint) {
        info storage userInfo = userStaked[_user][_id];

        if (block.timestamp - userInfo.stakeTime < durations[userInfo.durationCode])
            return 0;

        return getReward(_user, _id);
    }

    function claimableAllReward(address _user) public view returns(uint) {
        uint amount = 0;
        uint length = stakedIds[_user].length;
        for(uint i=0; i<length; i++){
            info storage userInfo = userStaked[_user][stakedIds[_user][i]];
            if (userInfo.amount == 0)
                continue;

            if (block.timestamp - userInfo.stakeTime < durations[userInfo.durationCode])
                continue;

            uint amountIndex = getReward(_user, stakedIds[_user][i]);
            amount += amountIndex;
        }

        return amount;
    }

    function claimReward(uint _id) public nonReentrant {
        info storage userInfo = userStaked[msg.sender][_id];
        require (block.timestamp - userInfo.stakeTime >= durations[userInfo.durationCode], 
            "Not claim yet, Locked period still.");

        claim(_id);

        emit ClaimReward(msg.sender, block.timestamp, _id);
    }

    function claim(uint _id) private {
        uint amount = 0;
        require(userStaked[msg.sender][_id].amount != 0, "Invalid ID");

        amount = getReward(msg.sender, _id);
        require(
            Token.balanceOf(address(this)) >= amount,
            "Insufficient token to pay your reward right now"
        );

        Token.transfer(msg.sender, amount);

        info storage userInfo = userStaked[msg.sender][_id];
        userInfo.lastClaim = block.timestamp;
        userInfo.earned += amount;

        userTotalEarnedReward[msg.sender] += amount;
        rewardTokenSupply -= amount;
    }

    function claimAllReward() public nonReentrant {
        uint amount = 0;
        uint length = stakedIds[msg.sender].length;
        for(uint i=0; i<length; i++){
            info storage userInfo = userStaked[msg.sender][stakedIds[msg.sender][i]];
            if (userInfo.amount == 0)
                continue;

            if (block.timestamp - userInfo.stakeTime < durations[userInfo.durationCode])
                continue;

            uint amountIndex = getReward(msg.sender, stakedIds[msg.sender][i]);
            if (amountIndex == 0)
                continue;

            userInfo.lastClaim = block.timestamp;
            userInfo.earned += amountIndex;
            amount += amountIndex;
        }

        Token.transfer(msg.sender, amount);
        rewardTokenSupply -= amount;
        userTotalEarnedReward[msg.sender] += amount;

        emit ClaimRewardAll(msg.sender, block.timestamp, amount);
    }

    function unstake(uint _amount, uint _id) external nonReentrant{
        claim(_id);

        info storage userInfo = userStaked[msg.sender][_id];
        require(userInfo.amount != 0 && _amount <= userInfo.amount ,"Invalid ID");
        require(block.timestamp - userInfo.stakeTime >= durations[userInfo.durationCode], "Not unlocked yet");

        if (_amount == userInfo.amount) {
            popSlot(_id);

            delete userStaked[msg.sender][_id];
        }
        else
            userInfo.amount -= _amount;

        require(
            Token.balanceOf(address(this)) >= _amount,
            "Insufficient token to unstake right now"
        );

        Token.transfer(msg.sender, _amount);

        totalStakedToken -= _amount;
        userTotalStaked[msg.sender] -= _amount;

        emit Unstaked(msg.sender, _id);
    }

    function unstake(uint _id) external nonReentrant{
        claim(_id);

        info storage userInfo = userStaked[msg.sender][_id];
        require(userInfo.amount != 0,"Invalid ID");
        require(block.timestamp - userInfo.stakeTime >= durations[userInfo.durationCode], "Not unlocked yet");

        require(
            Token.balanceOf(address(this)) >= userInfo.amount,
            "Insufficient token to unstake right now"
        );

        Token.transfer(msg.sender, userInfo.amount);

        popSlot(_id);
        delete userStaked[msg.sender][_id];

        totalStakedToken -= userInfo.amount;
        userTotalStaked[msg.sender] -= userInfo.amount;

        emit Unstaked(msg.sender, _id);
    }

    function popSlot(uint _id) internal {
        uint length = stakedIds[msg.sender].length;
        bool replace = false;
        for (uint256 i=0; i<length; i++) {
            if (stakedIds[msg.sender][i] == _id)
                replace = true;
            if (replace && i<length-1)
                stakedIds[msg.sender][i] = stakedIds[msg.sender][i+1];
        }
        stakedIds[msg.sender].pop();
    }

    function setToken(address _token) external onlyOwner{
        Token = IERC20(_token);
    }

    function Pause() external onlyOwner {
        paused = true;
        emit Paused();
    }

    function unpause() external onlyOwner {
        paused = false;
        emit Unpaused();
    }
}