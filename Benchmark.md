# Benchmark: GMPBigInt vs. JSCBigInt vs. attaswift/BigInt vs. swift-bignum

How does delegating to GNU MP compare to JavaScriptCore's `BigInt` and
to the pure-Swift bignums?  Short answer: **GMP wins everything that is
actually about arithmetic** — usually by one to two orders of magnitude —
and concedes only the many-tiny-ops case, where attaswift's inline
small-integer storage beats everyone's heap allocations.

## Environment

| | |
|:--|:--|
| Machine | Apple M1 |
| OS | macOS 26.6.1 |
| Swift | 6.3.3 (release build, `-c release`) |
| GMP | 6.3.0 (MacPorts) |
| [swift-bigint-javascriptcore] | main @ 9a87dc80 |
| [attaswift/BigInt] | 5.7.0 |
| [dankogai/swift-bignum] | 6.3.2 |
| Date | 2026-08-15 |

[swift-bigint-javascriptcore]: https://github.com/dankogai/swift-bigint-javascriptcore
[attaswift/BigInt]: https://github.com/attaswift/BigInt
[dankogai/swift-bignum]: https://github.com/dankogai/swift-bignum

## Method

The harness lives in [Benchmarks/](Benchmarks/) — a standalone package
depending on all four libraries, the same harness as
swift-bigint-javascriptcore's so the numbers are directly comparable.
Each case runs the identical algorithm on identical inputs on every
side, takes the **best of 3** runs, and all libraries' outputs are
checked for agreement before timing. Results are fed to a
`@inline(never)` sink to prevent dead-code elimination.
(attaswift/BigInt and swift-bignum both name their type `BigInt`, so the
harness imports each in its own file and races them under typealiases.)

```sh
cd Benchmarks && swift run -c release bench
# with MacPorts: PKG_CONFIG_PATH=/opt/local/lib/pkgconfig swift run -c release bench
```

## Results

Bold marks the fastest per row; parenthesized ratios are relative to it.

| Benchmark | GMPBigInt | JSCBigInt | attaswift/BigInt | swift-bignum |
|:--|--:|--:|--:|--:|
| sum 1...100_000 (100k small ops) | 25.15 ms (1.6×) | 320.46 ms (20.7×) | **15.45 ms** | 25.67 ms (1.7×) |
| fib(10_000) (2,090 digits) | **1.16 ms** | 11.03 ms (9.5×) | 4.36 ms (3.8×) | 2.75 ms (2.4×) |
| factorial(1_000) (2,568 digits) | **300.79 µs** | 2.74 ms (9.1×) | 389.50 µs (1.3×) | 355.29 µs (1.2×) |
| 2.power(100_000) (30,103 digits) | **0.54 µs** | 8.17 µs (15.1×) | 29.29 µs (54.0×) | 188.92 µs (348.6×) |
| 10k-digit × 10k-digit, 100 times | **2.92 ms** | 24.06 ms (8.2×) | 183.19 ms (62.8×) | 62.78 ms (21.5×) |
| 20k-digit ÷ 10k-digit, 100 times | **8.05 ms** | 66.42 ms (8.3×) | 326.55 ms (40.6×) | 172.97 ms (21.5×) |
| 2060-bit modPow (power(_:mod:)) | **1.83 ms** | 16.78 ms (9.2×) | 76.81 ms (41.9×) | 56.49 ms (30.8×) |
| gcd of two 1,000-digit numbers, 10 times | **122.12 µs** | 3.41 ms (27.9×) | 6.00 ms (49.1×) | 3.73 ms (30.6×) |
| isqrt of 20k-digit number, 10 times | **525.08 µs** | 107.02 ms (203.8×) | 520.04 ms (990.4×) | 272.68 ms (519.3×) |
| toString(2^100_000), decimal | **449.62 µs** | 19.65 ms (43.7×) | 26.10 ms (58.0×) | 19.25 ms (42.8×) |
| parse 10,000 decimal digits, 100 times | **5.62 ms** | 60.33 ms (10.7×) | 93.69 ms (16.7×) | 31.96 ms (5.7×) |

## Analysis

**GMPBigInt's overhead is a heap allocation; its advantage is GMP.**
Every operation allocates a fresh `mpz_t` (values are immutable), which
costs on the order of 100 ns — cheap enough that GMPBigInt loses only
where there is nothing *but* overhead:

- **sum 1...100_000** is the one loss: 100k additions of machine-word
  numbers is 200k wrapped calls with near-zero arithmetic in them.
  attaswift stores small values inline with no allocation at all and
  wins; GMPBigInt effectively ties swift-bignum at 1.6×. Compare
  JSCBigInt's 20.7× — a JS bridge crossing costs ~2 µs where a GMP call
  costs ~0.1 µs, so the wrapper tax is 20× smaller here.
- **fib(10_000)** and **factorial(1_000)** were transitional cases for
  JSCBigInt (it lost both); GMPBigInt already wins them. Once operands
  reach even a few hundred digits, GMP's limb arithmetic pays for the
  allocations.
- **Multiplication and division of 10k+-digit numbers** are pure
  arithmetic: GMPBigInt beats JSCBigInt about **8×** and the pure-Swift
  libraries **20–60×**, courtesy of GMP's asymptotically better
  algorithms (Toom, FFT ranges) and hand-tuned assembly limb loops.
- **RSA-sized modPow** runs the whole square-and-multiply ladder inside
  one `mpz_powm` call: **9× over JSCBigInt**, 31–42× over pure Swift.
- **gcd** (Lehmer/binary in GMP vs. Euclid or binary loops elsewhere)
  and **isqrt** (`mpz_sqrt`'s dedicated Karatsuba-square-root vs.
  Newton-by-division) are the bloodbaths: 28–49× on gcd, and **200–1000×
  on isqrt** — GMP takes half a millisecond where the others take a
  tenth to half a second.
- **Radix-10 conversion, both directions,** uses GMP's subquadratic
  divide-and-conquer: 43× over the best pure-Swift printer, 5.7× over
  the best parser.
- **2.power(100_000)** is a curiosity on every backend: GMP notices the
  power of two and effectively shifts, in half a microsecond.

The JSCBigInt column doubles as a consistency check: measured on the
same machine by this harness, it reproduces the numbers in
swift-bigint-javascriptcore's own [Benchmark.md] — and shows the two
wrappers' overheads differ by an order of magnitude while both delegate
to optimized C/C++ cores.

[Benchmark.md]: https://github.com/dankogai/swift-bigint-javascriptcore/blob/main/Benchmark.md

## Takeaway

JSCBigInt's benchmark concluded "the winner depends entirely on operand
size."  With GMP the answer collapses: **GMPBigInt is the fastest at
everything except trivially small, trivially frequent operations**, and
even there it holds within 1.6× of the best pure-Swift bignum.  If your
platform has GMP, this is the backend to beat; the others' remaining
selling point is having no C dependency at all.
