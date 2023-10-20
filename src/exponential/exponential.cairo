
//  * @title Exponential module for storing fixed-precision decimals
//  * @author Compound
//  * @notice Exp is a struct which stores decimals with a fixed precision of 18 decimal places.
//  *         Thus, if we wanted to store the 5.1, mantissa would store 5.1e18. That is:
//  *         `Exp({mantissa: 5100000000000000000})`.

    const expScale: u256 = 10**18;
    const doubleScale: u256 = 10**36;
    const halfExpScale: u256 = expScale/2;
    const mantissaOne: u256 = expScale;

    struct Exp {
        mantissa: u256,
    }

    struct Double {
        mantissa: u256,
    }

    fn truncate(exp: Exp) -> u256{
        exp.mantissa / expScale;
    }

    fn mul_ScalarTruncate (a: Exp, scalar: u256) -> u256 {
        Exp product = mul_(a, scalar);
        truncate(product);
    }

    fn mul_ScalarTruncateAddUInt(a: Exp, scalar: u256, addend: u256) -> u256 {
        Exp product = mul_(a, scalar);
        add_(truncate(product), addend);
    }

    fn add_(a: u256, b: u256) -> u256 {
        a + b;
    }
    
    fn mul_(a: Exp, b:exp) ->  Exp{
        Exp( mantissa: mul_(a.mantissa, b.mantissa) / expScale );
    }

    fn mul_(a: Exp, b: u256) -> Exp {
        Exp{ mantissa: mul_(a.mantissa, b)};
    }

    fn mul_(a: u256, b: Exp) -> u256 {
        mul_(a, b.mantissa) / expScale;
    }

    fn mul_(a: Double, b: Double) -> Double {
        Double{ mantissa: mul_(a.mantissa, b.mantissa ) / doubleScale };
    }

    fn mul_(a: Double, b: u256) -> Double {
        Double{ mantissa: mul_(a.mantissa, b)}
    }

    fn mul_(a: u256, b: Double)-> u256 {
        mul_(a, b.mantissa) / doubleScale
    }

    fn mul_(a: u256, b: u256) -> u256 {
        a * b
    }

    fn div_(a: Exp, b: Exp) ->  Exp{
        Exp{ mantissa: div_(mul_(a.mantissa, expScale), b.mantissa) };
    }

    fn div_(a: Exp, b: u256) -> Exp {
        Exp{ mantissa: div_(a.mantissa, b) };
    }

    fn div_(a: u256, b: Exp) -> u256 {
        div_(mul_(a, expScale), b.mantissa);
    }

    fn div_(a: u256, b: Double) -> Double {
        dev_(mul_(a, doubleScale), b.mantissa);
    }

    fn div_(a: Double, b: u256) -> Double {
        Double{ mantissa: div_(a.mantissa, b)};
    }

    fn div_(a: u256, b: Double) -> u256 {
        div_(mul_(a, doubleScale), b.mantissa);
    }

    fn div_(a: u256, b: u256) -> u256 {
        a / b
    }

    fn fraction(a: u256, b: u256) -> Double {
        Double{ mantissa: div_(mul_(a, doubleScale), b)};
    }

    fn safe32(n: u256, errorMessage: felt252) -> u32 {
        assert(n < 2**32, errorMessage);
        let n_32: u32 = n.try_into().unwrap();
        n_32;
    }

    fn safe256(n: u256, errorMessage: felt252) -> u256 {
        assert(n < 2**256, errorMessage);
        let n_256: u256 = n.try_into().unwrap();
        n_256;
    }

    fn sub_(a: Exp, b: Exp) -> Exp {
        Exp{ mantissa: sub_(a.mantissa, b.mantissa)};
    }

    fn sub_(a: Double, b: Double)->Double {
        Double{ mantissa: sub_(a.mantissa, b.mantissa) };
    }

    fn sub_(a: usize, b: usize) -> usize {
        a - b;
    }

    fn lessThanExp(left: Exp, right: Exp) {
        left.mantissa < right.mantissa;
    }

    fn lessThanOrEqualExp(left: Exp, right: Exp) {
        left.mantissa <= right.mantissa;
    }