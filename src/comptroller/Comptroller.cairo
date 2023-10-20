
const compInitialIndex: u256 = 10**36;
const closeFactorMinMantissa: u256 = 0.05**18;
const closeFactorMaxMantissa: u256 = 0.9**18;
const collateralFactorMaxMantissa: u256 = 0.9**18;

#[starknet::contract]
mod Comptroller {
  
  use starknet::ContractAddress;
  use starknet::get_caller_address;
  use mix::core::interface::CtokenInterface;
  use mix::core::interface::CtokenInterfaceDispatcher;
  use mix::exponential::{Exp, Double};
  use mix::exponential;
  use mix::priceOracle::PriceOracleInterface;
  use mix::priceOracle::PriceOracleInterfaceDispatcher;


  #[storage]
  struct Storage {
    admin: ContractAddress,
    pendingAdmin: ContractAddress,
    comptrollerImplementation: ContractAddress,
    pendingComptrollerImplementation: ContractAddress,


    //v1
    oracle: ContractAddress,
    closeFactorMantissa: u256,
    liquidationIncentiveMantissa: u256,
    maxAssets: u256,

    accountAssets: LegacyMap<ContractAddress, Array<ContractAddress>>,
   // key: (account-index) value: cToken
   // accountAssetsValue: LegacyMap<(ContractAddress, usize), u256>,


    //V2
    market: Market,
    markets: LegacyMap<ContractAddress, Market>,

    pauseGuardian: ContractAddress,
    _mintGuardianPaused: bool,
    _borrowGuardianPaused: bool,
    transferGuardianPaused: bool,
    seizeGuardianPaused: bool,

    mintGuardianPaused: LegacyMap<ContractAddress, bool>,
    borrowGuardianPaused: LegacyMap<ContractAddress, bool>,


    //V3
    compMarketState: CompMarketState,
    allMarkets: Array<ContractAddress>,
    compRate: u256,

    compSpeeds: LegacyMap<ContractAddress, u256>,
    compSupplyState: LegacyMap<ContractAddress, CompMarketState>,
    compBorrowState: LegacyMap<ContractAddress, CompMarketState>,
    compSupplierIndex: LegacyMap<ContractAddress, LegacyMap<ContractAddress, u256>>,
    compBorrowerIndex: LegacyMap<ContractAddress, LegacyMap<ContractAddress, u256>>,
    compAccrued: LegacyMap<ContractAddress, u256>,

    //V4
    borrowCapGuardian: ContractAddress,
    borrowCaps: LegacyMap<ContractAddress, u256>,

    //V5
    compContributorSpeeds: LegacyMap<ContractAddress, u256>,
    lastContributorBlock: LegacyMap<ContractAddress, u256>,

    //v6
    compBorrowSpeeds: LegacyMap<ContractAddress, u256>,
    compSupplySpeeds: LegacyMap<ContractAddress, u256>,

    proposal65FixExecuted: bool,
    compReceivable: LegacyMap<ContractAddress, u256>,
  }

  struct CompMarketState {
    index: u256,
    block: u32,
  }

  struct Market {
    isListed: bool,

    //  Multiplier representing the most one can borrow against their collateral in this market.
    //  For instance, 0.9 to allow borrowing 90% of collateral value.
    //  Must be between 0 and 1, and stored as a mantissa.
    collateralFactorMantissa: u256,

    // Per-market mapping of "accounts in this asset"
    accountMembership: LegacyMap<ContractAddress, bool>,

    // Whether or not this market receives COMP
    isComped: bool,
  }

  struct AccountLiquidityLocalVars{
    sumCollateral: u256,
    sumBorrowPlusEffects: u256,
    cTokenBalance: u256,
    borrowBalance: u256,
    exchangeRateMantissa: u256,
    oraclePriceMantissa: u256,
    collateralFactor: Exp,
    exchangeRate: Exp,
    oraclePrice: Exp,
    tokensToDenom: Exp,
  }



