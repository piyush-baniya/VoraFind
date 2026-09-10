package com.piyushbaniya.vorafind.content

/**
 * Builds the versioned capability payload and per-category access flags.
 *
 * Pure so the contract can be unit-tested on the JVM. Flags are derived from
 * [ContentAccessState] so a partial grant can never advertise full-library
 * access (architecture §20).
 */
object CapabilityMapper {

    const val CONTRACT_VERSION: Int = 1

    data class AccessFlags(
        val canQuery: Boolean,
        val canReadAll: Boolean,
        val canReadSelected: Boolean,
    )

    fun accessFlags(state: ContentAccessState): AccessFlags = when (state) {
        ContentAccessState.FULL_ACCESS ->
            AccessFlags(canQuery = true, canReadAll = true, canReadSelected = true)
        ContentAccessState.PARTIAL_ACCESS ->
            AccessFlags(canQuery = true, canReadAll = false, canReadSelected = true)
        ContentAccessState.NOT_REQUIRED ->
            AccessFlags(canQuery = true, canReadAll = false, canReadSelected = false)
        ContentAccessState.NO_ACCESS,
        ContentAccessState.DENIED,
        ContentAccessState.PERMANENTLY_DENIED,
        -> AccessFlags(canQuery = false, canReadAll = false, canReadSelected = false)
    }

    fun capabilities(
        apiLevel: Int,
        states: Map<ContentCategory, ContentAccessState>,
        externalVolumes: List<String>,
    ): Map<String, Any?> = mapOf(
        "contractVersion" to CONTRACT_VERSION,
        "platform" to "android",
        "apiLevel" to apiLevel,
        // SAF document trees are available from API 21; minSdk is 24.
        "safCapable" to true,
        "mediaStoreGenerationSupported" to (apiLevel >= 30),
        "partialMediaAccessSupported" to (apiLevel >= 34),
        "externalVolumes" to externalVolumes,
        "categories" to ContentCategory.entries.map { category ->
            category.accessMap(states[category] ?: ContentAccessState.NO_ACCESS)
        },
    )
}