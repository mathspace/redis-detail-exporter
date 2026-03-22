FROM alpine AS certs
RUN apk update && apk add ca-certificates

FROM --platform=$BUILDPLATFORM golang AS builder
ARG TARGETOS
ARG TARGETARCH
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=${TARGETOS:-linux} GOARCH=${TARGETARCH} go build -o /redis-detail-exporter

FROM busybox:glibc
COPY --from=builder /redis-detail-exporter /
COPY --from=certs /etc/ssl/certs /etc/ssl/certs
ENTRYPOINT ["/redis-detail-exporter"]
