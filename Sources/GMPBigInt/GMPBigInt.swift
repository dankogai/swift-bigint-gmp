import Cgmp

// gmp.h wraps every mpz_* entry point in an object-like macro over the real
// __gmpz_* symbol, and macros do not survive the Clang importer.  Bind the
// familiar names back to the symbols this file uses.
private let mpz_init             = __gmpz_init
private let mpz_clear            = __gmpz_clear
private let mpz_set              = __gmpz_set
private let mpz_set_si           = __gmpz_set_si
private let mpz_set_str          = __gmpz_set_str
private let mpz_get_str          = __gmpz_get_str
private let mpz_add              = __gmpz_add
private let mpz_add_ui           = __gmpz_add_ui
private let mpz_sub              = __gmpz_sub
private let mpz_sub_ui           = __gmpz_sub_ui
private let mpz_mul              = __gmpz_mul
private let mpz_tdiv_q           = __gmpz_tdiv_q
private let mpz_tdiv_r           = __gmpz_tdiv_r
private let mpz_neg              = __gmpz_neg
private let mpz_abs              = __gmpz_abs
private let mpz_and              = __gmpz_and
private let mpz_ior              = __gmpz_ior
private let mpz_xor              = __gmpz_xor
private let mpz_com              = __gmpz_com
private let mpz_mul_2exp         = __gmpz_mul_2exp
private let mpz_fdiv_q_2exp      = __gmpz_fdiv_q_2exp
private let mpz_pow_ui           = __gmpz_pow_ui
private let mpz_powm             = __gmpz_powm
private let mpz_invert           = __gmpz_invert
private let mpz_gcd              = __gmpz_gcd
private let mpz_sqrt             = __gmpz_sqrt
private let mpz_cmp              = __gmpz_cmp
private let mpz_sizeinbase       = __gmpz_sizeinbase
private let mpz_scan1            = __gmpz_scan1
private let mpz_tstbit           = __gmpz_tstbit
private let mpz_import           = __gmpz_import
private let mpz_export           = __gmpz_export
private let mpz_jacobi           = __gmpz_jacobi
private let mpz_perfect_square_p = __gmpz_perfect_square_p

/// An arbitrary-precision signed integer backed by [GNU MP]'s `mpz_t`.
///
/// Every value wraps a heap-allocated `mpz_t` that is written once and never
/// mutated afterward; all arithmetic is delegated to GMP.
/// Conforms to `SignedInteger`, so it can be used wherever a `BinaryInteger`
/// is expected.
///
/// [GNU MP]: https://gmplib.org
public struct GMPBigInt {
    /// The underlying GMP integer.  Initialized once, cleared on deinit,
    /// and treated as immutable in between.
    internal final class Storage {
        var z = __mpz_struct()
        init() { mpz_init(&z) }
        deinit { mpz_clear(&z) }
        /// Runs `body` with the raw `mpz_ptr` — the one safe way to alias
        /// rop and op in a single GMP call under Swift's exclusivity rules.
        func withMutablePointer<R>(_ body: (UnsafeMutablePointer<__mpz_struct>) -> R) -> R {
            withUnsafeMutablePointer(to: &z, body)
        }
    }

    internal let storage: Storage

    internal init(_ storage: Storage) {
        self.storage = storage
    }
}

// MARK: - GMP plumbing

extension GMPBigInt {
    /// -1, 0, or +1 — read straight off the mpz's limb count.
    internal var sign: Int {
        let size = storage.z._mp_size
        return size < 0 ? -1 : size == 0 ? 0 : 1
    }

    /// Bit 0 in two's complement, which GMP's `mpz_tstbit` shares with JS.
    internal var isOdd: Bool {
        mpz_tstbit(&storage.z, 0) != 0
    }

    internal static func unary(
        _ op: (UnsafeMutablePointer<__mpz_struct>?, UnsafePointer<__mpz_struct>?) -> Void,
        _ x: Self
    ) -> Self {
        let s = Storage()
        op(&s.z, &x.storage.z)
        return Self(s)
    }

