# Stripe / flutter_stripe
-keep class com.stripe.android.** { *; }
-dontwarn com.stripe.android.**

# If something is pulling reactnativestripesdk, keep it too
-keep class com.reactnativestripesdk.** { *; }
-dontwarn com.reactnativestripesdk.**