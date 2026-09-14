FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF-8"

RUN apt-get update && apt-get install -y \
    git \
    curl \
    wget \
    unzip \
    zip \
    openjdk-17-jdk \
    golang-go \
    python3 \
    ca-certificates \
    bash \
    file \
    sed \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /opt

RUN git clone --depth=1 https://github.com/HashShin/H2APK.git

WORKDIR /opt/H2APK

# H2APK's setup downloads d8.jar, apksigner.jar and android.jar.
RUN chmod +x setup.sh && ./setup.sh || true

# =========================================================
# INSTALL AAPT2
# =========================================================
RUN mkdir -p /opt/H2APK/tools && \
    AAPT2_VERSION=$(curl -fsSL \
    https://dl.google.com/dl/android/maven2/com/android/tools/build/aapt2/maven-metadata.xml \
    | grep -oP '(?<=<release>)[^<]+' | head -1) && \
    echo "Using AAPT2 version: $AAPT2_VERSION" && \
    curl -fL \
    "https://dl.google.com/dl/android/maven2/com/android/tools/build/aapt2/${AAPT2_VERSION}/aapt2-${AAPT2_VERSION}-linux.jar" \
    -o /tmp/aapt2.jar && \
    unzip -p /tmp/aapt2.jar aapt2 > /opt/H2APK/tools/aapt2 && \
    chmod +x /opt/H2APK/tools/aapt2 && \
    ln -sf /opt/H2APK/tools/aapt2 /usr/local/bin/aapt2 && \
    rm -f /tmp/aapt2.jar

# Make sure aapt2 is really available to H2APK.
RUN /usr/local/bin/aapt2 version || true
RUN command -v aapt2

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
# BUILD
# =========================================================
RUN go build -o h2apk main.go

ENV PORT=10000

EXPOSE 10000

CMD ["./h2apk"]