    internal static func binary(
        _ op: (UnsafeMutablePointer<__mpz_struct>?, UnsafePointer<__mpz_struct>?, UnsafePointer<__mpz_struct>?) -> Void,
        _ lhs: Self, _ rhs: Self
    ) -> Self {
        let s = Storage()
        op(&s.z, &lhs.storage.z, &rhs.storage.z)
        return Self(s)
    }

    private static func shift(
        _ op: (UnsafeMutablePointer<__mpz_struct>?, UnsafePointer<__mpz_struct>?, UInt) -> Void,
        _ x: Self, _ count: UInt
    ) -> Self {
        let s = Storage()
        op(&s.z, &x.storage.z, count)
        return Self(s)
    }

    /// The magnitude's bits as 64-bit words, least significant first;
    /// empty for zero.
    internal var magnitudeWords: [UInt] {
        guard sign != 0 else { return [] }
        let count = (mpz_sizeinbase(&storage.z, 2) + 63) / 64
        var written = 0
        var buf = [UInt](repeating: 0, count: count)
        buf.withUnsafeMutableBufferPointer { p in
            _ = mpz_export(p.baseAddress, &written, -1, MemoryLayout<UInt>.size, 0, 0, &storage.z)
        }
        return buf
    }

    /// Builds |words| interpreted as an unsigned little-endian magnitude,
    /// negated when asked.
    internal init(magnitudeWords words: [UInt], negative: Bool) {
        let s = Storage()
        if !words.isEmpty {
            words.withUnsafeBufferPointer { p in
                mpz_import(&s.z, words.count, -1, MemoryLayout<UInt>.size, 0, 0, p.baseAddress)
            }
        }
        if negative {
            s.withMutablePointer { mpz_neg($0, $0) }
        }
        self.init(s)
    }

    /// Builds the value whose two's-complement representation is `words`
    /// (least significant first, already sign-extended to full words).
    internal init(twosComplementWords words: [UInt], negative: Bool) {
        if !negative {
            self.init(magnitudeWords: words, negative: false)
            return
        }
        // magnitude = ~pattern + 1
        let s = Self(magnitudeWords: words.map { ~$0 }, negative: false).storage
        s.withMutablePointer { mpz_add_ui($0, $0, 1) }
        s.withMutablePointer { mpz_neg($0, $0) }
        self.init(s)
    }

    /// |self| - 1, an ingredient of the two's-complement views of negatives.
    private var magnitudeMinusOne: Self {
        let s = Storage()
        mpz_abs(&s.z, &storage.z)
        s.withMutablePointer { mpz_sub_ui($0, $0, 1) }
        return Self(s)
    }
}

// MARK: - Initializers

extension GMPBigInt {
    /// Creates a value from its textual representation in the given radix (2...36).
    /// Accepts an optional leading `+` or `-`. Returns `nil` on invalid input.
    public init?(_ description: String, radix: Int) {
        precondition(2 <= radix && radix <= 36, "radix must be in 2...36")
        var s = Substring(description)
        while let first = s.first, first.isWhitespace { s.removeFirst() }
        while let last = s.last, last.isWhitespace { s.removeLast() }
        var negative = false
        if let first = s.first, first == "+" || first == "-" {
            negative = first == "-"
            s.removeFirst()
        }
        guard !s.isEmpty else { return nil }
        for byte in s.utf8 {
            let digit: Int
            switch byte {
            case 0x30...0x39: digit = Int(byte) - 0x30       // 0-9
            case 0x61...0x7a: digit = Int(byte) - 0x61 + 10  // a-z
            case 0x41...0x5a: digit = Int(byte) - 0x41 + 10  // A-Z
            default: return nil
            }
            guard digit < radix else { return nil }
        }
        let storage = Storage()
        let cleaned = (negative ? "-" : "") + s
        guard cleaned.withCString({ mpz_set_str(&storage.z, $0, Int32(radix)) }) == 0 else {
            return nil
        }
        self.init(storage)
    }

