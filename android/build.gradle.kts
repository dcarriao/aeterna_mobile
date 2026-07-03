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

subprojects {
    val configureAndroid = Action<Project> {
        val android = extensions.findByName("android")
        if (android != null) {
            try {
                val method = android::class.java.getMethod("compileSdkVersion", Int::class.javaPrimitiveType)
                method.invoke(android, 36)
                println("[Gradle] Forçado compileSdkVersion 36 para ${project.name} via Reflexão!")
            } catch (e: Exception) {
                try {
                    val methodObj = android::class.java.getMethod("compileSdkVersion", Object::class.java)
                    methodObj.invoke(android, 36)
                    println("[Gradle] Forçado compileSdkVersion 36 para ${project.name} via Reflexão (Object)!")
                } catch (ex: Exception) {
                    println("[Gradle] Erro ao forçar compileSdkVersion para ${project.name}: $ex")
                }
            }
        }
    }

    if (state.executed) {
        configureAndroid.execute(this)
    } else {
        afterEvaluate {
            configureAndroid.execute(this)
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