  #[event]
  #[derive(Drop, starknet::Event)]
  enum Event {
    // @notice Emitted when an admin supports a market
    MarketListed,
    // @notice Emitted when an account enters a market
    MarketEntered,
    // @notice Emitted when an account exits a market
    MarketExited,

    // @notice Emitted when close factor is changed by admin
    NewCloseFactor,
    // @notice Emitted when a collateral factor is changed by admin
    NewCollateralFactor,
    // @notice Emitted when liquidation incentive is changed by admin
    NewLiquidationIncentive,

    // @notice Emitted when price oracle is changed
    NewPriceOracle,
    // @notice Emitted when pause guardian is changed
    NewPauseGuardian,
    // @notice Emitted when an action is paused globally
    ActionPausedGlobal,
    // @notice Emitted when an action is paused on a market
    ActionPausedMarket,
    // @notice Emitted when a new COMP speed is calculated for a market
    CompSpeedUpdated,
    // @notice Emitted when a new COMP speed is set for a contributor
    ContributorCompSpeedUpdated,
    // @notice Emitted when COMP is distributed to a supplier
    DistributedSupplierComp,
    // @notice Emitted when COMP is distributed to a borrower
    DistributedBorrowerComp,
    // @notice Emitted when borrow cap for a cToken is changed
    NewBorrowCap,
    // @notice Emitted when borrow cap guardian is changed
    NewBorrowCapGuardian,
    // @notice Emitted when COMP is granted by admin
    CompGranted,
    // @notice Emitted when COMP accrued for a user has been manually adjusted.
    CompAccruedAdjusted,
    // @notice Emitted when COMP receivable for a user has been updated.
    CompReceivableUpdated,
  }

  #[derive(Drop, starknet::Event)]
  struct MarketListed{
    cToken: ContractAddress
  }

  #[derive(Drop, starknet::Event)]
  struct MarketEntered{
    cToken: ContractAddress,
    account: ContractAddress
  }

  #[derive(Drop, starknet::Event)]
  struct MarketExited{
    cToken: ContractAddress,
    account: ContractAddress,
  }

  #[derive(Drop, starknet::Event)]
  struct NewCloseFactor{
    oldCloseFactorMantissa: u256,
    newCloseFactorMantissa: u256,
  }

  #[derive(Drop, starknet::Event)]
  struct NewCollateralFactor{
    cToken: ContractAddress,
    oldCloseFactorMantissa: u256,
    newCloseFactorMantissa: u256,
  }

  #[derive(Drop, starknet::Event)]
  struct NewLiquidationIncentive{
    oldLiquidationIncentiveMantissa: u256,
    newLiquidationIncentiveMantissa: u256,
  }

  #[derive(Drop, starknet::Event)]
  struct NewPriceOracle {
    oldPriceOracle: ContractAddress,
    newPriceOracle: ContractAddress,
  }

  #[derive(Drop, starknet::Event)]
  struct NewPauseGuardian {
    oldPauseGuardian: ContractAddress,
    newPauseGuardian: ContractAddress,
  }

  #[derive(Drop, starknet::Event)]
  struct ActionPausedGlobal {
    action: felt252,
    pauseState: bool,
  }

  #[derive(Drop, starknet::Event)]
  struct ActionPausedMarket{
    cToken: ContractAddress,
    action: felt252,
    pauseState: bool,
  }

  #[derive(Drop, starknet::Event)]
  struct CompSpeedUpdated {
    cToken: ContractAddress,
    newSpeed: u256,
  }

  #[derive(Drop, starknet::Event)]
  struct ContributorCompSpeedUpdated {
    contributor: ContractAddress,
    newSpeed: u256,
  }

  #[derive(Drop, starknet::Event)]
  struct DistributedSupplierComp {
    cToken: ContractAddress,
    supplier: ContractAddress,
    compDelta: u256,
    compSupplyIndex: u256,
  }

  #[derive(Drop, starknet::Event)]
  struct DistributedBorrowerComp {
    cToken: ContractAddress,
    borrower: ContractAddress,
    compDelta: u256,
    compBorrowIndex: u256,
  }

