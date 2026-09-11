package com.piyushbaniya.vorafind.ocr

/**
 * Downsampling math for OCR decoding.
 *
 * BitmapFactory's `inSampleSize` only accepts powers of two, and the Dart side
 * caps the decoded image so recognition stays fast and memory-sane on large
 * camera photos. Pick the smallest power-of-two sample that guarantees both
 * decoded dimensions are `<= maxDimension`.
 *
 * Pure: no Android dependencies, fully unit-testable on the JVM.
 */
object ImageSampler {

    const val DEFAULT_MAX_DIMENSION = 2048

    /**
     * @return a power-of-two sample size >= 1 such that
     *         `ceil(sourceWidth / sample) <= maxDimension` and
     *         `ceil(sourceHeight / sample) <= maxDimension`.
     *         Invalid inputs (non-positive dimension or max) yield `1`.
     */
    fun inSampleSizeFor(
        sourceWidth: Int,
        sourceHeight: Int,
        maxDimension: Int = DEFAULT_MAX_DIMENSION,
    ): Int {
        if (sourceWidth <= 0 || sourceHeight <= 0 || maxDimension <= 0) return 1
        val target = maxOf(
            ceilDiv(sourceWidth, maxDimension),
            ceilDiv(sourceHeight, maxDimension),
        )
        var sampleSize = 1
        while (sampleSize < target) sampleSize *= 2
        return sampleSize
    }

    private fun ceilDiv(a: Int, b: Int): Int = (a + b - 1) / b
}