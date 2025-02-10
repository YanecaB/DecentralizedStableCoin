// SPDX-License-Identifier: MIT

pragma solidity ^0.8.18;

import {Test, console} from "forge-std/Test.sol";
import {DeployDSC} from "../../script/DeployDSC.s.sol";
import {DecentralizedStableCoin} from "../../src/DecentralizedStableCoin.sol";
import {DSCEngine} from "../../src/DSCEngine.sol";
import {HelperConfig} from "../../script/HelperConfig.s.sol";
import {ERC20Mock} from "@openzeppelin/contracts/mocks/token/ERC20Mock.sol";

contract DSCEngineTest is Test {
    DeployDSC deployer;
    DecentralizedStableCoin dsc;
    DSCEngine dscEngine;
    HelperConfig config;
    address ethUsdPriceFeed;
    address btcUsdPriceFeed;
    address weth;

    address public USER = makeAddr("user");
    uint256 public constant AMOUNT_CALLATERAL = 10 ether;
    uint256 public constant STARTING_ERC20_BALANCE = 10 ether;
    uint256 public constant AMOUNT_DSC_TO_MINT = 4000; // remove the ether
    uint256 private constant LIQUIDATION_THRESHOLD = 50;
    uint256 private constant LIQUIDATION_PRECISION = 100;
    uint256 private constant PRECISION = 1e18;

    // modifiers
    modifier depositedCollateral() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_CALLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_CALLATERAL);
        vm.stopPrank();
        _;
    }

    modifier depositeCollateralAndMintDsc() {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_CALLATERAL);
        dscEngine.depositCollateral(weth, AMOUNT_CALLATERAL);
        dscEngine.mintDsc(AMOUNT_DSC_TO_MINT);
        vm.stopPrank();
        _;
    }

    function setUp() public {
        deployer = new DeployDSC();
        (dscEngine, dsc, config) = deployer.run();

        (ethUsdPriceFeed, btcUsdPriceFeed, weth,,) = config.activeNetworkConfig();

        ERC20Mock(weth).mint(USER, STARTING_ERC20_BALANCE);
    }

    // Constructor tests
    address[] public tokenAddresses;
    address[] public priceFeedAddresses;

    function testRevertIfTokenLengthDoesntMatchPriceFeeds() public {
        tokenAddresses.push(weth);
        priceFeedAddresses.push(ethUsdPriceFeed);
        priceFeedAddresses.push(btcUsdPriceFeed);

        vm.expectRevert(DSCEngine.DSCEngine__TokenAddressesAndPriceFeedAddressesMustBeSameLength.selector);
        new DSCEngine(tokenAddresses, priceFeedAddresses, address(dsc));
    }

    //Mint tests
    // function testRevertsIfMintedDscBreaksHealthFactor() public { // fix this test
    //     uint256 highMintAmount = 1000000;

    //     vm.startPrank(USER);
    //     ERC20Mock(weth).approve(address(dscEngine), AMOUNT_CALLATERAL);
    //     dscEngine.depositCollateral(weth, AMOUNT_CALLATERAL);
    //     dscEngine.mintDsc(AMOUNT_DSC_TO_MINT);

    //     uint256 expectedHealthFactor =
    //     dscEngine.getUserHealthFactor(highMintAmount, dscEngine.getUsdValue(weth, AMOUNT_CALLATERAL));

    //     console.log(dscEngine.getUserHealthFactor(USER));
    //     vm.expectRevert(abi.encodeWithSelector(DSCEngine.DSCEngine__BreaksHealthFactor.selector, expectedHealthFactor));
    //     dscEngine.mintDsc(highMintAmount);
    //     vm.stopPrank();
    //     console.log(dscEngine.getUserHealthFactor(USER));
    // }

    // Price tests
    function testGetUsdValue() public view {
        uint256 ethAmount = 15e18;
        uint256 expectedUsd = 30000e18;
        uint256 actualUsd = dscEngine.getUsdValue(weth, ethAmount);

        assertEq(expectedUsd, actualUsd);
    }

    function testGetTokenAmountFromUsd() public view {
        uint256 usdAmount = 100 ether;

        uint256 expectedWeth = 0.05 ether;
        uint256 actualWeth = dscEngine.getTokenAmountFromUsd(weth, usdAmount);

        assertEq(expectedWeth, actualWeth);
    }

    function testHealthFactor() public depositeCollateralAndMintDsc {
        uint256 collateralAdhustedForThreshold = (AMOUNT_CALLATERAL * LIQUIDATION_THRESHOLD) / LIQUIDATION_PRECISION;
        uint256 expectedResult =
            dscEngine.getUsdValue(weth, (collateralAdhustedForThreshold * PRECISION) / AMOUNT_DSC_TO_MINT);
        uint256 actualResult = dscEngine.getUserHealthFactor(USER);

        assertEq(actualResult, expectedResult);
    }

    // Deposite collateral test
    function testRevertsIfCollateralZero() public {
        vm.startPrank(USER);
        ERC20Mock(weth).approve(address(dscEngine), AMOUNT_CALLATERAL);

        vm.expectRevert(DSCEngine.DSCEngine__NeedsMoreThanZero.selector);
        dscEngine.depositCollateral(weth, 0);
        vm.stopPrank();
    }

    function testRevertsWithUnapprovedCollateral() public {
        ERC20Mock ranToken = new ERC20Mock("RAN", "RAN", USER, AMOUNT_CALLATERAL);
        vm.startPrank(USER);
        vm.expectRevert(DSCEngine.DSCEngine__NotAllowedToken.selector);
        dscEngine.depositCollateral(address(ranToken), AMOUNT_CALLATERAL);
        vm.stopPrank();
    }

    function testCanDepositCollateralAndGeAccountInfo() public depositedCollateral {
        (uint256 totalDscMinted, uint256 collateralValueInUsd) = dscEngine.getAccountInformation(USER);

        uint256 expectedTotalDscMinted = 0;
        uint256 expectedDepositeAmount = dscEngine.getTokenAmountFromUsd(weth, collateralValueInUsd);
        assertEq(totalDscMinted, expectedTotalDscMinted);
        assertEq(AMOUNT_CALLATERAL, expectedDepositeAmount);
    }

    function testGetAccountCollateralValue() public depositedCollateral {
        uint256 expecteAccountCollateralValue = dscEngine.getUsdValue(weth, AMOUNT_CALLATERAL);
        uint256 actualDepositedCollateral = dscEngine.getAccountCollateralValue(USER);

        assertEq(expecteAccountCollateralValue, actualDepositedCollateral);
    }
}
