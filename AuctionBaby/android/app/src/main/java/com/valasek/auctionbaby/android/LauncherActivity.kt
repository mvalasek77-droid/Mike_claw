package com.valasek.auctionbaby.android

import android.net.Uri
import android.os.Bundle
import com.google.androidbrowserhelper.trusted.LauncherActivity

class LauncherActivity : LauncherActivity() {

    override fun getLaunchingUrl(): Uri {
        val uri = intent?.data
        if (uri != null && uri.host == "mvalasek77.github.io") {
            return uri
        }
        return Uri.parse("https://mvalasek77.github.io/auctionbaby/app/")
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
    }
}
