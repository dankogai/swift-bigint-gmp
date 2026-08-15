//
//  GMPBigNum -- the conformance glue that lets MPBigInt ride swift-bignum's
//  generic machinery.  Two retroactive conformances and three typealiases;
//  everything else is what the two libraries already were.
//
import BigNum
import GMPBigInt

// `Rational` is generic over `RationalElement`, so MPBigInt can be its
// element.  MPBigInt's own greatestCommonDivisor(with:) and squareRoot() are
// the witnesses -- both requirements since swift-bignum#31 -- so reduction
// runs in GMP too.
extension MPBigInt: @retroactive RationalElement {}

// BigFloatOf<IntType> takes any BigIntegerType & RationalElement.  MPBigInt
// satisfies BigIntegerType save for spelling out `isZero`; string parsing and
// toString(radix:uppercase:) come from the protocol's own defaults.
extension MPBigInt: @retroactive BigIntegerType {
    public var isZero: Bool { self == 0 }
}

/// BigRat's machinery, GMP's digits.
public typealias MPRat = Rational<MPBigInt>

/// BigFloat's machinery, GMP's mantissa.
public typealias MPFloat = BigFloatOf<MPBigInt>

/// BigNum's own `BigInt`, still reachable -- not as `BigNum.BigInt` (the
/// `BigNum` *protocol* shadows the module name in qualified lookup), but
/// through an associated type that never stopped pointing at it.
public typealias BNBigInt = BigFloat.Significand