    public init<T: BinaryInteger>(_ source: T) {
        if let same = source as? Self {
            self = same
            return
        }
        if let small = Int(exactly: source) {
            let s = Storage()
            mpz_set_si(&s.z, small)
            self.init(s)
            return
        }
        self.init(magnitudeWords: Array(source.magnitude.words), negative: source < 0)
    }

    public init?<T: BinaryInteger>(exactly source: T) {
        self.init(source) // arbitrary precision: always exact
    }

    public init<T: BinaryInteger>(clamping source: T) {
        self.init(source)
    }

    public init<T: BinaryInteger>(truncatingIfNeeded source: T) {
        self.init(source)
    }

    public init?<T: BinaryFloatingPoint>(exactly source: T) {
        guard source.isFinite, source.rounded(.towardZero) == source else { return nil }
        self.init(integral: source)
    }

    public init<T: BinaryFloatingPoint>(_ source: T) {
        precondition(source.isFinite, "cannot convert \(source) to GMPBigInt")
        self.init(integral: source.rounded(.towardZero))
    }

    /// `source` must be finite and integral.
    private init<T: BinaryFloatingPoint>(integral source: T) {
        if source == 0 {
            self.init(Storage()) // a fresh mpz is zero
            return
        }
        // A nonzero integral value is normal, so the significand has an implicit
        // leading 1 bit: value = ±(pattern | 1 << significandBitCount) × 2^(exponent - significandBitCount)
        let mantissa = GMPBigInt(source.significandBitPattern) | (GMPBigInt(1) << T.significandBitCount)
        let shift = Int(source.exponent) - T.significandBitCount
        let magnitude = shift >= 0 ? mantissa << shift : mantissa >> (-shift)
        self = source < 0 ? -magnitude : magnitude
    }
}

// MARK: - String conversions

extension GMPBigInt: CustomStringConvertible, LosslessStringConvertible {
    public init?(_ description: String) {
        self.init(description, radix: 10)
    }

    public var description: String {
        toString()
    }

    /// The textual representation in the given radix (2...36), lowercase.
    public func toString(radix: Int = 10) -> String {
        precondition(2 <= radix && radix <= 36, "radix must be in 2...36")
        let capacity = mpz_sizeinbase(&storage.z, Int32(radix)) + 2 // sign + NUL
        var buf = [CChar](repeating: 0, count: capacity)
        buf.withUnsafeMutableBufferPointer { p in
            _ = mpz_get_str(p.baseAddress, Int32(radix), &storage.z)
        }
        return buf.withUnsafeBufferPointer { p in
            String(decoding: p.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) },
                   as: UTF8.self)
        }
    }
}

// MARK: - Equatable, Comparable, Hashable

extension GMPBigInt: Comparable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        mpz_cmp(&lhs.storage.z, &rhs.storage.z) == 0
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        mpz_cmp(&lhs.storage.z, &rhs.storage.z) < 0
    }
}

extension GMPBigInt: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(sign)
        for word in magnitudeWords { hasher.combine(word) }
    }
}

// MARK: - Integer literals

extension GMPBigInt: ExpressibleByIntegerLiteral {
    /// `StaticBigInt` makes literals of any size work: `let x: GMPBigInt = 10 ** 40` digits long.
    public init(integerLiteral value: StaticBigInt) {
        let wordCount = Swift.max(1, (value.bitWidth + 63) / 64)
        let words = (0 ..< wordCount).map { value[$0] }
        self.init(twosComplementWords: words, negative: value.signum() < 0)
    }
}

// MARK: - SignedInteger

extension GMPBigInt: SignedInteger {
    public typealias Magnitude = GMPBigInt
    public typealias Words = [UInt]
    public typealias Stride = Int

    public static var isSigned: Bool { true }

