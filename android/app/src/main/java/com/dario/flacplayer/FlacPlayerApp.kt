package com.dario.flacplayer

import android.app.Application
import com.dario.flacplayer.audio.AudioPlayer
import com.dario.flacplayer.library.Database
import com.dario.flacplayer.library.MusicLibrary

class FlacPlayerApp : Application() {
    lateinit var library: MusicLibrary
        private set
    lateinit var player: AudioPlayer
        private set

    override fun onCreate() {
        super.onCreate()
        library = MusicLibrary(this, Database(this))
        player = AudioPlayer(this, library)
        library.onTracksChanged = player::libraryChanged
        library.load()
        player.restoreSession()
    }
}