  #[derive(Drop, starknet::Event)]
  struct NewBorrowCap {
    cToken: ContractAddress,
    NewBorrowCap: u256,
  }

  #[derive(Drop, starknet::Event)]
  struct NewBorrowCapGuardian {
    oldBorrowCapGuardian: ContractAddress,
    newBorrowCapGuardian: ContractAddress,
  }

  #[derive(Drop, starknet::Event)]
  struct CompGranted {
    recipient: ContractAddress,
    amount: ContractAddress,
  }

  #[derive(Drop, starknet::Event)]
  struct CompAccruedAdjusted {
    user: ContractAddress,
    oldCompAccrued: u256,
    newCompAccrued: u256,
  }

  #[derive(Drop, starknet::Event)]
  struct CompReceivableUpdated {
    user: ContractAddress,
    oldComReceiveable: u256,
    newCompReceivable: u256,
  }



  #[constructor]
  fn constructor(ref self: ContractState) {
    admin = get_caller_address();
  }

  //  * Assets You Are In ***/

  //  * @notice Returns the assets an account has entered
  //  * @param account The address of the account to pull assets for
  //  * @return A dynamic list with the assets the account has entered
  fn getAssetsIn(ref self: ContractState, account: ContractAddress) -> Array<ContractAddress> {
    self.accountAssets.read(account);
  }

  //  * @notice Returns whether the given account is entered in the given asset
  //  * @param account The address of the account to check
  //  * @param cToken The cToken to check
  //  * @return True if the account is in the asset, otherwise false.
  fn checkMembership(ref self: ContractState, account: ContractAddress) -> bool {
    self.markets.read(account).accountMembership(account);
  }

  //  * @notice Add assets to be included in account liquidity calculation
  //  * @param cTokens The list of addresses of the cToken markets to be enabled
  //  * @return Success indicator for whether each corresponding market was entered
  fn enterMarkets (ref self: ContractState,cTokens: Array<ContractAddress>) {
    let len = cTokens.len();
    let mut i: usize = 0;
    loop {
      ContractAddress cToken = cToken[i];
      InternalImpl::addToMarketInternal(cToken, get_caller_address());
      i += 1;
    }
  }


  fn exitMarket(ref self: ContractState, cToken: ContractAddress) {
    Ctoken ctoken = CtokenInterfaceDispatcher{ contract_address: ContractAddress};
    (oErr, tokensHeld, amountOwed, exchangeRate) = ctoken.getAccountSnapshot(get_caller_address());
    assert(oErr==0, "exitMarket: getAccountSnapshot failed");

    assert(amountOwed == 0, "sender has a borrow balance");
    
    u8 allowed = InternalImpl::redeemAllowedInternal(cToken, get_caller_address(), tokensHeld);
    assert(allowed == 0, "exit market rejection");

    Market marketToExit = self.markets.read(cToken);

    assert(marketToExit.accountMembership.read(get_caller_address()), "sender is not already in the market");

    //* Set cToken account membership to false */
    marketToExit.accountMembership.read(get_caller_address()).write(false);

    Array<ContractAddress> userAssetList = self.accountAssets.read(get_caller_address());

    let len = userAssetList.len();
    u256 assetIndex = len;
    let mut i: usize = 0;
    loop {
      if i > len {
        break;
      }
      if (userAssetList.get(i) == cToken) {
          assetIndex = i;
          break;
      }
      i = i + 1;
    }

    assert(assetIndex < len, "not find asset in the list");

    let mut assetsListNew = ArrayTrait::<ContractAddress>::new();
    let mut m: usize = 0;
    loop {
      if m > len {
        break;
      }
      if (assetIndex = m) {
        continue;
      }
      assetsListNew.append(userAssetList.get(m));
    }
   
    self.accountAssets.write(get_caller_address(), assetsListNew);

    self.emit( MarketExited{ cToken: cToken, account: get_caller_address() } )

  }


  fn mintAllowed(ref self: ContractState, cToken: ContractAddress, minter: ContractAddress, mintAmount: u256) -> u8 {
    assert(!self.mintGuardianPaused.read(cToken), "mint is paused");

    assert(self.markets.read(cToken).isListed, "market not listed");

    InternalImpl::updateCompSupplyIndex(cToken);
    InternalImpl::distributeSupplierComp(cToken, minter);
    0;
  }

