
const isCToken: bool = true;



#[starknet::interface]
trait CEthInterface<TContractState> {
    fn mint(ref self: TContractState, mintAmount: u256) -> u8;
    fn redeem(ref self: TContractState, redeemTokens: u256) -> u8;
    fn redeemUnderlying(ref self: TContractState, redeemAmount: u256) -> u256;
    fn borrow(ref self: TContractState, borrowAmount: u256) -> u256;
    fn repayBorrow(ref self: TContractState, repayAmount: u256) -> u256;
    fn liquidateBorrow(ref self: TContractState, borrower: ContractAddress, repayAmount: u256, cTokenCollateral: ContractAddress)-> u256;

    fn _addReserves(ref self: TContractState, addAmount: u256) -> u256;
}


#[starknet::interface]
trait CErc20Interface<TContractState> {

    fn mint(ref self: TContractState, mintAmount: u256) -> u8;
    fn redeem(ref self: TContractState, redeemTokens: u256) -> u8;
    fn redeemUnderlying(ref self: TContractState, redeemAmount: u256) -> u256;
    fn borrow(ref self: TContractState, borrowAmount: u256) -> u256;
    fn repayBorrow(ref self: TContractState, repayAmount: u256) -> u256;
    fn repayBorrowBehalf(ref self: TContractState, repayAmount: u256) -> u256;
    fn liquidateBorrow(ref self: TContractState, borrower: ContractAddress, repayAmount: u256, cTokenCollateral: ContractAddress)-> u256;
    fn sweepToken(ref self: TContractState, token: ContractAddress);

    fn _addReserves(ref self: TContractState, addAmount: u256) -> u256;
    
}




#[starknet::interface]
trait CtokenInterface<TContractState> {

    // /*** User Interface ***/
    fn transfer(ref self: TContractState, dst: ContractAddress, amount: u256) -> bool;

    
    fn transferFrom(ref self: TContractState, dst: ContractAddress, amount: u256) -> bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn allowance(ref self: TContractState, owner: ContractAddress, spender: ContractAddress) -> u256;
    fn balanceOf(ref self: TContractState, owner: ContractAddress) -> u256;
    fn balanceOfUnderlying(ref self: TContractState, owner: ContractAddress) -> u256;
    fn getAccountSnapshot(ref self: TContractState, account: ContractAddress) -> (u256, u256, u256, u256);
    fn borrowRatePerBlock(ref self: TContractState) -> u256;
    fn supplyRatePerBlock(ref self: TContractState) -> u256;
    fn totalBorrowsCurrent(ref self: TContractState) -> u256;
    fn borrowBalanceCurrent(ref self: TContractState, account: ContractAddress) -> u256;
    fn borrowBalanceStored(ref self: TContractState, account: ContractAddress) -> u256;
    fn exchangeRate(ref self: TContractState) -> u256;
    fn exchangeRateStored(ref self: TContractState) -> u256;
    fn getCash(ref self: TContractState) -> u256;
    fn accrueInterest(ref self: TContractState, isErc20:bool) -> u256;
    fn seize(ref self: TContractState, liquidator: ContractAddress, borrower: ContractAddress, seizeTokens: ContractAddress) -> u256;
    fn comptroller(ref self: TContractState)-> ContractAddress;
    fn accrualBlockNumber(ref self: TContractState) -> u256;
    fn getCashPrior(ref self: TContractState, isErc20: bool) -> u256;

    // /*** Admin Functions ***/

    fn _setPendingAdmin(ref self: TContractState, newPending: ContractAddress) -> u256;
    fn _acceptAdmin(ref self: TContractState) -> u256;
    fn _setComptroller(ref self: TContractState, newComptroller: ContractAddress) -> u256;

    fn _setReserveFactor(ref self: TContractState, newReserveFactorMantissa: u256) -> u256;
    fn _reduceReserves(ref self: TContractState, reduceAmount: ContractAddress) -> u256;
    fn _setInterestRateModel(ref self: TContractState, newInterestRateModel: ContractAddress) -> u256; 

    fn reserveFactorMantissa(ref self: TContractState) -> u256;

}

#[starknet::interface]
trait EIP20Interface<TContractState> {
    fn name(ref self: TContractState);
    fn symbol(ref self: TContractState);
    fn decimals(ref self: TContractState) -> u8;
    fn totalSupply(ref self: TContractState) -> u256;
    fn balanceOf(ref self: TContractState, owner: ContractAddress) -> u256;
    fn transfer(ref self: TContractState, dst: ContractAddress, amount: u256)->bool;
    fn transferFrom(ref self: TContractState, src: ContractAddress, amount: u256) ->bool;
    fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
    fn allowance(ref self: TContractState, owner: ContractAddress, spender: ContractAddress)->u256;
}

// #[starknet::interface]
// trait EIP20NonStandardInterface<TContractState> {
//     fn totalSupply(ref self: TContractState) -> u256;
//     fn balanceOf(ref self: TContractState, owner: ContractAddress) -> u256;
//     fn transfer(ref self: TContractState, dst: ContractAddress, amount: u256);
//     fn transferFrom(ref self: TContractState, src: ContractAddress, amount: u256);
//     fn approve(ref self: TContractState, spender: ContractAddress, amount: u256) -> bool;
//     fn allowance(ref self: TContractState, owner: ContractAddress, spender: ContractAddress)->u256;
// }