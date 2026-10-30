package com.dario.flacplayer

import android.Manifest
import android.content.ComponentName
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.dario.flacplayer.audio.PlaybackService
import com.dario.flacplayer.ui.FlacPlayerRoot
import com.google.common.util.concurrent.ListenableFuture

class MainActivity : ComponentActivity() {
    private var controller: ListenableFuture<MediaController>? = null

    private val permissions = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) {
        (application as FlacPlayerApp).library.rescan(silent = true)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        val app = application as FlacPlayerApp
        setContent { FlacPlayerRoot(app.library, app.player) }
        permissions.launch(
            if (Build.VERSION.SDK_INT >= 33) {
                arrayOf(Manifest.permission.READ_MEDIA_AUDIO, Manifest.permission.POST_NOTIFICATIONS)
            } else {
                arrayOf(Manifest.permission.READ_EXTERNAL_STORAGE)
            },
        )
    }

    override fun onStart() {
        super.onStart()
        // Il collegamento avvia il servizio che tiene viva la riproduzione.
        val token = SessionToken(this, ComponentName(this, PlaybackService::class.java))
        controller = MediaController.Builder(this, token).buildAsync()
    }

    override fun onResume() {
        super.onResume()
        (application as FlacPlayerApp).library.rescan(silent = true)
    }

    override fun onStop() {
        (application as FlacPlayerApp).player.saveSession()
        controller?.let(MediaController::releaseFuture)
        controller = null
        super.onStop()
    }
}
