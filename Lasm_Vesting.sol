//SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract LasmVesting is ReentrancyGuard, Ownable {
    // Allocation distribution of the total supply.
    uint256 private constant E18                         = 10 ** 18;

    uint256 private constant LOCKED_ALLOCATION           = 160_000_000 * E18;
    uint256 private constant PUBLIC_SALE_ALLOCATION      =  56_000_000 * E18;
    uint256 private constant PRIVATE_SALE_ALLOCATION     =  12_000_000 * E18;
    uint256 private constant SEED_SALE_ALLOCATION        =  12_000_000 * E18;
    uint256 private constant TEAM_ALLOCATION             =  96_000_000 * E18;
    uint256 private constant PARTNERS_ALLOCATION         =  24_000_000 * E18;
    uint256 private constant MARKETING_ALLOCATION        =  40_000_000 * E18;
    uint256 private constant DEVELOPMENT_ALLOCATION      =  80_000_000 * E18;
    uint256 private constant STAKING_ALLOCATION          = 272_000_000 * E18;
    uint256 private constant AIRDROP_ALLOCATION          =  40_000_000 * E18;
    uint256 private constant NFT_AIRDROP_ALLOCATION      =   8_000_000 * E18;

    // vesting wallets
    address private constant lockedWallet            = address(0x0102aEa1a3D3F100bAd80feF23a2883a0C980833);
    address private constant managerWallet           = address(0x5e81892779c28617B066553d25499B9aD2630a47);
    address private constant teamWallet              = address(0xef08430d3e53198160D0cd33b0f84358291640bD);
    address private constant partnersWallet          = address(0xe5917b2686f9FA32cC88CF360bF03cCa1a223563);
    address private constant marketingWallet         = address(0xB2f33Cb375E21314A991f14c2d93570013E5a0a4);
    address private constant developmentWallet       = address(0x939Ad272c00efE7e4398b21b6Aa52A3a6B7BADbF);
    address private constant stakingRewardsWallet    = address(0x2Ad0ee5E02c7Be7701416925B72808df99D549ED);
    address private constant airdropWallet           = address(0xFA39969e9083e6Ddf1F18464573B9B5c002B6310);
    address private constant nftAirdropWallet        = address(0x18758Ea1A29e43A840DcB7EB3D9468294F7967dA);

    uint256 private constant VESTING_END_AT = 24 * 30 * 24 * 60 * 60;  // 24 months

    address public vestingToken;   // ERC20 token that get vested.

    event TokenSet(address vestingToken);
    event Claimed(address indexed beneficiary, uint256 amount);

    struct Schedule {
        // Name of the template
        string templateName;

        // Tokens that were already claimed
        uint256 claimedTokens;

        // Start time of the schedule
        uint256 startTime;

        // Total amount of tokens
        uint256 allocation;

        // Cliff of the schedule.
        uint256 cliff;

        // Last time of Claimed
        uint256 lastClaimTime;
    }

    struct ClaimedEvent {
        // Index of the schedule list
        uint8 scheduleIndex;

        // Tokens that were only unlocked in this event
        uint256 claimedTokens;

        // Tokens that were already unlocked
        uint256 unlockedTokens;

        // Tokens that are locked yet
        uint256 lockedTokens;

        // Time of the current event
        uint256 eventTime;
    }

    Schedule[] public schedules;
    ClaimedEvent[] public scheduleEvents;

    mapping (address => uint8[]) public schedulesByOwner;
    mapping (string => uint8) public schedulesByName;
    mapping (string => address) public beneficiary;

    mapping (address => uint8[]) public eventsByScheduleBeneficiary;
    mapping (string => uint8[]) public eventsByScheduleName;

    constructor() {
    }

    /**
     * @dev Allow owner to set the token address that get vested.
     * @param tokenAddress Address of the ERC-20 token.
     */
    function setToken(address tokenAddress) external onlyOwner {
        require(tokenAddress != address(0), "Vesting: ZERO_ADDRESS_NOT_ALLOWED");
        require(vestingToken == address(0), "Vesting: ALREADY_SET");

        vestingToken = tokenAddress;

        emit TokenSet(tokenAddress);
    }

    /**
     * @dev Allow owner to initiate the vesting schedule
     */
    function initVestingSchedule() public onlyOwner {
        // For Locked allocation
        _createSchedule(lockedWallet, Schedule({
            templateName         :  "Locked",
            claimedTokens        :  uint256(0),
            startTime            :  block.timestamp,
            allocation           :  LOCKED_ALLOCATION,
            cliff                :  62208000,     // 24 Months (24 * 30 * 24 * 60 * 60)
            lastClaimTime        :  0
        }));

        // For Public sale allocation
        _createSchedule(managerWallet, Schedule({
            templateName         :  "PublicSale",
            claimedTokens        :  uint256(0),
            startTime            :  block.timestamp,
            allocation           :  PUBLIC_SALE_ALLOCATION,
            cliff                :  0,            // 0 Month
            lastClaimTime        :  0
        }));

        // For Private sale allocation
        _createSchedule(managerWallet, Schedule({
            templateName         :  "PrivateSale",
            claimedTokens        :  uint256(0),
            startTime            :  block.timestamp,
            allocation           :  PRIVATE_SALE_ALLOCATION,
            cliff                :  0,            // 0 Month
            lastClaimTime        :  0
        }));

        // For Seed sale allocation
        _createSchedule(managerWallet, Schedule({
            templateName         :  "SeedSale",
            claimedTokens        :  uint256(0),
            startTime            :  block.timestamp,
            allocation           :  SEED_SALE_ALLOCATION,
            cliff                :  0,            // 0 Month
            lastClaimTime        :  0
        }));

        // For Team allocation
        _createSchedule(teamWallet, Schedule({
            templateName         :  "Team",
            claimedTokens        :  uint256(0),
            startTime            :  block.timestamp,
            allocation           :  TEAM_ALLOCATION,
            cliff                :  7776000,      //  3 Months ( 3 * 30 * 24 * 60 * 60)
            lastClaimTime        :  0
        }));

        // For Partners & Advisors allocation
        _createSchedule(partnersWallet, Schedule({
            templateName         :  "Partners",
            claimedTokens        :  uint256(0),
            startTime            :  block.timestamp,
            allocation           :  PARTNERS_ALLOCATION,
            cliff                :  15552000,     //  6 Months ( 6 * 30 * 24 * 60 * 60)
            lastClaimTime        :  0
        }));

        // For Marketing allocation
        _createSchedule(marketingWallet, Schedule({
            templateName         :  "Marketing",
            claimedTokens        :  uint256(0),
            startTime            :  block.timestamp,
            allocation           :  MARKETING_ALLOCATION,
            cliff                :  0,            //  0 Month
            lastClaimTime        :  0
        }));

        // For Development allocation
        _createSchedule(developmentWallet, Schedule({
            templateName         :  "Development",
            claimedTokens        :  uint256(0),
            startTime            :  block.timestamp,
            allocation           :  DEVELOPMENT_ALLOCATION,
            cliff                :  0,            //  0 Month
            lastClaimTime        :  0
        }));

        // For P2E & Staking rewards allocation
        _createSchedule(stakingRewardsWallet, Schedule({
            templateName         :  "Staking",
            claimedTokens        :  uint256(0),
            startTime            :  block.timestamp,
            allocation           :  STAKING_ALLOCATION,
            cliff                :   7776000,     //  3 Months ( 3 * 30 * 24 * 60 * 60)
            lastClaimTime        :  0
        }));

        // For Airdrop allocation
        _createSchedule(airdropWallet, Schedule({
            templateName         :  "Airdrop",
            claimedTokens        :  uint256(0),
            startTime            :  block.timestamp,
            allocation           :  AIRDROP_ALLOCATION,
            cliff                :  0,            //  0 Month
            lastClaimTime        :  0
        }));

        // For NFT Airdrop allocation
        _createSchedule(nftAirdropWallet, Schedule({
            templateName         :  "NFT_Airdrop",
            claimedTokens        :  uint256(0),
            startTime            :  block.timestamp,
            allocation           :  NFT_AIRDROP_ALLOCATION,
            cliff                :  0,            //  0 Month
            lastClaimTime        :  0
        }));
    }

    function _createSchedule(address _beneficiary, Schedule memory _schedule) internal {
        schedules.push(_schedule);

        uint8 index = uint8(schedules.length) - 1;

        schedulesByOwner[_beneficiary].push(index);
        schedulesByName[_schedule.templateName] = index;
        beneficiary[_schedule.templateName] = _beneficiary;
    }

    function createSchedule(address _beneficiary, string memory _templateName, uint256 _allocation, 
            uint256 _cliff) external onlyOwner {
        _createSchedule(_beneficiary, Schedule({
            templateName         :  _templateName,
            claimedTokens        :  uint256(0),
            startTime            :  block.timestamp,
            allocation           :  _allocation,
            cliff                :  _cliff,
            lastClaimTime        :  0
        }));
    }

    function updateSchedule(string memory _templateName, uint256 _allocation, 
            uint256 _cliff) external onlyOwner {
        uint index = schedulesByName[_templateName];
        require(index >= 0 && index < schedules.length, "Vesting: NOT_SCHEDULE");

        schedules[index].allocation = _allocation;
        schedules[index].cliff = _cliff;
    }

    /**
     * @dev Check the amount of claimable token of the beneficiary.
     */
    function pendingTokensByScheduleBeneficiary(address _account) public view returns (uint256) {
        uint8[] memory _indexs = schedulesByOwner[_account];
        require(_indexs.length != uint256(0), "Vesting: NOT_AUTORIZE");

        uint256 amount = 0;
        for (uint8 i = 0; i < _indexs.length; i++) {
            string memory _templateName = schedules[_indexs[i]].templateName;
            amount += pendingTokensByScheduleName(_templateName);
        }

        return amount;
    }

    /**
     * @dev Check the amount of claimable token of the schedule.
     */
    function pendingTokensByScheduleName(string memory _templateName) public view returns (uint256) {
        uint8 index = schedulesByName[_templateName];
        require(index >= 0 && index < schedules.length, "Vesting: NOT_SCHEDULE");

        Schedule memory schedule = schedules[index];

        if (
            schedule.startTime + schedule.cliff >= block.timestamp 
            || schedule.claimedTokens == schedule.allocation) {
            return 0;
        }
        else
            return schedule.allocation;
    }

    /**
     * @dev Allow the respective addresses claim the vested tokens.
     */
    function claimByScheduleBeneficiary() external nonReentrant {
        require(vestingToken != address(0), "Vesting: VESTINGTOKEN_NO__SET");

        uint8[] memory _indexs = schedulesByOwner[msg.sender];
        require(_indexs.length != uint256(0), "Vesting: NOT_AUTORIZE");

        uint256 amount = 0;
        uint8 index;
        for (uint8 i = 0; i < _indexs.length; i++) {
            index = _indexs[i];

            string memory _templateName = schedules[index].templateName;
            uint256 claimAmount = pendingTokensByScheduleName(_templateName);

            if (claimAmount == 0)
                continue;

            schedules[index].claimedTokens += claimAmount;
            schedules[index].lastClaimTime = block.timestamp;
            amount += claimAmount;

            registerEvent(msg.sender, index, claimAmount);
        }

        require(amount > uint256(0), "Vesting: NO_VESTED_TOKENS");

        SafeERC20.safeTransfer(IERC20(vestingToken), msg.sender, amount);

        emit Claimed(msg.sender, amount);
    }

    /**
     * @dev Allow the respective addresses claim the vested tokens of the schedule.
     */
    function claimByScheduleName(string memory _templateName) external nonReentrant {
        require(vestingToken != address(0), "Vesting: VESTINGTOKEN_NO__SET");

        uint8 index = schedulesByName[_templateName];
        require(index >= 0 && index < schedules.length, "Vesting: NOT_SCHEDULE");
        require(beneficiary[_templateName] == msg.sender, "Vesting: NOT_AUTORIZE");

        uint256 claimAmount = pendingTokensByScheduleName(_templateName);

        require(claimAmount > uint256(0), "Vesting: NO_VESTED_TOKENS");

        schedules[index].claimedTokens += claimAmount;
        schedules[index].lastClaimTime = block.timestamp;

        SafeERC20.safeTransfer(IERC20(vestingToken), msg.sender, claimAmount);

        registerEvent(msg.sender, index, claimAmount);

        emit Claimed(beneficiary[_templateName], claimAmount);
    }

    function registerEvent(address _account, uint8 _scheduleIndex, uint256 _claimedTokens) internal {
        Schedule memory schedule = schedules[_scheduleIndex];

        scheduleEvents.push(ClaimedEvent({
            scheduleIndex: _scheduleIndex,
            claimedTokens: _claimedTokens,
            unlockedTokens: schedule.claimedTokens,
            lockedTokens: schedule.allocation - schedule.claimedTokens,
            eventTime: schedule.lastClaimTime
        }));

        eventsByScheduleBeneficiary[_account].push(uint8(scheduleEvents.length) - 1);
        eventsByScheduleName[schedule.templateName].push(uint8(scheduleEvents.length) - 1);
    }

    /**
     * @dev Allow owner to withdraw the token from the contract.
     * @param amount       Amount of token that get skimmed out of the contract.
     * @param destination  Whom token amount get transferred to.
     */
    function withdraw(uint256 amount, address destination) external onlyOwner {
        require(vestingToken != address(0), "Vesting: VESTINGTOKEN_NO__SET");
        require(block.timestamp > VESTING_END_AT, "Vesting: NOT_ALLOWED");
        require(destination != address(0),        "Vesting: ZERO_ADDRESS_NOT_ALLOWED");
        require(amount <= IERC20(vestingToken).balanceOf(address(this)), "Insufficient balance");

        SafeERC20.safeTransfer(IERC20(vestingToken), destination, amount);
    }
}