  fn mintVerify(ref self: ContractState, cToken: ContractAddress, minter: ContractAddress, actualMintAmount: u256, mintTokens: u256){

  }

  fn redeemAllowed(ref self: ContractState, cToken: ContractAddress, redeemer: ContractAddress, redeemTokens: u256) -> u256 {
    let allowed: u256 = InternalImpl::redeemAllowedInternal(cToken, redeemer, redeemTokens);
    if (allowed != 0) {
      return allowed;
    }
    InternalImpl::updateCompSupplyIndex(cToken);
    InternalImpl::distributeSupplierComp(cToken, redeemer);
    0;
  }

  fn redeemVerify(ref self: ContractState, redeemer: ContractAddress, redeemAmount: u256, redeemTokens: u256) {

    assert(redeemTokens !=0 || redeemAmount <= 0, 'redeemTokens zero');

  }

  fn borrowAllowed(ref self: ContractState, cToken: ContractAddress, borrower: ContractAddress, BORROWaMOUNT: u256) {
    
    assert(!self.borrowGuardianPaused.read(cToken), "borrow is paused");

    if (!self.markets.read(cToken).isListed) {
      return 3;// Market_not_listed
    }

    if (self.markets.read(cToken).accountMembership.read(borrower)) {
      assert(get_caller_address() == cToken, "send must be cToken");

      let err: bool = InternalImpl::addToMarketInternal(get_caller_address(), borrower);
      if (!err) {
        return 3;
      }

      assert(self.markets.read(cToken).accountMembership.read(borrower), "");
    }

    if (self.oracle.getUnderlyingPrice(cToken) == 0) {
      return  4;//price error
    }

    let borrowCap: u256 = self.borrowCaps.read(cToken);

    if (borrowCap != 0) {
      let totalBorrows: u256 = CtokenInterfaceDispatcher{ contract_address: ContractAddress}.totalBorrows();
      let nextTotalBorrows = exponential.add_(totalBorrows, borrowAmount);
      assert(nextTotalBorrows < borrowCap, "market borrow cap reached");
    }

    (err, shortfall) = InternalImpl::getHypotheticalAccountLiquidityInternal(redeemer, cToken, redeemTokens, 0);
    if (err != 0) {
      return err;
    }

    if (shortfall > 0) {
      return 6;//insufficient_liquidity
    }

    let borrowIndex: Exp = Exp{ mantissa: CtokenInterfaceDispatcher{ contract_address: ContractAddress}.borrowIndex() };
    InternalImpl::updateCompBorrowIndex(cToken, borrowIndex);
    InternalImpl::distributeBorrowerComp(cToken, borrower, borrowIndex);

    0;
  }


  fn borrowVerify() {

  }

  fn repayBorrowAllow(ref self: ContractState, cToken: ContractAddress, 
            payer: ContractAddress, borrower: ContractAddress, repayAmount: unit256) -> unit256 {
    if (self.markets.read(cToken).isListed) {
      return 3;
    }

    let borrowIndex: Exp = Exp{ mantissa: CtokenInterfaceDispatcher{ contract_address: ContractAddress}.borrowIndex() };
    InternalImpl::updateCompBorrowIndex(cToken, borrowIndex);
    InternalImpl::distributeBorrowerComp(cToken, borrower, borrowIndex);
    0;
  }

  fn repayBorrowVerify (ref self: ContractState, cToken: ContractAddress, 
            payer: ContractAddress, borrower: ContractAddress, repayAmount: unit256, borrowerIndex: unit256) -> unit256 {

  }

