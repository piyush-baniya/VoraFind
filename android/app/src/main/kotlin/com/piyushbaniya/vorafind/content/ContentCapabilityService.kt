package com.piyushbaniya.vorafind.content

import android.content.Context
import android.os.Build
import android.provider.MediaStore

/**
 * One-shot capability snapshot for the current device and permission scope.
 *
 * Documents never reach [ContentAccessState.FULL_ACCESS]: SAF grants are folder
 * scoped by design, so a grant only ever produces [ContentAccessState.PARTIAL_ACCESS].
 */
class ContentCapabilityService(
    private val context: Context,
    private val mediaPermissionService: MediaPermissionService,
    private val documentAccessService: DocumentAccessService,
) {

    fun capabilities(): Map<String, Any?> {
        val apiLevel = Build.VERSION.SDK_INT
        val states = mapOf(
            ContentCategory.IMAGES to mediaPermissionService.stateFor(ContentCategory.IMAGES),
            ContentCategory.VIDEOS to mediaPermissionService.stateFor(ContentCategory.VIDEOS),
            ContentCategory.AUDIO to mediaPermissionService.stateFor(ContentCategory.AUDIO),
            ContentCategory.DOCUMENTS to documentState(),
        )
        return CapabilityMapper.capabilities(
            apiLevel = apiLevel,
            states = states,
            externalVolumes = if (apiLevel >= Build.VERSION_CODES.Q) externalVolumeNames() else emptyList(),
        )
    }

    private fun documentState(): ContentAccessState =
        if (documentAccessService.hasTreeGrant()) {
            ContentAccessState.PARTIAL_ACCESS
        } else {
            ContentAccessState.NO_ACCESS
        }

    private fun externalVolumeNames(): List<String> =
        try {
            MediaStore.getExternalVolumeNames(context).sorted()
        } catch (_: Exception) {
            emptyList()
        }
}