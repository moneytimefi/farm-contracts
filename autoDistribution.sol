/*

    http://moneytime.finance/

    https://t.me/moneytimefinance

*/
// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "@pancakeswap/pancake-swap-lib/contracts/math/SafeMath.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/IBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/token/BEP20/SafeBEP20.sol";
import "@pancakeswap/pancake-swap-lib/contracts/access/Ownable.sol";
import "./MasterChefMoney.sol";
import "./MasterChefTime.sol";
import "./interfaces.sol";


contract AutoDistribution is Ownable {
    using SafeMath for uint256;
    using SafeBEP20 for IBEP20;

    struct ProviderInfo{
        uint256 percent; // 1% = 1000
        address provider;
    }
    IUniswapV2Router02 public uniswapV2Router;

    IBEP20 public moneyToken;

    IBEP20 public busdToken;

    MasterChefMoney private masterChefMoney;
    MasterChefTime private masterChefTime;

    // uint8 private WALLET_1_POOLID = 4;
    // uint8 private WALLET_2_POOLID = 1;
    uint256 public maxPercent = 100000; // 100%

    address private BURN_ADDRESS = address(0x000000000000000000000000000000000000dEaD);

    address[10] private walletAddress = [0xc610422fBD4aB646b3A7b6144D706301a7d67e91,
                                         0xb2E9c3507c9867943152b74D0001Aa11279D70f8,
                                         0x1892569c7C00b3C7683730b71609F164024c4709,
                                         0x72400CE2A89F0C18BC003280D6263C34aFCA87AD,
                                         0xdc554288fC9100A54eD78fD1Cfa8FC6ef13FB05b,
                                         0x9270cb89a4a8aA44FC41B62dAC04ec79CC115fE7,
                                         0xba299E149981Bec61912642d83943519A429AAee,
                                         0x74345aA48E01cDe07918eAA266026a46F3018363,
                                         0x2b2D054FF40Fa09b8761a3ecBDC95Fc24563878f,
                                         0x6ef21724f67FC6AA5d6fAfF500dD14a0C8c65A8d];

    address[] public lpTokens;
    address[] public stakingTokens;

    mapping (address => uint256) feePercent;
    mapping (address => ProviderInfo[]) public providerInfo;

    constructor(
        IUniswapV2Router02 _uniswapV2Router,
        MasterChefMoney _masterChefMoney,
        MasterChefTime _masterChefTime,
        IBEP20 _moneyToken,
        IBEP20 _busdToken
    ) public {
        require(address(_uniswapV2Router) != address(0), "AutoDistrubution: router address is zero");
        require(address(_masterChefMoney) != address(0), "AutoDistrubution: masterchefMoney address is zero");
        require(address(_masterChefTime) != address(0), "AutoDistrubution: masterchefTime address is zero");
        require(address(_moneyToken) != address(0), "AutoDistrubution: money token address is zero");
        require(address(_busdToken) != address(0), "AutoDistrubution: busd token address is zero");

        uniswapV2Router = _uniswapV2Router;
        masterChefMoney = _masterChefMoney;
        masterChefTime = _masterChefTime;
        moneyToken = _moneyToken;
        busdToken = _busdToken;
    }

    // function to set timepool address
    function setMasterChefMoney(MasterChefMoney _masterChefMoney) external onlyOwner {
        require(address(_masterChefMoney) != address(0), "AutoDistrubution.setMasterChefMoney: masterchef address is zero");
        masterChefMoney = _masterChefMoney;
    }

    // function to set timepool address
    function setMasterChefTime(MasterChefTime _masterChefTime) external onlyOwner {
        require(address(_masterChefTime) != address(0), "AutoDistrubution.setMasterChefTime: masterchef address is zero");
        masterChefTime = _masterChefTime;
    }

    // function to check wallet is valid
    function checkWalletAddress(address _walletAddress) internal view returns (bool) {
        for(uint8 i=0; i < walletAddress.length; i++) {
            if (_walletAddress == walletAddress[i]) {
                return true;
            }
        }
        return false;
    }

    // function to add LP token
    function addLpToken(address _lpToken) external onlyOwner {
        require(_lpToken != address(0), "Zero Address");
        lpTokens.push(_lpToken);
    }

    // function to add LP token
    function addStakingToken(address _stakingToken) external onlyOwner {
        require(_stakingToken != address(0), "Zero Address");
        stakingTokens.push(_stakingToken);
    }
    // function to add LP token
    function addProvider(address _wallet, uint256 _percent, address _provider) external onlyOwner {
        require(_wallet != address(0), "Zero Address");
        require(checkWalletAddress(_wallet), "Invalid Wallet address");
        require(_provider != address(0), "Zero Address");
        require(_percent > 0 , "Invalid percent");
        ProviderInfo[] storage provider = providerInfo[_wallet];
        provider.push(
            ProviderInfo({
                percent: _percent,
                provider: _provider
            })
        );
    }

    function getFeeToWallet1() external onlyOwner {
        address wallet = walletAddress[0];
        for(uint256 i = 0; i < stakingTokens.length; i++ ) {
            ProviderInfo[] memory provider = providerInfo[wallet];

            uint256 balance = IBEP20(stakingTokens[i]).balanceOf(provider[0].provider);
            if(balance > 0) {
                uint256 amount = balance.mul(provider[0].percent).div(maxPercent);
                if(IBEP20(stakingTokens[i]) == busdToken ) {
                    IBEP20(stakingTokens[i]).safeTransferFrom(provider[0].provider, wallet, amount);
                } else {
                    IBEP20(stakingTokens[i]).safeTransferFrom(provider[0].provider, address(this), amount);
                    swapTokensForBusd(amount, stakingTokens[i], wallet);
                }
            }
        }
    }

    function getFeeToWallet2() external onlyOwner {
        address wallet = walletAddress[1];
        for(uint256 i = 0; i < stakingTokens.length; i++ ) {
            ProviderInfo[] memory provider = providerInfo[wallet];
            for(uint256 j = 0; j < provider.length; j++ ) {
                uint256 balance = IBEP20(stakingTokens[i]).balanceOf(provider[j].provider);
                if(balance > 0) {
                    uint256 amount = balance.mul(provider[j].percent).div(maxPercent);
                    if(IBEP20(stakingTokens[i]) == busdToken ) {
                        IBEP20(stakingTokens[i]).safeTransferFrom(provider[j].provider, wallet, amount);
                    } else {
                        IBEP20(stakingTokens[i]).safeTransferFrom(provider[j].provider, address(this), amount);
                        swapTokensForBusd(amount, stakingTokens[i], wallet);
                    }
                }
            }
        }
    }

    function buybackAndBurnMoney() external onlyOwner {
        // Wallet 3 and wallet 4
        for(uint256 i = 2; i < 4; i++)
        {
            address wallet = walletAddress[i];
            for(uint256 j = 0; j < stakingTokens.length; j++ ) {
                ProviderInfo[] memory provider = providerInfo[wallet];

                uint256 balance = IBEP20(stakingTokens[j]).balanceOf(provider[0].provider);
                uint256 amount = balance.mul(provider[0].percent).div(maxPercent);
                IBEP20(stakingTokens[j]).safeTransferFrom(provider[0].provider, address(this), amount);
                swapTokensForMoney(amount, stakingTokens[j], BURN_ADDRESS);
            }
        }
    }

    function getFeeToWallet5() external onlyOwner {
        address wallet = walletAddress[4];
        for(uint256 i = 0; i < lpTokens.length; i++ ) {
            ProviderInfo[] memory provider = providerInfo[wallet];
            uint256 balance = IBEP20(lpTokens[i]).balanceOf(provider[0].provider);
            uint256 amount = balance.mul(provider[0].percent).div(maxPercent);
            IBEP20(lpTokens[i]).safeTransferFrom(provider[0].provider, wallet, amount);
        }
    }

    function getFeeToWallet6() external onlyOwner {
        address wallet = walletAddress[5];
        address[] memory moneyBnbStakers = masterChefTime.usersByPid(20);
        address[] memory moneyBusdStakers = masterChefTime.usersByPid(21);
        require(!(moneyBnbStakers.length == 0 && moneyBusdStakers.length == 0), "getFeeToWallet6: there is no lp stakers.");
        for(uint256 i = 0; i < lpTokens.length; i++ ) {
            ProviderInfo[] memory provider = providerInfo[wallet];
            uint256 balance = IBEP20(lpTokens[i]).balanceOf(provider[0].provider);
            if(balance > 0) {
                uint256 amount = balance.mul(provider[0].percent).div(maxPercent);
                IBEP20(lpTokens[i]).safeTransferFrom(provider[0].provider, address(this), amount);
                
                uint256 oldBalance = moneyToken.balanceOf(address(this));

                // cast to pair:
                IUniswapV2Pair pair = IUniswapV2Pair(lpTokens[i]);
                // used to extrac balances
                IBEP20 token0 = IBEP20(pair.token0());
                IBEP20 token1 = IBEP20(pair.token1());

                //approve
                pair.approve(address(uniswapV2Router), pair.balanceOf(address(this)));

                // remove liquidity
                // if( i == 0) {
                //     uniswapV2Router.removeLiquidityETH(
                //     address(moneyToken), pair.balanceOf(address(this)),
                //     0, 0, address(this), block.timestamp+60);
                // }
                // else {
                    uniswapV2Router.removeLiquidity(
                        pair.token0(), pair.token1(), pair.balanceOf(address(this)),
                        0, 0, address(this), block.timestamp+60);
                // }

                // swap tokens to our token:
                if(token0 != moneyToken)
                    swapTokensForMoney( token0.balanceOf(address(this)), pair.token0(), address(this));
                if(token1 != moneyToken)
                    swapTokensForMoney( token1.balanceOf(address(this)), pair.token1(), address(this));

                uint256 newBalance = moneyToken.balanceOf(address(this));
                uint256 busdPerShare;
                uint256 bnbPerShare;
                if(moneyBnbStakers.length == 0) {
                    busdPerShare = newBalance.sub(oldBalance).div(moneyBusdStakers.length);
                    for(uint256 k = 0; k < moneyBusdStakers.length; k++) {
                        moneyToken.transfer(moneyBusdStakers[k], busdPerShare);
                    }
                }
                else if(moneyBusdStakers.length == 0) {
                    bnbPerShare = newBalance.sub(oldBalance).div(moneyBnbStakers.length);
                    for(uint256 j = 0; j < moneyBnbStakers.length; j++) {
                        moneyToken.transfer(moneyBnbStakers[j], bnbPerShare);
                    }
                }
                else {
                    busdPerShare = newBalance.sub(oldBalance).div(2).div(moneyBusdStakers.length);
                    bnbPerShare = newBalance.sub(oldBalance).div(2).div(moneyBnbStakers.length);
                    for(uint256 k = 0; k < moneyBusdStakers.length; k++) {
                        moneyToken.transfer(moneyBusdStakers[k], busdPerShare);
                    }
                    for(uint256 j = 0; j < moneyBnbStakers.length; j++) {
                        moneyToken.transfer(moneyBnbStakers[j], bnbPerShare);
                    }
                }
            }
        }
    }

    function getFeeToWallet7() external onlyOwner {
        address wallet = walletAddress[6];
        ProviderInfo[] memory provider = providerInfo[wallet];
        for(uint256 i = 0; i < stakingTokens.length; i++ ) {
            for(uint256 j = 0; j < 2; j++ ) {
                uint256 balance = IBEP20(stakingTokens[i]).balanceOf(provider[j].provider);
                if (balance > 0) {
                    uint256 amount = balance.mul(provider[j].percent).div(maxPercent);
                    IBEP20(stakingTokens[i]).safeTransferFrom(provider[j].provider, wallet, amount);
                }
            }
        }

        for(uint256 i = 0; i < lpTokens.length; i++ ) {
            uint256 balance = IBEP20(lpTokens[i]).balanceOf(provider[2].provider);
            if (balance > 0) {
                uint256 amount = balance.mul(provider[2].percent).div(maxPercent);
                IBEP20(lpTokens[i]).safeTransferFrom(provider[2].provider, wallet, amount);
            }
        }
    }

    function getFeeToWallet8() external onlyOwner {
        address wallet = walletAddress[7];
        ProviderInfo[] memory provider = providerInfo[wallet];
        uint256 balance = moneyToken.balanceOf(provider[0].provider);
        if (balance > 0) {
            moneyToken.transferFrom(provider[0].provider, wallet, balance);
        }
    }

    function getFeeToWallet9() external onlyOwner {
        address wallet = walletAddress[8];
        address[] memory moneyBnbStakers = masterChefTime.usersByPid(20);
        address[] memory moneyBusdStakers = masterChefTime.usersByPid(21);
        require(!(moneyBnbStakers.length == 0 && moneyBusdStakers.length == 0), "getFeeToWallet9: there is no lp stakers.");
        ProviderInfo[] memory provider = providerInfo[wallet];
        uint256 balance = moneyToken.balanceOf(provider[0].provider);
        if (balance > 0) {
            
            uint256 amount = balance.mul(provider[0].percent).div(maxPercent);
            uint256 oldBalance = moneyToken.balanceOf(address(this));
            moneyToken.transferFrom(provider[0].provider, address(this), amount);
            uint256 newBalance = moneyToken.balanceOf(address(this));
            amount = newBalance.sub(oldBalance);
            
            uint256 busdPerShare;
            uint256 bnbPerShare;
            if(moneyBnbStakers.length == 0) {
                busdPerShare = amount.div(moneyBusdStakers.length);
                for(uint256 k = 0; k < moneyBusdStakers.length; k++) {
                    moneyToken.transfer(moneyBusdStakers[k], busdPerShare);
                }
            }
            else if(moneyBusdStakers.length == 0) {
                bnbPerShare = amount.div(moneyBnbStakers.length);
                for(uint256 j = 0; j < moneyBnbStakers.length; j++) {
                    moneyToken.transfer(moneyBnbStakers[j], bnbPerShare);
                }
            }
            else {
                busdPerShare = amount.div(2).div(moneyBusdStakers.length);
                bnbPerShare = amount.div(2).div(moneyBnbStakers.length);
                for(uint256 k = 0; k < moneyBusdStakers.length; k++) {
                    moneyToken.transfer(moneyBusdStakers[k], busdPerShare);
                }
                for(uint256 j = 0; j < moneyBnbStakers.length; j++) {
                    moneyToken.transfer(moneyBnbStakers[j], bnbPerShare);
                }
            }
        }
    }

    function getFeeToWallet10() external onlyOwner {
        address wallet = walletAddress[9];
        address[] memory moneyBnbStakers = masterChefTime.usersByPid(20);
        address[] memory moneyBusdStakers = masterChefTime.usersByPid(21);
        require(!(moneyBnbStakers.length == 0 && moneyBusdStakers.length == 0), "getFeeToWallet10: there is no lp stakers.");
        for(uint256 i = 0; i < stakingTokens.length; i++ ) {
            ProviderInfo[] memory provider = providerInfo[wallet];
            uint256 balance = IBEP20(stakingTokens[i]).balanceOf(provider[0].provider);
            if (balance > 0) {
                uint256 amount = balance.mul(provider[0].percent).div(maxPercent);
                uint256 oldBalance = busdToken.balanceOf(address(this));

                IBEP20(stakingTokens[i]).safeTransferFrom(provider[0].provider, address(this), amount);

                if(IBEP20(stakingTokens[i]) != busdToken) {
                    swapTokensForBusd(amount, stakingTokens[i], address(this));
                }
                
                uint256 newBalance = busdToken.balanceOf(address(this));

                uint256 busdPerShare;
                uint256 bnbPerShare;
                if(moneyBnbStakers.length == 0) {
                    busdPerShare = newBalance.sub(oldBalance).div(moneyBusdStakers.length);
                    for(uint256 k = 0; k < moneyBusdStakers.length; k++) {
                        busdToken.safeTransfer(moneyBusdStakers[k], busdPerShare);
                    }
                }
                else if(moneyBusdStakers.length == 0) {
                    bnbPerShare = newBalance.sub(oldBalance).div(moneyBnbStakers.length);
                    for(uint256 j = 0; j < moneyBnbStakers.length; j++) {
                        busdToken.safeTransfer(moneyBnbStakers[j], bnbPerShare);
                    }
                }
                else {
                    busdPerShare = newBalance.sub(oldBalance).div(2).div(moneyBusdStakers.length);
                    bnbPerShare = newBalance.sub(oldBalance).div(2).div(moneyBnbStakers.length);
                    for(uint256 k = 0; k < moneyBusdStakers.length; k++) {
                        busdToken.safeTransfer(moneyBusdStakers[k], busdPerShare);
                    }
                    for(uint256 j = 0; j < moneyBnbStakers.length; j++) {
                        busdToken.safeTransfer(moneyBnbStakers[j], bnbPerShare);
                    }
                }
            }
        }
    }

    // function to swap LP token to Money token
    function swapTokensForMoney(uint balance, address token, address to) internal {

        // generate the uniswap pair path of token -> money
        address[] memory path = new address[](2);
        path[0] = token;
        path[1] = address(moneyToken);

        IBEP20(token).approve(address(uniswapV2Router), balance);

        // make the swap
        uniswapV2Router.swapExactTokensForTokens(
            balance,
            0, // accept any amount of money
            path,
            to,
            block.timestamp+60
        );
    }

    // function to swap LP token to Money token
    function swapTokensForBusd(uint amountIn, address tokenA, address to) internal {
        // generate the uniswap pair path of token -> money
        address[] memory path = new address[](2);
        path[0] = tokenA;
        path[1] = address(busdToken);

        IBEP20(tokenA).approve(address(uniswapV2Router), amountIn);

        // make the swap
        uniswapV2Router.swapExactTokensForTokens(
            amountIn,
            0, // accept any amount of money
            path,
            to,
            block.timestamp+60
        );
    }
}
