package com.olaf.ui.presentation

import android.app.Activity
import android.app.Application
import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.olaf.Olaf
import com.olaf.internal.OlafNotifier
import java.lang.ref.WeakReference

/**
 * Owns the shake gesture and launches the viewer in its own activity.
 *
 * iOS presents the viewer in a separate `UIWindow` so it never touches the app's navigation; the
 * Android equivalent is a dedicated activity — the host's back stack, navigation graph and
 * lifecycle stay untouched.
 */
internal object OlafPresenter {

    private var installed = false
    private var currentActivity: WeakReference<Activity>? = null
    private var detector: ShakeDetector? = null

    /** Handler registered through `OlafUI.onLogoTap`; makes the nav-bar logo a hand-off button. */
    @Volatile
    var logoTapHandler: (() -> Unit)? = null

    /** `true` while the viewer activity is on screen — a second shake closes it. */
    @Volatile
    var isPresented: Boolean = false

    /** Installs the shake observer. Idempotent. */
    fun install(application: Application) {
        if (installed) return
        installed = true

        val shakeDetector = ShakeDetector { toggle() }
        detector = shakeDetector

        application.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) {
                if (activity is OlafViewerActivity) return
                currentActivity = WeakReference(activity)
                // The sensor only runs while the app is in the foreground, so it costs nothing
                // in the background.
                shakeDetector.start(activity)
            }

            override fun onActivityPaused(activity: Activity) {
                if (activity is OlafViewerActivity) return
                shakeDetector.stop()
            }

            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        })
    }

    private fun toggle() {
        if (isPresented) dismiss() else present()
    }

    /** Opens the viewer. Safe to call from any thread. */
    fun present(context: Context? = null) {
        if (isPresented) return
        val host = context ?: currentActivity?.get() ?: return
        // Its own task, so split-screen puts Olaf next to the app rather than over it.
        host.startActivity(OlafNotifier.viewerLaunchIntent(host))
    }

    /** Closes the viewer if it is open. */
    fun dismiss() {
        viewerActivity?.get()?.finish()
    }

    // MARK: - Viewer activity bookkeeping

    private var viewerActivity: WeakReference<Activity>? = null

    fun onViewerCreated(activity: Activity) {
        viewerActivity = WeakReference(activity)
        isPresented = true
        // The captures have been seen; clearing keeps the shade from accumulating stale counts.
        Olaf.runtime.dismissNotification()
        // The detector follows the viewer too, so a shake closes it again.
        detector?.start(activity)
    }

    fun onViewerDestroyed() {
        viewerActivity = null
        isPresented = false
    }
}
