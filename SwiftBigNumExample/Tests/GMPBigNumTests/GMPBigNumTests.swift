import Foundation
import Testing
import BigNum
import GMPBigInt
import GMPBigNum

@Suite struct GMPRatTests {
    @Test func arithmetic() {
        let third = GMPBigInt(1).over(GMPBigInt(3))
        #expect(third + GMPBigInt(1).over(GMPBigInt(6)) == GMPBigInt(1).over(GMPBigInt(2)))
        #expect(third * 3 == 1)
        #expect(third - third == 0)
    }

    @Test func reduction() {
        // reduction runs through GMPBigInt's own gcd (a RationalElement
        // requirement since swift-bignum#31)
        let q = GMPBigInt(6).over(GMPBigInt(8))
        #expect(q.num == 3 && q.den == 4)
        let h10 = (1...10).map { GMPBigInt(1).over(GMPBigInt($0)) }.reduce(GMPRat(0), +)
        #expect(h10.num == 7381 && h10.den == 2520)
    }

    @Test func comparisonsAndMixed() {
        #expect(GMPBigInt(1).over(GMPBigInt(3)) < GMPBigInt(1).over(GMPBigInt(2)))
        #expect(GMPBigInt(-1).over(GMPBigInt(3)) < GMPRat(0))
        let (i, f) = GMPBigInt(7).over(GMPBigInt(3)).toMixed()
        #expect(i == 2 && f == GMPBigInt(1).over(GMPBigInt(3)))
        #expect(GMPBigInt(22).over(GMPBigInt(7)).toDouble() == 22.0 / 7.0)
    }

    @Test func squareRoot() {
        let two = GMPBigInt(2).over(GMPBigInt(1))
        let root = two.squareRoot(precision: 128)
        // r^2 <= 2 < (r + ulp)^2, and it must agree with BigRat's own digits
        #expect(root * root <= two)
        let reference = BNBigInt(2).over(BNBigInt(1)).squareRoot(precision: 128)
        #expect(root.num.description == reference.num.description)
        #expect(root.den.description == reference.den.description)
    }
}

@Suite struct GMPFloatTests {
    @Test func mantissaIsGMPBigInt() {
        #expect(type(of: GMPFloat(2).mantissa) == GMPBigInt.self)
    }

    @Test func agreesWithBigFloat() {
        // the point of the whole exercise: same machinery, different digits,
        // digit-for-digit identical output
        for px in [64, 128, 192] {
            #expect(GMPFloat.PI(precision: px).description
                 == BigFloat.PI(precision: px).description)
            #expect(GMPFloat.sqrt(GMPFloat(2), precision: px).description
                 == BigFloat.sqrt(BigFloat(2), precision: px).description)
            #expect(GMPFloat.exp(GMPFloat(1), precision: px).description
                 == BigFloat.exp(BigFloat(1), precision: px).description)
            #expect(GMPFloat.log(GMPFloat(10), precision: px).description
                 == BigFloat.log(BigFloat(10), precision: px).description)
        }
    }

    @Test func knownDigits() {
        #expect(GMPFloat.PI(precision: 128).description.hasPrefix("3.14159265358979323846"))
        #expect(GMPFloat.sqrt(GMPFloat(2), precision: 128).description.hasPrefix("1.41421356237309504880"))
        #expect(GMPFloat.exp(GMPFloat(1), precision: 128).description.hasPrefix("2.71828182845904523536"))
    }

    @Test func arithmetic() {
        #expect(GMPFloat(2) + GMPFloat(3) == 5)
        #expect(GMPFloat(2) * GMPFloat(3) == 6)
        #expect((GMPFloat(1) / GMPFloat(4)).description == "0.25")
        #expect(GMPFloat(2).power(GMPBigInt(10)) == 1024)
        #expect((GMPFloat(0.5) + GMPFloat(0.25)).description == "0.75")
    }

    @Test func zeroIsWellBehaved() {
        // regression: GMPBigInt(0).trailingZeroBitCount == 1 (the stdlib's own
        // convention) once smeared the scale, making a literal 0 a denormal
        // whose negation read as -infinity -- and 2 < 0 came out true
        let zero: GMPFloat = 0
        #expect(zero.isZero)
        #expect(zero.scale == 0 && zero.mantissa == 0)
        #expect(!(-zero).isInfinite)
        #expect((-zero).isZero)
        #expect((GMPFloat(2) - GMPFloat(2)).isZero)
        #expect(!(GMPFloat(2) < 0))
        #expect(GMPFloat(0) < GMPFloat(2))
        #expect(!GMPFloat(2).squareRoot(precision: 64).isNaN)
    }

    @Test func specialValues() {
        #expect(GMPFloat.nan.isNaN)
        #expect(GMPFloat.infinity.isInfinite)
        #expect((-GMPFloat.infinity).sign == .minus)
        #expect((GMPFloat(1) / GMPFloat(0)).isInfinite)
        #expect(GMPFloat(-1).squareRoot(precision: 64).isNaN)
        #expect(GMPFloat.negativeZero.isZero)
        #expect(GMPFloat.negativeZero == GMPFloat.zero)
    }

    @Test func conversions() {
        #expect(Double(GMPFloat(0.375)) == 0.375)
        #expect(GMPFloat(3.75).toDouble() == 3.75)
        // exact BigRat bridge in both directions
        let x = GMPFloat(3) / GMPFloat(4)
        #expect(x.toBigRat() == BigRat(3, 4))
        #expect(GMPFloat(BigRat(3, 4)) == x)
        // and the same-element Rational bridge
        let r = x.toRational()
        #expect(r.num == 3 && r.den == 4)
        // BinaryInteger both ways
        #expect(GMPFloat(GMPBigInt(1) << 100).exponent == 100)
        #expect(BNBigInt(12345) == BNBigInt(GMPBigInt(12345)))
    }

    @Test func stringParsing() {
        // the generic parser: IntType(String, radix:) underneath
        #expect(GMPFloat("3.5") == 3.5)
        #expect(GMPFloat("-0.25") == -0.25)
        #expect(GMPFloat("1.5e3") == 1500)
        #expect(GMPFloat("0x1.8p1") == 3)
        #expect(GMPFloat("0b101") == 5)
        #expect(GMPFloat("nonsense") == nil)
        #expect(GMPFloat("1e") == nil)
        #expect(GMPFloat("") == nil)
    }

    @Test func precisionKnob() {
        // the static knobs moved to per-specialization storage; setting
        // GMPFloat's must not disturb BigFloat's
        let saved = GMPFloat.precision
        defer { GMPFloat.precision = saved }
        GMPFloat.precision = 64
        #expect(GMPFloat.precision == 64)
        #expect(BigFloat.precision == 128)
    }

    @Test func codable() throws {
        let original = GMPFloat.PI(precision: 128)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GMPFloat.self, from: data)
        #expect(decoded == original)
    }
}
