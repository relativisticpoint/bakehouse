# syntax=docker/dockerfile:1
FROM golang:1.27 AS build
ARG VERSION=dev
ARG GIT_SHA=unknown
WORKDIR /src
COPY go.mod ./
COPY main.go ./
RUN CGO_ENABLED=0 go build -trimpath \
    -ldflags "-s -w -X main.version=${VERSION} -X main.gitSHA=${GIT_SHA}" \
    -o /out/app .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/app /app
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app"]