    public var magnitude: GMPBigInt {
        Self.unary(mpz_abs, self)
    }

    /// Two's-complement words, least significant first, minimally sign-extended.
    public var words: [UInt] {
        if sign >= 0 {
            var words = magnitudeWords
            if words.isEmpty { return [0] }
            if words.last!.leadingZeroBitCount == 0 { words.append(0) } // keep the sign bit clear
            return words
        }
        // -x == ~(x - 1): invert the words of (magnitude - 1), sign-extended
        var words = magnitudeMinusOne.magnitudeWords.map { ~$0 }
        if words.isEmpty { words = [UInt.max] } // self == -1
        if words.last!.leadingZeroBitCount != 0 { words.append(UInt.max) } // keep the sign bit set
        return words
    }

    /// The bit width of the minimal two's-complement representation, including the sign bit.
    public var bitWidth: Int {
        switch sign {
        case 0:
            return 1
        case 1:
            return mpz_sizeinbase(&storage.z, 2) + 1
        default:
            let m1 = magnitudeMinusOne
            return (m1.sign == 0 ? 0 : mpz_sizeinbase(&m1.storage.z, 2)) + 1
        }
    }

    public var trailingZeroBitCount: Int {
        guard sign != 0 else { return 1 } // == bitWidth of zero
        return Int(mpz_scan1(&storage.z, 0))
    }

    // Arithmetic
    public static func + (lhs: Self, rhs: Self) -> Self { binary(mpz_add, lhs, rhs) }
    public static func - (lhs: Self, rhs: Self) -> Self { binary(mpz_sub, lhs, rhs) }
    public static func * (lhs: Self, rhs: Self) -> Self { binary(mpz_mul, lhs, rhs) }
    /// Truncating division, like Swift's `/` (GMP's `tdiv` truncates toward zero).
    public static func / (lhs: Self, rhs: Self) -> Self {
        precondition(rhs.sign != 0, "Division by zero")
        return binary(mpz_tdiv_q, lhs, rhs)
    }
    /// Remainder with the sign of the dividend, like Swift's `%`.
    public static func % (lhs: Self, rhs: Self) -> Self {
        precondition(rhs.sign != 0, "Division by zero in remainder operation")
        return binary(mpz_tdiv_r, lhs, rhs)
    }

    public static func += (lhs: inout Self, rhs: Self) { lhs = lhs + rhs }
    public static func -= (lhs: inout Self, rhs: Self) { lhs = lhs - rhs }
    public static func *= (lhs: inout Self, rhs: Self) { lhs = lhs * rhs }
    public static func /= (lhs: inout Self, rhs: Self) { lhs = lhs / rhs }
    public static func %= (lhs: inout Self, rhs: Self) { lhs = lhs % rhs }

    public mutating func negate() {
        self = Self.unary(mpz_neg, self)
    }

    // Bitwise (GMP treats negatives as infinite two's complement, like JS BigInt)
    public static func & (lhs: Self, rhs: Self) -> Self { binary(mpz_and, lhs, rhs) }
    public static func | (lhs: Self, rhs: Self) -> Self { binary(mpz_ior, lhs, rhs) }
    public static func ^ (lhs: Self, rhs: Self) -> Self { binary(mpz_xor, lhs, rhs) }

    public static func &= (lhs: inout Self, rhs: Self) { lhs = lhs & rhs }
    public static func |= (lhs: inout Self, rhs: Self) { lhs = lhs | rhs }
    public static func ^= (lhs: inout Self, rhs: Self) { lhs = lhs ^ rhs }

    public static prefix func ~ (x: Self) -> Self {
        unary(mpz_com, x)
    }

