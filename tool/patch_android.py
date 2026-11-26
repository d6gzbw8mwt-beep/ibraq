"""يُشغَّل تلقائياً أثناء البناء بعد `flutter create` لتجهيز إعدادات أندرويد:
الأذونات، اسم التطبيق، دعم البصمة، والإشعارات."""
import glob
import re
import sys

APP_NAME = "الإبراق الإلكتروني"

# ---------- AndroidManifest.xml ----------
mf_path = "android/app/src/main/AndroidManifest.xml"
mf = open(mf_path, encoding="utf-8").read()
perms = [
    "android.permission.INTERNET",
    "android.permission.ACCESS_FINE_LOCATION",
    "android.permission.ACCESS_COARSE_LOCATION",
    "android.permission.ACCESS_BACKGROUND_LOCATION",
    "android.permission.FOREGROUND_SERVICE",
    "android.permission.FOREGROUND_SERVICE_LOCATION",
    "android.permission.WAKE_LOCK",
    "android.permission.RECORD_AUDIO",
    "android.permission.MODIFY_AUDIO_SETTINGS",
    "android.permission.CAMERA",
    "android.permission.POST_NOTIFICATIONS",
    "android.permission.USE_BIOMETRIC",
    "android.permission.VIBRATE",
]
block = "".join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in mf)
mf = mf.replace("<application", block + "    <application", 1)
mf = re.sub(r'android:label="[^"]*"', f'android:label="{APP_NAME}"', mf, count=1)
if "usesCleartextTraffic" not in mf:
    mf = mf.replace("<application", '<application\n        android:usesCleartextTraffic="true"', 1)
# فتح الروابط الخارجية (خرائط Google) والملفات
if "<queries>" in mf and "android.intent.action.VIEW" not in mf.split("<queries>")[1]:
    mf = mf.replace("<queries>", '<queries>\n        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>', 1)
elif "<queries>" not in mf:
    mf = mf.replace("</manifest>", '    <queries>\n        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>\n    </queries>\n</manifest>', 1)
# مزوّد الملفات المطلوب لالتقاط صورة بالكاميرا من داخل التطبيق (رفع الملفات في WebView)
if "InAppWebViewFileProvider" not in mf:
    mf = mf.replace("</application>", """        <provider
            android:name="com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFileProvider"
            android:authorities="${applicationId}.flutter_inappwebview_android.fileprovider"
            android:exported="false"
            android:grantUriPermissions="true">
            <meta-data
                android:name="android.support.FILE_PROVIDER_PATHS"
                android:resource="@xml/provider_paths" />
        </provider>
    </application>""", 1)
open(mf_path, "w", encoding="utf-8").write(mf)
print("manifest patched")

# ---------- MainActivity -> FlutterFragmentActivity (مطلوب للبصمة) ----------
acts = glob.glob("android/app/src/main/kotlin/**/MainActivity.kt", recursive=True) + \
       glob.glob("android/app/src/main/java/**/MainActivity.java", recursive=True)
for a in acts:
    s = open(a, encoding="utf-8").read()
    s = s.replace("io.flutter.embedding.android.FlutterActivity", "io.flutter.embedding.android.FlutterFragmentActivity")
    s = re.sub(r"\bFlutterActivity\b", "FlutterFragmentActivity", s)
    open(a, "w", encoding="utf-8").write(s)
    print("activity patched:", a)
if not acts:
    sys.exit("MainActivity not found")

# ---------- build.gradle: minSdk + desugaring (مطلوب للإشعارات) ----------
kts = glob.glob("android/app/build.gradle.kts")
groovy = glob.glob("android/app/build.gradle")
if kts:
    p = kts[0]; s = open(p, encoding="utf-8").read()
    s = re.sub(r"minSdk\s*=\s*[^\n]+", "minSdk = 24", s, count=1)
    if "isCoreLibraryDesugaringEnabled" not in s:
        s = s.replace("compileOptions {", "compileOptions {\n        isCoreLibraryDesugaringEnabled = true", 1)
    if "desugar_jdk_libs" not in s:
        s += '\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")\n}\n'
    open(p, "w", encoding="utf-8").write(s)
    print("build.gradle.kts patched")
elif groovy:
    p = groovy[0]; s = open(p, encoding="utf-8").read()
    s = re.sub(r"minSdk(Version)?\s*=?\s*[^\n]+", "minSdk = 24", s, count=1)
    if "coreLibraryDesugaringEnabled" not in s:
        s = s.replace("compileOptions {", "compileOptions {\n        coreLibraryDesugaringEnabled true", 1)
    if "desugar_jdk_libs" not in s:
        s += "\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'\n}\n"
    open(p, "w", encoding="utf-8").write(s)
    print("build.gradle patched")
else:
    sys.exit("app build.gradle not found")
