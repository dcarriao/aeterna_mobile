# ProGuard rules for WorkManager to prevent crash on Android Release

-keep class androidx.work.impl.WorkDatabase_Impl {
    public <init>(...);
}

-keep class androidx.work.** { *; }
-dontwarn androidx.work.**