    // Shifts: BinaryInteger's "smart shift" semantics — a negative count
    // reverses direction, and `>>` is arithmetic (mpz_fdiv_q_2exp floors).
    public static func << <RHS: BinaryInteger>(lhs: Self, rhs: RHS) -> Self {
        guard rhs >= 0 else {
            return shift(mpz_fdiv_q_2exp, lhs, UInt(clamping: rhs.magnitude))
        }
        guard let count = UInt(exactly: rhs) else {
            preconditionFailure("shift count \(rhs) is too large")
        }
        return shift(mpz_mul_2exp, lhs, count)
    }

    public static func >> <RHS: BinaryInteger>(lhs: Self, rhs: RHS) -> Self {
        guard rhs >= 0 else {
            guard let count = UInt(exactly: rhs.magnitude) else {
                preconditionFailure("shift count \(rhs) is too large")
            }
            return shift(mpz_mul_2exp, lhs, count)
        }
        // beyond any bitWidth just saturates to 0 or -1, so clamping is exact
        return shift(mpz_fdiv_q_2exp, lhs, UInt(clamping: rhs))
    }

    public static func <<= <RHS: BinaryInteger>(lhs: inout Self, rhs: RHS) { lhs = lhs << rhs }
    public static func >>= <RHS: BinaryInteger>(lhs: inout Self, rhs: RHS) { lhs = lhs >> rhs }

    // Strideable (Int strides; conversion traps on overflow like Int does)
    public func distance(to other: Self) -> Int { Int(other - self) }
    public func advanced(by n: Int) -> Self { self + Self(n) }
}

// MARK: - Exponentiation

extension GMPBigInt {
    /// `self` raised to `exponent` (which must be non-negative), via `mpz_pow_ui`.
    public func power(_ exponent: some BinaryInteger) -> Self {
        precondition(exponent >= 0, "exponent must be non-negative")
        guard let e = UInt(exactly: exponent) else {
            preconditionFailure("exponent \(exponent) is too large")
        }
        let s = Storage()
        mpz_pow_ui(&s.z, &storage.z, e)
        return Self(s)
    }

    /// Modular exponentiation: `self` raised to `exponent`, modulo `modulus`,
    /// via `mpz_powm` — only the modulus bounds the intermediates, so huge
    /// exponents stay cheap where `power(_:)` could not run at all.
    ///
    /// Semantics match swift-bignum's `power(_:mod:)`:
    /// * The result is the **least residue of matching sign**: in `0..<|m|` for
    ///   a positive modulus (so `GMPBigInt(-2).power(3, mod: 5)` is `2`, where
    ///   `GMPBigInt(-2).power(3) % 5` is `-3`), and in `(m, 0]` for a negative one.
    /// * A **negative `exponent`** raises the modular inverse of `self`, so
    ///   `x.power(-1, mod: m)` *is* that inverse.  It traps when `self` and
    ///   `modulus` are not coprime, there being no inverse to return.
    /// * A **zero `modulus`** traps.
    public func power(_ exponent: some BinaryInteger, mod modulus: Self) -> Self {
        precondition(modulus.sign != 0, "power(_:mod:) with a modulus of zero")
        let absModulus = modulus.magnitude
        var base = self
        var exp = Self(exponent)
        if exp < 0 {
            let inverse = Storage()
            guard mpz_invert(&inverse.z, &base.storage.z, &absModulus.storage.z) != 0 else {
                preconditionFailure("\(self) has no inverse modulo \(modulus)")
            }
            base = Self(inverse)
            exp.negate()
        }
        let s = Storage()
        mpz_powm(&s.z, &base.storage.z, &exp.storage.z, &absModulus.storage.z)
        var result = Self(s)
        if modulus.sign < 0 && result.sign != 0 { result -= absModulus }
        return result
    }
}

// MARK: - GCD and integer square root

extension GMPBigInt {
    /// The greatest common divisor of `self` and `other`, via `mpz_gcd`
    /// on the magnitudes — never negative, and zero only when both are zero.
    public func greatestCommonDivisor(with other: Self) -> Self {
        Self.binary(mpz_gcd, self, other)
    }

