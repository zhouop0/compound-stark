#[starknet::contract]
mod Ctoken {

    use starknet::get_caller_address;
    use starknet::get_contract_address;
    use starknet::info::get_block_number;
    use starknet::info::get_tx_info;
    use starknet::info::TxInfo;
    use super::ERC20DispatcherTrait;
    use super::ERC20Dispatcher;

    use mix::core::interface::CErc20Interface;
    use mix::core::interface::CEthInterface;

    use mix::core::interface::EIP20Interface;
    use mix::core::interface::EIP20InterfaceDispatcher;
    use mix::core::interface::CEthInterface;
    use mix::core::interface::CEthInterfaceDispatcher;

    use comptroller::ComptrollerInterface;
    use comptroller::ComptrollerInterfaceDispatcher;
    use comptroller::ComptrollerInterfaceDispatcherTrait;
    use interface::InterestRateModel;
    use interface::InterestRateModelDispatcher;
    use interface::InterestRateModelDispatcherTrait;
    use mix::exponential::{Exp, Double};
    use mix::exponential;

    const borrowRateMaxMantissa: u256 = 0.0005**16;
    const reserveFactorMaxMantissa: u256 = 1**18;
    const protocalSeizeShareMantissa: u256 = 2.8**16;
    const expScale: u256 = 1**18;
    const mantissaOne: u256 = 1**18;

    #[storage]
    struct Storage {
        underlying: ContractAddress,
        _notEntered: bool,
        name: felt252,
        symbol: felt252,
        decimals: u8,
        admin: ContractAddress,
        pendingAdmin: ContractAddress,
        comptroller: ContractAddress,
        interestRateModel: ContractAddress,
        initialExchangeRateMantissa: u256,
        reserveFactorMantissa: u256,
        accrualBlockNumber: u256,
        borrowIndex: u256,
        totalBorrows: u256,
        totalReserves: u256,
        totalSupply: u256,
        accountTokens: LegacyMap<ContractAddress, u256>,
        transferAllowances: LegacyMap<ContractAddress, LegacyMap<ContractAddress, u256>>,
        accountBorrows: LegacyMap<ContractAddress, BorrowSnapshot>,
        isErc20:bool,
    }

    struct BorrowSnapshot {
        principal: u256,
        interestIndex: u256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        NewComptroller,
        NewMarketInterestRateModel,
        AccrueInterest,
        Transfer,
        Redeem,
        Borrow,
        RepayBorrow,
        ReservesAdded,
        LiquidateBorrow,
        Approval,
        NewPendingAdmin,
        NewAdmin,
        NewReserveFactor,
        ReservesReduced,
        
    }


