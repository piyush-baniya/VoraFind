allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")

    // Force plugin/library modules to compile against the Flutter SDK's
    // compileSdk. Without this, AAR metadata checks fail for plugins that
    // ship newer androidx dependencies than their own pinned compileSdk (the
    // `onnxruntime` plugin pins 33 while its androidx deps require 34+).
    // Runs in afterEvaluate so it wins over the module's own `compileSdk`
    // assignment, but must tolerate projects Flutter already evaluated.
    fun forceCompileSdk() {
        if (!project.plugins.hasPlugin("com.android.library")) return
        val targetSdk =
            (project.rootProject.properties["flutter.compileSdkVersion"] as String?)
                ?.toInt() ?: 36
        project.extensions.configure<com.android.build.gradle.LibraryExtension>("android") {
            compileSdk = targetSdk
        }
    }
    if (project.state.executed) forceCompileSdk() else project.afterEvaluate { forceCompileSdk() }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
