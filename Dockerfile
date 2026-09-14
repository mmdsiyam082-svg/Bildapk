FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8
ENV JAVA_TOOL_OPTIONS="-Dfile.encoding=UTF-8"

# =========================================================
# SYSTEM DEPENDENCIES
# =========================================================
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
    locales \
    && locale-gen C.UTF-8 \
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
# MAKE SURE BUILD TOOLS ARE AVAILABLE
# =========================================================
ENV PATH="/opt/H2APK/tools:${PATH}"

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
