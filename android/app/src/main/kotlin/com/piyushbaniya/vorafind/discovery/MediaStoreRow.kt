package com.piyushbaniya.vorafind.discovery

/**
 * Read-only access to one MediaStore cursor row.
 *
 * An interface so mapping logic stays JVM-testable without an Android Cursor.
 * Column access is nullable and tolerates columns absent on some API levels.
 */
interface MediaStoreRow {
    /** Long column value, or null when the column is absent or null. */
    fun longOrNull(column: String): Long?

    /** String column value, or null when the column is absent or null. */
    fun stringOrNull(column: String): String?

    /** Canonical `content://` URI for this media item. */
    fun contentUri(): String
}