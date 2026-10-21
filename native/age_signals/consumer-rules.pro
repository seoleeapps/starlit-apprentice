-keep class com.seorilabs.starlit.agesignals.StarlitAgeSignals { *; }
-keepclassmembers class * extends org.godotengine.godot.plugin.GodotPlugin {
    @org.godotengine.godot.plugin.UsedByGodot <methods>;
}
