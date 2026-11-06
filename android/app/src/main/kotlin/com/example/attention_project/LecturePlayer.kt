package com.example.attention_project

import android.media.AudioAttributes
import android.media.MediaPlayer

/** Plays back one lecture recording at a time, for the lecture page's player. */
object LecturePlayer {
    private var player: MediaPlayer? = null
    private var path: String? = null

    /** Opens [file] (if it isn't already open) and returns its length in milliseconds. */
    fun load(file: String): Int {
        if (path == file && player != null) return player!!.duration
        release()
        val p = MediaPlayer()
        p.setAudioAttributes(
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_MEDIA)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                .build()
        )
        p.setDataSource(file)
        p.prepare()
        player = p
        path = file
        return p.duration
    }

    fun play() = player?.start()

    fun pause() {
        player?.takeIf { it.isPlaying }?.pause()
    }

    fun seekTo(ms: Int) = player?.seekTo(ms)

    /** Where playback is, and whether it is playing. */
    fun state(): Map<String, Any> = mapOf(
        "position" to (player?.currentPosition ?: 0),
        "playing" to (player?.isPlaying ?: false),
    )

    fun release() {
        player?.release()
        player = null
        path = null
    }
}