  fn liquidateBorrowAllowed(ref self: ContractState, cTokenBorrowed: ContractAddress, cTokenCollateral: ContractAddress,
            liquidator: ContractAddress, borrower: ContractAddress, repayAmount: unit256) -> unit256 {
    if (!self.markets.read(cTokenBorrowed).isListed || !self.markets.read(cTokenCollateral).isListed) {
      return 3;
    }

    let borrowBalance: u256 = CtokenInterfaceDispatcher{ contract_address: ContractAddress}.borrowBalanceStored(borrower);

    if (self.isDeprecated(cTokenBorrowed)) {
      assert(borrowBalance >= repayAmount, "Can not repay more than the total borrow");
    } else {
      (err, c, shortfall) = InternalImpl::getAccountLiquidityInternal(borrower);
      if (err != 0) {
        return err;
      }

      if (shortfall == 0) {
        return 6;//insufficient shortfall;
      }

      let maxClose: u256 = exponential.mul_ScalarTruncate(Exp{ mantissa: closeFactorMantissa }, borrowBalance);
      if (repayAmount > maxClose) {
        return 7; //too much repay
      }

    }
    0;
  }

  fn liquidateBorrowVerify(ref self: ContractState, cTokenBorrowed: ContractAddress, cTokenCollateral: ContractAddress,
            liquidator: ContractAddress, borrower: ContractAddress, repayAmount: unit256, seizeTokens: unit256) {

  
  }

  fn seizeAllowed(ref self: ContractState, cTokenCollateral: ContractAddress, cTokenBorrowed: ContractAddress, liquidator: ContractAddress,
            borrower: ContractAddress, seizeTokens: unit256) -> unit256 {
    assert(!self.seizeGuardianPaused, 'seize is paused');

    if (self.markets.read(cTokenCollateral).isListed || !self.markets.read(cTokenBorrowed).isListed) {
      return 3;
    }

    let cTokenCollateralAddr: ContractAddress = CtokenInterfaceDispatcher{contract_address: cTokenCollateral }.comptroller();
    let cTokenBorrowedAddr: ContractAddress = CtokenInterfaceDispatcher{contract_address: cTokenBorrowed }.comptroller();
    if (cTokenCollateralAddr!=cTokenBorrowedAddr) {
      return 8;//COMPTROLLER_MISMATCH
    }
    InternalImpl::updateCompSupplyIndex(cTokenCollateral);
    InternalImpl::distributeSupplierComp(cTokenCollateral, borrower);
    InternalImpl::distributeSupplierComp(cTokenCollateral, liquidator);

    0;
  }

  fn seizeVerify(ref self: TState, cTokenCollateral: ContractAddress, cTokenBorrowed: ContractAddress, liquidator: ContractAddress,
            borrower: ContractAddress, seizeTokens: unit256) {
 
  }

  fn transferAllowed(ref self: TState, cToken: ContractAddress, src: ContractAddress, dst: ContractAddress, transferToken: unit256) {
    assert(self.transferGuardianPaused, 'transfer is paused');

    let allowed: u256 = InternalImpl::redeemAllowedInternal(cToken, src, transferTokens);
    if (allowed != 0) {
      return allowed;
    }

    InternalImpl::updateCompSupplyIndex(cToken);
    InternalImpl::distributeSupplierComp(cToken, src);
    InternalImpl::distributeSupplierComp(cToken, dst);

    0;
  }

  fn transferVerify(ref self: TState, cToken: ContractAddress, src: ContractAddress, dst: ContractAddress, transferTokens:unit256) {

  }


  fn liquidateCalculateSeizeTokens(ref self: TState, cTokenBorrowed: ContractAddress, cTokenCollateral: ContractAddress) -> (u256, u256) {
    let priceBorrowedMantissa:u256 = self.oracle.getUnderlyingPrice(cTokenBorrowed);
    let priceCollateralMantissa = self.oracle.getUnderlyingPrice(cTokenCollateral);
    if (priceBorrowedMantissa == 0 || priceCollateralMantissa == 0) {
      return (4, 0);
    }

    let exchangeRateMantissa: u256 = CtokenInterfaceDispatcher{ contract_address: cTokenCollateral }.exchangeRateStored();
    let numerator: Exp = exponential.mul_(Exp{ mantissa: liquidationIncentiveMantissa}, Exp{ mantissa: priceBorrowedMantissa } );
    let denominator: Exp = exponential.mul_( Exp { mantissa: priceCollateralMantissa }, Exp{ mantissa: exchangeRateMantissa });

    let seizeTokens: u256 = exponential.mul_ScalarTruncate(ratio, actualRepayAmount);
    (0, seizeTokens);
  }


