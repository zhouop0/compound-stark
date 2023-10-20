use starknet::ContractAddress;
use array::ArrayTrait;

const isComptroller: bool = true;

#[starknet::interface]
trait ComptrollerInterface<TState> {
    fn enterMarkets(ref self: TState, cTokens: Array<ContractAddress>) -> Array<unit256>;
    fn exitMarket(ref self: TState, cToken: ContractAddress) -> unit256;

    fn mintAllowed(ref self: TState, cToken: ContractAddress, minter: ContractAddress, mintAmount: unit256, mintTokens: unit256);
    fn mintVerify(ref self: TState, cToken: ContractAddress, minter: ContractAddress, mintAmount: unit256, mintTokens: unit256);

    fn redeemAllowed(ref self: TState, cToken: ContractAddress, redeemer: ContractAddress, redeemTokens: ContractAddress)->unit256;
    fn redeemVerify(ref self: TState, cToken: ContractAddress, redeemer: ContractAddress, redeemAmount: unit256);

    fn borrowAllowed(ref self: TState, borrower: ContractAddress, borrowAmount: unit256) -> unit256;
    fn borrowVerify(ref self: TState, cToken: ContractAddress, borrower: ContractAddress, borrowAmount: unit256);

    fn repayBorrowAllow(ref self: TState, cToken: ContractAddress, 
            payer: ContractAddress, borrower: ContractAddress, repayAmount: unit256) -> unit256;
    fn repayBorrowVerify(ref self: TState, cToken: ContractAddress, 
            payer: ContractAddress, borrower: ContractAddress, repayAmount: unit256, borrowerIndex: unit256) -> unit256;

    fn liquidateBorrowAllowed(ref self: TState, cTokenBorrowed: ContractAddress, cTokenCollateral: ContractAddress,
            liquidator: ContractAddress, borrower: ContractAddress, repayAmount: unit256) -> unit256;
    fn liquidateBorrowVerify(ref self: TState, cTokenBorrowed: ContractAddress, cTokenCollateral: ContractAddress,
            liquidator: ContractAddress, borrower: ContractAddress, repayAmount: unit256, seizeTokens: unit256);

    fn seizeAllowed(ref self: TState, cTokenCollateral: ContractAddress, cTokenBorrowed: ContractAddress, liquidator: ContractAddress,
            borrower: ContractAddress, seizeTokens: unit256) -> unit256;
    fn seizeVerify(ref self: TState, cTokenCollateral: ContractAddress, cTokenBorrowed: ContractAddress, liquidator: ContractAddress,
            borrower: ContractAddress, seizeTokens: unit256);

    fn transferAllowed(ref self: TState, cToken: ContractAddress, src: ContractAddress, dst: ContractAddress, transferToken: unit256);
    fn transferVerify(ref self: TState, cToken: ContractAddress, src: ContractAddress, dst: ContractAddress, transferTokens:unit256);

    fn liquidateCalculateSeizeTokens(ref self: TState, cTokenBorrowed: ContractAddress, cTokenCollateral: ContractAddress) -> (u256, u256);
}