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
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}


subprojects {
    val configureNamespace = {
        val android = project.extensions.findByName("android")
        // android設定がある、かつnamespaceが未設定の場合のみ設定する
        if (android is com.android.build.gradle.BaseExtension) {
            if (android.namespace == null) {
                android.namespace = project.group.toString()
            }
        }
    }

    // ここが重要：すでに読み込み終わってるかどうかで分岐する
    if (project.state.executed) {
        configureNamespace()
    } else {
        project.afterEvaluate {
            configureNamespace()
        }
    }
}