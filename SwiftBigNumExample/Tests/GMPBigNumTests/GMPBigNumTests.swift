import Foundation
import Testing
import BigNum
import GMPBigInt
import GMPBigNum

@Suite struct MPRatTests {
    @Test func arithmetic() {
        let third = MPBigInt(1).over(MPBigInt(3))
        #expect(third + MPBigInt(1).over(MPBigInt(6)) == MPBigInt(1).over(MPBigInt(2)))
        #expect(third * 3 == 1)
        #expect(third - third == 0)
    }

    @Test func reduction() {
        // reduction runs through MPBigInt's own gcd (a RationalElement
        // requirement since swift-bignum#31)
        let q = MPBigInt(6).over(MPBigInt(8))
        #expect(q.num == 3 && q.den == 4)
        let h10 = (1...10).map { MPBigInt(1).over(MPBigInt($0)) }.reduce(MPRat(0), +)
        #expect(h10.num == 7381 && h10.den == 2520)
    }

    @Test func comparisonsAndMixed() {
        #expect(MPBigInt(1).over(MPBigInt(3)) < MPBigInt(1).over(MPBigInt(2)))
        #expect(MPBigInt(-1).over(MPBigInt(3)) < MPRat(0))
        let (i, f) = MPBigInt(7).over(MPBigInt(3)).toMixed()
        #expect(i == 2 && f == MPBigInt(1).over(MPBigInt(3)))
        #expect(MPBigInt(22).over(MPBigInt(7)).toDouble() == 22.0 / 7.0)
    }

    @Test func squareRoot() {
        let two = MPBigInt(2).over(MPBigInt(1))
        let root = two.squareRoot(precision: 128)
        // r^2 <= 2 < (r + ulp)^2, and it must agree with BigRat's own digits
        #expect(root * root <= two)
        let reference = BNBigInt(2).over(BNBigInt(1)).squareRoot(precision: 128)
        #expect(root.num.description == reference.num.description)
        #expect(root.den.description == reference.den.description)
    }
}

@Suite struct MPFloatTests {
    @Test func mantissaIsMPBigInt() {
        #expect(type(of: MPFloat(2).mantissa) == MPBigInt.self)
    }

    @Test func agreesWithBigFloat() {
        // the point of the whole exercise: same machinery, different digits,
        // digit-for-digit identical output
        for px in [64, 128, 192] {
            #expect(MPFloat.PI(precision: px).description
                 == BigFloat.PI(precision: px).description)
            #expect(MPFloat.sqrt(MPFloat(2), precision: px).description
                 == BigFloat.sqrt(BigFloat(2), precision: px).description)
            #expect(MPFloat.exp(MPFloat(1), precision: px).description
                 == BigFloat.exp(BigFloat(1), precision: px).description)
            #expect(MPFloat.log(MPFloat(10), precision: px).description
                 == BigFloat.log(BigFloat(10), precision: px).description)
        }
    }

    @Test func knownDigits() {
        #expect(MPFloat.PI(precision: 128).description.hasPrefix("3.14159265358979323846"))
        #expect(MPFloat.sqrt(MPFloat(2), precision: 128).description.hasPrefix("1.41421356237309504880"))
        #expect(MPFloat.exp(MPFloat(1), precision: 128).description.hasPrefix("2.71828182845904523536"))
    }

    @Test func arithmetic() {
        #expect(MPFloat(2) + MPFloat(3) == 5)
        #expect(MPFloat(2) * MPFloat(3) == 6)
        #expect((MPFloat(1) / MPFloat(4)).description == "0.25")
        #expect(MPFloat(2).power(MPBigInt(10)) == 1024)
        #expect((MPFloat(0.5) + MPFloat(0.25)).description == "0.75")
    }

    @Test func zeroIsWellBehaved() {
        // regression: MPBigInt(0).trailingZeroBitCount == 1 (the stdlib's own
        // convention) once smeared the scale, making a literal 0 a denormal
        // whose negation read as -infinity -- and 2 < 0 came out true
        let zero: MPFloat = 0
        #expect(zero.isZero)
        #expect(zero.scale == 0 && zero.mantissa == 0)
        #expect(!(-zero).isInfinite)
        #expect((-zero).isZero)
        #expect((MPFloat(2) - MPFloat(2)).isZero)
        #expect(!(MPFloat(2) < 0))
        #expect(MPFloat(0) < MPFloat(2))
        #expect(!MPFloat(2).squareRoot(precision: 64).isNaN)
    }

    @Test func specialValues() {
        #expect(MPFloat.nan.isNaN)
        #expect(MPFloat.infinity.isInfinite)
        #expect((-MPFloat.infinity).sign == .minus)
        #expect((MPFloat(1) / MPFloat(0)).isInfinite)
        #expect(MPFloat(-1).squareRoot(precision: 64).isNaN)
        #expect(MPFloat.negativeZero.isZero)
        #expect(MPFloat.negativeZero == MPFloat.zero)
    }

    @Test func conversions() {
        #expect(Double(MPFloat(0.375)) == 0.375)
        #expect(MPFloat(3.75).toDouble() == 3.75)
        // exact BigRat bridge in both directions
        let x = MPFloat(3) / MPFloat(4)
        #expect(x.toBigRat() == BigRat(3, 4))
        #expect(MPFloat(BigRat(3, 4)) == x)
        // and the same-element Rational bridge
        let r = x.toRational()
        #expect(r.num == 3 && r.den == 4)
        // BinaryInteger both ways
        #expect(MPFloat(MPBigInt(1) << 100).exponent == 100)
        #expect(BNBigInt(12345) == BNBigInt(MPBigInt(12345)))
    }

    @Test func stringParsing() {
        // the generic parser: IntType(String, radix:) underneath
        #expect(MPFloat("3.5") == 3.5)
        #expect(MPFloat("-0.25") == -0.25)
        #expect(MPFloat("1.5e3") == 1500)
        #expect(MPFloat("0x1.8p1") == 3)
        #expect(MPFloat("0b101") == 5)
        #expect(MPFloat("nonsense") == nil)
        #expect(MPFloat("1e") == nil)
        #expect(MPFloat("") == nil)
    }

    @Test func precisionKnob() {
        // the static knobs moved to per-specialization storage; setting
        // MPFloat's must not disturb BigFloat's
        let saved = MPFloat.precision
        defer { MPFloat.precision = saved }
        MPFloat.precision = 64
        #expect(MPFloat.precision == 64)
        #expect(BigFloat.precision == 128)
    }

    @Test func codable() throws {
        let original = MPFloat.PI(precision: 128)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MPFloat.self, from: data)
        #expect(decoded == original)
    }
}
