plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "app.ttok.ttokttok_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications 가 요구 (푸시 포그라운드 알림)
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "app.ttok.ttokttok_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // AUTH-006 소셜 로그인 키 — ~/.gradle/gradle.properties(사용자 홈, 커밋되지 않음) 또는 -P 로 넣는다. 없으면 앱이 버튼을 숨긴다
        manifestPlaceholders["kakaoNativeAppKey"] = (project.findProperty("KAKAO_NATIVE_APP_KEY") as String?) ?: "none"
        resValue("string", "naver_client_id", (project.findProperty("NAVER_CLIENT_ID") as String?) ?: "none")
        resValue("string", "naver_client_secret", (project.findProperty("NAVER_CLIENT_SECRET") as String?) ?: "none")
        resValue("string", "naver_client_name", "ttokttok")
    }

    buildFeatures {
        resValues = true
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