  fn isDeprecated(ref self: ContractState, cToken: ContractAddress) -> bool {
    self.markets.read(cToken).collateralFactorMantissa == 0 &&
    self.borrowGuardianPaused.read(cToken) == true &&
    CtokenInterfaceDispatcher{ contract_address: ContractAddress}.reserveFactorMantissa() == 10**18;
  }



  fn _setMintPaused(ref self: ContractState, cToken: ContractAddress, state: bool) -> bool {
     assert(self.markets.read(cToken).isListed, "cannot pause a market that is not listed");
     assert(get_caller_address() == self.pauseGuardian || get_caller_address() == admin , "only pause guardian and admin can pause");
     assert(get_caller_address() == admin || state == true, "only admin can unpause");

     self.mintGuardianPaused.write(cToken, state);

     self.emit(ActionPausedMarket{ cToken: cToken,  action: "Mint", pauseState: state});
     state;
  }

  fn _setPriceOracle(ref self: ContractState, oracle: ContractAddress ) {
    assert(get_caller_address()==self.admin, "set price oracle owner check failed");

    let oldOracle = self.oracle;

    self.oracle = oracle;

    self.emit( NewPriceOracle{ oldPriceOracle:oldOracle, newPriceOracle: oracle } );

    0;
  }

  fn _setCollateralFactor(ref self: ContractState, cToken: ContractAddress, newCollateralFactorMantissa: u256)->u8 {
    assert(get_caller_address() == admin , "set collateral factor owner check failed");

    let market: Market = self.markets.read(cToken);
    assert(market.isListed, "failed, set collateral factor no exists.");

    let newCollateralFactorExp: Exp = Exp{ mantissa: newCollateralFactorMantissa };
    let highLimit = Exp{ mantissa: collateralFactorMaxMantissa };
    assert(exponential.lessThanExp(highLimit, newCollateralFactorExp), "invalid collateral factor");

    assert(newCollateralFactorMantissa == 0 || self.oracle.getUnderlyingPrice(cToken) != 0 , "price error.SET_COLLATERAL_FACTOR_WITHOUT_PRICE");

    let oldCollateralFactorMantissa:u256 = market.collateralFactorMantissa;
    market.collateralFactorMantissa = newCollateralFactorMantissa;

    self.emit( NewCollateralFactor{cToekn: cToken, oldCloseFactorMantissa: oldCollateralFactorMantissa, newCloseFactorMantissa:newCollateralFactorMantissa  });
    0;
  }




  #[generate_trait]
  impl InternalImpl of InternalTrait {

    //  * @notice Add the market to the borrower's "assets in" for liquidity calculations
    //  * @param cToken The market to enter
    //  * @param borrower The address of the account to modify
    //  * @return Success indicator for whether the market was entered
    fn addToMarketInternal(ref self: ContractState,cToken: ContractAddress, borrower: ContractAddress ) -> bool {
      Market marketToJoin = self.markets.read(cToken);

      assert(marketToJoin.isListed, "market not listed");
      assert(!marketToJoin.accountMembership.read(borrower), "already joined");

      if (!marketToJoin.accountMembership.read(borrower)) {
        marketToJoin.accountMembership.write(borrower, true);
        self.accountAssets.read(borrower).append(cToken);

        self.emit( MarketEntered { cToken: cToken, account: borrower} );
        true;
      } 
    }

    fn redeemAllowedInternal(ref self: ContractState, cToken: ContractAddress, redeemer: ContractAddress, redeemTokens: u256 ) -> u8 {
      assert(self.markets.read(cToken).isListed, "market not listed");
      assert(self.markets.read(cToken).accountMembership.read(redeemer), "redeemer is not in the market");

      (err, shortfall) = getHypotheticalAccountLiquidityInternal(redeemer, cToken, redeemTokens, 0);
      if (err != 0) {
        return err;
      }
      if (shortfall > 0) {
        return 3;
      }
      return 0;
    }

