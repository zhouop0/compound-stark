

#[starknet::contract]
mod JumpRateModel {

    use starknet::ContractAddress;
    use starknet::get_caller_address;

    const blocksPerYear: unit256 = 2102400_u256;
    const BASE: unit256 = 10**18;

    #[storage]
    struct Storage {
        owner:ContractAddress,
        multiplerPerBlock: unit256,
        baseRatePerBlock: unit256,
        jumpMultiplierRerBlock: unit256,
        kink: unit256,
    }

    #[event]
    #[derive(Drop, starknet::Event)]
    enum Event {
        NewInterestParams,
    }

    #[derive(Drop, starknet::Event)]
    struct NewInterestParams {
       baseRatePerBlock: unit256,
       multiplierPerBlock: unit256,
       jumpMultiplierPerBlock: unit256,
       kink: unit256
    }

//  * @notice Construct an interest rate model
//  * @param baseRatePerYear The approximate target base APR, as a mantissa (scaled by BASE)  年基准利率
//  * @param multiplierPerYear The rate of increase in interest rate wrt utilization (scaled by BASE) 年利率乘数
//  * @param jumpMultiplierPerYear The multiplierPerBlock after hitting a specified utilization point 拐点年利率乘数
//  * @param kink_ The utilization point at which the jump multiplier is applied 拐点资金借出率
//  * @param owner_ The address of the owner, i.e. the Timelock contract (which has the ability to update parameters directly)
    #[constructor]
    fn constructor(ref self: ContractState, owner_: ContractAddress,baseRatePerYear: unit256, multiplierPerYear: unit256,jumpMultiplierPerYear: unit256,
            kink_: unit256) {
        owner = owner_;

        updateJumpRateModelInternal(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_);
    }

    #[external(v0)]
    fn updateJumpRateModel(ref self: ContractState, baseRatePerYear: unit256, multiplierPerYear: unit256,jumpMultiplierPerYear: unit256,
            kink_: unit256) {
        assert(get_caller_address == self.owner, "only the owner may call this function");

        InternalImpl::updateJumpRateModelInternal(baseRatePerYear, multiplierPerYear, jumpMultiplierPerYear, kink_);
    }

    #[generate_trait]
    impl InternalImpl of InternalTrait {

        fn updateJumpRateModelInternal(ref self: ContractState, baseRatePerYear: unit256, multiplierPerYear: unit256,jumpMultiplierPerYear: unit256,
            kink_: unit256) {
            // 块基准利率 = 年基准利率 / 年块数
            self.baseRatePerBlock = baseRatePerYear / self.blocksPerYear;
            // 块利率乘数 = 年基准利率 / (年块数 * 拐点资金借出率)
            self.multiplierPerBlock = (multiplierPerYear * self.BASE) / (blocksPerYear * kink_);
            // 拐点块利率乘数 = 拐点年利率乘数 / 年块数
            self.jumpMultiplierPerBlock = jumpMultiplierPerYear / blocksPerYear;
            // 记录拐点资金借出率
            self.kink = kink_;
            self.emit(NewInterestParams {baseRatePerBlock: self.baseRatePerBlock, multiplierPerBlock: self.multiplierPerBlock,
                jumpMultiplierPerBlock: self.jumpMultiplierPerBlock, kink: self.kink});
        }

        fn getBorrowRateInternal(self: TContractState, cash: unit256, borrows: unit256, reserves: unit256) -> unit256 {
            unit256 util = self.utilizationRate(cash, borrows, reserves);

            if (util <= self.kink) {
                ((util * self.multiplerPerBlock) / BASE ) + self.baseRatePerBlock;
            } else {
                unit256 normalRate = ((self.kink * self.multiplierPerBlock) / self.BASE ) + self.baseRatePerBlock;
                unit256 excessUtil = util - kink;
                ((excessUtil * jumpMultiplierPerBlock) / BASE) + normalRate;
            }
       }
    }

//      * @notice Calculates the utilization rate of the market: `borrows / (cash + borrows - reserves)`
//      * @param cash The amount of cash in the market
//      * @param borrows The amount of borrows in the market
//      * @param reserves The amount of reserves in the market (currently unused)
//      * @return The utilization rate as a mantissa between [0, BASE]
    #[external(v0)]
    fn utilizationRate(self: @ContractState, cash: unit256, borrows: unit256, reserves: unit256) -> unit256 {
        if (borrow == 0) {
            0
        }
        borrows * self.BASE / (cash + borrows - reserves);
    }

    #[external(v0)]
    impl JumpRateModelV2 of InterestRateModel<ContractState>{

    //  * @notice Calculates the current borrow rate per block
    //  * @param cash The amount of cash in the market
    //  * @param borrows The amount of borrows in the market
    //  * @param reserves The amount of reserves in the market
    //  * @return The borrow rate percentage per block as a mantissa (scaled by BASE)
       fn getBorrowRate(self: TContractState, cash: unit256, borrows: unit256, reserves: unit256) -> unit256 {
           InternalImpl::getBorrowRateInternal(self, cash, borrows, reserves);
       }

    //  * @notice Calculates the current supply rate per block
    //  * @param cash The amount of cash in the market
    //  * @param borrows The amount of borrows in the market
    //  * @param reserves The amount of reserves in the market
    //  * @param reserveFactorMantissa The current reserve factor for the market
    //  * @return The supply rate percentage per block as a mantissa (scaled by BASE)
       fn getSupplyRate(self: @ContractState, cash: unit256, borrows: unit256, reserves: unit256,
                reserveFactorMantissa: unit256) -> unit256 {
            unit256 oneMinusReserveFactor = self.BASE - reserveFactorMantissa;
            unit256 borrowRate = InternalImpl::getBorrowRateInternal(self, cash, borrows, reserves);
            unit256 rateToPool = borrowRate * oneMinusReserveFactor / self.BASE;
            utilizationRate(self, cash, borrows, reserves) * rateToPool /self.BASE;
       }

       
    }



 

}
