/*

    http://moneytime.finance/

    https://t.me/moneytimefinance

*/
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

pragma experimental ABIEncoderV2;
import '@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol';
import '@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol';
import "./libs/ReentrancyGuard.sol";

import './libs/AddrArrayLib.sol';
import "./TimeToken.sol";

// import "@nomiclabs/buidler/console.sol";

// MasterChef is the master of cake. He can make cake and he is a fair guy.
//
// Note that it's ownable and the owner wields tremendous power. The ownership
// will be transferred to a governance smart contract once cake is sufficiently
// distributed and the community can show to govern itself.
//
// Have fun reading it. Hopefully it's bug-free. God bless.
contract MasterChefTime is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;
    using AddrArrayLib for AddrArrayLib.Addresses;

    // Info of each user.
    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
        // We do some fancy math here. Basically, any point in time, the amount of times
        // entitled to a user but is pending to be distributed is:
        //
        //   pending reward = (user.amount * pool.accTimePerShare) - user.rewardDebt
        //
        // Whenever a user deposits or withdraws LP tokens to a pool. Here's what happens:
        //   1. The pool's `accTimePerShare` (and `lastRewardBlock`) gets updated.
        //   2. User receives the pending reward sent to his/her address.
        //   3. User's `amount` gets updated.
        //   4. User's `rewardDebt` gets updated.
    }

    // Info of each pool.
    struct PoolInfo {
        IBEP20 lpToken;           // Address of LP token contract.
        uint256 allocPoint;       // How many allocation points assigned to this pool. times to distribute per block.
        uint256 lastRewardBlock;  // Last block number that times distribution occurs.
        uint256 accTimePerShare; // Accumulated times per share, times 1e12. See below.
        uint256 depositFee; // Deposit Fee Percent of LP token
        uint256 withdrawFee; // Withdraw Fee Percent of LP token
        bool isBurn; // Burn Deposit Fee
    }

    // The time TOKEN!
    // AUDIT: MCT-02 | Set immutable to Variables
    TimeToken public immutable time;
    // Dev address.
    address public devaddr;
    // Withdraw Recipient address.
    address public withdrawRecipient;
    // Deposit Recipient address.
    address public depositRecipient;
    // Max percent with 2 decimal -> 10000 = 100%
    // AUDIT: MCT-03 | Set constant to Variables
    uint256 public constant maxShare = 10000;
    // time tokens created per block.
    uint256 public timePerBlock;
    // Bonus muliplier for early time makers.
    uint256 public bonusMultiplier = 1;

    // Info of each pool.
    PoolInfo[] public poolInfo;
    // Info of each user that stakes LP tokens.
    mapping (uint256 => mapping (address => UserInfo)) public userInfo;
    mapping(uint256 => AddrArrayLib.Addresses) private addressByPid;
    mapping(uint256 => uint[]) public userIndexByPid;

    // AUDIT: MCT-06 | add() Function Not Restricted
    // The Staking token list
    mapping (address => bool) private stakingTokens;

    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when time mining starts.
    // AUDIT: MCT-02 | Set immutable to Variables
    uint256 public immutable startBlock;

    // AUDIT: MCT-03 | Set constant to Variables
    address public constant BURN_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    event Deposit(address indexed user, uint256 indexed pid, uint256 amount, uint256 fee);
    event Withdraw(address indexed user, uint256 indexed pid, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 indexed pid, uint256 amount);

    event timePerBlockUpdated(uint256 timePerBlock);
    // AUDIT: MCT-05 | Missing indexed in Events
    event depositRecipientUpdated(address indexed depositRecipient);
    event withdrawRecipientUpdated(address indexed withdrawRecipient);
    event Transfer(address indexed to, uint256 requsted, uint256 sent);
    // AUDIT: MCT-04 | Missing Emit Events
    event UpdateMultiplier(uint256 multiplierNumber);

    event SetDev(address indexed prevDev, address indexed newDev);

    // AUDIT: MCT-11 | Lack of Pool Validity Checks
    modifier validatePoolByPid(uint256 _pid) {
        require(_pid < poolInfo.length, "pool id not exisit");
        _;
    }

    constructor(
        TimeToken _time,
        address _devaddr,
        address _depositRecipient,
        address _withdrawRecipient,
        uint256 _timePerBlock,
        uint256 _startBlock
    ) public {
        require(address(_time) != address(0), "MasterChefTime.Constructor: Time token shouldn't be zero address");
        require(address(_devaddr) != address(0), "MasterChefTime.Constructor: Dev address shouldn't be zero address");
        require(_depositRecipient != address(0), "MasterChefTime.Constructor: Deposit recipient shouldn't be zero address");
        require(_withdrawRecipient != address(0), "MasterChefTime.Constructor: Withdraw recipient shouldn't be zero address");
        require(_timePerBlock != 0, "MasterChefTime.Constructor: Reward token count per block can't be zero");

        time = _time;
        devaddr = _devaddr;
        depositRecipient = _depositRecipient;
        withdrawRecipient = _withdrawRecipient;
        timePerBlock = _timePerBlock;
        startBlock = _startBlock;
    }

    //update reward count per block
    // AUDIT: MCT-01 | Proper Usage of public and external
    function updateTimePerBlock(uint256 _timePerBlock) external onlyOwner {
        require(_timePerBlock != 0, "MasterChefTime.updateTimePerBlock: Reward token count per block can't be zero");
        timePerBlock = _timePerBlock;
        // emitts event when timePerBlock updated
        emit timePerBlockUpdated(_timePerBlock);
    }

    // AUDIT: MCT-01 | Proper Usage of public and external
    function updateMultiplier(uint256 multiplierNumber) external onlyOwner {
        bonusMultiplier = multiplierNumber;
        // AUDIT: MCT-04 | Missing Emit Events
        emit UpdateMultiplier(multiplierNumber);
    }

    //update the address of depositRecipient
    // AUDIT: MCT-01 | Proper Usage of public and external
    function updateDepositRecipient(address _depositRecipient) external onlyOwner {
        require(_depositRecipient != address(0), "MasterChefTime.updateDepositRecipient: Recipient address cannot be zero");
        depositRecipient = _depositRecipient;
        // emitts event when depositRecipient address updated
        emit depositRecipientUpdated(depositRecipient);
    }
    //update the address of withdrawRecipient
    // AUDIT: MCT-01 | Proper Usage of public and external
    function updateWithdrawRecipient(address _withdrawRecipient) external onlyOwner {
        require(_withdrawRecipient != address(0), "MasterChefTime.updateWithdrawRecipient: Recipient address cannot be zero");
        withdrawRecipient = _withdrawRecipient;
        // emitts event when withdrawRecipient address updated
        emit withdrawRecipientUpdated(withdrawRecipient);
    }

    function poolLength() external view returns (uint256) {
        return poolInfo.length;
    }

    // Add a new lp to the pool. Can only be called by the owner.
    // XXX DO NOT add the same LP token more than once. Rewards will be messed up if you do.
    // AUDIT: MCT-01 | Proper Usage of public and external
    function add(uint256 _allocPoint, IBEP20 _lpToken, uint256 _depositFee, uint256 _withdrawFee, bool _isBurn, bool _withUpdate) external onlyOwner {
        // AUDIT: MCT-06 | add() Function Not Restricted
        require(!stakingTokens[address(_lpToken)], "MasterChefMoney.add: This staking token already added.");
        require(_depositFee <= 500, "add: invalid deposit fee basis points");
        require(_withdrawFee <= 199, "add: invalid withdraw fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 lastRewardBlock = block.number > startBlock ? block.number : startBlock;
        totalAllocPoint = totalAllocPoint.add(_allocPoint);
        poolInfo.push(PoolInfo({
        lpToken: _lpToken,
        allocPoint: _allocPoint,
        lastRewardBlock: lastRewardBlock,
        accTimePerShare: 0,
        depositFee: _depositFee,
        withdrawFee: _withdrawFee,
        isBurn: _isBurn
        }));

        // AUDIT: MCT-06 | add() Function Not Restricted
        stakingTokens[address(_lpToken)] = true;
    }

    // Update the given pool's time allocation point, deposit fee and withdraw fee. Can only be called by the owner.
    // AUDIT: MCT-11 | Lack of Pool Validity Checks
    function set(uint256 _pid, uint256 _allocPoint, uint256 _depositFee, uint256 _withdrawFee, bool _isBurn, bool _withUpdate) public onlyOwner validatePoolByPid(_pid){
        require(_depositFee <= 500, "set: invalid deposit fee basis points");
        require(_withdrawFee <= 199, "set: invalid withdraw fee basis points");
        if (_withUpdate) {
            massUpdatePools();
        }
        uint256 prevAllocPoint = poolInfo[_pid].allocPoint;
        poolInfo[_pid].allocPoint = _allocPoint;
        poolInfo[_pid].depositFee = _depositFee;
        poolInfo[_pid].withdrawFee = _withdrawFee;
        poolInfo[_pid].isBurn = _isBurn;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(bonusMultiplier);
    }

    // View function to see pending time tokens on frontend.
    // AUDIT: MCT-11 | Lack of Pool Validity Checks
    function pendingTime(uint256 _pid, address _user) external view validatePoolByPid(_pid) returns (uint256) {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][_user];
        uint256 accTimePerShare = pool.accTimePerShare;
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (block.number > pool.lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
            uint256 timeReward = multiplier.mul(timePerBlock).mul(pool.allocPoint).div(totalAllocPoint);
            accTimePerShare = accTimePerShare.add(timeReward.mul(1e12).div(lpSupply));
        }
        return user.amount.mul(accTimePerShare).div(1e12).sub(user.rewardDebt);
    }

    // Update reward variables for all pools. Be careful of gas spending!
    function massUpdatePools() public {
        uint256 length = poolInfo.length;
        for (uint256 pid = 0; pid < length; ++pid) {
            updatePool(pid);
        }
    }


    // Update reward variables of the given pool to be up-to-date.
    // AUDIT: MCT-11 | Lack of Pool Validity Checks
    function updatePool(uint256 _pid) public validatePoolByPid(_pid) {
        PoolInfo storage pool = poolInfo[_pid];
        if (block.number <= pool.lastRewardBlock) {
            return;
        }
        uint256 lpSupply = pool.lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            pool.lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(pool.lastRewardBlock, block.number);
        uint256 timeReward = multiplier.mul(timePerBlock).mul(pool.allocPoint).div(totalAllocPoint);
        time.mint(devaddr, timeReward.div(10));
        time.mint(address(this), timeReward);
        pool.accTimePerShare = pool.accTimePerShare.add(timeReward.mul(1e12).div(lpSupply));
        pool.lastRewardBlock = block.number;
    }

    // AUDIT: MCT-01 | Proper Usage of public and external
    // AUDIT: MCT-07 | Check Effect Interaction Pattern Violated
    function deposit(uint256 _pid, uint256 _amount) external {
        depositFor(msg.sender, _pid, _amount);
    }

    // Deposit LP tokens to MasterChef for time allocation.
    function depositFor(address recipient, uint256 _pid, uint256 _amount) public validatePoolByPid(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][recipient];
        uint256 depositAmount = _amount;
        uint256 depositFeeAmount = 0;
        updatePool(_pid);
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(pool.accTimePerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                safeTimeTransfer(recipient, pending);
            }
        }
        if (depositAmount > 0) {
            if(pool.depositFee > 0) {
                // Check if there is pool's deposit fee.
                depositFeeAmount = depositAmount.mul(pool.depositFee).div(maxShare);

                // Burn or send deposit fee to recipient
                if(pool.isBurn)
                    pool.lpToken.safeTransferFrom(address(msg.sender), BURN_ADDRESS, depositFeeAmount);
                else
                    pool.lpToken.safeTransferFrom(address(msg.sender), depositRecipient, depositFeeAmount);

                depositAmount = depositAmount.sub(depositFeeAmount);
            }
            uint256 oldBalance = pool.lpToken.balanceOf(address(this));
            pool.lpToken.safeTransferFrom(address(msg.sender), address(this), depositAmount);
            uint256 newBalance = pool.lpToken.balanceOf(address(this));
            depositAmount = newBalance.sub(oldBalance);

            user.amount = user.amount.add(depositAmount);
            userIndex(_pid, recipient);
        }
        user.rewardDebt = user.amount.mul(pool.accTimePerShare).div(1e12);
        emit Deposit(recipient, _pid, depositAmount, depositFeeAmount);
    }

    // Withdraw LP tokens from MasterChef.
    // AUDIT: MCT-01 | Proper Usage of public and external
    // AUDIT: MCT-07 | Check Effect Interaction Pattern Violated
    // AUDIT: MCT-11 | Lack of Pool Validity Checks
    function withdraw(uint256 _pid, uint256 _amount) external validatePoolByPid(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];
        uint256 withdrawAmount = _amount;
        require(user.amount >= withdrawAmount, "withdraw: not good");

        updatePool(_pid);
        uint256 pending = user.amount.mul(pool.accTimePerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
            safeTimeTransfer(msg.sender, pending);
        }
        if(withdrawAmount > 0) {
            user.amount = user.amount.sub(withdrawAmount);
            userIndex(_pid, msg.sender);
            // avoid rounding errors on withdraw if fee=0
            if( pool.withdrawFee > 0 ){
                uint256 withdrawFeeAmount = withdrawAmount.mul(pool.withdrawFee).div(maxShare);
                pool.lpToken.safeTransfer(withdrawRecipient, withdrawFeeAmount);
                withdrawAmount = withdrawAmount.sub(withdrawFeeAmount);
            }
            pool.lpToken.safeTransfer(address(msg.sender), withdrawAmount);
        }
        user.rewardDebt = user.amount.mul(pool.accTimePerShare).div(1e12);
        emit Withdraw(msg.sender, _pid, withdrawAmount);
    }

    // Withdraw without caring about rewards. EMERGENCY ONLY.
    // AUDIT: MCT-01 | Proper Usage of public and external
    // AUDIT: MCT-07 | Check Effect Interaction Pattern Violated
    // AUDIT: MCT-11 | Lack of Pool Validity Checks
    function emergencyWithdraw(uint256 _pid) external validatePoolByPid(_pid) nonReentrant {
        PoolInfo storage pool = poolInfo[_pid];
        UserInfo storage user = userInfo[_pid][msg.sender];

        uint256 withdrawFeeAmount = user.amount.mul(pool.withdrawFee).div(maxShare);
        pool.lpToken.safeTransfer(withdrawRecipient, withdrawFeeAmount);
        pool.lpToken.safeTransfer(address(msg.sender), user.amount.sub(withdrawFeeAmount));

        emit EmergencyWithdraw(msg.sender, _pid, user.amount.sub(withdrawFeeAmount)); // TESTER: need to fix this

        user.amount = 0;
        user.rewardDebt = 0;

        userIndex(_pid, msg.sender);
    }

    function safeTimeTransfer(address _to, uint256 _amount) internal {
        uint256 balance = time.balanceOf(address(this));
        bool transferSuccess = false;
        if (_amount > balance) {
            transferSuccess = time.transfer(_to, balance);
            emit Transfer(_to, _amount, balance);
        } else {
            transferSuccess = time.transfer(_to, _amount);
            emit Transfer(_to, _amount, balance);
        }
        require(transferSuccess, "transfer failed");
    }

    function dev(address _devaddr) external {
        require(msg.sender == devaddr, "dev: wut?");

        // AUDIT: MCM-18 | Lack of Input Validation
        require(_devaddr != address(0), "dev: zero address");

        emit SetDev(devaddr, _devaddr);
        devaddr = _devaddr;
    }

    // AUDIT: MCT-01 | Proper Usage of public and external
    function totalUsersByPid( uint256 _pid ) external virtual view returns (uint256) {
        return addressByPid[_pid].getAllAddresses().length;
    }
    function usersByPid( uint256 _pid ) public virtual view returns (address[] memory) {
        return addressByPid[_pid].getAllAddresses();
    }
    // AUDIT: MCT-01 | Proper Usage of public and external
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
        if( amount > 0 ){ // add user
            addr.pushAddress(_user);
        }else if( amount == 0 ){ // remove user
            addr.removeAddress(_user);
        }
    }

}
