# Release-build R8 rules.

# pdfbox-android references an optional JPEG2000 codec (com.gemalto.jp2) that
# is not shipped with the AAR. The reference is optional at runtime; failing
# the release build over it would break the APK for no functional gain.
-dontwarn com.gemalto.jp2.**