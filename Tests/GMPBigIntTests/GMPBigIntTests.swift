import Testing
import Foundation
@testable import GMPBigInt

@Suite struct MPBigIntTests {
    @Test func integerLiterals() {
        // StaticBigInt literals: arbitrary size, no strings needed
        let huge: MPBigInt = 123456789012345678901234567890123456789012345678901234567890
        #expect(huge.description == "123456789012345678901234567890123456789012345678901234567890")
        let negHuge: MPBigInt = -0x1_0000_0000_0000_0000 // -(2^64)
        #expect(negHuge == -(MPBigInt(1) << 64))
        #expect((0 as MPBigInt).description == "0")
        #expect((-42 as MPBigInt).description == "-42")
    }

    @Test func stringConversions() {
        let x = MPBigInt("123456789123456789123456789")
        #expect(x != nil)
        #expect(x!.description == "123456789123456789123456789")
        #expect(MPBigInt("deadbeef", radix: 16) == 0xdeadbeef)
        #expect(MPBigInt("-DEADBEEF", radix: 16) == -0xdeadbeef)
        #expect(MPBigInt("777", radix: 8) == 0o777)
        #expect(MPBigInt("101010", radix: 2) == 0b101010)
        #expect(MPBigInt("zz", radix: 36) == 1295) // 35 * 36 + 35
        #expect(MPBigInt("+123") == 123)
        #expect(MPBigInt("") == nil)
        #expect(MPBigInt("12a") == nil)
        #expect(MPBigInt("-") == nil)
        #expect(MPBigInt("z", radix: 35) == nil)

        let big = MPBigInt(1) << 200 - 1
        for radix in [2, 8, 10, 16, 36] {
            #expect(MPBigInt(big.toString(radix: radix), radix: radix) == big)
        }
        #expect((255 as MPBigInt).toString(radix: 16) == "ff")
        #expect((-255 as MPBigInt).toString(radix: 16) == "-ff")
    }

    @Test func arithmetic() {
        let a: MPBigInt = 123456789123456789123456789
        let b: MPBigInt = 987654321987654321987654321
        #expect(a + b == 1111111111111111111111111110)
        #expect(b - a == 864197532864197532864197532)
        #expect(a * b == 121932631356500531591068431581771069347203169112635269)
        #expect((a + b) - b == a)
        #expect(2.0 * Double(a) != 0) // just exercise Double conversion path

        // factorial(100), the classic sanity check
        let fact100 = (1...100).map { MPBigInt($0) }.reduce(1, *)
        #expect(fact100.description ==
            "93326215443944152681699238856266700490715968264381621468592963895217599993229915608941463976156518286253697920827223758251185210916864000000000000000000000000")

