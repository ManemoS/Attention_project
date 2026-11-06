package com.example.attention_project

import android.content.Context
import android.net.Uri
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.zip.ZipEntry
import java.util.zip.ZipInputStream
import java.util.zip.ZipOutputStream

/**
 * Backs the app's data up into one .zip file, and restores it.
 *
 * The zip holds the lectures folder, the app's settings and plans (passed in from Flutter as
 * JSON), and the focus history. Secrets stay out: the Claude API key is never included (Flutter
 * leaves it out of the settings it passes), and neither are lock codes or a session in progress.
 */
object Backup {
    private const val MANIFEST = "apls-backup.json"
    private const val PREFS_ENTRY = "settings.json"
    private const val FOCUS_ENTRY = "focus.json"
    private const val LECTURES = "lectures/"

    /** Files left over from an interrupted transcription, which are big and can be remade. */
    private fun isScratch(name: String) = name.endsWith(".wav") || name.endsWith(".part")

    /** Writes a backup zip into the app's cache and returns it. */
    fun create(context: Context, settings: String, includeAudio: Boolean): File {
        val out = File(context.cacheDir, "backup.zip")
        ZipOutputStream(out.outputStream().buffered()).use { zip ->
            fun put(name: String, text: String) {
                zip.putNextEntry(ZipEntry(name))
                zip.write(text.toByteArray())
                zip.closeEntry()
            }
            put(MANIFEST, JSONObject().put("app", "APLS").put("version", 1).put("created", System.currentTimeMillis()).toString())
            put(PREFS_ENTRY, settings)
            put(FOCUS_ENTRY, JSONObject()
                .put("history", LockState.history(context))
                .put("blocked", LockState.blocked(context))
                .toString())
            val dir = LectureRecorderService.lecturesDir(context)
            dir.listFiles()?.sortedBy { it.name }?.forEach { file ->
                if (!file.isFile || isScratch(file.name)) return@forEach
                if (!includeAudio && file.name.endsWith(".m4a")) return@forEach
                zip.putNextEntry(ZipEntry(LECTURES + file.name))
                file.inputStream().use { it.copyTo(zip) }
                zip.closeEntry()
            }
        }
        return out
    }

    /** Copies [file] to where the user chose to save it. */
    fun saveTo(context: Context, file: File, uri: Uri) {
        context.contentResolver.openOutputStream(uri)?.use { out -> file.inputStream().use { it.copyTo(out) } }
            ?: throw IllegalStateException("Couldn't write the backup there.")
        file.delete()
    }

    /**
     * Restores the backup at [uri]: lecture files are added (an existing file with the same name is
     * replaced), and focus history is merged. Returns the settings JSON for Flutter to apply.
     */
    fun restore(context: Context, uri: Uri): String {
        val dir = LectureRecorderService.lecturesDir(context)
        val root = dir.canonicalPath + File.separator
        var settings: String? = null
        var focus: String? = null
        var valid = false
        val input = context.contentResolver.openInputStream(uri) ?: throw IllegalStateException("Couldn't open that file.")
        ZipInputStream(input.buffered()).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                when {
                    entry.isDirectory -> Unit
                    entry.name == MANIFEST -> valid = JSONObject(zip.readBytes().decodeToString()).optString("app") == "APLS"
                    entry.name == PREFS_ENTRY -> settings = zip.readBytes().decodeToString()
                    entry.name == FOCUS_ENTRY -> focus = zip.readBytes().decodeToString()
                    entry.name.startsWith(LECTURES) -> {
                        val target = File(dir, entry.name.removePrefix(LECTURES))
                        // Refuses names like "../x" that would write outside the lectures folder.
                        if (!target.canonicalPath.startsWith(root) || isScratch(target.name)) continue
                        target.outputStream().use { zip.copyTo(it) }
                    }
                }
            }
        }
        if (!valid) throw IllegalArgumentException("That isn't an APLS backup.")
        focus?.let { mergeFocus(context, JSONObject(it)) }
        return settings ?: "{}"
    }

    /** Adds backed-up sessions and blocked-open counts that aren't on the phone already. */
    private fun mergeFocus(context: Context, focus: JSONObject) {
        val have = LockState.history(context)
        val starts = (0 until have.length()).map { have.getJSONObject(it).optLong("start") }.toSet()
        val incoming = focus.optJSONArray("history") ?: JSONArray()
        val merged = (0 until have.length()).map { have.getJSONObject(it) } +
            (0 until incoming.length()).map { incoming.getJSONObject(it) }.filter { it.optLong("start") !in starts }
        val blocked = LockState.blocked(context)
        val backedUp = focus.optJSONObject("blocked") ?: JSONObject()
        for (day in backedUp.keys()) {
            if (!blocked.has(day)) blocked.put(day, backedUp.getJSONObject(day))
        }
        LockState.replaceHistory(context, JSONArray(merged.sortedBy { it.optLong("start") }), blocked)
    }
}
