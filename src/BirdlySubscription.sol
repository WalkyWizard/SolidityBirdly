pragma solidity ^0.8.20;

contract BirdlySubscription {
    error Unauthorized();
    error InvalidPrice();
    error InvalidDuration();
    error InvalidFeatures();
    error PlanNotFound();
    error PlanInactive();
    error InsufficientPayment(uint256 required, uint256 sent);
    error InvalidRecipient();
    error ETHTransferFailed();
    error ReentrancyGuardReentrantCall();
    error ContractPaused();
    error ContractNotPaused();
    error NoFundsToWithdraw();
    error SubscriptionAlreadyActive();
    error NoActiveSubscription();

    struct Plan {
        uint256 id;
        string name;
        uint256 price;
        uint256 duration;
        bool unlocksHistory;
        bool unlocksMultimodal;
        bool active;
    }

    address public owner;
    bool public paused;
    uint256 public planCount;

    mapping(uint256 => Plan) public plans;
    mapping(address => uint256) public historyExpiration;
    mapping(address => uint256) public multimodalExpiration;

    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;
    uint256 private _status;

    event PlanCreated(
        uint256 indexed planId,
        string name,
        uint256 price,
        uint256 duration,
        bool unlocksHistory,
        bool unlocksMultimodal
    );

    event PlanUpdated(
        uint256 indexed planId,
        uint256 price,
        uint256 duration,
        bool active
    );

    event SubscriptionPurchased(
        address indexed subscriber,
        address indexed recipient,
        uint256 indexed planId,
        uint256 historyExpiresAt,
        uint256 multimodalExpiresAt
    );

    event SubscriptionGranted(
        address indexed recipient,
        uint256 historyExpiresAt,
        uint256 multimodalExpiresAt
    );

    event SubscriptionCancelled(address indexed user);
    event FundsWithdrawn(address indexed to, uint256 amount);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event Paused(address account);
    event Unpaused(address account);

    modifier onlyOwner() {
        if (msg.sender != owner) revert Unauthorized();
        _;
    }

    modifier whenNotPaused() {
        if (paused) revert ContractPaused();
        _;
    }

    modifier nonReentrant() {
        if (_status == _ENTERED) revert ReentrancyGuardReentrantCall();
        _status = _ENTERED;
        _;
        _status = _NOT_ENTERED;
    }

    constructor() {
        owner = msg.sender;
        _status = _NOT_ENTERED;

        _createPlan("History Pass", 0.005 ether, 30 days, true, false);
        _createPlan("Multimodal Pass", 0.01 ether, 30 days, false, true);
        _createPlan("Birdly Pro Monthly", 0.012 ether, 30 days, true, true);
        _createPlan("Birdly Pro Yearly", 0.1 ether, 365 days, true, true);
    }

    function _createPlan(
        string memory name,
        uint256 price,
        uint256 duration,
        bool unlocksHistory,
        bool unlocksMultimodal
    ) internal returns (uint256 planId) {
        if (price == 0) revert InvalidPrice();
        if (duration == 0) revert InvalidDuration();
        if (!unlocksHistory && !unlocksMultimodal) revert InvalidFeatures();

        unchecked {
            planCount++;
        }
        planId = planCount;

        plans[planId] = Plan({
            id: planId,
            name: name,
            price: price,
            duration: duration,
            unlocksHistory: unlocksHistory,
            unlocksMultimodal: unlocksMultimodal,
            active: true
        });

        emit PlanCreated(
            planId,
            name,
            price,
            duration,
            unlocksHistory,
            unlocksMultimodal
        );
    }

    function createPlan(
        string calldata name,
        uint256 price,
        uint256 duration,
        bool unlocksHistory,
        bool unlocksMultimodal
    ) external onlyOwner returns (uint256) {
        return _createPlan(name, price, duration, unlocksHistory, unlocksMultimodal);
    }

    function updatePlan(
        uint256 planId,
        uint256 newPrice,
        uint256 newDuration,
        bool active
    ) external onlyOwner {
        if (planId == 0 || planId > planCount) revert PlanNotFound();
        if (newPrice == 0) revert InvalidPrice();
        if (newDuration == 0) revert InvalidDuration();

        Plan storage plan = plans[planId];
        plan.price = newPrice;
        plan.duration = newDuration;
        plan.active = active;

        emit PlanUpdated(planId, newPrice, newDuration, active);
    }

    function subscribe(uint256 planId) external payable {
        subscribeFor(msg.sender, planId);
    }

    function subscribeFor(address recipient, uint256 planId)
        public
        payable
        whenNotPaused
        nonReentrant
    {
        if (recipient == address(0)) revert InvalidRecipient();
        if (planId == 0 || planId > planCount) revert PlanNotFound();
        if (historyExpiration[recipient] > block.timestamp || multimodalExpiration[recipient] > block.timestamp) {
            revert SubscriptionAlreadyActive();
        }

        Plan storage plan = plans[planId];
        if (!plan.active) revert PlanInactive();
        if (msg.value < plan.price) revert InsufficientPayment(plan.price, msg.value);

        if (plan.unlocksHistory) {
            historyExpiration[recipient] = block.timestamp + plan.duration;
        }

        if (plan.unlocksMultimodal) {
            multimodalExpiration[recipient] = block.timestamp + plan.duration;
        }

        if (msg.value > plan.price) {
            uint256 refund = msg.value - plan.price;
            (bool success, ) = payable(msg.sender).call{value: refund}("");
            if (!success) revert ETHTransferFailed();
        }

        emit SubscriptionPurchased(
            msg.sender,
            recipient,
            planId,
            historyExpiration[recipient],
            multimodalExpiration[recipient]
        );
    }

    function cancelSubscription() external {
        if (historyExpiration[msg.sender] <= block.timestamp && multimodalExpiration[msg.sender] <= block.timestamp) {
            revert NoActiveSubscription();
        }
        historyExpiration[msg.sender] = 0;
        multimodalExpiration[msg.sender] = 0;
        emit SubscriptionCancelled(msg.sender);
    }

    function grantSubscription(
        address recipient,
        bool grantHistory,
        bool grantMultimodal,
        uint256 duration
    ) external onlyOwner {
        if (recipient == address(0)) revert InvalidRecipient();
        if (duration == 0) revert InvalidDuration();
        if (!grantHistory && !grantMultimodal) revert InvalidFeatures();

        if (grantHistory) {
            uint256 currentHist = historyExpiration[recipient];
            historyExpiration[recipient] = currentHist > block.timestamp
                ? currentHist + duration
                : block.timestamp + duration;
        }

        if (grantMultimodal) {
            uint256 currentMulti = multimodalExpiration[recipient];
            multimodalExpiration[recipient] = currentMulti > block.timestamp
                ? currentMulti + duration
                : block.timestamp + duration;
        }

        emit SubscriptionGranted(
            recipient,
            historyExpiration[recipient],
            multimodalExpiration[recipient]
        );
    }

    function hasHistoryAccess(address user) external view returns (bool) {
        return historyExpiration[user] > block.timestamp;
    }

    function hasMultimodalAccess(address user) external view returns (bool) {
        return multimodalExpiration[user] > block.timestamp;
    }

    function hasFullAccess(address user) external view returns (bool) {
        return historyExpiration[user] > block.timestamp && multimodalExpiration[user] > block.timestamp;
    }

    function getSubscriptionStatus(address user)
        external
        view
        returns (
            bool hasHistory,
            uint256 historyExpiresAt,
            bool hasMultimodal,
            uint256 multimodalExpiresAt
        )
    {
        return (
            historyExpiration[user] > block.timestamp,
            historyExpiration[user],
            multimodalExpiration[user] > block.timestamp,
            multimodalExpiration[user]
        );
    }

    function getPlan(uint256 planId) external view returns (Plan memory) {
        if (planId == 0 || planId > planCount) revert PlanNotFound();
        return plans[planId];
    }

    function getPlans() external view returns (Plan[] memory result) {
        result = new Plan[](planCount);
        for (uint256 i = 0; i < planCount; i++) {
            result[i] = plans[i + 1];
        }
    }

    function pause() external onlyOwner {
        if (paused) revert ContractPaused();
        paused = true;
        emit Paused(msg.sender);
    }

    function unpause() external onlyOwner {
        if (!paused) revert ContractNotPaused();
        paused = false;
        emit Unpaused(msg.sender);
    }

    function withdraw() external onlyOwner nonReentrant {
        uint256 balance = address(this).balance;
        if (balance == 0) revert NoFundsToWithdraw();

        (bool success, ) = payable(owner).call{value: balance}("");
        if (!success) revert ETHTransferFailed();

        emit FundsWithdrawn(owner, balance);
    }

    function transferOwnership(address newOwner) external onlyOwner {
        if (newOwner == address(0)) revert InvalidRecipient();
        emit OwnershipTransferred(owner, newOwner);
        owner = newOwner;
    }

    receive() external payable {
        revert PlanNotFound();
    }
}
