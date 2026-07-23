package com.olaf.sample

import android.app.Application
import com.olaf.LogCategory
import com.olaf.Olaf
import com.olaf.ui.OlafUI

/**
 * Shows the two-line setup a host app needs.
 *
 * In a real app both calls belong behind a debug-only guard — see Android/INTEGRATION.md.
 */
class SampleApp : Application() {

    override fun onCreate() {
        super.onCreate()

        // Start before the shared OkHttp client is built, so the earliest calls are captured.
        Olaf.start(this)
        OlafUI.install(this)

        Olaf.info("Sample app started", LogCategory.General)
    }
}
