package audio

import (
	"math"
	"math/cmplx"
)

// hannWindow precomputes Hann window coefficients for a given size n.
func hannWindow(n int) []float64 {
	w := make([]float64, n)
	for i := range w {
		w[i] = 0.5 * (1.0 - math.Cos(2.0*math.Pi*float64(i)/float64(n-1)))
	}
	return w
}

// fft computes the radix-2 Cooley-Tukey FFT in-place (iterative).
// Input length must be a power of 2.
func fft(x []complex128) []complex128 {
	n := len(x)
	if n <= 1 {
		return x
	}

	// Bit-reversal permutation.
	bits := 0
	for v := n; v > 1; v >>= 1 {
		bits++
	}
	for i := range n {
		j := bitReverse(i, bits)
		if i < j {
			x[i], x[j] = x[j], x[i]
		}
	}

	// Butterfly stages.
	for size := 2; size <= n; size <<= 1 {
		half := size / 2
		wn := cmplx.Exp(complex(0, -2.0*math.Pi/float64(size)))
		for start := 0; start < n; start += size {
			w := complex(1, 0)
			for k := range half {
				even := x[start+k]
				odd := w * x[start+k+half]
				x[start+k] = even + odd
				x[start+k+half] = even - odd
				w *= wn
			}
		}
	}
	return x
}

// bitReverse reverses the lower `bits` bits of v.
func bitReverse(v, bits int) int {
	r := 0
	for range bits {
		r = (r << 1) | (v & 1)
		v >>= 1
	}
	return r
}

// binRange defines a range of FFT bins (inclusive) that map to one output band.
type binRange struct {
	lo, hi int
}

// Analyzer performs FFT-based spectrum analysis, grouping FFT bins into
// log-spaced frequency bands suitable for visualization.
type Analyzer struct {
	window     []float64
	fftSize    int
	bands      int
	sampleRate float64
	binRanges  []binRange
}

// NewAnalyzer creates an Analyzer with precomputed Hann window and
// logarithmic bin groupings.
//
// fftSize must be a power of 2 (1024 typical).
// bands is the number of output frequency bands (16 typical).
// sampleRate is the audio sample rate in Hz (44100 typical).
func NewAnalyzer(fftSize, bands int, sampleRate float64) *Analyzer {
	a := &Analyzer{
		window:     hannWindow(fftSize),
		fftSize:    fftSize,
		bands:      bands,
		sampleRate: sampleRate,
		binRanges:  make([]binRange, bands),
	}

	// Precompute log-spaced bin groupings across bins 1..fftSize/2.
	// Use math.Pow to produce log-spaced boundaries so that bass bands
	// cover fewer bins and treble bands cover more, matching human perception.
	half := fftSize / 2
	prevBin := 1
	for b := range bands {
		boundary := min(max(int(math.Pow(float64(half), float64(b+1)/float64(bands))), prevBin), half)
		a.binRanges[b] = binRange{lo: prevBin, hi: boundary}
		prevBin = boundary + 1
	}

	return a
}

// Process takes raw PCM float32 samples and returns bands values normalized
// to 0.0-1.0. Input length should equal fftSize; it is padded or truncated
// as needed.
func (a *Analyzer) Process(samples []float32) []float64 {
	// Build complex input with Hann window applied, pad/truncate to fftSize.
	buf := make([]complex128, a.fftSize)
	for i := range a.fftSize {
		var s float64
		if i < len(samples) {
			s = float64(samples[i])
		}
		buf[i] = complex(s*a.window[i], 0)
	}

	// Compute FFT.
	fft(buf)

	// Take magnitudes of bins 1..N/2 (skip DC bin 0).
	half := a.fftSize / 2
	mags := make([]float64, half+1)
	for i := 1; i <= half; i++ {
		mags[i] = cmplx.Abs(buf[i])
	}

	// Group into bands: take max magnitude in each bin range.
	result := make([]float64, a.bands)
	for b := 0; b < a.bands; b++ {
		br := a.binRanges[b]
		maxMag := 0.0
		for i := br.lo; i <= br.hi && i <= half; i++ {
			if mags[i] > maxMag {
				maxMag = mags[i]
			}
		}

		// Convert to dB with floor of -80 dB.
		var dB float64
		if maxMag <= 0 {
			dB = -80.0
		} else {
			dB = 20.0 * math.Log10(maxMag)
			if dB < -80.0 {
				dB = -80.0
			}
		}

		// Normalize to 0.0-1.0: map [-80, 0] dB to [0.0, 1.0].
		norm := (dB + 80.0) / 80.0
		if norm < 0.0 {
			norm = 0.0
		}
		if norm > 1.0 {
			norm = 1.0
		}
		result[b] = norm
	}

	return result
}