    fn getAccountLiquidityInternal(ref self: ContractState, account: ContractAddress) -> (u8, u256, u256) {
      getHypotheticalAccountLiquidityInternal(account, 0, 0, 0);
    }

    fn getHypotheticalAccountLiquidityInternal(ref self: ContractState, account: ContractAddress, cTokenModify: ContractAddress, redeemTokens: u256, borrowAmount: u256) -> (u8, u256, u256) {
      AccountLiquidityLocalVars vars;
      oErr u8;

      let assets: Array<ContractAddress> = self.accountAssets.read(account);
      let mut index: u256 = 0;
      loop {
        ContractAddress asset = *assets.get(index);
        (oErr, vars.cTokenBalance, vars.borrowBalance, vars.exchangeRateMantissa) = asset.getAccountSnapshot(account);
        if (oErr != 0) {
          break (1, 0, 0);
        }

        vars.collateralFactor = Exp{ mantissa: markets.read(asset).collateralFactorMantissa };
        vars.exchangeRate = Exp {mantissa: vars.exchangeRateMantissa };

        let oracleDispatcher = PriceOracleInterfaceDispatcher{ contract_address: self.oracle };

        vars.oraclePriceMantissa = oracleDispatcher.getUnderlyingPrice(asset);

        if (vars.oraclePriceMantissa == 0) {
          break (2, 0, 0);
        }

        vars.oraclePrice = Exp{ mantissa: vars.oraclePriceMantissa };

        vars.tokensTodenom = exponential.mul_(exponential.mul_(vars.collateralFactor, vars.exchangeRate), vars.oraclePrice);

        vars.sumCollateral = exponential.mul_ScalarTruncateAddUInt(vars.tokensToDenom, vars.cTokenBalance, vars.sumCollateral);

        vars.sumborrowPlusEffects = exponential.mul_ScalarTruncateAddUInt(vars.oraclePrice, vars.borrowBalance, vars.sumBorrowPlusEffects);

        if (asset == cTokenModify) {
          var.sumBorrowPlusEffects = exponential.mul_ScalarTruncateAddUInt(vars.tokensToDenom, redeemTokens, vars.sumBorrowPlusEffects);

          vars.sumBorrowPlusEffects = exponential.mul_ScalarTruncateAddUInt(vars.oraclePrice, borrowAmount, vars.sumBorrowPlusEffects);
        }

        index = index + 1;
      }

      if (vars.sumCollateral > vars.sumBorrowPlusEffects) {
        return (0, vars.sumCollateral - vars.sumBorrowPlusEffects, 0);
      } else {
        return (0, 0, vars.sumBorrowPlusEffects - vars.sumCollateral);
      }

    }

    //https://godorz.info/2021/11/compound_comp_and_price_oracles/
    fn updateCompSupplyIndex(ref self: ContractState, cToken: ContractAddress) {
      CompMarketState supplyState = self.compSupplyState.read(cToken);
      u256 supplySpeed = self.compSupplySpeeds.read(cToken);
      u32 blockNumber = exponential.safe32(get_block_number(), "block number exceeds 32 bits");
      u32 deltaBlocks = exponential.sub_(blockNumber, supplyState.block);
      if (deltaBlocks > 0 && supplySpeed > 0) {
        u256 supplyTokens = CtokenInterfaceDispatcher { contract_address: cToken }.totalSupply();
        u256 compAccrued = exponential.mul_(deltaBlocks, supplySpeed);
        let mut ratio:Double = exponential.fraction(compAccrued, supplyTokens);
        if (supplyTokens <= 0) {
          ratio = Double{ mantissa: 0 };
        }

        supplyState.index = exponential.safe256(add_(Double{ mantissa: supplyState.index }, ratio.mamtissa), "new index exceeds 256 bits");
      } else if (deltaBlocks > 0 ){
        supplyState.block = blockNumber;
      }

    }