        // 2^128
        #expect(MPBigInt(2).power(128).description == "340282366920938463463374607431768211456")
    }

    @Test func divisionSemantics() {
        // Swift semantics: / truncates toward zero, % takes the dividend's sign
        #expect((-7 as MPBigInt) / 2 == -3)
        #expect((-7 as MPBigInt) % 2 == -1)
        #expect((7 as MPBigInt) / -2 == -3)
        #expect((7 as MPBigInt) % -2 == 1)
        let (q, r) = MPBigInt(-7).quotientAndRemainder(dividingBy: 2)
        #expect(q == -3 && r == -1)
        #expect(MPBigInt(12).isMultiple(of: 4))
        #expect(!MPBigInt(12).isMultiple(of: 5))
    }

    @Test func bitwiseAndShifts() {
        let x: MPBigInt = 0b1100
        let y: MPBigInt = 0b1010
        #expect(x & y == 0b1000)
        #expect(x | y == 0b1110)
        #expect(x ^ y == 0b0110)
        #expect(~x == -13)
        #expect(MPBigInt(1) << 100 == MPBigInt("1267650600228229401496703205376"))
        #expect((MPBigInt(1) << 100) >> 100 == 1)
        #expect(MPBigInt(1) << -2 == 0)     // smart shift: negative count reverses direction
        #expect(MPBigInt(16) >> -2 == 64)
        #expect(MPBigInt(-1) >> 1000 == -1) // arithmetic shift
    }

    @Test func comparisons() {
        let values: [MPBigInt] = [3, -5, 0, 12345678901234567890123456789, -12345678901234567890123456789]
        let sorted = values.sorted()
        #expect(sorted == [-12345678901234567890123456789, -5, 0, 3, 12345678901234567890123456789])
        #expect(MPBigInt(5) > 4)
        #expect(MPBigInt(-5) < -4)
        #expect(MPBigInt(5).signum() == 1)
        #expect(MPBigInt(-5).signum() == -1)
        #expect(MPBigInt(0).signum() == 0)
        #expect(abs(MPBigInt(-42)) == 42)
        #expect(MPBigInt(-42).magnitude == 42)
    }

    @Test func integerConversions() {
        #expect(MPBigInt(Int.max).description == "\(Int.max)")
        #expect(MPBigInt(Int.min).description == "\(Int.min)")
        #expect(MPBigInt(UInt64.max).description == "18446744073709551615")
        #expect(Int(MPBigInt(Int.max)) == Int.max)
        #expect(Int(MPBigInt(Int.min)) == Int.min)
        #expect(UInt64(MPBigInt(UInt64.max)) == UInt64.max)
        #expect(Int8(MPBigInt(-128)) == -128)
        #expect(Int(exactly: MPBigInt(1) << 100) == nil)
        #expect(Int(exactly: MPBigInt(42)) == 42)
        #expect(UInt(exactly: MPBigInt(-1)) == nil)
    }

    @Test func floatingPointConversions() {
        #expect(MPBigInt(3.75) == 3)
        #expect(MPBigInt(-3.75) == -3)
        #expect(MPBigInt(exactly: 3.75) == nil)
        #expect(MPBigInt(exactly: 4.0) == 4)
        #expect(MPBigInt(exactly: Double.nan) == nil)
        #expect(MPBigInt(exactly: Double.infinity) == nil)
        // 2^100 is exactly representable as a Double
        let d = Double(sign: .plus, exponent: 100, significand: 1)
        #expect(MPBigInt(exactly: d) == MPBigInt(1) << 100)
        #expect(Double(MPBigInt(1) << 100) == d)
        #expect(Double(MPBigInt(3)) == 3.0)
        #expect(Float(MPBigInt(-12345)) == -12345.0)
    }

    @Test func wordsAndBitWidth() {
        #expect(MPBigInt(0).words == [0])
        #expect(MPBigInt(1).words == [1])
        #expect(MPBigInt(-1).words == [UInt.max])
        #expect(MPBigInt(UInt64.max).words == [UInt.max, 0])
        #expect((MPBigInt(1) << 64).words == [0, 1])
        #expect(MPBigInt(Int.min).words == [UInt(bitPattern: Int.min)])

        #expect(MPBigInt(0).bitWidth == 1)
        #expect(MPBigInt(1).bitWidth == 2)
        #expect(MPBigInt(-1).bitWidth == 1)
        #expect(MPBigInt(-2).bitWidth == 2)
        #expect(MPBigInt(127).bitWidth == 8)
        #expect(MPBigInt(128).bitWidth == 9)
        #expect(MPBigInt(-128).bitWidth == 8)
        #expect((MPBigInt(1) << 100).bitWidth == 102)

        #expect(MPBigInt(0).trailingZeroBitCount == 1) // == bitWidth, per BinaryInteger docs
        #expect(MPBigInt(1).trailingZeroBitCount == 0)
        #expect(MPBigInt(8).trailingZeroBitCount == 3)
        #expect((MPBigInt(1) << 100).trailingZeroBitCount == 100)
        #expect(MPBigInt(-8).trailingZeroBitCount == 3)
    }

    @Test func hashing() {
        let a = MPBigInt("123456789123456789123456789")!
        let b = MPBigInt("123456789123456789123456788")! + 1
        #expect(a == b)
        #expect(a.hashValue == b.hashValue)
        let set: Set<MPBigInt> = [a, b, 42, 42]
        #expect(set.count == 2)
    }

    @Test func codable() throws {
        let original: [MPBigInt] = [0, -1, 12345678901234567890123456789012345678901234567890]
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([MPBigInt].self, from: data)
        #expect(decoded == original)
        #expect(String(data: data, encoding: .utf8)!.contains("\"-1\""))
    }

    @Test func genericAlgorithms() {
        // MPBigInt should work in any BinaryInteger-generic code
        func gcd<T: BinaryInteger>(_ a: T, _ b: T) -> T {
            var (a, b) = (a, b)
            while b != 0 { (a, b) = (b, a % b) }
            return a
        }
        let f90 = (1...90).map { MPBigInt($0) }.reduce(1, *)
        let f92 = (1...92).map { MPBigInt($0) }.reduce(1, *)
        #expect(gcd(f90, f92) == f90)
        #expect(gcd(MPBigInt(48), MPBigInt(18)) == 6)

        // Strideable
        let sum = stride(from: MPBigInt(1), through: 10, by: 1).reduce(0, +)
        #expect(sum == 55)
    }

    @Test func modularExponentiation() {
        #expect(MPBigInt(2).power(10, mod: 1000) == 24)
        #expect(MPBigInt(2).power(0, mod: 1000) == 1)
        #expect(MPBigInt(5).power(0, mod: 1) == 0)   // everything is 0 mod 1
        // least non-negative residue, unlike truncated %
        #expect(MPBigInt(-2).power(3, mod: 5) == 2)
        #expect(MPBigInt(-2).power(3) % 5 == -3)
        // negative modulus: least residue in (m, 0]
        #expect(MPBigInt(2).power(10, mod: -1000) == -976)
        // agreement with plain power where both are computable
        #expect(MPBigInt(7).power(20, mod: 1000003) == MPBigInt(7).power(20) % 1000003)
        // negative exponent is the modular inverse
        #expect(MPBigInt(3).power(-1, mod: 7) == 5)  // 3 * 5 == 15 ≡ 1 (mod 7)
        #expect(MPBigInt(3).power(-2, mod: 7) == 4)  // 5 * 5 == 25 ≡ 4 (mod 7)
        // Fermat's little theorem: a^(p-1) ≡ 1 (mod p) for prime p ∤ a
        let p: MPBigInt = 1000000007
        #expect(MPBigInt(12345).power(p - 1, mod: p) == 1)
        // RSA textbook example: n = 61 * 53, e = 17, d = 2753
        let n: MPBigInt = 3233
        let c = MPBigInt(65).power(17, mod: n)
        #expect(c == 2790)
        #expect(c.power(2753, mod: n) == 65)
        // huge exponent that plain power(_:) could never materialize
        #expect(MPBigInt(2).power(MPBigInt(1) << 512, mod: 1_000_000_007) == 656254629)
    }

    @Test func greatestCommonDivisor() {
        #expect(MPBigInt(48).greatestCommonDivisor(with: 18) == 6)
        #expect(MPBigInt(-48).greatestCommonDivisor(with: 18) == 6)   // never negative
        #expect(MPBigInt(48).greatestCommonDivisor(with: -18) == 6)
        #expect(MPBigInt(0).greatestCommonDivisor(with: 5) == 5)
        #expect(MPBigInt(0).greatestCommonDivisor(with: 0) == 0)      // only zero case
        #expect(MPBigInt(17).greatestCommonDivisor(with: 19) == 1)    // coprime
        let p2_100 = MPBigInt(1) << 100
        #expect(p2_100.greatestCommonDivisor(with: MPBigInt(1) << 60) == MPBigInt(1) << 60)
        let f90 = (1...90).map { MPBigInt($0) }.reduce(1, *)
        let f92 = f90 * 91 * 92
        #expect(f90.greatestCommonDivisor(with: f92) == f90)
    }

    @Test func squareRoot() {
        #expect(MPBigInt(0).squareRoot() == 0)
        #expect(MPBigInt(1).squareRoot() == 1)
        #expect(MPBigInt(2).squareRoot() == 1)
        #expect(MPBigInt(3).squareRoot() == 1)
        #expect(MPBigInt(4).squareRoot() == 2)
        #expect(MPBigInt(15).squareRoot() == 3)
        #expect(MPBigInt(16).squareRoot() == 4)
        #expect(MPBigInt(17).squareRoot() == 4)
        // floor semantics around a huge perfect square
        let n = MPBigInt(10).power(50) + 12345
        #expect((n * n).squareRoot() == n)
        #expect((n * n - 1).squareRoot() == n - 1)
        #expect((n * n + 1).squareRoot() == n)
        // consistency: r^2 <= x < (r+1)^2
        let x = MPBigInt("123456789", radix: 10)!.power(7)
        let r = x.squareRoot()
        #expect(r * r <= x && x < (r + 1) * (r + 1))
    }

    @Test func primality() {
        // small values: proven either way
        #expect(MPBigInt(-7).isPrime == false)
        #expect(MPBigInt(0).isPrime == false)
        #expect(MPBigInt(1).isPrime == false)
        #expect(MPBigInt(2).isPrime == true)
        #expect(MPBigInt(3).isPrime == true)
        #expect(MPBigInt(4).isPrime == false)
        #expect(MPBigInt(97).isPrime == true)
        #expect(MPBigInt(91).isPrime == false)       // 7 × 13
        #expect(MPBigInt(1000003).isPrime == true)
        #expect(MPBigInt(1000001).isPrime == false)  // 101 × 9901
        // Carmichael numbers fool Fermat, not Miller-Rabin
        #expect(MPBigInt(561).isPrime == false)
        #expect(MPBigInt(1105).isPrime == false)
        #expect(MPBigInt(1729).isPrime == false)
        // 2047 = 23 × 89 is a strong pseudoprime to base 2: one round lies,
        // the verdict does not
        #expect(MPBigInt(2047).millerRabinTest(base: 2))
        #expect(MPBigInt(2047).isPrime == false)
        // beyond 2^64 but inside A014233's deterministic range: still a proof
        #expect(MPBigInt("100000000000000000039")!.isPrime == true)
        #expect(MPBigInt("100000000000000000037")!.isPrime == false)
        // Mersenne numbers beyond the deterministic MR range: Lucas-Lehmer
        // settles them outright, so isPrime answers where it once said nil
        let m89 = (MPBigInt(1) << 89) - 1   // Mersenne prime 2^89 - 1
        #expect(m89.isProbablePrime)
        #expect(m89.isPrime == true)
        let m127 = (MPBigInt(1) << 127) - 1 // Mersenne prime 2^127 - 1
        #expect(m127.isProbablePrime)
        #expect(m127.isPrime == true)
        // a witness is a proof at any size
        #expect((m89 * m127).isPrime == false)
        #expect((m127 * m127).isPrime == false)
        // past every deterministic bound and not Mersenne: still nil
        let q = m89.nextPrime
        #expect(q.isPrime == nil && q.isProbablePrime)
        #expect(q.isSurelyPrime == (true, surely: false))
        #expect(MPBigInt(2047).isSurelyPrime == (false, surely: true))
        #expect(m127.isSurelyPrime == (true, surely: true))
    }

    @Test func jacobiSymbol() {
        // (a/7) for a in 1...6, verified via Euler's criterion
        #expect((1...6).map { MPBigInt(7).jacobiSymbol($0) } == [1, 1, -1, 1, -1, -1])
        // composite modulus: multiplicative over the factors
        #expect(MPBigInt(15).jacobiSymbol(2) == 1)   // (2/3)(2/5) = (-1)(-1)
        #expect(MPBigInt(15).jacobiSymbol(7) == -1)  // (7/3)(7/5) = (1)(-1)
        #expect(MPBigInt(9).jacobiSymbol(5) == 1)    // (5/3)^2
        #expect(MPBigInt(3).jacobiSymbol(-1) == -1)
        #expect(MPBigInt(9907).jacobiSymbol(1001) == -1)
        // 0 unless self is odd and positive
        #expect(MPBigInt(15).jacobiSymbol(3) == 0)   // shared factor
        #expect(MPBigInt(8).jacobiSymbol(3) == 0)
        #expect(MPBigInt(-7).jacobiSymbol(3) == 0)
        #expect(MPBigInt(0).jacobiSymbol(3) == 0)
    }

    @Test func lucasProbablePrime() {
        #expect(MPBigInt(2).isLucasProbablePrime)
        #expect(MPBigInt(1000003).isLucasProbablePrime)
        #expect(((MPBigInt(1) << 127) - 1).isLucasProbablePrime)
        #expect(!MPBigInt(1).isLucasProbablePrime)
        #expect(!MPBigInt(4).isLucasProbablePrime)
        #expect(!MPBigInt(561).isLucasProbablePrime)   // Carmichael
        #expect(!MPBigInt(2047).isLucasProbablePrime)  // base-2 strong pseudoprime
        // perfect squares are screened out before the D search
        #expect(!MPBigInt(25).isLucasProbablePrime)
        let big = MPBigInt(10).power(20) + 39          // prime
        #expect(big.isLucasProbablePrime)
        #expect(!(big * big).isLucasProbablePrime)
    }

    @Test func mersennePrime() {
        // 2^p - 1 for prime p: Lucas-Lehmer verdicts
        #expect(MPBigInt(3).isMersennePrime == true)          // M2
        #expect(MPBigInt(7).isMersennePrime == true)          // M3
        #expect(MPBigInt(8191).isMersennePrime == true)       // M13
        #expect(MPBigInt(2047).isMersennePrime == false)      // M11 = 23 × 89
        #expect(((MPBigInt(1) << 67) - 1).isMersennePrime == false)  // M67, Cole's composite
        #expect(((MPBigInt(1) << 89) - 1).isMersennePrime == true)   // M89
        #expect(((MPBigInt(1) << 127) - 1).isMersennePrime == true)  // M127
        // composite exponent: composite without running the recurrence
        #expect(((MPBigInt(1) << 12) - 1).isMersennePrime == false)
        // not 2^p - 1 at all
        #expect(MPBigInt(10).isMersennePrime == nil)
        #expect(MPBigInt(2).isMersennePrime == nil)
        #expect(MPBigInt(0).isMersennePrime == nil)
        #expect(MPBigInt(-7).isMersennePrime == nil)
    }

    @Test func primeWalking() {
        // nextPrime: anything below 2 gets 2
        #expect(MPBigInt(-5).nextPrime == 2)
        #expect(MPBigInt(0).nextPrime == 2)
        #expect(MPBigInt(1).nextPrime == 2)
        #expect(MPBigInt(2).nextPrime == 3)
        #expect(MPBigInt(3).nextPrime == 5)
        #expect(MPBigInt(7).nextPrime == 11)
        #expect(MPBigInt(89).nextPrime == 97)
        // prevPrime: 2 and below have no answer
        #expect(MPBigInt(-5).prevPrime == nil)
        #expect(MPBigInt(2).prevPrime == nil)
        #expect(MPBigInt(3).prevPrime == 2)
        #expect(MPBigInt(4).prevPrime == 3)
        #expect(MPBigInt(100).prevPrime == 97)
        // around 10^20, straddling 2^64 but inside the deterministic range
        let p20 = MPBigInt(10).power(20)
        #expect(p20.nextPrime == MPBigInt("100000000000000000039"))
        #expect(p20.prevPrime == MPBigInt("99999999999999999989"))
        // walking is exclusive: a prime's neighbors skip the prime itself
        let p = MPBigInt("100000000000000000039")!
        #expect(p.prevPrime == MPBigInt("99999999999999999989"))
        #expect(MPBigInt("99999999999999999989")!.nextPrime == p)
        // past the deterministic range the walk still terminates, on the
        // probable test
        let m89 = (MPBigInt(1) << 89) - 1
        let q = m89.nextPrime
        #expect(q > m89 && q.isProbablePrime && q.isPrime == nil)
        #expect(q.prevPrime == m89)  // 2^89 - 1 is itself prime
    }

    @Test func primeSequence() {
        #expect(Array(MPBigInt.primes.prefix(10)) == [2, 3, 5, 7, 11, 13, 17, 19, 23, 29])
        // endless and lazy: only walks as far as asked
        #expect(MPBigInt.primes.first(where: { $0 > 1000 }) == 1009)
        #expect(MPBigInt.primes.prefix(while: { $0 < 100 }).reduce(0, +) == 1060)
        // independent iterators do not share state
        let a = MPBigInt.primes.makeIterator()
        var b = a, c = a
        #expect(b.next() == 2 && b.next() == 3)
        #expect(c.next() == 2)
    }

    @Test func fibonacci() {
        func fib(_ n: Int) -> MPBigInt {
            var (a, b): (MPBigInt, MPBigInt) = (0, 1)
            for _ in 0..<n { (a, b) = (b, a + b) }
            return a
        }
        #expect(fib(100).description == "354224848179261915075")
        #expect(fib(10) == 55)
    }
}
