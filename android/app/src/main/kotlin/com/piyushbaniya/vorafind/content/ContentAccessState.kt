package com.piyushbaniya.vorafind.content

/**
 * How VoraFind can currently access a content category.
 *
 * Wire values are part of the Dart/Kotlin contract; do not rename without
 * updating the Dart side (lib/core/platform/content_access_models.dart).
 *
 * [PARTIAL_ACCESS] must never be treated as full-library access: whole-library
 * deletion reconciliation is only safe under [FULL_ACCESS] (architecture §20).
 */
enum class ContentAccessState(val wire: String) {
    NOT_REQUIRED("notRequired"),
    NO_ACCESS("noAccess"),
    DENIED("denied"),
    PERMANENTLY_DENIED("permanentlyDenied"),
    FULL_ACCESS("fullAccess"),
    PARTIAL_ACCESS("partialAccess");

    companion object {
        fun fromWire(value: String): ContentAccessState =
            entries.firstOrNull { it.wire == value }
                ?: throw IllegalArgumentException("Unknown content access state: $value")
    }
}

/**
 * Pure mapping from Android permission facts to our domain [ContentAccessState].
 *
 * Deliberately free of Android calls so the model can be unit-tested on the JVM.
 * `canAskAgain` mirrors [android.app.Activity.shouldShowRequestPermissionRationale].
 */
object AccessStateMapper {

    /** Status query: no request dialog has necessarily been shown yet. */
    fun fromStatusQuery(hasAccess: Boolean, canAskAgain: Boolean): ContentAccessState =
        if (hasAccess) {
            ContentAccessState.FULL_ACCESS
        } else if (canAskAgain) {
            ContentAccessState.DENIED
        } else {
            ContentAccessState.NO_ACCESS
        }

    /** After a request dialog was shown: a "no" with no retry path is permanent. */
    fun fromRequestResult(hasAccess: Boolean, canAskAgain: Boolean): ContentAccessState =
        if (hasAccess) {
            ContentAccessState.FULL_ACCESS
        } else if (canAskAgain) {
            ContentAccessState.DENIED
        } else {
            ContentAccessState.PERMANENTLY_DENIED
        }

    /** Visual media (images/videos) status including Android 14+ partial grants. */
    fun visualStatus(
        isFullGranted: Boolean,
        isSelectedGranted: Boolean,
        canAskAgain: Boolean,
    ): ContentAccessState =
        if (isFullGranted) {
            ContentAccessState.FULL_ACCESS
        } else if (isSelectedGranted) {
            ContentAccessState.PARTIAL_ACCESS
        } else {
            fromStatusQuery(false, canAskAgain)
        }

    /** Visual media state after a permission request dialog was shown. */
    fun visualRequestResult(
        isFullGranted: Boolean,
        isSelectedGranted: Boolean,
        canAskAgain: Boolean,
    ): ContentAccessState =
        if (isFullGranted) {
            ContentAccessState.FULL_ACCESS
        } else if (isSelectedGranted) {
            ContentAccessState.PARTIAL_ACCESS
        } else {
            fromRequestResult(false, canAskAgain)
        }
}