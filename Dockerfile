FROM ubuntu:24.04

ENV DEBIAN_FRONTEND=noninteractive

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

RUN chmod +x setup.sh && ./setup.sh

# CORS FIX
RUN python3 - <<'PY'
from pathlib import Path

p = Path("/opt/H2APK/internal/app/app.go")
s = p.read_text()

old = 'log.Fatal(http.Serve(listener, mux))'
new = 'log.Fatal(http.Serve(listener, corsMiddleware(mux)))'

if old not in s:
    raise SystemExit("H2APK server line not found")

s = s.replace(old, new, 1)

s += r'''

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

p.write_text(s)
PY

RUN go build -o h2apk main.go

ENV PORT=10000

EXPOSE 10000

CMD ["./h2apk"]
