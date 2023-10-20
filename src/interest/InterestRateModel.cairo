
const isInterestRateModel: bool = true;

#[starknet::interface]
trait InterestRateModel<TContractState> {

    //   * @notice Calculates the current borrow interest rate per block
    //   * @param cash The total amount of cash the market has
    //   * @param borrows The total amount of borrows the market has outstanding
    //   * @param reserves The total amount of reserves the market has
    //   * @return The borrow rate per block (as a percentage)
    fn getBorrowRate(self: TContractState, cash: unit256, borrows: unit256, reserves: unit256) -> unit256;
    
    //   @notice Calculates the current supply interest rate per block
    //   * @param cash The total amount of cash the market has
    //   * @param borrows The total amount of borrows the market has outstanding
    //   * @param reserves The total amount of reserves the market has
    //   * @param reserveFactorMantissa The current reserve factor the market has
    //   * @return The supply rate per block (as a percentage)
    fn getSupplyRate(self: TContractState, cash: unit256, borrows: unit256, 
        reserves: unit256,reserveFactorMantissa: unit256) -> unit256;
}