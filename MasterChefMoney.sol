/*

    http://moneytime.finance/

    https://t.me/moneytimefinance

*/
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;


pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;
import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "./libs/ReentrancyGuard.sol";
import './libs/AddrArrayLib.sol';
import "./MoneyToken.sol";

// MasterChef is the master of money. He can make money and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once money is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChefMoney is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using AddrArrayLib for AddrArrayLib.Addresses;

    // Info of each user.
    struct UserInfo {
        uint256 amount; // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        uint256 busdRewardDebt; // Reward debt. See explanation below.
        uint256 lastDepositTime;
        uint256 moneyRewardLockedUp;
        uint256 busdRewardLockedUp;
        //
        // We do some fancy math here. Basically, any point in time, the amount of moneys
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accMoneyPerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accMoneyPerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken; // Address of LP token contract.
        uint256 allocPoint; // How many allocation points assigned to this pool. moneys to distribute per block.
        uint256 lastRewardBlock; // Last block number that moneys distribution occurs.
        uint256 accMoneyPerShare; // Accumulated moneys per share, times 1e12. See below.
        uint256 accBusdPerShare; // Accumulated moneys per share, times 1e12. See below.
        uint256 burnRate; // Burn rate when unstake. ex: WHEN UNSTAKE  95% of THE $TIME TOKEN STAKED ARE BURNED AUTOMATICALY
        uint256 emergencyBurnRate; // Burn rate when emergencyWithdraw. ex: IF UNSTAKE BEFORE 2 WEEK THE USER GET NO REWARD AND 25% OF THE $TIME TOKEN STAKED ARE BURN WHEN UNSTAKE
        uint256 lockPeriod; // Staking lock period. ex: POOL 5 REWARD LOCKED: 2 WEEK
        uint256 depositFee; // deposit fee.
        bool depositBurn;
        bool secondaryReward;
    }

    // The money TOKEN!
    // AUDIT: MCM-06 | Set immutable to Variables
    MoneyToken public immutable money;
    // Busd token
    // AUDIT: MCM-06 | Set immutable to Variables
    IBEP20 public immutable busdToken;
    // Dev address.
    address public devaddr;

    // Busd Feeder
    address public busdFeeder1;
    address public busdFeeder2;
    // Max percent with 2 decimal -> 10000 = 100%
    // AUDIT: MCM-02 | Set constant to Variables
    uint256 public constant maxShare = 10000;
    // money tokens created per block.
    uint256 public moneyPerBlock;
    // busd tokens created per block.
    uint256 public busdPerBlock;
    // Bonus muliplier for early money makers.
    // AUDIT: MCM-12 | Incorrect Naming Convention Utilization
    uint256 public bonusMultiplier = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping(uint256 => mapping(address => UserInfo)) public userInfo;
    mapping(uint256 => AddrArrayLib.Addresses) private addressByPid;
    mapping(uint256 => uint[]) public userIndexByPid;

    mapping (address => bool) private _authorizedCaller;

    // Total deposit amount of each pool
    mapping(uint256 => uint256) public poolDeposit;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalBusdAllocPoint = 0;

    // The block number when money mining starts.
    // AUDIT: MCM-06 | Set immutable to Variables
    uint256 public immutable startBlock;

    uint256 public busdEndBlock;

    uint256 public constant busdPoolId = 0;

    // AUDIT: MCM-02 | Set constant to Variables
    address public constant BURN_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event Burn(address indexed user, uint256 indexed pid, uint256 sent, uint256 burned);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);
    // AUDIT: MCM-03 | Missing indexed in Events
    event Transfer(address indexed to, uint256 requsted, uint256 sent);
    event MoneyPerBlockUpdated(uint256 moneyPerBlock);
    event BusdPerBlockUpdated(uint256 busdPerBlock);
    // AUDIT: MCM-03 | Missing indexed in Events
    event UpdateEmissionSettings(address indexed from, uint256 depositAmount, uint256 endBlock);
    // AUDIT: MCM-08 | Missing Emit Events
    event UpdateMultiplier(uint256 multiplierNumber);
    event SetDev(address indexed prevDev, address indexed newDev);
    event SetAuthorizedCaller(address indexed caller, bool _status);
    event SetBusdFeeder1(address indexed busdFeeder);
    event SetBusdFeeder2(address indexed busdFeeder);
    event RewardLockedUp(address indexed recipient, uint256 indexed pid, uint256 moneyLockedUp, uint256 busdLockedUp);

    modifier onlyAuthorizedCaller() {
        require(_msgSender() == owner() || _authorizedCaller[_msgSender()],"MINT_CALLER_NOT_AUTHORIZED");
        _;
    }

    modifier validatePoolByPid(uint256 _pid) {
        require(_pid < poolInfo.length, "pool id not exisit");
        _;
    }

    constructor(
        MoneyToken _money,
        IBEP20 _busdToken,
        address _devaddr,
        address _busdFeeder1,
        address _busdFeeder2,
        uint256 _moneyPerBlock,
        uint256 _busdPerBlock, //should be 0
        uint256 _startBlock,
        uint256 _busdEndBlock //should be 0
    ) public {
        require(address(_money) != address(0), "MasterChefMoney.Constructor: Money token shouldn't be zero address");
        require(address(_busdToken) != address(0), "MasterChefMoney.Constructor: Busd token shouldn't be zero address");
        require(_devaddr != address(0), "MasterChefMoney.Constructor: Dev address shouldn't be zero address");
        require(_busdFeeder1 != address(0), "MasterChefMoney.Constructor: Busd feeder 1 address shouldn't be zero address");
        require(_busdFeeder2 != address(0), "MasterChefMoney.Constructor: Busd feeder 2 address shouldn't be zero address");
        require(_moneyPerBlock != 0, "MasterChefMoney.Constructor: Money reward token count per block can't be zero");

        money = _money;
        busdToken = _busdToken;
        devaddr = _devaddr;
        busdFeeder1 = _busdFeeder1;
        busdFeeder2 = _busdFeeder2;
        moneyPerBlock = _moneyPerBlock;
        busdPerBlock = _busdPerBlock;
        startBlock = _startBlock;
        busdEndBlock = _busdEndBlock;
        _authorizedCaller[busdFeeder1] = true; // tester: to allow call to updateEmissionSettings
        _authorizedCaller[busdFeeder2] = true; // tester: to allow call to updateEmissionSettings
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    //update money reward count per block
    function updateMoneyPerBlock(uint256 _moneyPerBlock) external onlyOwner {
        require(_moneyPerBlock != 0, "MasterChefMoney.updateMoneyPerBlock: Reward token count per block can't be zero");
        moneyPerBlock = _moneyPerBlock;
        // emitts event when moneyPerBlock updated
        emit MoneyPerBlockUpdated(_moneyPerBlock);
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    //update busd reward count per block
    function updateBusdPerBlock(uint256 _busdPerBlock) external onlyOwner {
        require(_busdPerBlock != 0, "MasterChefMoney.updateBusdPerBlock: Reward token count per block can't be zero");
        busdPerBlock = _busdPerBlock;
        // emitts event when busdPerBlock updated
        emit BusdPerBlockUpdated(_busdPerBlock);
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    function updateMultiplier(uint256 multiplierNumber) external onlyOwner {
        bonusMultiplier = multiplierNumber;
        // AUDIT: MCM-08 | Missing Emit Events
        emit UpdateMultiplier(multiplierNumber);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    // Add a new lp to the pool. Can only be called by the owner.
    function add (
        uint256 _allocPoint,
        IBEP20 _lpToken,
        uint256 _burnRate,
        uint256 _emergencyBurnRate,
        uint256 _lockPeriod,
        uint256 _depositFee,
        bool _depositBurn,
        bool _secondaryReward,
        bool _withUpdate
    ) external onlyOwner {
        // AUDIT: MCM-21 | The Logic Issue of add()
        if( poolInfo.length == 0 ) {
            require ( busdToken == _lpToken, "add: first pool should be busd pool") ;
        } else {
            require(busdToken != _lpToken,"busd pool already added" );
        }

        require(_depositFee <= 1000, "add: invalid deposit fee basis points");
        require(_burnRate <= 10000, "add: invalid deposit fee basis points");
        require(_emergencyBurnRate <= 2500, "add: invalid emergency brun rate basis points");
        require(_lockPeriod <= 30 days, "add: invalid lock period");

        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock =
        block.number > startBlock ? block.number : startBlock;

        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        if(_secondaryReward) {
            totalBusdAllocPoint = totalBusdAllocPoint.add(_allocPoint);
        }
        poolInfo.push(
            PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accMoneyPerShare: 0,
        accBusdPerShare: 0,
        burnRate: _burnRate,
        emergencyBurnRate: _emergencyBurnRate,
        lockPeriod: _lockPeriod,
        depositFee: _depositFee,
        depositBurn: _depositBurn,
        secondaryReward: _secondaryReward
        })
        );
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    // AUDIT: MCM-04 | Lack of Pool Validity Checks
    // Update the given pool's money allocation point. Can only be called by the owner.
    function set(
        uint256 _pid,
        uint256 _allocPoint,
        uint256 _burnRate,
        uint256 _emergencyBurnRate,
        uint256 _lockPeriod,
        uint256 _depositFee,
        bool _depositBurn,
        bool _secondaryReward,
        bool _withUpdate
    ) external onlyOwner validatePoolByPid(_pid){
        require(_depositFee <= 1000, "set: invalid deposit fee basis points");
        require(_burnRate <= 10000, "set: invalid deposit fee basis points");
        require(_emergencyBurnRate <= 2500, "set: invalid emergency brun rate basis points");
        require(_lockPeriod <= 30 days, "set: invalid lock period");

        if (_withUpdate) {
            massUpdatePools();
        }

        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].burnRate = _burnRate;
        poolInfo[_pid].emergencyBurnRate = _emergencyBurnRate;
        poolInfo[_pid].lockPeriod = _lockPeriod;
        poolInfo[_pid].depositFee = _depositFee;
        poolInfo[_pid].depositBurn = _depositBurn;


        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(
                _allocPoint
            );
        }
        if(_secondaryReward) {
            totalBusdAllocPoint = totalBusdAllocPoint.add(_allocPoint);
        }
        if(poolInfo[_pid].secondaryReward) {
            totalBusdAllocPoint = totalBusdAllocPoint.sub(prevAllocPoint);
        }
        poolInfo[_pid].secondaryReward = _secondaryReward;
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to)
    public
    view
    returns (uint256)
    {
        return _to.sub(_from).mul(bonusMultiplier);
    }

    // Return reward multiplier over the given _from to _to block.
    function getBusdMultiplier(uint256 _from, uint256 _to)
    public
    view
    returns (uint256)
    {
        if (_to <= busdEndBlock) {
            return _to.sub(_from).mul(bonusMultiplier);
        } else if (_from >= busdEndBlock) {
            return 0;
        } else {
            return busdEndBlock.sub(_from).mul(bonusMultiplier);
        }
    }

    function getBusdBalance() public view returns (uint256) {
        uint256 balance = busdToken.balanceOf(address(this)).sub(poolDeposit[busdPoolId]);
        return balance;
    }

    // AUDIT: MCM-04 | Lack of Pool Validity Checks
    // View function to see pending moneys and busd on frontend.
    function pendingReward(uint256 _pid, address _user)
    external
    view
    validatePoolByPid(_pid)
    returns (uint256, uint256)
    {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accMoneyPerShare = pool.accMoneyPerShare;
        uint256 accBusdPerShare = pool.accBusdPerShare;
        uint256 lpSupply = poolDeposit[_pid];

        uint256 moneyPendingReward;
        uint256 busdPendingReward;

        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier =
            getMultiplier(pool.lastRewardBlock, block.number);
            uint256 moneyReward =
            multiplier.mul(moneyPerBlock).mul(pool.allocPoint).div(
                totalAllocPoint
            );
            accMoneyPerShare = accMoneyPerShare.add(
                moneyReward.mul(1e12).div(lpSupply)
            );
            if(pool.secondaryReward) {
                uint256 busdMultiplier = getBusdMultiplier(pool.lastRewardBlock, block.number);
                uint256 busdReward =
                busdMultiplier.mul(busdPerBlock).mul(pool.allocPoint).div(
                    totalBusdAllocPoint
                );
                accBusdPerShare = accBusdPerShare.add(
                    busdReward.mul(1e12).div(lpSupply)
                );
            }
        }
        moneyPendingReward = user.amount.mul(accMoneyPerShare).div(1e12).sub(user.rewardDebt).add(user.moneyRewardLockedUp);
        // AUDIT: MCM-16 | Calculation of busdPendingReward
        // AUDIT: MCM-23 | Set The secondaryReward
        // DEV: busd reward will be 0 if pool.secondaryReward is false.
        // DEV: becuase accBusdPerShare and busdRewardDebt are 0 in non 2nd reward pools.
        // DEV: We already did test for this.
        busdPendingReward = user.amount.mul(accBusdPerShare).div(1e12).sub(user.busdRewardDebt).add(user.busdRewardLockedUp);

        return (moneyPendingReward, busdPendingReward);
    }


    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }

    // AUDIT: MCM-04 | Lack of Pool Validity Checks
    // Update reward variables of the given pool to be up-to-date.
    function updatePool(uint256 _pid) public validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = poolDeposit[_pid];
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 moneyReward =
        multiplier.mul(moneyPerBlock).mul(pool.allocPoint).div(
            totalAllocPoint
        );
        // AUDIT: MCM-10 | Over Minted Token
        // DEV: we prefer to keep 108% emission model.
        money.mint(devaddr, moneyReward.mul(800).div(10000));
        money.mint(address(this), moneyReward);
        pool.accMoneyPerShare = pool.accMoneyPerShare.add(
            moneyReward.mul(1e12).div(lpSupply)
        );
        if(pool.secondaryReward) {
            uint256 busdMultiplier = getBusdMultiplier(pool.lastRewardBlock, block.number);
            uint256 busdReward =
            busdMultiplier.mul(busdPerBlock).mul(pool.allocPoint).div(
                totalBusdAllocPoint
            );
            pool.accBusdPerShare = pool.accBusdPerShare.add(
                busdReward.mul(1e12).div(lpSupply)
            );
        }
        pool.lastRewardBlock = block.number;
    }

    function payOrLockupPendingMoney(address _recipient, uint256 _pid) internal {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_recipient];

        uint256 pending = user.amount.mul(pool.accMoneyPerShare).div(1e12).sub(user.rewardDebt).add(user.moneyRewardLockedUp);
        uint256 pendingBusd = user.amount.mul(pool.accBusdPerShare).div(1e12).sub(user.busdRewardDebt).add(user.busdRewardLockedUp);
        if (pool.lockPeriod > 0 ) {
            user.moneyRewardLockedUp = pending;
            user.busdRewardLockedUp = pendingBusd;
            emit RewardLockedUp(_recipient, _pid, pending, pendingBusd);
        } else {
            if (pending > 0) {
                safeMoneyTransfer(_recipient, pending);
            }
        }
    }
    // AUDIT: MCM-01 | Proper Usage of public and external
    function deposit(uint256 _pid, uint256 _amount) external {
        depositFor(msg.sender, _pid, _amount);
    }

    // AUDIT: MCM-04 | Lack of Pool Validity Checks
    // Deposit LP tokens to MasterChef for money allocation.
    function depositFor(address _recipient, uint256 _pid, uint256 _amount) public validatePoolByPid(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_recipient];
        updatePool(_pid);

        // AUDIT: MCM-22 | The Logic Issue Of UnDistributed Rewards
        // DEV: There is no harvest Action in lock pool, once user deposit again in lock pool
        // DEV: We save user's reward amount, that's why rewardDebt is not updated in lock pool.

        if (user.amount > 0) {
            // TESTER: I thing that you need to run this block on every deposit.
            payOrLockupPendingMoney(_recipient, _pid);
        }
        if (_amount > 0) {
            if(pool.depositFee > 0)
            {
                uint256 tax = _amount.mul(pool.depositFee).div(maxShare);
                uint256 received = _amount.sub(tax);
                if(pool.depositBurn){
                    pool.lpToken.safeTransferFrom(address(msg.sender), BURN_ADDRESS, tax);
                }
                else {
                    pool.lpToken.safeTransferFrom(address(msg.sender), devaddr, tax);
                }
                // MCM-05 | Incompatibility With Deflationary Tokens
                uint256 oldBalance = pool.lpToken.balanceOf(address(this));
                pool.lpToken.safeTransferFrom(address(msg.sender), address(this), received);
                uint256 newBalance = pool.lpToken.balanceOf(address(this));
                received = newBalance.sub(oldBalance);
                //add user deposit amount to the total pool deposit amount
                poolDeposit[_pid] = poolDeposit[_pid].add(received);
                user.amount = user.amount.add(received);
                userIndex(_pid, _recipient);
            }
            else{
                uint256 oldBalance = pool.lpToken.balanceOf(address(this));
                pool.lpToken.safeTransferFrom(
                    address(msg.sender),
                    address(this),
                    _amount
                );
                uint256 newBalance = pool.lpToken.balanceOf(address(this));
                _amount = newBalance.sub(oldBalance);
                //add user deposit amount to the total pool deposit amount
                poolDeposit[_pid] = poolDeposit[_pid].add(_amount);
                user.amount = user.amount.add(_amount);
                userIndex(_pid, _recipient);
            }

            user.lastDepositTime = _getNow();
        }

        user.rewardDebt = user.amount.mul(pool.accMoneyPerShare).div(1e12);
        user.busdRewardDebt = user.amount.mul(pool.accBusdPerShare).div(1e12);
        emit Deposit(_recipient, _pid, _amount);
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    // AUDIT: MCM-04 | Lack of Pool Validity Checks
    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _pid, uint256 _amount) external validatePoolByPid(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        if(pool.lockPeriod > 0){
            require(user.amount == _amount, "withdraw: Should unstake 100% of time token");
        }
        else {
            require(user.amount >= _amount, "withdraw: not good");
        }

        updatePool(_pid);

        poolDeposit[_pid] = poolDeposit[_pid].sub(_amount);

        if (pool.lockPeriod > 0 ) {
            if(_getNow() < user.lastDepositTime + pool.lockPeriod) {
                if (_amount > 0) {
                    user.amount = user.amount.sub(_amount);
                    userIndex(_pid, msg.sender);
                    uint256 tax = _amount.mul(pool.emergencyBurnRate).div(maxShare);
                    uint256 sent = _amount.sub(tax);
                    pool.lpToken.safeTransfer(BURN_ADDRESS, tax );
                    pool.lpToken.safeTransfer(address(msg.sender), sent );
                    emit Burn(msg.sender, _pid, sent, tax);
                }
                user.moneyRewardLockedUp = 0;
                user.busdRewardLockedUp = 0;
                user.rewardDebt = user.amount.mul(pool.accMoneyPerShare).div(1e12);
                user.busdRewardDebt = user.amount.mul(pool.accBusdPerShare).div(1e12);
                emit Withdraw(msg.sender, _pid, _amount);
            }else{
                uint256 pending = user.amount.mul(pool.accMoneyPerShare).div(1e12).sub(user.rewardDebt).add(user.moneyRewardLockedUp);
                if (pending > 0) {
                    safeMoneyTransfer(msg.sender, pending);
                }
                if(pool.secondaryReward) { // TESTER: moved outside as pendingBusd is checked
                    uint256 pendingBusd = user.amount.mul(pool.accBusdPerShare).div(1e12).sub(user.busdRewardDebt).add(user.busdRewardLockedUp);
                    if( pendingBusd > 0 ){
                        safeBusdTransfer(msg.sender, pendingBusd); // TESTER: change pool.lpToken to busdToken
                    }
                }
                if (_amount > 0) {
                    user.amount = user.amount.sub(_amount);
                    userIndex(_pid, msg.sender);
                    if(pool.burnRate == maxShare)
                        pool.lpToken.safeTransfer(BURN_ADDRESS, _amount );
                    else
                    {
                        uint256 tax = _amount.mul(pool.burnRate).div(maxShare);
                        uint256 sent = _amount.sub(tax);
                        pool.lpToken.safeTransfer(BURN_ADDRESS, tax );
                        pool.lpToken.safeTransfer(address(msg.sender), sent );
                    }
                }
                user.moneyRewardLockedUp = 0;
                user.busdRewardLockedUp = 0;
                user.rewardDebt = user.amount.mul(pool.accMoneyPerShare).div(1e12);
                user.busdRewardDebt = user.amount.mul(pool.accBusdPerShare).div(1e12);

                emit Withdraw(msg.sender, _pid, _amount);
            }
        } else {
            uint256 pending = user.amount.mul(pool.accMoneyPerShare).div(1e12).sub(user.rewardDebt).add(user.moneyRewardLockedUp);
            if (pending > 0) {
                safeMoneyTransfer(msg.sender, pending);
            }
            if(pool.secondaryReward) {
                // TESTER: adding secondary reward here too (if no lock).
                // why? bcs reward is computed with and without lock on updatePool
                uint256 pendingBusd = user.amount.mul(pool.accBusdPerShare).div(1e12).sub(user.busdRewardDebt).add(user.busdRewardLockedUp);
                if( pendingBusd > 0 ){
                    safeBusdTransfer(msg.sender, pendingBusd); // TESTER: change pool.lpToken to busdToken
                }
            }
            if (_amount > 0) {
                user.amount = user.amount.sub(_amount);
                userIndex(_pid, msg.sender);
                pool.lpToken.safeTransfer(address(msg.sender), _amount);
            }
            user.moneyRewardLockedUp = 0;
            user.busdRewardLockedUp = 0;
            user.rewardDebt = user.amount.mul(pool.accMoneyPerShare).div(1e12);
            // AUDIT: MCM-17 | user.busdRewardDebt Not Updated
            user.busdRewardDebt = user.amount.mul(pool.accBusdPerShare).div(1e12);
            emit Withdraw(msg.sender, _pid, _amount);
        }
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    // AUDIT: MCM-04 | Lack of Pool Validity Checks
    // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw(uint256 _pid) external validatePoolByPid(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        // AUDIT: MCM-19 | The logical Issue of emergencyWithdraw ()
        // DEV: There is no emergencyWithdraw feature in Lock pools.
        require(pool.lockPeriod == 0, "use withdraw");
        pool.lpToken.safeTransfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, _pid, user.amount);
        poolDeposit[_pid] = poolDeposit[_pid].sub(user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
        user.busdRewardDebt = 0; // TESTER: critical bug correction!
        user.moneyRewardLockedUp = 0;
        user.busdRewardLockedUp = 0;
        // AUDIT: MCM-16 | Calling Function userIndex Before Balance Updating
        userIndex(_pid, msg.sender);
    }

    // Safe money transfer function, just in case if rounding error causes pool to not have enough moneys.
    function safeMoneyTransfer(address _to, uint256 _amount) internal {
        uint256 balance = money.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > balance) {
            transferSuccess = money.transfer(_to, balance);
        } else {
            transferSuccess = money.transfer(_to, _amount);
        }
        emit Transfer(_to, _amount, balance); // TESTER: let's emit event here
        require(transferSuccess, "transfer failed");
    }

    // Safe busd transfer function, just in case if rounding error causes pool to not have enough busd.
    function safeBusdTransfer(address _to, uint256 _amount) internal {
        uint256 balance = getBusdBalance();
        bool transferSuccess = false;
        if (_amount > balance) {
            transferSuccess = busdToken.transfer(_to, balance);
        } else {
            transferSuccess = busdToken.transfer(_to, _amount);
        }
        emit Transfer(_to, _amount, balance); // TESTER: let's emit event here
        require(transferSuccess, "transfer failed");
    }

    function updateEmissionSettings(uint256 _pid, uint256 _depositAmount, uint256 _endBlock) external onlyAuthorizedCaller {
        require(msg.sender == busdFeeder1 || msg.sender == busdFeeder2, "MasterChefMoney.updateEmissionSettings: msg sender should be busd feeder");
        require(_endBlock > block.number, "End block should be bigger than current block");
        updatePool(_pid);

        busdEndBlock = _endBlock;

        //TESTER: note that _from wallet must approve this contract before.
        // AUDIT: MCM-20 | Token Transfer In updateEmissionSettings
        // DEV: Msg.sender is not user's wallet. This is admin wallet which provide busd for 2nd reward in this contract.
        busdToken.safeTransferFrom(msg.sender, address(this), _depositAmount);
        uint256 busdBalance = getBusdBalance();
        uint256 blockCount = busdEndBlock.sub(block.number);
        busdPerBlock = busdBalance.div(blockCount);

        emit UpdateEmissionSettings(msg.sender, _depositAmount, _endBlock);
    }

    function setAuthorizedCaller(address caller, bool _status) onlyOwner external {
        require(caller != address(0), "MasterChefMoney.setAuthorizedCaller: Zero address");
        _authorizedCaller[caller] = _status;

        emit SetAuthorizedCaller(caller, _status);
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    // Update dev address by the previous dev.
    function dev(address _devaddr) external {
        require(msg.sender == devaddr, "dev: wut?");

        // AUDIT: MCM-18 | Lack of Input Validation
        require(_devaddr != address(0), "dev: zero address");
        // AUDIT: MCM-08 | Missing Emit Events
        emit SetDev(devaddr, _devaddr);
        devaddr = _devaddr;
    }

    function setBusdFeeder1(address _busdFeeder1) onlyOwner external {
        require(_busdFeeder1 != address(0), "setBusdFeeder: zero address");
        busdFeeder1 = _busdFeeder1;
        emit SetBusdFeeder1(_busdFeeder1);
    }

    function setBusdFeeder2(address _busdFeeder2) onlyOwner external {
        require(_busdFeeder2 != address(0), "setBusdFeeder: zero address");
        busdFeeder2 = _busdFeeder2;
        emit SetBusdFeeder2(_busdFeeder2);
    }

    function _getNow() public virtual view returns (uint256) {
        return block.timestamp;
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    function totalUsersByPid( uint256 _pid ) external virtual view returns (uint256) {
        return addressByPid[_pid].getAllAddresses().length;
    }
    function usersByPid( uint256 _pid ) public virtual view returns (address[] memory) {
        return addressByPid[_pid].getAllAddresses();
    }

    // AUDIT: MCM-01 | Proper Usage of public and external
    function usersBalancesByPid( uint256 _pid ) external virtual view returns (UserInfo[] memory) {
        address[] memory list = usersByPid(_pid);
        UserInfo[] memory balances = new UserInfo[]( list.length );
        for (uint i = 0; i < list.length; i++) {
            address addr = list[i];
            balances[i] = userInfo[_pid][addr];
        }
        return balances;
    }
    function userIndex( uint256 _pid, address _user ) internal {
        AddrArrayLib.Addresses storage addr = addressByPid[_pid];

        uint256 amount = userInfo[_pid][_user].amount;
        // AUDIT: MCM-07 | Comparison to A Boolean Constant
        if( amount > 0 ){ // add user
            addr.pushAddress(_user);
        }else if( amount == 0 ){ // remove user
            addr.removeAddress(_user);
        }
    }

    // allow to change tax treasure via timelock
    function adminSetTaxAddr(address payable _taxTo) external onlyOwner {
        money.setTaxAddr(_taxTo);
    }

    // allow to change tax via timelock
    function adminSetTax(uint16 _tax) external onlyOwner {
        money.setTax(_tax);
    }

    // whitelist address (like vaults)
    function adminSetWhiteList(address _addr, bool _status) external onlyOwner {
        money.setWhiteList(_addr, _status);
    }

    // liquidity lock setting
    function setSwapAndLiquifyEnabled(bool _enabled) external onlyOwner {
        money.setSwapAndLiquifyEnabled(_enabled);
    }
}