    /// The integer square root: the largest value whose square is at most `self`.
    /// Traps when `self` is negative, like swift-bignum's `squareRoot()`.
    public func squareRoot() -> Self {
        guard sign >= 0 else {
            preconditionFailure("square root of a negative GMPBigInt")
        }
        return Self.unary(mpz_sqrt, self)
    }
}

// MARK: - Primality

extension GMPBigInt {
    /// Modular exponentiation on non-negative operands with m > 0,
    /// straight through `mpz_powm`.
    private static func mpow(_ base: Self, _ exponent: Self, _ modulus: Self) -> Self {
        let s = Storage()
        mpz_powm(&s.z, &base.storage.z, &exponent.storage.z, &modulus.storage.z)
        return Self(s)
    }

    /// A single Miller-Rabin round: `true` when `base` fails to witness `self`
    /// composite.  A single base proves nothing on its own (2047 = 23 × 89
    /// passes base 2); use `isPrime` or `isProbablePrime` for an actual verdict.
    public func millerRabinTest(base: Self) -> Bool {
        let n = self
        if n < 2 { return false }
        if !n.isOdd { return n == 2 }
        var a = base % n
        if a < 0 { a += n }
        if a.sign == 0 { return true }
        let s = (n - 1).trailingZeroBitCount
        let d = (n - 1) >> s
        var x = Self.mpow(a, d, n)
        if x == 1 || x == n - 1 { return true }
        for _ in 1 ..< s {
            x = (x * x) % n
            if x == n - 1 { return true }
        }
        return false
    }

    /// The [Jacobi symbol] (`i` / `self`), which is 0 unless `self` is odd and
    /// positive.
    ///
    /// [Jacobi symbol]: https://en.wikipedia.org/wiki/Jacobi_symbol
    public func jacobiSymbol(_ i: Int) -> Int {
        guard sign > 0 && isOdd else { return 0 }
        let a = Self(i)
        return Int(mpz_jacobi(&a.storage.z, &storage.z))
    }

    /// `true` if `self` is a [Lucas probable prime] for the first Selfridge
    /// parameters — D from 5, -7, 9, -11, … the first with (D/self) == -1,
    /// then P = 1 and Q = (1 - D)/4.
    ///
    /// [Lucas probable prime]: https://en.wikipedia.org/wiki/Lucas_pseudoprime
    public var isLucasProbablePrime: Bool {
        let n = self
        if n < 2 { return false }
        if !n.isOdd { return n == 2 }
        // a perfect square has no D with (D/n) == -1
        if mpz_perfect_square_p(&n.storage.z) != 0 { return false }
        var d = 0
        for i in 2 ... 256 {
            let candidate = ((i & 1) == 0 ? 1 : -1) * (2 * i + 1)
            if n.jacobiSymbol(candidate) == -1 { d = candidate; break }
        }
        guard d != 0 else {
            preconditionFailure("no D with (D/\(n)) == -1")
        }
        let dd = Self(d)
        var q = (1 - dd) / 4
        var q2 = 2 * q
        var (u, v): (Self, Self) = (0, 2)    // U_0, V_0
        var (u2, v2): (Self, Self) = (1, 1)  // U_1, V_1 == P == 1
        // climb the bits of h = (n + 1)/2, doubling (u2, v2) each
        // step and folding it into (u, v) where the bit is set
        var h = (n + 1) / 2
        while 0 < h {
            u2 = (u2 * v2) % n
            v2 = (v2 * v2 - q2) % n
            if h.isOdd {
                let t = u
                // U_{m+k} = (U_m V_k + U_k V_m) / 2, halved modulo n
                u = u * v2 + u2 * v
                u += u.isOdd ? n : 0
                u /= 2
                u %= n
                // V_{m+k} = (V_m V_k + D U_m U_k) / 2, likewise
                v = v * v2 + u2 * t * dd
                v += v.isOdd ? n : 0
                v /= 2
                v %= n
            }
            q = (q * q) % n
            q2 = q << 1
            h >>= 1
        }
        // U_h == 0 is the pass (u is in (-n, n) here, so == 0 is it)
        return u.sign == 0
    }