    #[derive(Drop, starknet::Event)]
    struct NewComptroller {
        oldComptroller: ContractAddress,
        newComptroller: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct NewMarketInterestRateModel {
        oldInterestRateModel: ContractAddress ,
        newInterestRateModel: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct AccrueInterest {
        cashPrior: u256 ,
        interestAccumulated: u256,
        borrowIndex: u256,
        totalBorrows: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Transfer {
        from: ContractAddress,
        to: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Redeem {
        redeemer: ContractAddress,
        redeemAmount: u256,
        redeemTokens: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Borrow {
        borrower: ContractAddress,
        borrowAmount: u256,
        accountBorrowsNew: u256,
        totalBorrowsNew: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct RepayBorrow {
        payer: ContractAddress,
        borrower: ContractAddress,
        repayAmount: u256,
        accountBorrows: u256,
        totalBorrows: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ReservesAdded {
        admin: ContractAddress,
        actualAddAmount: u256,
        totalReservesNew: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct LiquidateBorrow {
        liquidator: ContractAddress,
        borrower: ContractAddress,
        repayAmount: u256,
        cTokenCollateral: ContractAddress,
        seizeTokens: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct Approval {
        owner: ContractAddress,
        spender: ContractAddress,
        amount: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct NewPendingAdmin {
        oldPendingAdmin: ContractAddress,
        newPendingAdmin: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct NewAdmin {
        oldAdmin: ContractAddress,
        newAdmin: ContractAddress,
    }

    #[derive(Drop, starknet::Event)]
    struct NewReserveFactor {
        oldReserveFactorMantissa: u256,
        newReserveFactorMantissa: u256,
    }

    #[derive(Drop, starknet::Event)]
    struct ReservesReduced {
        admin: ContractAddress,
        reduceAmount: u256,
        newTotalReserves: u256,
    }


    #[constructor]
    fn constructor(ref self: ContractState, 
                    underlying_: ContractAddress,
                    comptroller_: ContractAddress,
                    interestRateModel_: ContractAddress,
                    initialExchangeRateMantissa: u256,
                    name_: felt252, 
                    symbol_: felt252,
                    decimals_: u8,
                    isErc20: bool,
                    admin_: ContractAddress
                    ) {
        self.isErc20 = isErc20;
        if (!isErc20) {
            self.admin = get_caller_address();
            InternalImpl::initializer(self, comptroller_, interestRateModel_, initialExchangeRateMantissa, name_, symbol_, decimals_);
            self.admin = admin_;
        } else {
            InternalImpl::initializer(self, comptroller_, interestRateModel_, initialExchangeRateMantissa, name_, symbol_, decimals_);
            self.underlying = underlying_;
            EIP20InterfaceDispatcher { _underlying }.totalSupply();
        }
    }

    
    impl CEth of CEthInterface {

        fn mint(ref self: ContractState, mintAmount: u256) -> u8 {
            InternalImpl::mintInternal(mintAmount, false);
            0;
        }

        fn redeem(ref self: ContractState, mintAmount: u256) -> u8  {
            self.accrueInterest(false);
            //  * @param redeemer The address of the account which is redeeming the tokens
            //  * @param redeemTokensIn The number of cTokens to redeem into underlying (only one of redeemTokensIn or redeemAmountIn may be non-zero)
            ContractAddress redeemer = get_caller_address();
            u256 redeemTokensIn = redeemTokens;

            assert(redeemTokensIn == 0 || redeemAmountIn == 0, "one of redeemTokensIn or redeemAmountIn must be zero");

            Exp exchangeRate = Exp{ mantissa: InternalImpl::exchangeRateStoredInternal(false) };

            u256 redeemTokens;
            u256 redeemAmount;

            if (redeemTokensIn > 0) {
                
            //  * We calculate the exchange rate and the amount of underlying to be redeemed:
            //  *  redeemTokens = redeemTokensIn
            //  *  redeemAmount = redeemTokensIn x exchangeRateCurrent
                redeemTokens = redeemTokensIn;
                redeemAmount = exponential.mul_ScalarTruncate(exchangeRate, redeemTokensIn);
            } else {
                redeemTokens = exponential.div_(redeemAmountIn, exchangeRate);
                redeemAmount = redeemAmountIn;
            }

            ContractAddress comptroller_address = self.comptroller;

            u256 allowed = ComptrollerInterfaceDispatcher { contract_address: comptroller_address }.redeemAllowed(get_contract_address().redeemer, redeemTokens);

            assert(allowed == 0, "redeem rejection");
            assert(self.accrualBlockNumber == get_block_number(), "redeem freshness check");
            assert(getCashPrior(false) >= redeemAmount, "redeem transfer out not possible");

            // * We write the previously calculated values into storage.
            // *  Note: Avoid token reentrancy attacks by writing reduced supply before external transfer.
            self.totalSupply = self.totalSupply - redeemTokens;
            let res = self.accountTokens.read(redeemer) - redeemTokens;
            self.accountTokens.write(redeemer, res);

            InternalImpl::doTransferOut(redeemer, redeemAmount, false);

            self.emit( Transfer(from: redeemer, to: get_contract_address(), amount: redeemTokens) );
            self.emit( Redeem(redeemer: redeemer, redeemAmount: redeemAmount, redeemTokens: redeemTokens) );

            let comptrollerAddress = self.comptroller;
            ComptrollerInterfaceDispatcher { contract_address:comptrollerAddress }.redeemVerify(get_contract_address(), redeemer, redeemAmount, redeemTokens);
            0;
        }

        fn redeemUnderlying(ref self: ContractState, redeemAmount: u256) -> u8 {

            self.accrueInterest(false);
            ContractAddress redeemer = get_caller_address();
            u256 redeemTokensIn = 0;

            assert(redeemTokensIn == 0 || redeemAmountIn == 0, "one of redeemTokensIn or redeemAmountIn must be zero");

            Exp exchangeRate = Exp{ mantissa: InternalImpl::exchangeRateStoredInternal(false) };

            u256 redeemTokens;
            u256 redeemAmount;

            if (redeemTokensIn > 0) {
                
            //  * We calculate the exchange rate and the amount of underlying to be redeemed:
            //  *  redeemTokens = redeemTokensIn
            //  *  redeemAmount = redeemTokensIn x exchangeRateCurrent
                redeemTokens = redeemTokensIn;
                redeemAmount = exponential.mul_ScalarTruncate(exchangeRate, redeemTokensIn);
            } else {
                redeemTokens = exponential.div_(redeemAmountIn, exchangeRate);
                redeemAmount = redeemAmountIn;
            }

            ContractAddress comptroller_address = self.comptroller;

            u256 allowed = ComptrollerInterfaceDispatcher { comptroller_address }.redeemAllowed(get_contract_address().redeemer, redeemTokens);

            assert(allowed == 0, "redeem rejection");
            assert(self.accrualBlockNumber == get_block_number(), "redeem freshness check");
            assert(getCashPrior(false) >= redeemAmount, "redeem transfer out not possible");

            // * We write the previously calculated values into storage.
            // *  Note: Avoid token reentrancy attacks by writing reduced supply before external transfer.
            self.totalSupply = self.totalSupply - redeemTokens;
            let res = self.accountTokens.read(redeemer) - redeemTokens;
            self.accountTokens.write(redeemer, res);

            InternalImpl::doTransferOut(redeemer, redeemAmount, false);

            self.emit( Transfer(from: redeemer, to: get_contract_address(), amount: redeemTokens) );
            self.emit( Redeem(redeemer: redeemer, redeemAmount: redeemAmount, redeemTokens: redeemTokens) );

            let comptrollerAddress = self.comptroller;
            ComptrollerInterfaceDispatcher { comptrollerAddress }.redeemVerify(get_contract_address(), redeemer, redeemAmount, redeemTokens);
            0;
        }

        fn borrow(ref self: ContractState, borrowAmount: u256) -> u8 {
            InternalImpl::borrowInternal(borrowAmount, false);
            0;
        } 

        fn repayBorrow(ref self: ContractState, repayAmount: u256 ) -> u256 {
            self.accrueInterest(false);
            let comptrollerAddress = self.comptroller;
            ContractAddress borrower = get_caller_address();
            ContractAddress payer = get_caller_address();
            InternalImpl::repayBorrowFresh(payer, borrower, repayAmount, false);
        }

        fn repayBorrowBehalf(ref self: ContractState, borrower: ContractAddress) {
            self.accrueInterest(false);
            let comptrollerAddress = self.comptroller;
            ContractAddress borrower = get_caller_address();
            ContractAddress payer = get_caller_address();
            u256 allowed = ComptrollerInterfaceDispatcher { contract_address:comptrollerAddress }.repayBorrowAllowed(get_contract_address(), payer, borrower, repayAmount);

            assert(allowed == 0, "repay borrow comptroller rejection");
            assert(self.accrualBlockNumber == get_block_number(), "repay borrow freshness check");
            assert(repayAmount>0, "repayAmount can not be less than zero ");

            u256 accountBorrowsPrev = InternalImpl::borrowBalanceStoredInternal(borrower);

            u256 repayAmountFinal;

            // need validate
            if (repayAmount >= accountBorrowsPrev) {
                repayAmountFinal = accountBorrowsPrev;
            } else {
                repayAmountFinal = repayAmount;
            }
            
            u256 actualRepayAmount = InternalImpl::doTransferInErc20(payer, repayAmountFinal);


            u256 accountBorrowsNew = accountBorrowsPrev - actualRepayAmount;
            u256 totalBorrowsNew = self.totalBorrows - actualRepayAmount;

            BorrowSnapshot borrowSnapshot = self.accountBorrows.read(borrower);
            borrowSnapshot.principal = accountBorrowsNew;
            borrowSnapshot.interestIndex = self.borrowIndex;

            self.totalBorrows = totalBorrowsNew;

            self.emit( RepayBorrow(payer: payer, borrow: borrow, repayAmount: actualRepayAmount, accountBorrows: accountBorrowsNew, totalBorrows: totalBorrowsNew) );

            actualRepayAmount;
        }


        fn repayBorrowBehalf (ref self: ContractState, borrower: ContractAddress, repayAmount: u256 ) -> u256 {
            self.accrueInterest(false);

            let comptrollerAddress = self.comptroller;
            ContractAddress payer = get_caller_address();

            u256 allowed = ComptrollerInterfaceDispatcher { contract_address:comptrollerAddress }.repayBorrowAllowed(get_contract_address(), payer, borrower, repayAmount);

            assert(allowed == 0, "repay borrow comptroller rejection");
            assert(self.accrualBlockNumber == get_block_number(), "repay borrow freshness check");
            assert(repayAmount>0, "repayAmount can not be less than zero ");

            u256 accountBorrowsPrev = InternalImpl::borrowBalanceStoredInternal(borrower);

            u256 repayAmountFinal;

            // need validate
            if (repayAmount >= accountBorrowsPrev) {
                repayAmountFinal = accountBorrowsPrev;
            } else {
                repayAmountFinal = repayAmount;
            }
            
            u256 actualRepayAmount = InternalImpl::doTransferInEth(payer, repayAmountFinal);


            u256 accountBorrowsNew = accountBorrowsPrev - actualRepayAmount;
            u256 totalBorrowsNew = self.totalBorrows - actualRepayAmount;

            BorrowSnapshot borrowSnapshot = self.accountBorrows.read(borrower);
            borrowSnapshot.principal = accountBorrowsNew;
            borrowSnapshot.interestIndex = self.borrowIndex;

            self.totalBorrows = totalBorrowsNew;

            self.emit( RepayBorrow(payer: payer, borrow: borrow, repayAmount: actualRepayAmount, accountBorrows: accountBorrowsNew, totalBorrows: totalBorrowsNew) );

            actualRepayAmount;

        }

        fn _addReserves(ref self: TContractState, addAmount: u256) -> u256 {
            InternalImpl::_addReserves(addAmount);

        }

        //清算
        fn liquidateBorrow(ref self: ContractState, borrower: ContractAddress, repayAmount: u256, cTokenCollateral: ContractAddress) -> u256 {
            InternalImpl::liquidateBorrowInternal(borrower, repayAmount, cTokenCollateral);
            0;
        }

    }


    #[external(v0)]
    impl CErc20 of CErc20Interface<ContractState>{

        fn mint(ref self: ContractState, mintAmount: u256) -> u8 {
            InternalImpl::mintInternal(mintAmount, true);
            0;
        }

        fn redeem(ref self: ContractState, redeemTokens: u256) -> u256 {
            self.accrueInterest(true);
            //  * @param redeemer The address of the account which is redeeming the tokens
            //  * @param redeemTokensIn The number of cTokens to redeem into underlying (only one of redeemTokensIn or redeemAmountIn may be non-zero)
            ContractAddress redeemer = get_caller_address();
            u256 redeemTokensIn = redeemTokens;

            assert(redeemTokensIn == 0 || redeemAmountIn == 0, "one of redeemTokensIn or redeemAmountIn must be zero");

            Exp exchangeRate = Exp{ mantissa: InternalImpl::exchangeRateStoredInternal(true) };

            u256 redeemTokens;
            u256 redeemAmount;

            if (redeemTokensIn > 0) {
                
            //  * We calculate the exchange rate and the amount of underlying to be redeemed:
            //  *  redeemTokens = redeemTokensIn
            //  *  redeemAmount = redeemTokensIn x exchangeRateCurrent
                redeemTokens = redeemTokensIn;
                redeemAmount = exponential.mul_ScalarTruncate(exchangeRate, redeemTokensIn);
            } else {
                redeemTokens = exponential.div_(redeemAmountIn, exchangeRate);
                redeemAmount = redeemAmountIn;
            }

            ContractAddress comptroller_address = self.comptroller;

            u256 allowed = ComptrollerInterfaceDispatcher { contract_address: comptroller_address }.redeemAllowed(get_contract_address().redeemer, redeemTokens);

            assert(allowed == 0, "redeem rejection");
            assert(self.accrualBlockNumber == get_block_number(), "redeem freshness check");
            assert(getCashPrior(true) >= redeemAmount, "redeem transfer out not possible");

            // * We write the previously calculated values into storage.
            // *  Note: Avoid token reentrancy attacks by writing reduced supply before external transfer.
            self.totalSupply = self.totalSupply - redeemTokens;
            let res = self.accountTokens.read(redeemer) - redeemTokens;
            self.accountTokens.write(redeemer, res);

            InternalImpl::doTransferOut(redeemer, redeemAmount, true);

            self.emit( Transfer(from: redeemer, to: get_contract_address(), amount: redeemTokens) );
            self.emit( Redeem(redeemer: redeemer, redeemAmount: redeemAmount, redeemTokens: redeemTokens) );

            let comptrollerAddress = self.comptroller;
            ComptrollerInterfaceDispatcher { contract_address:comptrollerAddress }.redeemVerify(get_contract_address(), redeemer, redeemAmount, redeemTokens);
            0;
        }

        fn redeemUnderlying(ref self: ContractState, redeemAmount: u256) -> u256 {
            self.accrueInterest(true);
            ContractAddress redeemer = get_caller_address();
            u256 redeemTokensIn = 0;

            assert(redeemTokensIn == 0 || redeemAmountIn == 0, "one of redeemTokensIn or redeemAmountIn must be zero");

            Exp exchangeRate = Exp{ mantissa: InternalImpl::exchangeRateStoredInternal(true) };

            u256 redeemTokens;
            u256 redeemAmount;

            if (redeemTokensIn > 0) {
                
            //  * We calculate the exchange rate and the amount of underlying to be redeemed:
            //  *  redeemTokens = redeemTokensIn
            //  *  redeemAmount = redeemTokensIn x exchangeRateCurrent
                redeemTokens = redeemTokensIn;
                redeemAmount = exponential.mul_ScalarTruncate(exchangeRate, redeemTokensIn);
            } else {
                redeemTokens = exponential.div_(redeemAmountIn, exchangeRate);
                redeemAmount = redeemAmountIn;
            }

            ContractAddress comptroller_address = self.comptroller;

            u256 allowed = ComptrollerInterfaceDispatcher { comptroller_address }.redeemAllowed(get_contract_address().redeemer, redeemTokens);

            assert(allowed == 0, "redeem rejection");
            assert(self.accrualBlockNumber == get_block_number(), "redeem freshness check");
            assert(getCashPrior(true) >= redeemAmount, "redeem transfer out not possible");

            // * We write the previously calculated values into storage.
            // *  Note: Avoid token reentrancy attacks by writing reduced supply before external transfer.
            self.totalSupply = self.totalSupply - redeemTokens;
            let res = self.accountTokens.read(redeemer) - redeemTokens;
            self.accountTokens.write(redeemer, res);

            InternalImpl::doTransferOut(redeemer, redeemAmount, true);

            self.emit( Transfer(from: redeemer, to: get_contract_address(), amount: redeemTokens) );
            self.emit( Redeem(redeemer: redeemer, redeemAmount: redeemAmount, redeemTokens: redeemTokens) );

            let comptrollerAddress = self.comptroller;
            ComptrollerInterfaceDispatcher { comptrollerAddress }.redeemVerify(get_contract_address(), redeemer, redeemAmount, redeemTokens);
            0;
        }
        
        fn borrow(ref self: ContractState, borrowAmount: u256) ->  u8{
            InternalImpl::borrowInternal(borrowAmount, true);
        }


        fn repayBorrow(ref self: ContractState, repayAmount: u256 ) -> u256 {
            self.accrueInterest(true);
            let comptrollerAddress = self.comptroller;
            ContractAddress borrower = get_caller_address();
            ContractAddress payer = get_caller_address();
            InternalImpl::repayBorrowFresh(payer, borrower, repayAmount, true);
        }


        fn repayBorrowBehalf (ref self: ContractState, borrower: ContractAddress, repayAmount: u256 ) -> u256 {
            self.accrueInterest(true);

            let comptrollerAddress = self.comptroller;
            ContractAddress payer = get_caller_address();

            InternalImpl::repayBorrowFresh(payer, borrower, repayAmount, true);
        }

        //清算
        fn liquidateBorrow(ref self: ContractState, borrower: ContractAddress, repayAmount: u256, cTokenCollateral: ContractAddress) -> u256 {
            InternalImpl::liquidateBorrowInternal(borrower, repayAmount, cTokenCollateral);
            0;
        }

        fn sweepToken(ref self: ContractState, token: ContractAddress) {
            assert(get_caller_address() == admin, "CErc20::sweepToken: only admin can sweep tokens");
            assert(token != self.underlying, "CErc20::sweepToken: can not sweep underlying token");
            let balance:u256 = token.balanceOf(get_contract_address());
            token.transfer(admin, balance);
        }

        fn _addReserves(ref self: ContractState, addAmount: u256)->u256 {
            InternalImpl::_addReserves(addAmount);
        }
    }



    fn transfer(ref self: ContractState, dst: ContractAddress, amount: u256) -> bool{
        InternalImpl::transferTokens(get_caller_address(), get_caller_address(), dst, amount) == 0;
    }

    fn transferFrom(ref self: ContractState, src: ContractAddress, dst: ContractAddress, amount: u256)->bool {
        InternalImpl::transferTokens(get_caller_address(), src, dst, amount) == 0;
    }

    fn approve(ref self: ContractState, spender: ContractAddress, amount: u256) -> bool{
            let src: ContractAddress = get_caller_address();
            let values: LegacyMap<ContractAddress, u256> = self.transferAllowances.read(src);
            values.write(spender, amount);
            self.transferAllowances.write(src, values);

            self.emit(Approval{owner: src, spender: spender, amount: amount})
            true;
        }

        fn allowance(ref self: ContractState, owner: ContractAddress, spender: ContractAddress)-> u256{
            self.transferAllowances.read(owner).read(spender);
        }

        fn balanceOf(ref self: ContractState, owner: ContractAddress)->u256 {
            self.accountTokens.read(owner);
        }

        fn balanceOfUnderlying(ref self: ContractState,)-> u256{
            let exchangeRate:Exp = Exp{ mantissa: exchangeRateCurrent()};
            exponential.mul_ScalarTruncate(exchangeRate, self.accountTokens.read(owner));
        }

        fn exchangeRateCurrent(ref self: ContractState) -> u256 {
            accrueInterest(self.isErc20);
            exchangeRateStored();
        }

        fn exchangeRateStored(ref self: ContractState) -> u256 {
            InternalImpl::exchangeRateStoredInternal(self.isErc20);
        }

        fn getAccountSnapshot(ref self: ContractState, account: ContractAddress) -> (u256, u256, u256, u256){
            (0, self.accountTokens.read(account), InternalImpl::borrowBalanceStoredInternal(account), InternalImpl::exchangeRateStoredInternal(self.isErc20))
        }

        fn getBlockNumber(ref self: ContractState,) -> u256 {
            get_block_number();
        }

        fn borrowRatePerBlock(ref self: ContractState,) -> u256{
            InterestRateModelDispatcher{ contract_address: self.interestRateModel}.getBorrowRate(InternalImpl::getCashPrior(self.isErc20), self.totalBorrows, self.totalReserves);
        }

        fn supplyRatePerBlock(ref self: ContractState,) -> u256 {
             InterestRateModelDispatcher{ contract_address: self.interestRateModel}.getSupplyRate(InternalImpl::getCashPrior(self.isErc20), self.totalBorrows, self.totalReserves, self.reserveFactorMantissa);
        }

        fn totalBorrowsCurrent(ref self: ContractState,) -> u256 {
            accrueInterest(self.isErc20);
            self.totalBorrows;
        }

        fn borrowBalanceCurrent(ref self: ContractState,account: ContractAddress)->u256 {
            accrueInterest(self.isErc20);
            borrowBalanceStored(account);
        }

        fn borrowBalanceStored(ref self: ContractState, account: ContractAddress)->u256  {
            InternalImpl::borrowBalanceStoredInternal(account);
        }

        fn getCash(ref self: ContractState) -> u256 {
            InternalImpl::getCashPrior(self.isErc20);
        }


        fn seize(ref self: ContractState, liquidator: ContractAddress, borrower: ContractAddress, seizeTokens: u256) -> u256 {
            InternalImpl::seizeInternal(get_caller_address(), liquidator, borrower, seizeTokens);
            0;
        }

        fn _setPendingAdmin(ref self: ContractState, newPendingAdmin:ContractAddress) -> u256 {
            assert(get_caller_address() == admin, "set pending admin owner check");
            let oldPendingAdmin:ContractAddress = self.pendingAdmin;
            self.pendingAdmin = newPendingAdmin;

            self.emit(NewPendingAdmin{ oldPendingAdmin:oldPendingAdmin, newPendingAdmin: newPendingAdmin });
            0;
        }

        fn _acceptAdmin(ref self: ContractState) -> u256 {
            assert(get_caller_address() == pendingAdmin && get_caller_address() != 0, "accept admin pending admin check");
            let oldAdmin:ContractAddress = self.admin;
            let oldPendingAdmin:ContractAddress = self.pendingAdmin;

            self.admin = self.pendingAdmin;

            self.pendingadmin = 0;

            self.emit(NewAdmin{oldAdmin: oldAdmin, newAdmin: self.Admin});
            self.emit(NewPendingAdmin{ oldPendingAdmin:oldPendingAdmin, newPendingAdmin: self.pendingAdmin });
        }

        fn _setComptroller(ref self: ContractState, newComptroller: ContractAddress ) -> u8 {
            assert(get_caller_address() == admin, "set comptroller owner check");
            let newComptrollerDespatcher = ComptrollerInterfaceDispatcher { contract_address: newComptroller };
            assert(newComptrollerDespatcher.isComptroller(), "marker method returned false");
            let oldComptroller = self.comptroller;
            self.comptroller = newComptroller;
            self.emit( NewComptroller{ oldComptroller: oldComptroller, newComptroller: newComptroller })
            0;
        }

        fn _setReserveFactor(ref self: ContractState, newReserveFactorMantissa: u256) -> u256 {
            accrueInterest(self.isErc20);
            InternalImpl::_setReserveFactorFresh(newReserveFactorMantissa);
        }

        fn _reduceReserves(ref self: ContractState, reduceAmount: u256) -> u256 {
            accrueInterest(self.isErc20);
            InternalImpl::_reduceReservesFresh(reduceAmount);
        }

        fn _setInterestRateModel(ref self: ContractState, newInterestRateModel: ContractAddress) -> u256 {
            accrueInterest(self.isErc20);
            InternalImpl::_setInterestRateModelFresh(newInterestRateModel);
        }


        fn reserveFactorMantissa(ref self: ContractState) -> u256 {
            self.reserveFactorMantissa;
        }

        fn accrueInterest(ref self: ContractState, isErc20: bool) -> u8{
            let currentBlockNumber = get_block_number();
            let accrualBlockNumberPrior = self.accrualBlockNumber;

            if (accrualBlockNumberPrior == currentBlockNumber) {
                0;
            } else {
                u256 cashPrior = self.getCashPrior(isErc20);
                u256 borrowsPrior = self.totalBorrows;
                u256 reservesPrior = self.totalReserves;
                u256 borrowIndexPrior = self.borrowIndex;

                let interestRateModel = self.interestRateModel;

                let InterestRateModelDispatcher = InterestRateModelDispatcher { contract_address: interestRateModel };
                uint256 borrowRateMantissa = InterestRateModelDispatcher.getBorrowRate(cashPrior, borrowsPrior, reservesPrior);

                assert(borrowRateMantissa <= borrowRateMaxMantissa, "borrow rate is absurdly high");

                u256 blockDelta = currentBlockNumber - accrualBlockNumberPrior;

            //  * Calculate the interest accumulated into borrows and reserves and the new index:
            //  *  simpleInterestFactor = borrowRate * blockDelta
            //  *  interestAccumulated = simpleInterestFactor * totalBorrows
            //  *  totalBorrowsNew = interestAccumulated + totalBorrows
            //  *  totalReservesNew = interestAccumulated * reserveFactor + totalReserves
            //  *  borrowIndexNew = simpleInterestFactor * borrowIndex + borrowIndex

                Exp simpleInterestFactor = exponential::mul_(Exp{ mantissa: borrowRateMantissa }, blockDelta);
                u256 interestAccumulated = exponential::mul_ScalarTruncate(simpleInterestFactor, borrowsPrior);
                u256 totalBorrowsNew = interestAccumulated + borrowsPrior;
                u256 totalReservesNew = exponential::mul_ScalarTruncateAddUInt( Exp{mantissa: reserveFactorMantissa}, interestAccumulated, reservesPrior );
                u256 borrowIndexNew = exponential::mul_ScalarTruncateAddUInt(simpleInterestFactor, borrowIndexPrior, borrowIndexPrior);

                self.accrualBlockNumber = currentBlockNumber;
                self.borrowIndex = borrowIndexNew;
                self.totalBorrows = totalBorrowsNew;
                self.totalReserves = totalReservesNew;

                self.emit( AccrueInterest{cashPrior: cashPrior, interestAccumulated: interestAccumulated, borrowIndexNew: borrowIndexNew, totalBorrowsNew: totalBorrowsNew } )
                0;
           }
       }


    #[generate_trait]
    impl InternalImpl of InternalTrait {

        fn initializer(ref self: ContractState, comptroller_: ContractAddress, interestRateModel_: ContractAddress,
                initialExchangeRateMantissa_: u256, name_: felt256, symbol_: felt256, decimals_: u8) {
            assert(get_caller_address == admin, "only admin may initialize the market");
            assert(self.accrualBlockNumber == 0 && borrowIndex == 0, "market may only be intialized once");

            //set initial exchange rate
            self.initialExchangeRateMantissa = initialExchangeRateMantissa_;

            //set the comptroller
            u8 err = self._setComptroller(comptroller_);
            assert(err == 1, "setting comptroller failed");

            // getBlockNumber()
            self.accrualBlockNumber = get_block_number();
            self.borrowIndex = mantissaOne;

            u8 err = self._setInterestRateModel(interestRateModel_);
            assert(err == 1, "setting interest rate model failed");

            self.name = name_;
            self.symbol = symbol_;
            self.decimals = decimals_;

            self._notEntered = true;
        }

        fn borrowInternal(ref self: ContractState, borrowAmount: u256, isErc20: bool) {
            self.accrueInterest(isErc20);
            borrowFresh(get_caller_address(), borrowAmount, isErc20);
        }

        fn borrowFresh(ref self: ContractState, borrower: ContractAddress, borrowAmount: u256, isErc20: bool) {
            let comptrollerAddress = self.comptroller;
            ContractAddress borrower = get_caller_address();
            u256 allowed = ComptrollerInterfaceDispatcher { contract_address:comptrollerAddress }.borrowAllowed(get_contract_address(), borrower, borrowAmount);
            assert(allowed == 0, "borrow comptroller rejection");
            assert(self.accrualBlockNumber == get_block_number, "borrow freshness check");
            assert(InternalImpl::getCashPrior(true) >= borrowAmount, "borrow cash not available");

            u256 accountBorrowsPrev = InternalImpl::borrowBalancesStoredInternal(borrower);
            u256 accountBorrowsNew = accountBorrowsPrev + borrowAmount;
            u256 totalBorrowsNew = self.totalBorrows + borrowAmount;
            BorrowSnapshot borrowSnapshot = self.accountBorrows.read(borrower);
            borrowSnapshot.principal = accountBorrowsNew;
            borrowSnapshot.interestIndex = self.borrowIndex;
            self.accountBorrows.write(borrower, borrowSnapshot);
            self.totalBorrows = totalBorrowsNew;
            InternalImpl::doTransferOut(borrower, borrowAmount, isErc20);
            self.emit(Borrow{ borrower: borrower, borrowAmount: borrowAmount, accountBorrowsNew: accountBorrowsNew, totalBorrowsNew: totalBorrowsNew})
        }

        fn doTransferOut(ref self: ContractState, to: ContractAddress, amount: u256, isErc20: bool) -> bool {
            if (isErc20) {
                let underlying = self.underlying;
                let token = EIP20InterfaceDispatcher{ contract_address: underlying };
                bool res = token.transfer(to, amount);
                assert(res, "TOKEN_TRANSFER_OUT_FAILED");
            } else {
                to.transfer(amount);
            }
        }


        // fn doTransferOutErc20 (ref self: ContractState, to: ContractAddress, amount: u256) -> bool {
        //     let underlying = self.underlying;
        //     let token = EIP20InterfaceDispatcher{ contract_address: underlying };
        //     bool res = token.transfer(to, amount);
        //     assert(res, "TOKEN_TRANSFER_OUT_FAILED");
        //     true;
        // }

        // fn doTransferOutEth (ref self: ContractState, to: ContractAddress, amount: u256) -> bool {
        //     to.transfer(amount);
        // }


        fn setInitialExchangeRateMantissa(ref self: ContractState, initialExchangeRate: u256) {
            assert(initialExchangeRate > 0, 'exchangeRate must be greater than zero');
            self.initialExchangeRateMantissa.write(initialExchangeRate);
        }

    //  * @notice Sender supplies assets into the market and receives cTokens in exchange
    //  * @dev Accrues interest whether or not the operation succeeds, unless reverted
    //  * @param mintAmount The amount of the underlying asset to supply
        fn mintInternal(ref self: ContractState, mintAmount: u256, isErc20: bool) {
            self.accrueInterest();
            if (isErc20) {
               mintFreshErc20(get_caller_address(), mintAmount);
            } else {
               mintFreshETH()
            }
      
        }

        fn mintFreshErc20(self: @ContractState, minter: ContractAddress, mintAmount: u256) {
            let comptrollerAddress = self.comptroller;
            u256 allowed = ComptrollerInterfaceDispatcher { contract_address: comptrollerAddress }.mintAllowed(get_contract_address(), minter, mintAmount);
            assert(allowed == 0, "mint comptroller rejection");
            assert(self.accrualBlockNumber == get_block_number(), "mint freshness check");

            let exchangeRate = exchangeRateStoredInternal(true);
            u256 actualMintAmount = doTransferInErc20(minter, mintAmount);
            u256 mintTokens = actualMintAmount / exchangeRate;
            self._totalSupply = self._totalSupply + mintTokens;
            let res = self.accountTokens.read(minter)+ mintTokens;
            self.accountTokens.write(res);
        }

        fn mintFreshETH(self: @ContractState, minter: ContractAddress, mintAmount: u256) {
            let comptrollerAddress = self.comptroller;
            u256 allowed = ComptrollerInterfaceDispatcher { contract_address: comptrollerAddress }.mintAllowed(get_contract_address(), minter, mintAmount);
            assert(allowed == 0, "mint comptroller rejection");
            assert(self.accrualBlockNumber == get_block_number(), "mint freshness check");

            let exchangeRate = exchangeRateStoredInternal(false);
            u256 actualMintAmount = doTransferInErc20(minter, mintAmount);
            u256 mintTokens = actualMintAmount / exchangeRate;
            self._totalSupply = self._totalSupply + mintTokens;
            let res = self.accountTokens.read(minter)+ mintTokens;
            self.accountTokens.write(res);
        }

        fn getCashPrior(self:@ContractState, isErc20: bool) -> u256 {
            if (isErc20) {
              let contract_address = self._underlying;
              EIP20InterfaceDispatcher { contract_address: contract_address }.balanceOf(get_contract_address());
            } else {
                let tx_info:TxInfo = get_tx_info().unbox();
                let ownerAccount:u256 = CtokenInterfaceDispatcher{ contract_address: get_contract_address()}.balanceOf(get_contract_address());
                ownerAccount - tx_info.max_fee;
            }
        }


        fn doTransferInErc20(self: @ContractState, minter: ContractAddress, mintAmount: u256) -> u256 {
            let contract_address = self._underlying;
            let token = EIP20InterfaceDispatcher { contract_address: contract_address };
            u256 balance_before = token.balanceOf(get_contract_address);
            let result = toekn.transferFrom(minter, get_contract_address(), mintAmount); 
            assert(result, "TOKEN_TRANSFER_IN_FAILED");

            u256 balance_after = EIP20InterfaceDispatcher { contract_address: contract_address }.balanceOf(get_contract_address);
            let res = balance_after - balance_before;
        }

        fn doTransferInEth(ref self: ContractState, from: ContractAddress, amount: u256) -> bool {
            assert(get_caller_address() == from, "sender mismatch");
            amount;
        }

        fn exchangeRateStoredInternal(ref self: ContractState, isErc20:bool) -> u256 {
            u256 totalSupply = self._totalSupply;
            if(totalSupply == 0) {
                self.initialExchangeRateMantissa;
            } else {
                u256 totalCash = getCashPrior(isErc20);
                u256 cashPlusBorrowsMinusReserves = totalCash + self._totalBorrow - _totalReserves;
                u256 exchangeRate = cashPlusBorrowsMinusReserves / self._totalSupply;
            }
        }

        fn borrowBalanceStoredInternal(ref self: ContractState, account: ContractAddress) ->  u256{
            BorrowSnapshot borrowSnapshot = self.accountBorrows.read(account);
            if (borrowSnapshot.principal == 0) {
                0;
            } else {
                u256 principalTimesIndex = borrowSnapshot.principal * self.borrowIndex;
                principalTimesIndex / borrowSnapshot.interestIndex;
            }

        }

        fn repayBorrowFresh(ref self: ContractState, payer: ContractAddress, borrower: ContractAddress, repayAmount: u256, isErc20: bool) -> u256 {
            let allowed: u256 = ComptrollerInterfaceDispatcher { contract_address:comptrollerAddress }.repayBorrowAllowed(get_contract_address(), payer, borrower, repayAmount);

            assert(allowed == 0, "repay borrow comptroller rejection");
            assert(self.accrualBlockNumber == get_block_number(), "repay borrow freshness check");
            assert(repayAmount>0, "repayAmount can not be less than zero ");

            u256 accountBorrowsPrev = InternalImpl::borrowBalanceStoredInternal(borrower);

            u256 repayAmountFinal;

            let ONES_MASK = 0xffffffffffffffffffffffffffffffff_u128;
            let isMax = repayAmount.low == ONES_MASK & repayAmount.high == ONES_MASK;

            if (isMax) {
                repayAmountFinal = accountBorrowsPrev;
            } else {
                repayAmountFinal = repayAmount;
            }
            let mut actualRepayAmount: u256 = 0;

            if (isErc20) {
                actualRepayAmount = InternalImpl::doTransferInErc20(payer, repayAmountFinal);
            } else {
                actualRepayAmount = InternalImpl::doTransferInEth(payer, repayAmountFinal);
            }


            u256 accountBorrowsNew = accountBorrowsPrev - actualRepayAmount;
            u256 totalBorrowsNew = self.totalBorrows - actualRepayAmount;

            BorrowSnapshot borrowSnapshot = self.accountBorrows.read(borrower);
            borrowSnapshot.principal = accountBorrowsNew;
            borrowSnapshot.interestIndex = self.borrowIndex;

            self.totalBorrows = totalBorrowsNew;

            self.emit( RepayBorrow(payer: payer, borrow: borrow, repayAmount: actualRepayAmount, accountBorrows: accountBorrowsNew, totalBorrows: totalBorrowsNew) );

            actualRepayAmount;

        }


        fn liquidateBorrowInternal(ref self: ContractState, borrower: ContractAddress, repayAmount: u256, cTokenCollateral: ContractAddress ) {
            self.accrueInterest();
            let error: u8 = CtokenInterfaceDispatcher{ contract_address: cTokenCollateral }.accrueInterest();
            assert(error == 0 , "liquidate accrue collateral interest failed");
            liquidateBorrowFresh(get_caller_address(), borrower, repayAmount, cTokenCollateral);
        }

        fn liquidateBorrowFresh(ref self: ContractState, liquidator: ContractAddress,  borrower: ContractAddress, repayAmount: u256, cTokenCollateral: ContractAddress, isErc20: bool) {
            let allowed = self.comptroller.liquidateBorrowAllowed(get_contract_address(), cTokenCollateral, liquidator, borrower, repayAmount);
            assert(allowed == 0, "liquidate comptroller rejection");
            assert(self.accrualBlockNumber == get_block_number(), "liquidate freshness check");
            let accrualBlockNumber:u256 = CtokenInterfaceDispatcher{ contract_address: cTokenCollateral }.accrualBlockNumber();
            assert(accrualBlockNumber == get_block_number(), "liquidate freshness check");

            assert(borrower != liquidator, "liquidate is borrower");
            assert(repayAmount!=0, "liquidate close amount is zero");
            //https://foresightnews.pro/article/detail/29844
            let ONES_MASK = 0xffffffffffffffffffffffffffffffff_u128;
            let is_unlimited_max = account.low == ONES_MASK & account.high == ONES_MASK;

            assert(!is_unlimited_max, "liquidate close amount is unit max");

            let actualRepayAmount = repayBorrowFresh(liquidator, borrower, repayAmount, isErc20);
            
            (amountSeizeError, seizeTokens) = ComptrollerInterfaceDispatcher{ contract_address: self.comptroller }.liquidateCalculateSeizeTokens(get_contract_address(),
                                 cTokenCollateral,actualRepayAmount);

            assert(amountSeizeError == 0 , 'LIQUIDATE_COMPTROLLER_CALCULATE_AMOUNT_SEIZE_FAILED');

            let balance:u256 = CtokenInterfaceDispatcher{ contract_address: cTokenCollateral }.balanceOf(borrower);
            assert(balance>=seizeTokens, "LIQUIDATE_SEIZE_TOO_MUCH");

            if (cTokenCollateral == get_contract_address()) {
                seizeInternal(get_contract_address(), liquidator, borrower, seizeTokens);
            } else {
                let res:u256 = CtokenInterfaceDispatcher{ contract_address: cTokenCollateral }.seize(liquidator, borrower, seizeTokens);
                assert(res == 0, 'LIQUIDATE_COMPTROLLER_CALCULATE_AMOUNT_SEIZE_FAILED');
            }

            self.emit(LiquidateBorrow{liquidator: liquidator, borrower: borrower, repayAmount: actualRepayAmount,cTokenCollateral:cTokenCollateral, seizeTokens:seizeTokens});
        }

        fn seizeInternal(ref self: ContractState, seizerToken:ContractAddress, liquidator: ContractAddress, borrower:ContractAddress,seizeTokens:u256 ) {
            let allowed = ComptrollerInterfaceDispatcher{ contract_address: self.comptroller }.seizeAllowed(get_contract_address(),seizerToken, liquidator, borrower, seizeTokens);
            assert(allowed == 0, 'liquidate seize comptroller rejection');
            assert(borrower!=liquidator, "liquidate seize liquidator is borrower");

            let protocolSeizeTokens:u256 = exponential.mul_(seizeTokens, Exp{ mantissa: protocolSeizeShareMantissa});
            let liquidatorSeizeTokens:u256 = seizeTokens - protocolSeizeTokens;
            let exchangeRate:Exp = Exp{ mantissa: exchangeRateStoredInternal(self.isErc20) };
            let protocolSeizeAmount = exponential.mul_ScalarTruncate(exchangeRate, protocolSeizeTokens);
            let totalReservesNew:u256 = totalReserves +  protocolSeizeAmount;

            totalReserves = totalReservesNew;

            totalSupply = totalSupply - protocolSeizeTokens;
            let accountTokensBorrow:u256 = accountTokens.read(borrower) - seizeTokens;
            accountTokens.write(accountTokensBorrow);
            let accountTokensLiquidate = accountTokens.read(liquidator) + liquidatorSeizeTokens;
            accountTokens.write(accountTokensLiquidate);

            self.emit(Transfer{from: borrower, to: liquidator, amount: liquidatorSeizeTokens});
            self.emit(Transfer{from: borrower, to: get_contract_address(), amount: protocolSeizeTokens});
            self.emit(ReservesAdded{admin: get_contract_address(), actualAddAmount:protocolSeizeAmount, totalReservesNew: totalReservesNew});
        }

        fn _addReservesInternal(ref self: ContractState, addAmount: u256, isErc20: bool) -> u256 {
            self.accrueInterest();
            self._addReservesFresh(addAmount, isErc20);
            0;
        }

        fn _addReservesFresh(ref self: ContractState, addAmount: u256, isErc20:bool) -> (u256, u256) {
            assert(self.accrualBlockNumber == get_block_number(), "add reserves factor fresh check");
            let mut actualAddAmount:u256 = 0;
            let mut totalReservesNew:u256 = 0;
            if (isErc20) {
                actualAddAmount = doTransferInErc20(get_caller_address(), addAmount);
            } else {
                actualAddAmount = doTransferInEth(get_caller_address(), addAmount);
            }

            totalReservesNew = totalReserves + actualAddAmount;
            totalReserves = totalReservesNew;

            self.emit(ReservesAdded{ admin: get_caller_address(), actualAddAmount:actualAddAmount, totalReservesNew: totalReservesNew });

            (0, actualAddAmount);
        }

        fn transferTokens(ref self: ContractState, spender: ContractAddress, src: ContractAddress, dst:ContractAddress,tokens:u256 ) -> u256 {
            let allowed:u256 = ComptrollerInterfaceDispatcher{contract_address: self.comptroller}.transferAllowed(get_contract_address(), src, dst, tokens);
            assert(allowed == 0 , "transfer comptroller rejection");
            assert(src != dst, "transfer not allowed");

            let mut startingAllowance = 0;
            let ONES_MASK = 0xffffffffffffffffffffffffffffffff_u128;
            if (spender == src) {
                startingAllowance.low = ONES_MASK;
                startingAllowance.high = ONES_MASK;
            } else {
                startingAllowance = self.transferAllowances.read(src).read(spender);
            }


            let allowanceNew:u256 = startingAllowance - tokens;
            let srcTokensNew:u256 = self.accountTokens.read(src) - tokens;
            let dstTokensNew:u256 = self.accountTokens.read(dst) + tokens;

            self.accountTokens.write(src, srcTokensNew);
            self.accountTokens.write(dst, dstTokensNew);

            if (startingAllowance.low != ONES_MASK && startingAllowance.high != ONES_MASK) {
                LegacyMap values = self.transferAllowances.read(src);
                values.write(spender, allowanceNew);
                self.transferAllowances.write(src, values);
            }

            self.emit(Transfer{ from: src, to: dst, amount: tokens })

            0;
        }

        fn _setReserveFactorFresh(ref self: ContractState, newReserveFactorMantissa: u256) {
            assert(get_caller_address() == admin, "set reserve factor admin check");
            assert(self.accrualBlockNumber == get_block_number(), 'set reserve factor fresh check');
            assert(newReserveFactorMantissa <= reserveFactorMaxMantissa, "set reserve factor bounds check");
            let oldReserveFactorMantissa: u256 = self.reserveFactorMantissa;
            self.reserveFactorMantissa = newReserveFactorMantissa;

            self.emit(NewReserveFactor{ oldReserveFactorMantissa: oldReserveFactorMantissa, newReserveFactorMantissa:newReserveFactorMantissa});
            0;
        }

        fn _reduceReservesFresh(ref self: ContractState, reduceAmount: u256) -> u256 {
            assert(get_caller_address() == admin, "reduce reserves admin check");
            assert(self.accrualBlockNumber == get_block_number(), "reduce reserves fresh check");
            assert(getCashPrior(self.isErc20) >= reduceAmount , "reduce reserves cash not available");
            assert(reduceAmount <= self.totalReserves, "reduce reserves cash validation");

            let totalReservesNew:u256 = self.totalReserves - reduceAmount;
            self.totalReserves = totalReservesNew;

            doTransferOut(self.admin, reduceAmount);

            self.emit(ReservesReduced{ admin:self.admin, reduceAmount: reduceAmount, newTotalReserves: totalReservesNew });
            0;
        }

        fn _setInterestRateModelFresh(ref self: ContractState, newInterestRateModel: ContractAddress) -> u256 {
            assert(get_caller_address() == admin, "set interest rate model owner check");
            assert(self.accrualBlockNumber == get_block_number(), 'set interest rate model fresh check');

            let oldInterestRateModel:ContractAddress = self.interestRateModel;
            let interestRateModelDispatcher = InterestRateModelDispatcher{ contract_address: newInterestRateModel };
            assert(interestRateModelDispatcher.isInterestRateModel, "marker method returned false");

            self.interestRateModel = newInterestRateModel;

            self.emit(  NewMarketInterestRateModel { oldInterestRateModel: oldInterestRateModel, newInterestRateModel: newInterestRateModel })
            0;
        }
    }


    fn comptroller(ref self: ContractState) -> ContractAddress {
        self.comptroller;
    }

    fn accrualBlockNumber() -> u256 {
        self.accrualBlockNumber;
    }

    
}


