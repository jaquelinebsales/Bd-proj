pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
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
    id("com.android.application") version "9.1.0" apply false
    id("org.jetbrains.kotlin.android") version "2.4.0" apply false
    // O maplibre_android 0.3.6 aplica o ktlint sem declarar a versão; sem esta linha o Gradle não acha o plugin
    // (issue #565 do flutter-maplibre, corrigida na 0.3.7). Pode sair quando o pacote for atualizado.
    id("org.jlleitschuh.gradle.ktlint") version "14.2.0" apply false
}

include(":app")
