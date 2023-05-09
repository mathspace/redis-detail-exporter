FROM --platform=linux/amd64 alpine as certs
RUN apk update && apk add ca-certificates

FROM --platform=linux/amd64 golang as builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o /redis-detail-exporter

FROM --platform=linux/amd64 busybox:glibc
COPY --from=builder /redis-detail-exporter /
COPY --from=certs /etc/ssl/certs /etc/ssl/certs
ENTRYPOINT ["/redis-detail-exporter"]
