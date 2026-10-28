# Certificates
FROM --platform=$BUILDPLATFORM debian:bookworm-slim AS certs
# This line busts the cache if there's security updates.
ADD https://deb.debian.org/debian/dists/bookworm/InRelease /tmp/bust-debian
ADD https://deb.debian.org/debian/dists/bookworm-updates/InRelease /tmp/bust-updates
ADD https://security.debian.org/debian-security/dists/bookworm-security/InRelease /tmp/bust-security
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates

FROM --platform=$BUILDPLATFORM golang:bookworm AS builder
# This line busts the cache if there's security updates.
ADD https://deb.debian.org/debian/dists/bookworm/InRelease /tmp/bust-debian
ADD https://deb.debian.org/debian/dists/bookworm-updates/InRelease /tmp/bust-updates
ADD https://security.debian.org/debian-security/dists/bookworm-security/InRelease /tmp/bust-security
ARG TARGETOS
ARG TARGETARCH
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -o /redis-detail-exporter

FROM scratch
COPY --from=builder /redis-detail-exporter /
COPY --from=certs /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
ENTRYPOINT ["/redis-detail-exporter"]
