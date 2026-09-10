package com.piyushbaniya.vorafind.discovery

import java.security.MessageDigest

/**
 * Secondary identity ("re-link signature") from architecture §8.1.
 *
 * MediaStore can rebuild and renumber `_ID`s; this SHA-256 of the metadata tuple
 * `(RELATIVE_PATH | DISPLAY_NAME | SIZE | DATE_MODIFIED)` lets a later index layer
 * remap an old stable key onto a new `_ID` exactly once. It is metadata-only — no
 * file bytes are ever read or hashed.
 *
 * Null when [relativePath] is unavailable (API < 29), because the signature loses
 * its stabilizing power without the path component.
 */
object RelinkSignature {

    /** Returns null when the signature cannot be computed meaningfully. */
    fun compute(
        relativePath: String?,
        displayName: String?,
        sizeBytes: Long?,
        dateModified: Long?,
    ): String? {
        if (relativePath.isNullOrBlank()) return null
        val raw = listOf(
            relativePath,
            displayName.orEmpty(),
            sizeBytes?.toString().orEmpty(),
            dateModified?.toString().orEmpty(),
        ).joinToString(separator = "|")
        return sha256(raw)
    }

    private fun sha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray(Charsets.UTF_8))
        val hex = StringBuilder(digest.size * 2)
        for (byte in digest) {
            hex.append("%02x".format(byte))
        }
        return hex.toString()
    }
}