    /// The [Lucas-Lehmer test], which settles a Mersenne number exactly.
    ///
    /// - returns: `true` if `self` is a Mersenne prime, `false` if it is a
    ///   composite Mersenne number, and `nil` if `self` is not 2^p - 1 at all.
    ///
    /// [Lucas-Lehmer test]: https://en.wikipedia.org/wiki/Lucas%E2%80%93Lehmer_primality_test
    public var isMersennePrime: Bool? {
        let n = self
        let next = n + 1
        if n < 3 || (next & n).sign != 0 { return nil }
        let p = next.trailingZeroBitCount
        if p == 2 { return true } // M2 == 3, below the recurrence
        // a composite p gives a composite Mp; p is tiny, so BPSW is exact
        if !Self(p).isProbablePrime { return false }
        // s -> s^2 - 2 (mod n), p - 2 times, from 4.  Reduction is by
        // folding: 2^p == 1 (mod 2^p - 1), so the high half of a
        // square just adds to the low half.
        var s: Self = 4
        for _ in 0 ..< (p - 2) {
            let square = s * s
            s = (square & n) + (square >> p)
            while n <= s { s -= n }
            s = 2 <= s ? s - 2 : s + n - 2
        }
        return s.sign == 0
    }

    /// `true` if `self` is prime according to the [Baillie-PSW] test:
    /// Miller-Rabin on base 2, then a Lucas probable-prime test.
    ///
    /// No composite is known to pass, and none below 2^64 exists — that range
    /// has been checked exhaustively — so this is exact for anything a `UInt64`
    /// could hold.  Above it, `true` means only that neither half found a
    /// witness, which is why `isPrime` withholds an answer there and this one
    /// is spelled "probable".
    ///
    /// [Baillie-PSW]: https://en.wikipedia.org/wiki/Baillie%E2%80%93PSW_primality_test
    public var isProbablePrime: Bool {
        let n = self
        if n < 2 { return false }
        if !n.isOdd { return n == 2 }
        if n % 3 == 0 { return n == 3 }
        if n % 5 == 0 { return n == 5 }
        if n % 7 == 0 { return n == 7 }
        return millerRabinTest(base: 2) && isLucasProbablePrime
    }

    internal enum Primality {
        case composite, prime, probablyPrime
    }

    // A014233: below entry i, passing prime bases 0...i proves primality
    internal static let mrBases: [Self] = [2, 3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41]
    internal static let mrTable: [Self] = [
        2047, 1373653, 25326001, 3215031751, 2152302898747,
        3474749660383, 341550071728321, 341550071728321,
        3825123056546413051, 3825123056546413051, 3825123056546413051,
        318665857834031151167461, 3317044064679887385961981,
    ]
    private static let u64max: Self = 18446744073709551615

    internal var primality: Primality {
        let n = self
        if n < 2 { return .composite }
        if !n.isOdd { return n == 2 ? .prime : .composite }
        if n % 3 == 0 { return n == 3 ? .prime : .composite }
        if n % 5 == 0 { return n == 5 ? .prime : .composite }
        if n % 7 == 0 { return n == 7 ? .prime : .composite }
        // BPSW is exhaustively verified below 2^64
        if n <= Self.u64max { return isProbablePrime ? .prime : .composite }
        // Lucas-Lehmer settles a Mersenne number outright
        if let mersenne = isMersennePrime { return mersenne ? .prime : .composite }
        // the A014233 ladder proves anything below its last entry
        if n < Self.mrTable.last! {
            for (base, bound) in zip(Self.mrBases, Self.mrTable) {
                if !millerRabinTest(base: base) { return .composite }
                if n < bound { return .prime }
            }
        }
        return isProbablePrime ? .probablyPrime : .composite
    }

