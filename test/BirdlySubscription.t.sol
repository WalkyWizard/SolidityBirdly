pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {BirdlySubscription} from "../src/BirdlySubscription.sol";

contract BirdlySubscriptionTest is Test {
    BirdlySubscription public subscription;

    address payable public owner;
    address payable public user1;
    address payable public user2;

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

    function setUp() public {
        owner = payable(address(this));
        user1 = payable(makeAddr("user1"));
        user2 = payable(makeAddr("user2"));

        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);

        subscription = new BirdlySubscription();
    }

    receive() external payable {}

    function testDefaultPlansInitialized() public view {
        assertEq(subscription.planCount(), 4);

        BirdlySubscription.Plan memory plan1 = subscription.getPlan(1);
        assertEq(plan1.price, 0.005 ether);
        assertEq(plan1.duration, 30 days);
        assertTrue(plan1.unlocksHistory);
        assertFalse(plan1.unlocksMultimodal);
        assertTrue(plan1.active);

        BirdlySubscription.Plan memory plan2 = subscription.getPlan(2);
        assertEq(plan2.price, 0.01 ether);
        assertFalse(plan2.unlocksHistory);
        assertTrue(plan2.unlocksMultimodal);

        BirdlySubscription.Plan memory plan3 = subscription.getPlan(3);
        assertEq(plan3.price, 0.012 ether);
        assertTrue(plan3.unlocksHistory);
        assertTrue(plan3.unlocksMultimodal);

        BirdlySubscription.Plan memory plan4 = subscription.getPlan(4);
        assertEq(plan4.price, 0.1 ether);
        assertEq(plan4.duration, 365 days);
        assertTrue(plan4.unlocksHistory);
        assertTrue(plan4.unlocksMultimodal);
    }

    function testSubscribeHistoryOnly() public {
        vm.prank(user1);
        subscription.subscribe{value: 0.005 ether}(1);

        assertTrue(subscription.hasHistoryAccess(user1));
        assertFalse(subscription.hasMultimodalAccess(user1));
        assertFalse(subscription.hasFullAccess(user1));
        assertEq(subscription.historyExpiration(user1), block.timestamp + 30 days);
    }

    function testSubscribeMultimodalOnly() public {
        vm.prank(user1);
        subscription.subscribe{value: 0.01 ether}(2);

        assertFalse(subscription.hasHistoryAccess(user1));
        assertTrue(subscription.hasMultimodalAccess(user1));
        assertFalse(subscription.hasFullAccess(user1));
        assertEq(subscription.multimodalExpiration(user1), block.timestamp + 30 days);
    }

    function testSubscribeFullBundle() public {
        vm.prank(user1);
        subscription.subscribe{value: 0.012 ether}(3);

        assertTrue(subscription.hasHistoryAccess(user1));
        assertTrue(subscription.hasMultimodalAccess(user1));
        assertTrue(subscription.hasFullAccess(user1));
    }

    function testCannotSubscribeWhileActive() public {
        vm.startPrank(user1);
        subscription.subscribe{value: 0.012 ether}(3);

        vm.expectRevert(BirdlySubscription.SubscriptionAlreadyActive.selector);
        subscription.subscribe{value: 0.005 ether}(1);
        vm.stopPrank();
    }

    function testCancelSubscriptionResetsAccess() public {
        vm.startPrank(user1);
        subscription.subscribe{value: 0.012 ether}(3);
        assertTrue(subscription.hasHistoryAccess(user1));
        assertTrue(subscription.hasMultimodalAccess(user1));

        subscription.cancelSubscription();

        assertFalse(subscription.hasHistoryAccess(user1));
        assertFalse(subscription.hasMultimodalAccess(user1));
        assertEq(subscription.historyExpiration(user1), 0);
        assertEq(subscription.multimodalExpiration(user1), 0);

        subscription.subscribe{value: 0.005 ether}(1);
        assertTrue(subscription.hasHistoryAccess(user1));
        assertFalse(subscription.hasMultimodalAccess(user1));
        vm.stopPrank();
    }

    function testCancelSubscriptionWhenNoneActiveReverts() public {
        vm.prank(user1);
        vm.expectRevert(BirdlySubscription.NoActiveSubscription.selector);
        subscription.cancelSubscription();
    }

    function testAccessExpiresAfterDuration() public {
        vm.prank(user1);
        subscription.subscribe{value: 0.005 ether}(1);
        assertTrue(subscription.hasHistoryAccess(user1));

        vm.warp(block.timestamp + 31 days);
        assertFalse(subscription.hasHistoryAccess(user1));
    }

    function testExcessPaymentRefunded() public {
        uint256 balanceBefore = user1.balance;

        vm.prank(user1);
        subscription.subscribe{value: 0.05 ether}(1);

        uint256 balanceAfter = user1.balance;
        assertEq(balanceBefore - balanceAfter, 0.005 ether);
    }

    function testSubscribeInsufficientPaymentReverts() public {
        vm.prank(user1);
        vm.expectRevert(
            abi.encodeWithSelector(
                BirdlySubscription.InsufficientPayment.selector,
                0.005 ether,
                0.001 ether
            )
        );
        subscription.subscribe{value: 0.001 ether}(1);
    }

    function testSubscribeInvalidPlanReverts() public {
        vm.prank(user1);
        vm.expectRevert(BirdlySubscription.PlanNotFound.selector);
        subscription.subscribe{value: 1 ether}(999);
    }

    function testSubscribeInactivePlanReverts() public {
        subscription.updatePlan(1, 0.005 ether, 30 days, false);

        vm.prank(user1);
        vm.expectRevert(BirdlySubscription.PlanInactive.selector);
        subscription.subscribe{value: 0.005 ether}(1);
    }

    function testSubscribeForRecipient() public {
        vm.prank(user1);
        subscription.subscribeFor{value: 0.012 ether}(user2, 3);

        assertFalse(subscription.hasHistoryAccess(user1));
        assertTrue(subscription.hasHistoryAccess(user2));
        assertTrue(subscription.hasMultimodalAccess(user2));
    }

    function testGrantSubscriptionByOwner() public {
        subscription.grantSubscription(user1, true, false, 7 days);

        assertTrue(subscription.hasHistoryAccess(user1));
        assertFalse(subscription.hasMultimodalAccess(user1));
        assertEq(subscription.historyExpiration(user1), block.timestamp + 7 days);
    }

    function testGrantSubscriptionUnauthorizedReverts() public {
        vm.prank(user1);
        vm.expectRevert(BirdlySubscription.Unauthorized.selector);
        subscription.grantSubscription(user2, true, true, 7 days);
    }

    function testPauseAndUnpause() public {
        subscription.pause();

        vm.prank(user1);
        vm.expectRevert(BirdlySubscription.ContractPaused.selector);
        subscription.subscribe{value: 0.005 ether}(1);

        subscription.unpause();

        vm.prank(user1);
        subscription.subscribe{value: 0.005 ether}(1);
        assertTrue(subscription.hasHistoryAccess(user1));
    }

    function testWithdrawFunds() public {
        vm.prank(user1);
        subscription.subscribe{value: 0.012 ether}(3);

        uint256 ownerBalanceBefore = address(this).balance;
        subscription.withdraw();
        uint256 ownerBalanceAfter = address(this).balance;

        assertEq(ownerBalanceAfter - ownerBalanceBefore, 0.012 ether);
        assertEq(address(subscription).balance, 0);
    }

    function testWithdrawUnauthorizedReverts() public {
        vm.prank(user1);
        subscription.subscribe{value: 0.012 ether}(3);

        vm.prank(user1);
        vm.expectRevert(BirdlySubscription.Unauthorized.selector);
        subscription.withdraw();
    }

    function testCreatePlanByOwner() public {
        uint256 newPlanId = subscription.createPlan(
            "Weekend Pass",
            0.002 ether,
            2 days,
            true,
            true
        );

        assertEq(newPlanId, 5);
        BirdlySubscription.Plan memory plan = subscription.getPlan(5);
        assertEq(plan.name, "Weekend Pass");
        assertEq(plan.price, 0.002 ether);
        assertEq(plan.duration, 2 days);
    }

    function testTransferOwnership() public {
        subscription.transferOwnership(user1);
        assertEq(subscription.owner(), user1);

        vm.prank(user1);
        subscription.pause();
        assertTrue(subscription.paused());
    }

    function testGetSubscriptionStatus() public {
        vm.prank(user1);
        subscription.subscribe{value: 0.005 ether}(1);

        (
            bool hasHist,
            uint256 histExpiry,
            bool hasMulti,
            uint256 multiExpiry
        ) = subscription.getSubscriptionStatus(user1);

        assertTrue(hasHist);
        assertEq(histExpiry, block.timestamp + 30 days);
        assertFalse(hasMulti);
        assertEq(multiExpiry, 0);
    }
}
