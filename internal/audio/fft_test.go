package audio

import (
	"math"
	"math/cmplx"
	"testing"
)

func TestHannWindow(t *testing.T) {
	const n = 64
	w := hannWindow(n)

	if len(w) != n {
		t.Fatalf("expected length %d, got %d", n, len(w))
	}

	// Endpoints should be near zero.
	if w[0] > 1e-10 {
		t.Errorf("w[0] = %g, expected near 0", w[0])
	}
	if w[n-1] > 1e-10 {
		t.Errorf("w[n-1] = %g, expected near 0", w[n-1])
	}

	// Middle should be near 1.
	mid := w[n/2]
	if mid < 0.99 {
		t.Errorf("w[n/2] = %g, expected near 1.0", mid)
	}

	// Symmetry: w[i] == w[n-1-i].
	for i := range n / 2 {
		if math.Abs(w[i]-w[n-1-i]) > 1e-12 {
			t.Errorf("asymmetry at i=%d: w[%d]=%g != w[%d]=%g", i, i, w[i], n-1-i, w[n-1-i])
		}
	}
}

func TestFFTSineWave(t *testing.T) {
	const (
		sampleRate = 44100.0
		fftSize    = 1024
		freq       = 440.0
	)

	// Generate a 440Hz sine wave.
	x := make([]complex128, fftSize)
	for i := range fftSize {
		sample := math.Sin(2.0 * math.Pi * freq * float64(i) / sampleRate)
		x[i] = complex(sample, 0)
	}

	result := fft(x)

	// Expected bin: freq * fftSize / sampleRate ≈ 10.2
	expectedBin := int(math.Round(freq * fftSize / sampleRate))

	// Find bin with maximum magnitude in the lower half.
	maxMag := 0.0
	maxBin := 0
	for i := 1; i <= fftSize/2; i++ {
		mag := cmplx.Abs(result[i])
		if mag > maxMag {
			maxMag = mag
			maxBin = i
		}
	}

	if maxBin != expectedBin {
		t.Errorf("expected peak at bin %d (440Hz), got bin %d", expectedBin, maxBin)
	}

	// The peak should be significantly larger than noise floor.
	// Check a bin far from the peak.
	noiseBin := fftSize / 4 // well away from bin 10
	noiseMag := cmplx.Abs(result[noiseBin])
	if noiseMag > maxMag*0.01 {
		t.Errorf("noise bin %d magnitude %g is too high relative to peak %g",
			noiseBin, noiseMag, maxMag)
	}
}

func TestAnalyzerSineWave(t *testing.T) {
	const (
		sampleRate = 44100.0
		fftSize    = 1024
		bands      = 16
		freq       = 440.0
	)

	a := NewAnalyzer(fftSize, bands, sampleRate)

	// Generate a 440Hz sine wave as float32.
	samples := make([]float32, fftSize)
	for i := range samples {
		samples[i] = float32(math.Sin(2.0 * math.Pi * freq * float64(i) / sampleRate))
	}

	result := a.Process(samples)

	if len(result) != bands {
		t.Fatalf("expected %d bands, got %d", bands, len(result))
	}

	// Find the band with the highest value.
	maxVal := 0.0
	maxBand := 0
	for i, v := range result {
		if v > maxVal {
			maxVal = v
			maxBand = i
		}
	}

	// 440Hz should land in one of the lower bands (bass/low-mid).
	// The exact band depends on log-spaced grouping, but it should be
	// significantly above zero.
	if maxVal < 0.5 {
		t.Errorf("peak band %d value %g is too low for a full-amplitude sine wave", maxBand, maxVal)
	}

	t.Logf("440Hz sine: peak band=%d value=%.3f", maxBand, maxVal)

	// All other bands should be lower than the peak band.
	for i, v := range result {
		if i != maxBand && v > maxVal {
			t.Errorf("band %d (%g) exceeds peak band %d (%g)", i, v, maxBand, maxVal)
		}
	}
}

func TestAnalyzerSilence(t *testing.T) {
	const (
		sampleRate = 44100.0
		fftSize    = 1024
		bands      = 16
	)

	a := NewAnalyzer(fftSize, bands, sampleRate)

	// All-zero input.
	samples := make([]float32, fftSize)
	result := a.Process(samples)

	if len(result) != bands {
		t.Fatalf("expected %d bands, got %d", bands, len(result))
	}

	for i, v := range result {
		if v > 0.001 {
			t.Errorf("band %d = %g, expected ~0 for silence", i, v)
		}
	}
}

func TestAnalyzerBandCount(t *testing.T) {
	testCases := []struct {
		name    string
		fftSize int
		bands   int
	}{
		{"16 bands", 1024, 16},
		{"8 bands", 1024, 8},
		{"32 bands", 2048, 32},
	}

	for _, tc := range testCases {
		t.Run(tc.name, func(t *testing.T) {
			a := NewAnalyzer(tc.fftSize, tc.bands, 44100)

			// Random-ish input.
			samples := make([]float32, tc.fftSize)
			for i := range samples {
				samples[i] = float32(math.Sin(float64(i) * 0.1))
			}

			result := a.Process(samples)

			if len(result) != tc.bands {
				t.Fatalf("expected %d bands, got %d", tc.bands, len(result))
			}

			for i, v := range result {
				if v < 0.0 || v > 1.0 {
					t.Errorf("band %d = %g, out of [0, 1] range", i, v)
				}
			}
		})
	}
}
