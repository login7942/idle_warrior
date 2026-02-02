pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val propertiesFile = file("local.properties")
            var path: String? = null
            if (propertiesFile.exists()) {
                propertiesFile.inputStream().use { properties.load(it) }
                path = properties.getProperty("flutter.sdk")
            }
            if (path == null) {
                path = System.getenv("FLUTTER_ROOT") ?: System.getenv("FLUTTER_HOME")
            }
            path ?: throw GradleException("Flutter SDK not found. Define 'flutter.sdk' in local.properties or set FLUTTER_ROOT environment variable.")
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
