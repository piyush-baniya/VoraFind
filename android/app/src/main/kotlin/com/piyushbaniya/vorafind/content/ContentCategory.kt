package com.piyushbaniya.vorafind.content

/**
 * Content categories VoraFind can eventually index.
 *
 * Wire values are part of the Dart/Kotlin contract; do not rename without
 * updating the Dart side (lib/core/platform/content_access_models.dart).
 */
enum class ContentCategory(val wire: String) {
    IMAGES("images"),
    VIDEOS("videos"),
    AUDIO("audio"),
    DOCUMENTS("documents");

    companion object {
        fun fromWire(value: String): ContentCategory =
            entries.firstOrNull { it.wire == value }
                ?: throw IllegalArgumentException("Unknown content category: $value")
    }
}

/** Wire payload describing one category's access on the method channel. */
fun ContentCategory.accessMap(state: ContentAccessState): Map<String, Any?> {
    val flags = CapabilityMapper.accessFlags(state)
    return mapOf(
        "category" to wire,
        "state" to state.wire,
        "canQuery" to flags.canQuery,
        "canReadAll" to flags.canReadAll,
        "canReadSelected" to flags.canReadSelected,
    )
}