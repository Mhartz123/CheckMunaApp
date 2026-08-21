# Release builds run with isMinifyEnabled = true, so every class reached only
# through JNI or reflection has to be kept by name here or it is stripped and
# the feature fails at runtime rather than at build time.

# ML Kit on-device text recognition (frozen pretrained model, loaded natively).
-keep class com.google.mlkit.** { *; }
-keep class com.google_mlkit_text_recognition.** { *; }
-keep class com.google_mlkit_commons.** { *; }
-dontwarn com.google.mlkit.**

# ONNX Runtime backs both the DistilBERT semantic tier and the YOLOv8n damage
# detector. The Java API is a thin shell over JNI, so R8 cannot see the native
# side calling back into these classes.
-keep class ai.onnxruntime.** { *; }
-dontwarn ai.onnxruntime.**

# CameraX, used by camera_android_camerax for capture.
-keep class androidx.camera.** { *; }
-dontwarn androidx.camera.**