    /// Whether `self` is prime, and whether that answer is certain.
    ///
    /// `surely` is always `true` for a composite: a witness is a proof.  For a
    /// prime it is `true` below 2^64 (BPSW is exhaustively verified there),
    /// for any Mersenne number (Lucas-Lehmer settles those outright), and
    /// below 3317044064679887385961981, the last entry of [A014233] (thirteen
    /// Miller-Rabin bases prove that range).  Past all of those a `true` rests
    /// on BPSW, which no composite is known to pass but none is proven not to.
    ///
    /// [A014233]: https://oeis.org/A014233
    public var isSurelyPrime: (Bool, surely: Bool) {
        switch primality {
        case .composite:     return (false, true)
        case .prime:         return (true, true)
        case .probablyPrime: return (true, false)
        }
    }

    /// Whether `self` is prime, or `nil` when no test here can settle it.
    ///
    /// Follows swift-bignum's contract: `false` is always a proof (a witness
    /// to compositeness is a proof), and `true` is a proof too — below 2^64,
    /// below [A014233]'s last entry with thirteen Miller-Rabin bases, or for
    /// a Mersenne number through Lucas-Lehmer.  Past all of those, BPSW still
    /// has an opinion and this declines to launder it into a fact;
    /// `isProbablePrime` is that opinion and `isSurelyPrime` gives both
    /// halves at once.  `nil` is not "no": treat it deliberately, with
    /// `== true`, rather than by reaching for `??`.
    ///
    /// **Never `nil` at or below `UInt64.max`**, so if your values fit a
    /// `UInt64` — or are negative, or anything else `Int`-sized — the force
    /// unwrap is safe.
    ///
    /// [A014233]: https://oeis.org/A014233
    public var isPrime: Bool? {
        let (prime, surely) = isSurelyPrime
        return surely ? prime : nil
    }

    /// The first prime greater than `self`; anything below 2 gets 2.
    ///
    /// The walk is on the probable test, not `isPrime`: past the deterministic
    /// range `isPrime` is `nil`, and a walk that read that as "composite"
    /// would step over every candidate and never return.  So above the
    /// [A014233] bound this is the next *probable* prime.
    ///
    /// [A014233]: https://oeis.org/A014233
    public var nextPrime: Self {
        if self < 2 { return 2 }
        var u = self + (isOdd ? 2 : 1)
        while u.primality == .composite { u += 2 }
        return u
    }

    /// The last prime less than `self`, or `nil` when there is none — which is
    /// what 2 and everything below it gets.  Probable above the A014233 bound,
    /// as `nextPrime` is.
    public var prevPrime: Self? {
        if self <= 2 { return nil }
        if self == 3 { return 2 }
        var u = self - (isOdd ? 2 : 1)
        while u.primality == .composite { u -= 2 }
        return u
    }

    /// An endless sequence of the primes, in order.  `GMPBigInt.primes` builds one.
    public struct PrimeSequence: Sequence, IteratorProtocol {
        private var current: GMPBigInt? = nil
        public init() {}
        public mutating func next() -> GMPBigInt? {
            let value = current.map { $0.nextPrime } ?? 2
            current = value
            return value
        }
    }

    /// The primes from 2 upward, lazily and without end.
    ///
    ///     Array(GMPBigInt.primes.prefix(5))    // [2, 3, 5, 7, 11]
    public static var primes: PrimeSequence { PrimeSequence() }
}

// MARK: - Codable

extension GMPBigInt: Codable {
    /// Encoded as a decimal string, since most JSON decoders cannot handle huge numbers.
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let string = try container.decode(String.self)
        guard let value = GMPBigInt(string) else {
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "invalid GMPBigInt string: \(string)"
            )
        }
        self = value
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }
}

// MARK: - Sendable

// The underlying mpz is written once, before the value is ever shared, and
// never mutated afterward; GMP is safe for concurrent reads of distinct or
// shared operands.
extension GMPBigInt: @unchecked Sendable {}
