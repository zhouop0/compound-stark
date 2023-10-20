#[starknet::contract]
mod WhitePaperInterestRateModel {

    const blocksPerYear: unit256 = 2102400_u256;
    const BASE: unit256 = 10**18;

    #[storage]
    struct Storage {
        multiplerPerBlock: unit,
        baseRatePerBlock: unit,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        NewInterestParams,
    }

    #[derive(Drop, starknet::Event)]
    struct NewInterestParams {
       baseRatePerBlock: unit256,
       multiplierPerBlock: unit256
    }

    #[constructor]
    fn constructor(ref self: ContractState, multiplierPerYear: unit256) {
        self.baseRatePerBlock = self.baseRatePerYear / self.baseRatePerYear;
        self.multiplierPerBlock = self.multiplierPerYear / blocksPerYear;
        self.emit(NewInterestParams { baseRatePerBlock: self.baseRatePerBlock, multiplierPerBlock: self.multiplierPerBlock });
    }

    #[external(v0)]
    fn utilizationRate(self: @ContractState, cash: unit256, borrows: unit256, reserves: unit256) -> unit256 {
        if (borrow == 0) {
            0
        }
        borrows * self.BASE / (cash + borrows - reserves);
    }

    #[external(v0)]
    impl WhitePaperInterestRateModelImpl of InterestRateModel<ContractState>{

        fn getBorrowRate(ref self: ContractState, cash: unit, borrows: unit, reserves: unit) {
            unit ur = self.utilizationRate(self, cash, borrows, reserves);
            (ur * multiplierPerBlock / BASE) + baseRatePerBlock;
        }

        fn getSupplyRate(ref self: ContractState, borrows: unit, reserves: unit, reserveFactorMantissa: unit) {
            unit oneMinusReserveFactor = self.BASE - reserveFactorMantissa;
            unit borrowRate = self.getBorrowRate(cash, borrows, reserves);
            unit rateToPool = borrowRate * oneMinusReserveFactor / self.BASE;
            utilizationRate(cash, borrows, reserves) * rateToPool / self.BASE;
        }
    }

 

}
