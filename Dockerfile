FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF-8"

# =========================================================
# SYSTEM PACKAGES
# =========================================================
RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    unzip \
    zip \
    ca-certificates \
    bash \
    file \
    sed \
    python3 \
    openjdk-17-jdk \
    golang-go \
    && rm -rf /var/lib/apt/lists/*

# =========================================================
# CLONE H2APK
# =========================================================
WORKDIR /opt

RUN git clone --depth=1 https://github.com/HashShin/H2APK.git

WORKDIR /opt/H2APK

# =========================================================
# H2APK SETUP
# =========================================================
RUN chmod +x setup.sh && ./setup.sh || true

# =========================================================
# ANDROID COMMAND LINE TOOLS
# Used for zipalign + apksigner + Android platform tools
# =========================================================
RUN mkdir -p /opt/H2APK/tools && \
    cd /opt/H2APK/tools && \
    wget -q \
    https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip \
    -O cmdline-tools.zip && \
    unzip -q cmdline-tools.zip && \
    rm cmdline-tools.zip

# =========================================================
# INSTALL ANDROID BUILD TOOLS
# =========================================================
RUN yes | /opt/H2APK/tools/cmdline-tools/bin/sdkmanager --licenses >/dev/null 2>&1 || true && \
    /opt/H2APK/tools/cmdline-tools/bin/sdkmanager \
    --sdk_root=/opt/H2APK/tools/android-sdk \
    "platform-tools" \
    "platforms;android-35" \
    "build-tools;35.0.0"

# =========================================================
# PUT ANDROID TOOLS IN SYSTEM PATH
# =========================================================
RUN BT="/opt/H2APK/tools/android-sdk/build-tools/35.0.0" && \
    ln -sf "$BT/zipalign" /usr/local/bin/zipalign && \
    ln -sf "$BT/apksigner" /usr/local/bin/apksigner && \
    chmod +x "$BT/zipalign" "$BT/apksigner"

ENV ANDROID_HOME=/opt/H2APK/tools/android-sdk
ENV ANDROID_SDK_ROOT=/opt/H2APK/tools/android-sdk

ENV PATH="/opt/H2APK/tools/android-sdk/platform-tools:/opt/H2APK/tools/android-sdk/build-tools/35.0.0:/opt/H2APK/tools:/opt/H2APK/tools/cmdline-tools/bin:${PATH}"

# =========================================================
# AAPT2
# =========================================================
RUN AAPT2_VERSION=$(curl -fsSL \
    https://dl.google.com/dl/android/maven2/com/android/tools/build/aapt2/maven-metadata.xml \
    | grep -oP '(?<=<release>)[^<]+' | head -1) && \
    echo "AAPT2 version: $AAPT2_VERSION" && \
    curl -fL \
    "https://dl.google.com/dl/android/maven2/com/android/tools/build/aapt2/${AAPT2_VERSION}/aapt2-${AAPT2_VERSION}-linux.jar" \
    -o /tmp/aapt2.jar && \
    unzip -p /tmp/aapt2.jar aapt2 > /usr/local/bin/aapt2 && \
    chmod +x /usr/local/bin/aapt2 && \
    rm -f /tmp/aapt2.jar

# =========================================================
# FRAMEWORK RESOURCE
# =========================================================
RUN cp \
    /opt/H2APK/tools/android-sdk/platforms/android-35/data/res/framework-res.apk \
    /opt/H2APK/tools/framework-res.apk

# =========================================================
# VERIFY ALL ANDROID BUILD TOOLS
# =========================================================
RUN echo "===== JAVA =====" && \
    java -version && \
    echo "===== JAVAC =====" && \
    javac -version && \
    echo "===== AAPT2 =====" && \
    aapt2 version || true && \
    echo "===== ZIPALIGN =====" && \
    zipalign -h >/dev/null && \
    echo "zipalign OK" && \
    echo "===== APKSIGNER =====" && \
    apksigner version && \
    echo "apksigner OK" && \
    echo "===== FRAMEWORK =====" && \
    test -f /opt/H2APK/tools/framework-res.apk && \
    echo "framework-res.apk OK"

# =========================================================
# CORS FIX
# =========================================================
RUN python3 - <<'PY'
from pathlib import Path

p = Path("/opt/H2APK/internal/app/app.go")
s = p.read_text(encoding="utf-8")

old = 'log.Fatal(http.Serve(listener, mux))'
new = 'log.Fatal(http.Serve(listener, corsMiddleware(mux)))'

if old in s:
    s = s.replace(old, new, 1)

middleware = r'''

// corsMiddleware enables browser clients such as HopWeb
// to call the H2APK API from another origin.
func corsMiddleware(next http.Handler) http.Handler {
    return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
        w.Header().Set("Access-Control-Allow-Origin", "*")
        w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Accept, Origin")
        w.Header().Set("Access-Control-Max-Age", "86400")

        if r.Method == http.MethodOptions {
            w.WriteHeader(http.StatusNoContent)
            return
        }

        next.ServeHTTP(w, r)
    })
}
'''

if "func corsMiddleware(next http.Handler)" not in s:
    s += middleware

p.write_text(s, encoding="utf-8")
PY

# =========================================================
# BUILD H2APK
# =========================================================
RUN go build -o h2apk main.go

# =========================================================
# RENDER
# =========================================================
ENV PORT=10000

EXPOSE 10000

CMD ["./h2apk"]
