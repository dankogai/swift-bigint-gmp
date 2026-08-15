# swift-bigint-gmp

BigInt Implementation via the [GNU Multiple Precision Arithmetic Library]

`GMPBigInt` wraps GMP's `mpz_t` and delegates all arithmetic to GMP —
the fastest bignum library there is — behind the exact same Swift API as
[dankogai/swift-bignum]'s `BigInt` and
[dankogai/swift-bigint-javascriptcore]'s `JSBigInt`.

[GNU Multiple Precision Arithmetic Library]: https://gmplib.org
[dankogai/swift-bignum]: https://github.com/dankogai/swift-bignum
[dankogai/swift-bigint-javascriptcore]: https://github.com/dankogai/swift-bigint-javascriptcore

## Synopsis

```swift
import GMPBigInt

// Integer literals of any size, thanks to StaticBigInt
let n: GMPBigInt = 123456789012345678901234567890123456789012345678901234567890

// A full SignedInteger: use it like any Swift integer
let fact100 = (1...100).map { GMPBigInt($0) }.reduce(1, *)
GMPBigInt(2).power(128)              // 340282366920938463463374607431768211456
(GMPBigInt(1) << 100) >> 100         // 1
GMPBigInt("deadbeef", radix: 16)!    // 3735928559
fact100.toString(radix: 36)         // "1cnfrwcnvxbzzicfd6…"
Int(GMPBigInt(42))                   // 42 — stdlib conversions just work
Double(GMPBigInt(1) << 100)          // 1.2676506002282294e+30
```

## Prerequisite: GMP

GMP is found through `pkg-config`:

```sh
sudo port install gmp          # MacPorts
brew install gmp               # Homebrew
sudo apt-get install libgmp-dev  # Debian/Ubuntu
```

Homebrew and apt installations are found automatically.  MacPorts keeps
its `gmp.pc` off SwiftPM's search path, so point `PKG_CONFIG_PATH` at it:

```sh
PKG_CONFIG_PATH=/opt/local/lib/pkgconfig swift test
```

## Usage

Add to your `Package.swift`:

```swift
.package(url: "https://github.com/dankogai/swift-bigint-gmp.git", branch: "main")
```

and `import GMPBigInt`.

## Features

- `GMPBigInt` conforms to `SignedInteger` (hence `BinaryInteger`, `Numeric`,
  `Comparable`, `Hashable`, `Strideable`…), so it works with generic
  integer algorithms out of the box.
- Integer literals use `StaticBigInt` — no precision loss, no strings needed.
- Swift semantics throughout: `/` truncates toward zero, `%` takes the
  dividend's sign, `>>` is an arithmetic (smart) shift, division by zero traps.
- String conversion to and from any radix in `2...36`.
- Exact conversions to and from `BinaryInteger` and `BinaryFloatingPoint`
  types, including two's-complement `words` for stdlib interop.
- `power(_:)` via `mpz_pow_ui`, and modular exponentiation
  `power(_:mod:)` via `mpz_powm` with swift-bignum-compatible semantics
  (least non-negative residue; a negative exponent takes the modular
  inverse).
- `greatestCommonDivisor(with:)` and `squareRoot()` (integer square
  root, floor), named and behaving like their swift-bignum and
  attaswift/BigInt counterparts.
- The whole primality kit, ported from swift-bignum with identical
  verdicts: `isPrime` is tri-state — `false` and `true` are proofs
  (below 2⁶⁴ via exhaustively-verified [Baillie-PSW], below
  [A014233]'s last entry ≈3.3 × 10²⁴ via thirteen Miller-Rabin bases,
  or for any Mersenne number via Lucas-Lehmer), `nil` means "probably
  prime, unproven" with `isProbablePrime` (BPSW) holding that opinion
  and `isSurelyPrime` giving both halves at once.  The building blocks
  are public too: `millerRabinTest(base:)`, `isLucasProbablePrime`,
  `isMersennePrime`, and `jacobiSymbol(_:)`.  `nextPrime`/`prevPrime`
  walk to the neighboring primes (on the probable test, so they
  terminate at any size), and `GMPBigInt.primes` is the endless lazy
  sequence of them: `Array(GMPBigInt.primes.prefix(5))` is `[2, 3, 5, 7, 11]`.

[Baillie-PSW]: https://en.wikipedia.org/wiki/Baillie%E2%80%93PSW_primality_test

[A014233]: https://oeis.org/A014233
- `Codable` (encoded as a decimal string).
- Thread-safe: every value's `mpz_t` is written once and never mutated,
  and GMP is safe for concurrent reads.
- Works on macOS *and* Linux — anywhere GMP does.

## SwiftBigNumExample

[SwiftBigNumExample](SwiftBigNumExample/) shows `GMPBigInt` riding
[dankogai/swift-bignum]'s generic machinery: `Rational<GMPBigInt>` and
`BigFloatOf<GMPBigInt>` — `BigRat` and `BigFloat` with GMP digits — via
two retroactive conformances.

## Prerequisite

Swift 5.9 or better, macOS 14 or later, GMP.

## License

MIT. See [LICENSE](LICENSE).
