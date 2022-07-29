// SPDX-License-Identifier: MIT
pragma solidity ^0.8.6;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _transferOwnership(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        _checkOwner();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if the sender is not the owner.
     */
    function _checkOwner() internal view virtual {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _transferOwnership(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _transferOwnership(newOwner);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Internal function without access restriction.
     */
    function _transferOwnership(address newOwner) internal virtual {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

abstract contract ReentrancyGuard {
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }
    modifier nonReentrant() {
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        _status = _ENTERED;

        _;

        _status = _NOT_ENTERED;
    }
}

library TransferHelper {
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::safeApprove: approve failed'
        );
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::safeTransfer: transfer failed'
        );
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::transferFrom: transferFrom failed'
        );
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'TransferHelper::safeTransferETH: ETH transfer failed');
    }
}

interface IERC20 {
    function transfer(address to, uint256 amount) external returns (bool);

    function balanceOf(address account) external view returns (uint256);

     function approve(address spender, uint256 amount) external returns (bool);
}

interface ILoopPool {
    function withdraw(address token, uint256 amount) external ;
}

interface IERC721 {
    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);
}

contract FalaUPool is Ownable, ReentrancyGuard {
    address public usdtTokenAddr = address(0x55d398326f99059fF775485246999027B3197955); //usdt 0x0D6Cd65015cabA96590B74aE4371e170A27B3a29
    address public falaTokenAddr = address(0x6b6da2C8CCb7043851cfa3D93D42EE67E8aCE867); // token地址
    address public falaNFTAddr = address(0x785fdb070B528D78f214d77CedE7ee3Bc9e5BF66); // NFT合约地址

    uint256 constant public falaTokenTotalSupply = 10000000000000 * 1e18; //10000亿
    address constant private destroyAddress = address(0x000000000000000000000000000000000000dEaD);
    uint256 public secondsPerMin = 10;  // 测试时，用1，表示1秒代表1一分钟，线上用 60
    uint256 public luckyPer = 5;   // 幸运奖单数，默认100，测试用5

    uint256 constant public initPrice = 1000000000000; //0.000001U/个，放大了1e18倍
    uint256 constant public pricePerOrder = 100 * 1e18; //每单价格 100 USDT
    uint256 public curRoundStartTime; // 本轮开启交易时间
    uint256 public curRoundEndTime; // 本轮结束交易时间
    uint256 public curRound = 0; //当前轮次，dapp展示时，加1展示

    mapping (address => address) public inviteMap; // 签名推荐关系
    address[] public inviteKeys;  //签名推荐关系的key  
    
    struct RoundInfo {
        uint256 startTime; // 开启交易时间
        uint256 initTokenAmt; // 初始币数量
        uint256 initUSDTAmt; // 初始USDT数量
        uint256 curUSDTAmt; // 当前USDT数量
        uint256 orderAmt; // 总下单数
        uint256 nextLuckyTokenAmt; // 下一个幸运奖的Token数量，U的数量不用存，就是多少单多少U
        uint256 center1TokenAmt; // 中心化处理的Token数量（每天都处理的）
        uint256 center1USDTAmt;  // 中心化处理的USDT数量（每天都处理的）
        uint256 center2TokenAmt; // 中心化处理的Token数量（每轮处理的）
        uint256 center2USDTAmt;  // 中心化处理的USDT数量（每轮都处理的）
        uint256 latestOrderTime; // 最后一笔订单时间
        uint256 tokenAmtFromLoopPool; // 从循环池出币数量
    }
    RoundInfo[] public roundInfos; // 各轮次基本信息

    mapping (uint256 => address[]) public roundBuyUsers; // 公排数组   轮次=>数组
    mapping (uint256 => uint256[]) public roundBuyTimes; // 公排数组时间   轮次=>时间
    mapping (uint256 => mapping(address => uint256[])) public roundBuyUserIdxs;  // 用户在各轮买入时对应roundBuyUsers的下标
    mapping (uint256 => mapping(address => uint256)) public roundUserUseWhiteNums;  // 用户在各轮买入时使用上轮白名单次数
    mapping (uint256 => mapping(address => uint256)) public inviteOrderNums; // 轮次=>地址=>总推荐单数关系
    mapping (uint256 => mapping(address => mapping(address => bool))) public inviteOrderNumsCaled; // 轮次=>地址=>被推荐人=>是否已计算

    //mapping (address => uint256) public nftHolder; // 地址和NFT数量关系
    mapping (uint256 => mapping(address => uint256)) public roundUserUseNFTNums;  // 用户在各轮买入时使用NFT次数

    address private mgrAddress; // 管理地址
    address private sysAddress; // 系统操作地址
    address public projectAddr;  // 项目方地址，比如首单的公排，奖励给这个地址
    address public receiveUSDTAddr;  // 下轮第一单开始前，将多余的U转到该地址
    address public loopPoolAddr;  // 循环池地址

    mapping (address => uint256) public usdtUserBalance; // USDT的用户可提现余额
    mapping (address => uint256) public tokenUserBalance; // Token的用户可提现余额，目前是Fala

    /* 奖励事件
        to表示接收奖励地址；
        tokenType表示奖励的代币类型，分别为1：USDT和2：FALA；
        tokenAmt表示数量;
        rewardType表示奖励类型，1：幸运奖， 2：终极奖， 3：公排奖， 4：直推奖
        time：时间
        finalIdx: 终极奖index，从1开始
        round: 轮次
        from: 买入的用户
    */
    event Rewards(address to, uint8 tokenType, uint256 tokenAmt, uint8 rewardType, uint256 time, uint256 finalIdx, uint256 round, address from);

    constructor(address mgrAddress_, address sysAddress_, address projectAddr_, address receiveUSDTAddr_, uint256 firstStartTime_) {
        mgrAddress = mgrAddress_;
        sysAddress = sysAddress_;
        projectAddr = projectAddr_;
        receiveUSDTAddr = receiveUSDTAddr_;
        curRoundStartTime = firstStartTime_;
        curRoundEndTime = curRoundStartTime + secondsPerMin * 60 * 48;
    }

    function inviteKeysLen() public view returns(uint256) {
        return inviteKeys.length;
    }

    function roundBuyUsersLen(uint256 round_) public view returns(uint256) {
        return roundBuyUsers[round_].length;
    }

    function setRootFather(address self) public onlyOwner {  // 管理员设置根级用户
        inviteMap[self] = destroyAddress;
        inviteKeys.push(self);
    }

    function setFather(address father) public nonReentrant returns (bool) {
        require(father != address(0), "setFather: father can't be zero.");
        require(inviteMap[_msgSender()] == address(0), "setFather: Father already exists.");
        require(!isContract(father), "setFather: Father is a contract.");
        require(inviteMap[father] != address(0), "setFather: Father don't have father.");

        inviteMap[_msgSender()] = father;
        inviteKeys.push(_msgSender());

        return true;
    }
    
    function sysSetFather(address self, address father) public returns (bool) {
    	require(_msgSender() == sysAddress, "sysSetFather: Not SYS Address.");
    
        require(father != address(0), "setFather: father can't be zero.");
        require(inviteMap[self] == address(0), "setFather: Father already exists.");
        require(!isContract(father), "setFather: Father is a contract.");
        require(inviteMap[father] != address(0), "setFather: Father don't have father.");

        inviteMap[self] = father;
        inviteKeys.push(self);

        return true;
    }

    function isContract(address account) internal view returns (bool) {
        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    function getForefathers(address self, uint num) internal view returns(address[] memory fathers){
        fathers = new address[](num);
        address parent  = self;
        for( uint i = 0; i < num; i++){
            parent = inviteMap[parent];
            if(parent == destroyAddress) break;
            fathers[i] = parent;
        }
    }

    // 获得当前价格，前端展示时，需要除以1e18
    function getCurPrice() public view returns(uint256) {
        if (roundInfos.length > 0) {
            RoundInfo memory ri = roundInfos[roundInfos.length - 1];
            return ri.curUSDTAmt * 1e18 / (falaTokenTotalSupply - IERC20(falaTokenAddr).balanceOf(loopPoolAddr));
        } else {
            return initPrice;
        }
    }

    // 中心化后台判断是否需要重启，如果返回true，则再调用下面的restart方法
    function needRestart() public view returns(bool) {
        if (roundInfos.length > 0 && block.timestamp > curRoundEndTime) {
            return true;
        }
        return false;
    }

    event Restart(address from, uint256 time);
    // 中心化后台调用此接口重启，此处不做权限控制没有问题
    function restart() public nonReentrant returns(bool) {
        if (roundInfos.length > 0 && block.timestamp > curRoundEndTime) {  // 超过结束时间，则需要重启
            RoundInfo memory ri = roundInfos[roundInfos.length - 1];

            // 终极奖  5%? 终极大奖(每一轮最后50单平均分)
            uint256 finalRewardAmt = ri.orderAmt * 5 * 1e18;   // 实际上，这里就是5% 正常写法： ri.orderAmt * 100 * 5 / 100
            if (curRound < roundInfos.length) { // 这个判断是防止有一轮或几轮没人参与时，重复奖励了
                uint256 buyUsersLen = roundBuyUsers[roundInfos.length - 1].length;
                uint256 rewardUserAmt = buyUsersLen < 50 ? buyUsersLen : 50;
                uint256 rewardAmtPerUser = finalRewardAmt / rewardUserAmt;
                uint256 j = 1;
                for(uint256 i = buyUsersLen - 1; i >= buyUsersLen - rewardUserAmt; ) {
                    TransferHelper.safeTransfer(usdtTokenAddr, roundBuyUsers[roundInfos.length - 1][i], rewardAmtPerUser);
                    emit Rewards(roundBuyUsers[roundInfos.length - 1][i], 1, rewardAmtPerUser, 2, block.timestamp, j, roundInfos.length - 1, address(0));
                    if (i > 0) {
                        i--;
                    } else {
                        break;
                    }
                    j++;
                }
            }

            // 下轮启动时间是上轮结束时间 + 48小时（给人卖币的时间）（这是白名单入场时间，普通用户是50小时入场）
            curRoundStartTime = curRoundEndTime + secondsPerMin * 60 * 48;

            if (curRoundStartTime < block.timestamp) { //如果开始时间已经过去了，以当前时间为开始时间。
                curRoundStartTime = block.timestamp;
            }
            curRoundEndTime = curRoundStartTime + secondsPerMin * 60 * 48;
            
            curRound = roundInfos.length;  // 以这个为curRound值，避免整个一轮或几轮都没有人参与时，数据不对

            emit Restart(_msgSender(), block.timestamp);
        }
        return true;
    }

    
    event StartTrade(address from, uint256 time);
    // 中心化后台调用此接口启动交易，本接口可以不控制权限
    // curRoundStartTime_是普通用户开始交易时间
    function startTrade(uint256 curRoundStartTime_) public nonReentrant returns(bool) {
        if (roundInfos.length == curRound) {  // 只有还没有建池的情况下，才执行
            uint256 circulationToken = falaTokenTotalSupply - IERC20(falaTokenAddr).balanceOf(loopPoolAddr);  // 本轮初始Token数量，为当前流通数量
            require(IERC20(usdtTokenAddr).balanceOf(address(this)) >= circulationToken * initPrice / 1e18, "order: pool usdt amount exceeds balance");

            if (curRound > 0 && roundInfos[curRound - 1].curUSDTAmt > circulationToken * initPrice / 1e18) { // 第二轮开始，如果U有多，就转给项目方
                TransferHelper.safeTransfer(usdtTokenAddr, receiveUSDTAddr, roundInfos[curRound - 1].curUSDTAmt - circulationToken * initPrice / 1e18);
            }

            RoundInfo memory ri = RoundInfo({
                startTime: block.timestamp, 
                initTokenAmt: circulationToken, 
                initUSDTAmt: circulationToken * initPrice / 1e18, 
                curUSDTAmt: circulationToken * initPrice / 1e18,
                orderAmt: 0,
                nextLuckyTokenAmt: 0,
                center1TokenAmt: 0,
                center1USDTAmt: 0,
                center2TokenAmt: 0,
                center2USDTAmt: 0,
                latestOrderTime: 0,
                tokenAmtFromLoopPool : 0
            });
            roundInfos.push(ri);

            curRoundStartTime = curRoundStartTime_;
            curRoundEndTime = curRoundStartTime + secondsPerMin * 60 * 48;  // 本轮结束时间

            emit StartTrade(_msgSender(), curRoundStartTime);
        }
        return true;
    }

    // 紧急情况下，Owner可以手动修改
    function manulRestart(uint256 startTime_, uint256 round_) public onlyOwner returns(bool) {
        curRoundStartTime = startTime_;
        curRoundEndTime = curRoundStartTime + secondsPerMin * 60 * 48;
        curRound = round_;
        return true;
    }

    /*
         下单事件
         from：下单地址
         usdtAmt：USDT数量，都是100
         round：轮次，从0开始，展示需加1
         idx：在本轮中的位置，从1开始
         time：时间
    */
    event Order(address from, uint256 usdtAmt, uint256 round, uint256 idx, uint256 time);
    // 用户下单
    function order() external nonReentrant returns (bool){
        require(_msgSender() == tx.origin, "order: Can't Call From Contract.");
        require(inviteMap[_msgSender()] != address(0), "order: Don't have Father.");
        require(IERC20(usdtTokenAddr).balanceOf(_msgSender()) >= pricePerOrder, "order: usdt amount exceeds balance");
        require(block.timestamp <= curRoundEndTime, "order: This round has ended.");
        require(roundInfos.length > curRound, "order: Start time not reached.");
    
        if (curRound > 0 && block.timestamp < curRoundStartTime
            && roundBuyUserIdxs[curRound - 1][_msgSender()].length > roundUserUseWhiteNums[curRound][_msgSender()]
            && roundBuyUserIdxs[curRound - 1][_msgSender()][roundBuyUserIdxs[curRound - 1][_msgSender()].length - roundUserUseWhiteNums[curRound][_msgSender()] - 1] 
                >= (roundBuyUsers[curRound - 1].length > 5001 ? roundBuyUsers[curRound - 1].length - 5001 : 0)
            ) {
            require(block.timestamp + 2 * 60 * secondsPerMin >= curRoundStartTime, "order: Start time not reached.");

            roundUserUseWhiteNums[curRound][_msgSender()]++;
        } else if (curRound == 0 && block.timestamp < curRoundStartTime
            && IERC721(falaNFTAddr).balanceOf(_msgSender()) > 0
            && 2 > roundUserUseNFTNums[curRound][_msgSender()]  // 持有NFT可以提前一小时抢2单(只有第一轮有效)
            )  {
            require(block.timestamp + 2 * 60 * secondsPerMin >= curRoundStartTime, "order: Start time not reached.");

            roundUserUseNFTNums[curRound][_msgSender()]++;
        } else {
            require(block.timestamp >= curRoundStartTime, "order: Start time not reached.");
        }

        TransferHelper.safeTransferFrom(usdtTokenAddr, _msgSender(), address(this), pricePerOrder);

        uint256 curPrice;


        RoundInfo storage ri = roundInfos[curRound];

        curPrice = getCurPrice();  // 在这里计算时因为下面会更改USDT的值

        ri.orderAmt += 1;
        ri.curUSDTAmt += 60 * 1e18;  // 25U固定进入，另外35U买Token
        ri.latestOrderTime = block.timestamp;

        if (block.timestamp >= curRoundStartTime) {  // 普通会员的才延时
            /*
            1-9999笔订单内每进一单加10小时
            10000-49999笔订单内每进一单加5小时
            50000-99999笔订单内每进一单加1小时
            100000笔以上订单每进一单加 10分钟
            */
            if (roundInfos[curRound].orderAmt < 10000) {//1  10
                curRoundEndTime += 10 * 60 * secondsPerMin;   // 本轮结束时间
            } else if (roundInfos[curRound].orderAmt < 50000) {
                curRoundEndTime += 5 * 60 * secondsPerMin;   // 本轮结束时间
            } else if (roundInfos[curRound].orderAmt < 100000) {
                curRoundEndTime += 1 * 60 * secondsPerMin;   // 本轮结束时间
            } else {
                curRoundEndTime += 10 * secondsPerMin;   // 本轮结束时间
            }

            if (curRoundEndTime > block.timestamp + secondsPerMin * 60 * 48) {  //每单延迟10分钟，最多延迟48小时
                curRoundEndTime = block.timestamp + secondsPerMin * 60 * 48;
            }
        }        

        roundBuyUsers[curRound].push(_msgSender());  // 公排数据
        roundBuyTimes[curRound].push(block.timestamp); //公排时间
        roundBuyUserIdxs[curRound][_msgSender()].push(roundBuyUsers[curRound].length - 1);

        uint256 tokenAmt = 35 * 1e18 / curPrice * 1e18;  // 35U 换币数量
        ILoopPool(loopPoolAddr).withdraw(falaTokenAddr, tokenAmt);  // 从循环池转对应的币到U池，然后进行分配

        ri.tokenAmtFromLoopPool += tokenAmt;

        // 分配奖励
        // 19点前卖出
        ri.center1TokenAmt += tokenAmt * 25 / 3500;
        ri.center1USDTAmt += 25 * 1e16; // 0.25%
        // NFT奖励、推荐排名
        ri.center2TokenAmt += tokenAmt * 350 / 3500;
        ri.center2USDTAmt += 350 * 1e16; // 3.5%
        
        
        // 奖励幸运奖
        ri.nextLuckyTokenAmt += tokenAmt * 125 / 3500;
        if (ri.orderAmt % luckyPer == 0) {
            TransferHelper.safeTransfer(usdtTokenAddr, _msgSender(), 125 * 1e18 * luckyPer / 100); 
            emit Rewards(_msgSender(), 1, 125 * 1e18 * luckyPer / 100, 1, block.timestamp, 0, curRound, _msgSender());
            TransferHelper.safeTransfer(falaTokenAddr, _msgSender(), ri.nextLuckyTokenAmt);
            emit Rewards(_msgSender(), 2, ri.nextLuckyTokenAmt, 1, block.timestamp, 0, curRound, _msgSender());
            ri.nextLuckyTokenAmt = 0;
        }

        // 公排 40%
        if (ri.orderAmt == 1) { // 本轮第一单，前面没有公排
            TransferHelper.safeTransfer(usdtTokenAddr, projectAddr, 20 * 1e18);
            TransferHelper.safeTransfer(falaTokenAddr, projectAddr, tokenAmt * 2000 / 3500);            
        } else {
            usdtUserBalance[roundBuyUsers[curRound][ri.orderAmt - 2]] += 20 * 1e18;    
            emit Rewards(roundBuyUsers[curRound][ri.orderAmt - 2], 1, 20 * 1e18, 3, block.timestamp, 0, curRound, _msgSender());        
            tokenUserBalance[roundBuyUsers[curRound][ri.orderAmt - 2]] += tokenAmt * 2000 / 3500;
            emit Rewards(roundBuyUsers[curRound][ri.orderAmt - 2], 2, tokenAmt * 2000 / 3500, 3, block.timestamp, 0, curRound, _msgSender());
        }

        // 直推
        address parent = inviteMap[_msgSender()];
        if (!inviteOrderNumsCaled[curRound][parent][_msgSender()]) {
            inviteOrderNums[curRound][parent] ++;  // 推荐单数
            inviteOrderNumsCaled[curRound][parent][_msgSender()] = true;
        }
        

        if (parent == address(0) || parent == destroyAddress) { // 没有推荐人
            TransferHelper.safeTransfer(usdtTokenAddr, projectAddr, 10 * 1e18);
            TransferHelper.safeTransfer(falaTokenAddr, projectAddr, tokenAmt * 1000 / 3500);
        } else {
            if (inviteOrderNums[curRound][parent] >= 5) {
                usdtUserBalance[parent] += 10 * 1e18;     
                emit Rewards(parent, 1, 10 * 1e18, 4, block.timestamp, 0, curRound, _msgSender());       
                tokenUserBalance[parent] += tokenAmt * 1000 / 3500;
                emit Rewards(parent, 2, tokenAmt * 1000 / 3500, 4, block.timestamp, 0, curRound, _msgSender());
            }else if (inviteOrderNums[curRound][parent] >= 3) {
                usdtUserBalance[parent] += 75 * 1e17;
                emit Rewards(parent, 1, 75 * 1e17, 4, block.timestamp, 0, curRound, _msgSender());
                tokenUserBalance[parent] += tokenAmt * 750 / 3500;
                emit Rewards(parent, 2, tokenAmt * 750 / 3500, 4, block.timestamp, 0, curRound, _msgSender());

                TransferHelper.safeTransfer(usdtTokenAddr, projectAddr, 25 * 1e17);
                TransferHelper.safeTransfer(falaTokenAddr, projectAddr, tokenAmt * 250 / 3500);
            } else { // 肯定有1单
                usdtUserBalance[parent] += 5 * 1e18;      
                emit Rewards(parent, 1, 5 * 1e18, 4, block.timestamp, 0, curRound, _msgSender());      
                tokenUserBalance[parent] += tokenAmt * 500 / 3500;
                emit Rewards(parent, 2, tokenAmt * 500 / 3500, 4, block.timestamp, 0, curRound, _msgSender());

                TransferHelper.safeTransfer(usdtTokenAddr, projectAddr, 5 * 1e18);
                TransferHelper.safeTransfer(falaTokenAddr, projectAddr, tokenAmt * 500 / 3500);
            }
            
        }

        emit Order(_msgSender(), pricePerOrder, curRound, roundBuyUsers[curRound].length, block.timestamp);

        return true;
    }

    /*
        卖出事件
        from：卖出地址
        falaAmt：卖出数量
        price： 价格
        usdtAmt：USDT数量
        usdtReceiveAmt：USDT到账数量（扣usdtAmt的10%）
        time：时间
    */
    event Sell(address from, uint256 falaAmt, uint256 price, uint256 usdtAmt, uint256 usdtReceiveAmt, uint256 time);
    // 用户卖出
    function sell(uint256 falaAmt) external nonReentrant returns (bool){
        require(_msgSender() == tx.origin, "order: Can't Call From Contract.");
        require(IERC20(falaTokenAddr).balanceOf(_msgSender()) >= falaAmt, "order: fala amount exceeds balance");
        uint256 curPrice = getCurPrice();
        uint256 usdtAmt = curPrice * falaAmt / 1e18;
        require(usdtAmt <= IERC20(usdtTokenAddr).balanceOf(address(this)), "system balance not enough");

        TransferHelper.safeTransferFrom(falaTokenAddr, _msgSender(), loopPoolAddr, falaAmt);  //卖币是回到循环池

        RoundInfo storage ri = roundInfos[roundInfos.length - 1];
        ri.curUSDTAmt -= usdtAmt * 90 / 100; // 扣10%

        TransferHelper.safeTransfer(usdtTokenAddr, _msgSender(), usdtAmt * 90 / 100);  // 给用户转U

        emit Sell(_msgSender(), falaAmt, curPrice, usdtAmt, usdtAmt * 90 / 100, block.timestamp);

        return true;
    }

    function setMgrAddress(address mgrAddress_) public onlyOwner {
        mgrAddress = mgrAddress_;
    } 

    function setSysAddress(address sysAddress_) public onlyOwner {
        sysAddress = sysAddress_;
    }

    function setLoopPoolAddr(address loopPoolAddr_) public onlyOwner {
        loopPoolAddr = loopPoolAddr_;
    }

    /*
        tokenType表示奖励的代币类型，分别为1：USDT和2：FALA；
    */
    event Withdraw(address addr, uint8 tokenType, uint256 tokenAmt, uint256 time);
    // 用户提现USDT
    function userWithdrawUSDT() public nonReentrant returns (bool) {
        uint256 canWithdraw = usdtUserBalance[_msgSender()];
        require(canWithdraw > 0, "balance not enough");
        require(canWithdraw <= IERC20(usdtTokenAddr).balanceOf(address(this)), "system balance not enough");

        usdtUserBalance[_msgSender()] = 0;

        TransferHelper.safeTransfer(usdtTokenAddr, _msgSender(), canWithdraw);

        emit Withdraw(_msgSender(), 1, canWithdraw, block.timestamp);

        return true;
    }


    // 用户提现Fala
    function userWithdrawFALA() public nonReentrant returns (bool) {
        uint256 canWithdraw = tokenUserBalance[_msgSender()];
        require(canWithdraw > 0, "balance not enough");
        require(canWithdraw <= IERC20(falaTokenAddr).balanceOf(address(this)), "system balance not enough");

        tokenUserBalance[_msgSender()] = 0;

        TransferHelper.safeTransfer(falaTokenAddr, _msgSender(), canWithdraw);

        emit Withdraw(_msgSender(), 2, canWithdraw, block.timestamp);

        return true;
    }

    // 系统地址提现NFT持有者奖励的Token，到系统那边进行分配
    function sysAddressRescueCenter1Token(uint256 round_) public returns (bool success) {
        require(_msgSender() == sysAddress, "sysAddressRescueCenter1Token: Not SYS Address.");

        uint256 tokenAmt = roundInfos[round_].center1TokenAmt;
        require(tokenAmt > 0, "sysAddressRescueCenter1Token: balance not enough.");

        roundInfos[round_].center1TokenAmt = 0;

        TransferHelper.safeTransfer(falaTokenAddr, sysAddress, tokenAmt);
        return true;
    }

    // 系统地址提现NFT持有者奖励的USDT，到系统那边进行分配
    function sysAddressRescueCenter1USDT(uint256 round_) public returns (bool success) {
        require(_msgSender() == sysAddress, "sysAddressRescueCenter1USDT: Not SYS Address.");

        uint256 tokenAmt = roundInfos[round_].center1USDTAmt;
        require(tokenAmt > 0, "sysAddressRescueCenter1USDT: balance not enough.");

        roundInfos[round_].center1USDTAmt = 0;

        TransferHelper.safeTransfer(usdtTokenAddr, sysAddress, tokenAmt);
        return true;
    }


    // 系统地址提现NFT持有者奖励的Token，到系统那边进行分配
    function sysAddressRescueCenter2Token(uint256 round_) public returns (bool success) {
        require(_msgSender() == sysAddress, "sysAddressRescueCenter2Token: Not SYS Address.");

        uint256 tokenAmt = roundInfos[round_].center2TokenAmt;
        require(tokenAmt > 0, "sysAddressRescueCenter2Token: balance not enough.");

        roundInfos[round_].center2TokenAmt = 0;

        TransferHelper.safeTransfer(falaTokenAddr, sysAddress, tokenAmt);
        return true;
    }

    // 系统地址提现NFT持有者奖励的USDT，到系统那边进行分配
    function sysAddressRescueCenter2USDT(uint256 round_) public returns (bool success) {
        require(_msgSender() == sysAddress, "sysAddressRescueCenter2USDT: Not SYS Address.");

        uint256 tokenAmt = roundInfos[round_].center2USDTAmt;
        require(tokenAmt > 0, "sysAddressRescueCenter2USDT: balance not enough.");

        roundInfos[round_].center2USDTAmt = 0;

        TransferHelper.safeTransfer(usdtTokenAddr, sysAddress, tokenAmt);
        return true;
    }

    function getNFTNum(address user) public view returns(uint256) {
        return IERC721(falaNFTAddr).balanceOf(user);
    }

    function rescueToken(address tokenAddress, uint256 tokens) public nonReentrant returns (bool success) {
        require(_msgSender() == mgrAddress, "rescueToken: Not Mgr Address.");

        TransferHelper.safeTransfer(tokenAddress, _msgSender(), tokens);
        return true;
    }
}
