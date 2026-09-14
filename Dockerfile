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
    android-sdk-build-tools \
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
RUN chmod +x setup.sh && ./setup.sh

# =========================================================
# FIND ANDROID TOOLS
# =========================================================
RUN echo "===== LOCATING ANDROID TOOLS =====" && \
    command -v aapt2 || true && \
    command -v zipalign || true && \
    find /usr -type f -name aapt2 2>/dev/null | head -20 && \
    find /usr -type f -name zipalign 2>/dev/null | head -20

# =========================================================
# MAKE TOOLS AVAILABLE IN PATH
# =========================================================
RUN AAPT2_PATH=$(command -v aapt2) && \
    ZIPALIGN_PATH=$(command -v zipalign) && \
    ln -sf "$AAPT2_PATH" /usr/local/bin/aapt2 && \
    ln -sf "$ZIPALIGN_PATH" /usr/local/bin/zipalign && \
    chmod +x "$AAPT2_PATH" "$ZIPALIGN_PATH"

# =========================================================
# VERIFY
# =========================================================
RUN echo "===== VERIFY aapt2 =====" && \
    command -v aapt2 && \
    echo "===== VERIFY zipalign =====" && \
    command -v zipalign && \
    echo "===== VERIFY JAVA =====" && \
    javac -version

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