    fn updateCompBorrowIndex(ref self: ContractState, cToken: ContractAddress, marketBorrowIndex: Exp) {
      CompMarketState borrowState = self.compBorrowState.read(cToken);
      let mut borrowSpeed:u256 = self.compBorrowSpeeds.read(cToken);
      let mut blockNumber:u32 = exponential.safe32(get_block_number(), "block number exceeds 32 bits");
      let deltaBlocks:u256 = exponential.mul_(deltaBlocks, borrowSpeed);
      if (deltaBlocks > 0 && borrowSpeed > 0) {
        let totalBorrow:u256 = CtokenInterfaceDispatcher { contract_address: cToken }.totalSupply();
        let borrowAmount:u256 = exponential.dev_(totalBorrow, marketBorrowIndex);
        let ratio:Double = exponential.fraction(compAccrued, brrowAmount);
        if (borrowAmount <= 0) {
          ratio = Double{ mantissa: 0 };
        }
        borrowState.index = exponential.safe256(exponential.add_(Double{ mantissa: borrowState.index }, ratio).mantissa, "new index exceeds 256 bits");
        borrowState.block = blockNumber;
      } else if (deltaBlocks > 0) {
        borrowState.block = blockNumber;
      }
    }

    fn distributeSupplierComp(ref self: ContractState, cToken: ContractAddress, supplier: ContractAddress) {
      CompMarketState supplyState = self.compSupplyState.read(cToken);
      u256 supplyIndex = supplyState.index;
      let mut compSupply:LegacyMap<ContractAddress, u256> = self.compSupplierIndex.read(cToken);
      u256 supplierIndex = compSupply.read(supplier);
      compSupply.write(supplier, supplyIndex);

      self.compSupplierIndex.write(cToken, compSupply);

      if (supplierIndex == 0 && supplyIndex >= compInitialIndex ) {
        supplierIndex = compInitialIndex;
      }
      let deltaIndex:Double = Double { mantissa: exponential.sub_(supplyIndex, supplierIndex) };
      let supplierTokens:u256 =  CtokenInterfaceDispatcher { contract_address: cToken }.balanceOf(supplier);
      let supplierDelta:u256 = exponential.mul_(supplierTokens, deltaIndex);
      let supplierAccrued:u256 = exponential.add_(self.compAccrued.read(supplier), supplierDelta);

      self.compAccrued.write(supplier, supplierAccrued);

      self.emit( DistributedSupplierComp { cToken: cToken, supplier: supplier, compDelta: supplierDelta, compSupplyIndex: supplyIndex } );
    }

    fn distributeBorrowerComp(ref self: ContractState, cToken: ContractAddress, borrower: ContractAddress, marketBorrowIndex: Exp ) {
      CompMarketState borrowState = self.compBorrowState.read(cToken);
      let borrowIndex = borrowState.index;
      let mut borrowerIndexMap:LegacyMap<ContractAddress, u256> = self.compBorrowerIndex.read(cToken);
      let borrowerIndex: u256 = borrowerIndexMap.read(borrower);
      borrowerIndexMap.write(borrower, borrowIndex);
      self.compBorrowerIndex.write(cToken, borrowerIndexMap);

      if (borrowerIndex == 0 && borrowIndex >= compInitialIndex) {
        borrowerIndex = compInitialIndex;
      }

      let deltaIndex:Double = Double{ mantissa: exponential.sub_(borrowIndex, borrowerIndex)};
      let borrowerAmount = exponential.div_(CtokenInterfaceDispatcher { contract_address: cToken }.borrowBalanceStored(borrower), marketBorrowIndex);

      let borrowerDelta:u256 = exponential.mul_(borrowerAmount, deltaIndex);

      let borrowerAccrued = exponential.add_(self.compAccrued.read(borrower), borrowerDelta);

      self.compAccrued.write(borrower, borrowerAccrued);

      self.emit(DistributedBorrowerComp{ cToken: cToken, borrower:borrower, compDelta: borrowerDelta, compBorrowIndex: borrowIndex});

    }
  }
}
