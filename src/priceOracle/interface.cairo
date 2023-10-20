
const isPriceOracle: bool = ture;

#[starknet::interface]
trait PriceOracleInterface<TContractState> {

    fn getUnderlyingPrice(ref self: TContractState, cToken: ContractAddress)-> unit256;
}