package com.piyushbaniya.vorafind.content

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.lifecycle.Lifecycle

/**
 * Runtime permissions each media category requires per API level.
 *
 * Pure (no Android calls) so the API-level policy is unit-testable.
 */
internal fun permissionsFor(category: ContentCategory, apiLevel: Int): Array<String> {
    if (category == ContentCategory.DOCUMENTS) {
        throw IllegalArgumentException("Documents are granted via SAF, not a media permission.")
    }
    return if (apiLevel >= Build.VERSION_CODES.TIRAMISU) {
        when (category) {
            ContentCategory.IMAGES -> arrayOf(Manifest.permission.READ_MEDIA_IMAGES)
            ContentCategory.VIDEOS -> arrayOf(Manifest.permission.READ_MEDIA_VIDEO)
            ContentCategory.AUDIO -> arrayOf(Manifest.permission.READ_MEDIA_AUDIO)
            ContentCategory.DOCUMENTS -> error("unreachable")
        }
    } else {
        arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
    }
}

/**
 * Media permission state detection and request plumbing.
 *
 * Requesting READ_MEDIA_IMAGES/VIDEO on Android 14+ can end in a partial grant
 * (the user selected specific items); that yields READ_MEDIA_VISUAL_USER_SELECTED
 * instead of READ_MEDIA_* and is reported as [ContentAccessState.PARTIAL_ACCESS],
 * never as [ContentAccessState.FULL_ACCESS].
 */
class MediaPermissionService(private val activity: ComponentActivity) {

    private var pendingCategory: ContentCategory? = null
    private var pendingCallback: ((ContentAccessState) -> Unit)? = null

    private val launcher = activity.registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions(),
    ) { _ ->
        val category = pendingCategory
        val callback = pendingCallback
        pendingCategory = null
        pendingCallback = null
        if (category != null && callback != null) {
            callback(accessAfterRequest(category))
        }
    }

    private val apiLevel: Int
        get() = Build.VERSION.SDK_INT

    /** Side-effect-free state query: never shows a dialog or opens a picker. */
    fun stateFor(category: ContentCategory): ContentAccessState {
        if (apiLevel >= Build.VERSION_CODES.TIRAMISU) {
            return when (category) {
                ContentCategory.IMAGES -> AccessStateMapper.visualStatus(
                    isFullGranted = has(Manifest.permission.READ_MEDIA_IMAGES),
                    isSelectedGranted = has(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED),
                    canAskAgain = canAskAgain(Manifest.permission.READ_MEDIA_IMAGES),
                )
                ContentCategory.VIDEOS -> AccessStateMapper.visualStatus(
                    isFullGranted = has(Manifest.permission.READ_MEDIA_VIDEO),
                    isSelectedGranted = has(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED),
                    canAskAgain = canAskAgain(Manifest.permission.READ_MEDIA_VIDEO),
                )
                ContentCategory.AUDIO -> AccessStateMapper.fromStatusQuery(
                    hasAccess = has(Manifest.permission.READ_MEDIA_AUDIO),
                    canAskAgain = canAskAgain(Manifest.permission.READ_MEDIA_AUDIO),
                )
                ContentCategory.DOCUMENTS ->
                    throw IllegalArgumentException("Documents are not a media permission.")
            }
        }
        // API 24–32: one full-read permission covers all media collections.
        return AccessStateMapper.fromStatusQuery(
            hasAccess = has(Manifest.permission.READ_EXTERNAL_STORAGE),
            canAskAgain = canAskAgain(Manifest.permission.READ_EXTERNAL_STORAGE),
        )
    }

    /** Requests the media permission for [category] and reports the resulting state. */
    fun request(category: ContentCategory, onResult: (ContentAccessState) -> Unit) {
        val permissions = permissionsFor(category, apiLevel)
        if (permissions.all { has(it) }) {
            onResult(accessAfterRequest(category))
            return
        }
        if (pendingCallback != null ||
            !activity.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)
        ) {
            // Either a request is already in flight (a second dialog cannot be
            // shown), or the activity is not resumed yet (no dialog can be
            // displayed). Resolve with the current state instead of overwriting
            // an in-flight callback or leaving the Dart side waiting forever
            // (Prompt #15.1).
            onResult(accessAfterRequest(category))
            return
        }
        pendingCategory = category
        pendingCallback = onResult
        try {
            launcher.launch(permissions)
        } catch (_: Exception) {
            // Resolve with the current (legal) state rather than failing the
            // call: the caller re-reads capabilities afterwards.
            val resolved = pendingCallback
            pendingCategory = null
            pendingCallback = null
            resolved?.invoke(accessAfterRequest(category))
        }
    }

    private fun accessAfterRequest(category: ContentCategory): ContentAccessState {
        if (apiLevel >= Build.VERSION_CODES.TIRAMISU) {
            return when (category) {
                ContentCategory.IMAGES -> AccessStateMapper.visualRequestResult(
                    isFullGranted = has(Manifest.permission.READ_MEDIA_IMAGES),
                    isSelectedGranted = has(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED),
                    canAskAgain = canAskAgain(Manifest.permission.READ_MEDIA_IMAGES),
                )
                ContentCategory.VIDEOS -> AccessStateMapper.visualRequestResult(
                    isFullGranted = has(Manifest.permission.READ_MEDIA_VIDEO),
                    isSelectedGranted = has(Manifest.permission.READ_MEDIA_VISUAL_USER_SELECTED),
                    canAskAgain = canAskAgain(Manifest.permission.READ_MEDIA_VIDEO),
                )
                ContentCategory.AUDIO -> AccessStateMapper.fromRequestResult(
                    hasAccess = has(Manifest.permission.READ_MEDIA_AUDIO),
                    canAskAgain = canAskAgain(Manifest.permission.READ_MEDIA_AUDIO),
                )
                ContentCategory.DOCUMENTS -> ContentAccessState.NO_ACCESS
            }
        }
        return AccessStateMapper.fromRequestResult(
            hasAccess = has(Manifest.permission.READ_EXTERNAL_STORAGE),
            canAskAgain = canAskAgain(Manifest.permission.READ_EXTERNAL_STORAGE),
        )
    }

    private fun has(permission: String): Boolean =
        activity.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun canAskAgain(permission: String): Boolean =
        activity.shouldShowRequestPermissionRationale(permission)
}