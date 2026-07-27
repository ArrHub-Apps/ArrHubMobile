# WorkManager instantiates its Room database via reflection; R8 full mode
# strips the no-arg constructor without this, crashing release builds at
# startup (NoSuchMethodException: WorkDatabase_Impl.<init>).
-keep class * extends androidx.room.RoomDatabase { <init>(); }
-keep class androidx.work.impl.WorkDatabase_Impl { *; }
