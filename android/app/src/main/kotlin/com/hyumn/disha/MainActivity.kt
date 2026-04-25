package com.hyumn.disha

import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register the Native AR View with the correct standardized viewType
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "com.hyumn.disha/ar_view", ArViewFactory(this, flutterEngine.dartExecutor.binaryMessenger)
        )
    }
}
