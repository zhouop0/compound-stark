#[starknet::contract]
mod PriceOracle {
    #[storage]
    struct Storage {
        prices: LegacyMap<ContractAddress, unit256>,
    }
    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        PricePosted
    }

    struct PricePosted {
        asset: ContractAddress,
        previousPriceMantissa: unit256,
        requestedPriceMantissa: unit256,
        newPriceMantissa: unit256,
    }

}
