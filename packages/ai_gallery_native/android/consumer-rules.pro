# LiteRT-LM 0.18.0 ships no consumer rules. Its JNI resolves SDK classes,
# constructors and accessors by name (including InputData$Text/$Image/$Audio).
# Preserve this boundary while leaving the rest of the app's R8 optimization on.
-keep class com.google.ai.edge.litertlm.** { *; }
